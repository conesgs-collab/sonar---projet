# Étape 6 — Protocole de validation matérielle des profils

But : prouver, sur 3 scénarios réels, que ce que `--profile` promet
fonctionne vraiment — pas juste que les outils sont présents sur la clé
(ça, `--fetch` le garantit déjà par le SHA-256), mais qu'ils **résolvent
le problème** annoncé. Minimum imposé par `ROADMAP.md` : 3 scénarios
(`boot-repair`, `data-recovery`, `malware`). `disk-clone` et
`password-reset` sont en bonus à la fin si le temps le permet.

## Avant de commencer

- **Utilisez des machines virtuelles jetables** (VirtualBox, VMware,
  Hyper-V, QEMU — ce que vous avez sous la main), pas du matériel de
  production. Le boot physique réel de la clé est déjà validé
  (`ROADMAP.md`, section P0, HP EliteBook 840 G3) — ce qu'on teste ici,
  c'est la **capacité de réparation des outils**, pas la compatibilité
  de démarrage, et une VM avec snapshots est plus sûre et plus rapide à
  réinitialiser entre deux essais qu'un disque physique.
- **Snapshot AVANT chaque injection de panne**, systématiquement — vous
  allez casser la VM exprès, vous devez pouvoir revenir en arrière.
- Préparez la clé une fois pour tous les scénarios :
  ```bash
  sudo SONAR_ROLE=Vault SONAR_ROLE_TOKEN="<jeton>" \
      ./sonar_master.sh --fetch-manifest-seal
  ./sonar_master.sh --fetch full --source ./SONAR_SOURCE
  sudo ./sonar_master.sh --disk /dev/sdX --source ./SONAR_SOURCE \
      --yes --accept-hardware-risk
  ```
- Pour chaque scénario : notez l'heure de début/fin, chaque commande
  tapée, chaque écran inattendu (même mineur) — c'est la matière
  première de l'entrée CHANGELOG, pas un résumé a posteriori qui oublie
  des détails.

---

## Scénario 1 — `boot-repair` : boot cassé réparé

**Limite déjà connue et à respecter** : sans WinPE fourni par vous-même
(`docs/WINPE.md`), ce profil ne couvre que la réparation **côté
Linux**. Le test ci-dessous valide donc une casse de boot qui touche la
table de partitions/le chargeur — pas une réparation Windows interne
(`bootrec`, `sfc`). Si vous avez construit un WinPE et voulez tester
cette partie aussi, voir "Extension WinPE" à la fin de cette section.

### Injection de panne (sur la VM cible, PAS sur la clé SONAR)

1. Créez une VM avec un disque virtuel, une table de partitions GPT ou
   MBR, et un OS installé dessus (Linux le plus simple à réinstaller si
   besoin ; Windows si vous voulez rester dans l'esprit de l'énoncé
   original — le mécanisme cassé/réparé est le même : la table de
   partitions, pas l'OS lui-même).
2. **Snapshot.**
3. Démarrez sur un live CD/USB quelconque (pas SONAR) ou utilisez un
   accès disque direct à la VM éteinte, et détruisez délibérément le
   secteur de boot :
   ```bash
   dd if=/dev/zero of=/dev/sdX bs=512 count=1
   ```
   (1 seul secteur — la table de partitions/MBR, pas le disque entier.)
4. Redémarrez la VM normalement : confirmez qu'elle ne boot plus
   (firmware signale "no bootable device" ou équivalent).

### Réparation via la clé SONAR

1. Démarrez la VM sur la clé SONAR (ISO SystemRescue, via le menu
   Ventoy).
2. Dans SystemRescue, lancez `testdisk` sur le disque de la VM.
3. Suivez l'assistant TestDisk : type de table (Intel/GPT selon le
   cas), "Analyse", "Recherche rapide" puis, si besoin, "Recherche
   approfondie".
4. Si TestDisk retrouve la partition perdue : "Écrire" pour
   reconstruire la table.
5. Éteignez la VM, retirez/désélectionnez la clé SONAR du boot, et
   redémarrez sur le disque interne.

### À consigner

- TestDisk a-t-il retrouvé la partition automatiquement, ou fallu une
  recherche approfondie ?
- La VM a-t-elle rebooté sur son OS d'origine après réparation ?
- Combien de temps, du démarrage sur la clé à la confirmation du boot
  réparé ?
- Tout écran, message d'erreur, ou comportement surprenant de
  SystemRescue/TestDisk dans cet environnement précis (résolution
  d'écran, clavier, réseau, lenteur...).

### Extension WinPE (optionnelle, si vous en avez construit un)

Répétez avec une VM Windows dont vous corrompez le BCD
(`bcdedit /export` avant, pour pouvoir comparer) plutôt que la table de
partitions, et réparez via votre WinPE (`bootrec /rebuildbcd`) ajouté à
la clé selon `docs/WINPE.md`. Consignez séparément — c'est un test de
*votre* WinPE, pas du profil `boot-repair` de SONAR tel que livré.

---

## Scénario 2 — `data-recovery` : fichier supprimé récupéré

### Préparation (sur la VM cible)

1. Créez/formatez une partition de test (ext4 ou NTFS selon ce que vous
   voulez valider).
2. Copiez-y 5 fichiers de test à contenu connu et distinct (par
   exemple 5 images ou PDF différents — PhotoRec carve par signature de
   type de fichier, autant tester avec des formats reconnaissables).
3. **Avant suppression**, calculez et notez leur empreinte :
   ```bash
   sha256sum /chemin/vers/les/5/fichiers/* > /tmp/empreintes_avant.txt
   ```
4. **Snapshot.**
5. Supprimez les 5 fichiers normalement (`rm`, pas d'effacement
   sécurisé — la suppression normale est le scénario réel : l'espace
   disque est juste marqué libre, le contenu reste physiquement présent
   jusqu'à être écrasé).

### Récupération via la clé SONAR

1. Démarrez sur la clé SONAR → SystemRescue.
2. Lancez `photorec` (ou `testdisk` puis son mode PhotoRec intégré) en
   ciblant la partition de test.
3. **Récupérez vers un AUTRE disque/une autre partition** que la
   source — jamais sur la même partition qu'on est en train de scanner
   (règle de base de la récupération de données, pas spécifique à
   SONAR).
4. Une fois le scan terminé, comparez les fichiers récupérés aux
   originaux :
   ```bash
   sha256sum /chemin/vers/recuperes/* > /tmp/empreintes_apres.txt
   diff /tmp/empreintes_avant.txt /tmp/empreintes_apres.txt
   ```
   (Les noms de fichiers PhotoRec seront différents — comparez les
   empreintes SHA-256 elles-mêmes, pas les noms.)

### À consigner

- Combien de fichiers sur 5 récupérés, avec une empreinte identique à
  l'original (récupération bit-exacte) ?
- Des fichiers partiellement corrompus (récupérés mais empreinte
  différente) ?
- Le format de fichier choisi a-t-il influencé le taux de succès
  (PhotoRec carve mieux certains formats que d'autres) ?
- Temps du scan complet.

---

## Scénario 3 — `malware` : machine infectée nettoyée

**Important** : n'utilisez JAMAIS de malware réel pour ce test, même
sur une VM jetable. Le standard de l'industrie pour tester qu'un
antivirus détecte correctement, sans manipuler de code malveillant
réel, est le [fichier de test EICAR](https://www.eicar.org/download-anti-malware-testfile/)
— une chaîne de caractères inoffensive que tous les moteurs AV
(ClamAV compris) sont conçus pour reconnaître comme "signature de
test".

### Préparation (sur la VM cible)

1. Créez le fichier de test EICAR dans quelques emplacements (racine du
   disque, un sous-dossier, éventuellement renommé avec une extension
   trompeuse type `.exe` ou `.scr` pour simuler un cas un peu moins
   trivial) :
   ```bash
   printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > eicar.com
   ```
2. **Snapshot** (utile si vous voulez répéter avec d'autres emplacements
   ensuite).

### Nettoyage via la clé SONAR

1. Démarrez sur la clé SONAR → SystemRescue.
2. Extrayez ClamAV depuis le paquet `.deb` récupéré par `--fetch`
   (SystemRescue est Arch-based, pas de `dpkg`) :
   ```bash
   cd /chemin/vers/ISO_ou_Portable/Fetched
   mkdir clamav_extracted && cd clamav_extracted
   ar x ../clamav-1.5.4.linux.x86_64.deb
   tar xf data.tar.*
   ```
3. Montez le disque de la VM **en lecture seule d'abord**, cohérent
   avec la discipline "non-destructif par défaut" de SONAR :
   ```bash
   mount -o ro /dev/sdX1 /mnt/cible
   ```
4. Lancez un scan (chemin vers le binaire `clamscan` extrait à l'étape
   2, typiquement sous `usr/bin/clamscan` dans l'arborescence
   extraite) :
   ```bash
   ./usr/bin/clamscan -r /mnt/cible
   ```
   Si les signatures embarquées dans le paquet sont trop anciennes et
   qu'un réseau est disponible sur place, `freshclam` peut les mettre à
   jour avant le scan — notez si vous avez dû le faire.
5. Si détection confirmée et qu'un nettoyage réel était nécessaire
   (pas le cas avec EICAR, qui est inoffensif), remontez en
   lecture-écriture pour la suppression : c'est le moment où la
   discipline de confirmation de SONAR Field (une fois ce second produit
   disponible) prendrait le relais — pour ce test-ci, la détection seule
   suffit à valider le profil.

### À consigner

- L'extraction du `.deb` sans `dpkg` a-t-elle fonctionné sans accroc sur
  SystemRescue ?
- `clamscan` a-t-il détecté tous les fichiers EICAR déposés, y compris
  ceux à extension trompeuse ?
- Fallu mettre à jour les signatures (`freshclam`) pour que la
  détection fonctionne, ou les signatures embarquées suffisaient ?
- Temps du scan sur un disque de taille réaliste.

---

## Bonus — `disk-clone` et `password-reset` (si le temps le permet)

- **`disk-clone`** : clonez une VM de test source vers une VM cible
  vierge avec Clonezilla (menu SystemRescue ou boot direct sur l'ISO
  Clonezilla récupérée par `--fetch`), puis confirmez que la VM cible
  boote et contient les mêmes données (comparaison de quelques
  empreintes SHA-256 comme au scénario 2).
- **`password-reset`** : sur une VM Windows de test avec un compte
  local à mot de passe connu, démarrez sur `cd140201.iso` (chntpw,
  récupéré par `--fetch`), réinitialisez le mot de passe de ce compte,
  confirmez la connexion sans l'ancien mot de passe.

---

## Après les 3 (ou 5) scénarios : rédiger l'entrée CHANGELOG

Gabarit à remplir, cohérent avec le format déjà utilisé dans
`CHANGELOG.md` (`Contexte`/`Testé`, pas de section `Corrigé` s'il n'y a
pas eu de bug de code trouvé pendant les tests — sinon l'ajouter) :

```markdown
## [X.Y.Z-hardware-validation-step6] — <date>

### Contexte
Étape 6/6 du recentrage : validation matérielle des profils sur 3
scénarios réels, protocole détaillé dans docs/VALIDATION-ETAPE6.md.

### Testé
- **boot-repair** : <ce qui a marché / échoué / surpris, chiffres à
  l'appui — ex. "TestDisk a retrouvé la table GPT en recherche rapide,
  ~2 min, VM rebootée normalement ensuite">
- **data-recovery** : <ex. "5/5 fichiers récupérés avec empreinte
  SHA-256 identique à l'original, scan PhotoRec ~4 min sur 20 Go">
- **malware** : <ex. "clamscan a détecté les 3 fichiers EICAR dont
  celui à extension .exe trompeuse, extraction .deb sans dpkg OK,
  signatures embarquées suffisantes sans freshclam">

### Non résolu / surprises
<tout ce qui n'a pas marché comme prévu, même mineur — c'est la partie
la plus utile de cette entrée>
```

Une fois rempli, marquer l'étape 6 `[x]` dans `ROADMAP.md` avec la même
référence de version, et bumper `SONAR_VERSION`.
