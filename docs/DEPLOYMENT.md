# SONAR — Processus de déploiement, du branchement de la clé au résultat final

Ce document décrit, étape par étape, ce qui se passe réellement dans
`sonar_master.sh` lors d'un déploiement — pas une version simplifiée, mais
l'ordre exact des opérations internes (`preflight_final` →
`deploy_single_disk_final`), pour qu'un opérateur sache précisément à quoi
s'attendre et où se trouve chaque garde-fou.

> **Rappel important (voir `ROADMAP.md`, section P0)** : validé sur un
> premier déploiement matériel réel avec boot UEFI + Secure Boot effectif
> (2026-09-14/15) — une seule machine/configuration testée à ce jour, pas
> encore de BIOS legacy ni de second modèle. Le garde-fou de l'étape 6
> continue de s'afficher à chaque déploiement réel, quel que soit
> l'historique de succès précédent.
>
> **Ce que SONAR met sur la clé, et ce qu'il n'y met pas par défaut** :
> le déploiement copie tel quel le contenu de `--source` (voir Étape 0bis
> ci-dessous) — SONAR ne devine pas quels outils vous voulez, il organise
> et trace ce que vous lui donnez. Pour que les profils de dépannage
> (`--profile`) soient réellement utilisables une fois la clé bootée,
> récupérez leurs outils avec `--fetch` **avant** `--disk` (Étape 0bis).

---

## Étape 0 — Avant de brancher quoi que ce soit

1. Vérifiez que `sonar_master.sh` est exécutable :
   ```bash
   chmod +x sonar_master.sh
   ```
2. Activez le filet de sécurité local (une fois par clone du dépôt) :
   ```bash
   git config core.hooksPath hooks/
   ```
3. Si ce n'est pas déjà fait sur cette machine, initialisez le verrou de
   rôle (une seule fois, jamais à refaire ensuite) :
   ```bash
   sudo ./sonar_master.sh --role-bootstrap
   ```
   Ceci crée `Secure/Keys/role_secret.key` (chmod 600). Si vous êtes le
   seul opérateur et restez sur le rôle `Technician` par défaut, cette
   étape n'est pas obligatoire — elle ne devient nécessaire que si vous
   comptez utiliser un rôle élevé (Senior/Forensic/Admin/Expert).
4. Préparez l'arborescence source (`ISO/`, `Portable/`, `Scripts/`,
   `Drivers/`, `macOS/`, `Branding/`) à l'emplacement que vous passerez en
   `--source`. Le script la crée automatiquement si elle n'existe pas
   encore, mais un `ISO/` vide donnera un `--self-test` avec des
   avertissements. `Branding/background.png` (ou `.jpg`/`.jpeg`) est
   optionnel — voir « Personnaliser le fond d'écran Ventoy » plus bas.

---

## Étape 0bis — Récupérer les outils des profils (recommandé)

Sans cette étape, la clé se déploiera normalement mais les profils de
dépannage (`--profile boot-repair`, etc.) resteront vides de tout outil
réellement utilisable sur le terrain — voir `README.md` : "SONAR
construit la clé et trace son origine. Les outils qui dépannent sont
ceux des profils `--profile X`."

1. Une seule fois par machine de build, scellez le manifeste de
   téléchargement (rôle VAULT requis pour la création du scellé) :
   ```bash
   sudo SONAR_ROLE=Vault SONAR_ROLE_TOKEN="<jeton Vault>" \
       ./sonar_master.sh --fetch-manifest-seal
   ```
2. Avant `--disk`, récupérez les outils du ou des profils visés (vers
   votre dossier `--source`, donc **avant** de le passer à `--disk`) :
   ```bash
   SONAR_ROOT=. SOURCE_DIR=./SONAR_SOURCE \
       ./sonar_master.sh --fetch boot-repair
   ```
   Chaque outil est téléchargé, son SHA-256 vérifié contre le manifeste
   scellé (fichier supprimé et commande en échec sur non-correspondance
   — jamais un fichier non vérifié qui traîne), et tracé dans
   `SOURCE_DIR/.../FETCH/MANIFEST_FETCH.tsv` + l'audit. Répétez pour
   chaque profil voulu, ou une seule fois avec `--fetch full` pour tout
   récupérer d'un coup.
3. **Rien d'autre à faire** : les fichiers récupérés atterrissent dans
   `SOURCE_DIR/ISO/Fetched/` ou `SOURCE_DIR/Portable/Fetched/` (selon le
   type), et l'Étape 10 (`copy_payload_final`) copie **tout**
   `SOURCE_DIR/ISO` et `SOURCE_DIR/Portable` récursivement sur la clé —
   aucune étape de déploiement séparée n'est nécessaire pour que
   Ventoy voie ces ISO (son `VTOY_DEFAULT_SEARCH_ROOT` scanne `/ISO`
   récursivement par défaut).

> **Réparation côté Windows (bootrec/bcdedit/DISM)** : nécessite un
> WinPE, que SONAR ne construit pas (outillage Windows ADK, incompatible
> avec ce script Linux+root) — voir [`docs/WINPE.md`](WINPE.md) pour
> pourquoi et comment ajouter le vôtre. Le même mécanisme de copie
> récursive ci-dessus s'applique : déposez votre ISO dans
> `SOURCE_DIR/ISO/WinPE/` avant `--disk`.

---

## Étape 1 — Brancher la clé USB et l'identifier

1. Branchez le périphérique USB.
2. Identifiez-le **précisément** :
   ```bash
   lsblk
   ```
   Notez le nom exact (`/dev/sdb`, `/dev/sdc`, etc.). Une erreur ici est
   irréversible une fois la confirmation d'effacement passée — vérifiez
   deux fois la taille et le nom affichés par `lsblk` avant de continuer.
3. Ne montez pas la clé manuellement — le script gère lui-même le montage
   de la partition Ventoy à chaque étape qui en a besoin
   (`mount_ventoy_final`, points de montage suivis dans
   `SONAR_MOUNTED_PARTS` et démontés automatiquement en cas d'erreur).

---

## Étape 2 — Répétition à blanc obligatoire (`--dry-run`)

**Ne sautez jamais cette étape**, même en confiance. Elle exécute
exactement le même chemin de code que le déploiement réel, sans écrire un
seul octet sur le disque :

```bash
sudo ./sonar_master.sh --disk /dev/sdX --dry-run \
    --source ./SONAR_SOURCE --yes
```

Ce que ça vérifie concrètement : présence de toutes les dépendances système
(`preflight_final`), que le disque ciblé n'est pas le disque système
(comparaison `rootpk`/`targetpk`), la taille minimale (`MIN_DISK_GIB`,
64 Go par défaut, surchageable), et l'enchaînement complet du pipeline sans
erreur de configuration. Si cette étape échoue, **rien** dans les étapes
suivantes ne pourra fonctionner correctement.

---

## Étape 3 — `preflight_final` (démarre au lancement réel)

Dès que vous lancez `--disk /dev/sdX` sans `--dry-run`, voici l'ordre exact
des vérifications, dans le code :

1. **Doit tourner en root** (`sudo`) — sinon arrêt immédiat.
2. **Vérification de toutes les dépendances système** : `awk`, `basename`,
   `blockdev`, `findmnt`, `lsblk`, `mount`, `umount`, `sync`, `dd`,
   `mkfs.ext4`, `sha256sum`, `tar`, `gzip`, `sed`, `grep`, `find`, `sort`,
   `date`, `head`, `python3`, `wget`, `curl`, `cp` — chacune vérifiée
   individuellement, arrêt net et nommé si l'une manque.
3. **Vérification du dossier source** (`--source`), création des
   sous-dossiers manquants (`ISO/Portable/Scripts/Drivers/macOS/Branding`).
4. **Garde-fou anti-disque-système** : compare le disque parent de `/`
   (racine du système en cours d'exécution) au disque ciblé — refus net
   si vous pointez accidentellement sur le disque de démarrage de la
   machine.
5. **Vérification de la taille** : refuse si `< MIN_DISK_GIB` (64 Go par
   défaut).

---

## Étape 4 — Le garde-fou matériel (obligatoire, non-dry-run)

Puisque ce build n'a jamais été validé sur un vrai démarrage physique
(voir l'avertissement en tête de document), le script exige un
acquiescement explicite avant de continuer :

```
==============================================================
[SONAR] AVERTISSEMENT: ce build n'a JAMAIS été validé sur un
[SONAR] démarrage physique réel (Ventoy + BIOS/UEFI). Seule la
[SONAR] logique d'écriture a été testée (--dry-run, /dev/loop).
[SONAR] La clé produite peut échouer à démarrer sur du matériel
[SONAR] réel. Voir ROADMAP.md (section P0).
==============================================================
Tapez exactement: JE COMPRENDS LE RISQUE
```

- **Interactif** : tapez la phrase exacte.
- **Automatisé/scripté** : passez `--accept-hardware-risk` (ou
  `SONAR_HARDWARE_RISK_ACK=true`) — **volontairement indépendant** de
  `--yes` (voir étape 5), pour qu'un script qui passe `--yes` seul ne
  saute pas cet acquiescement précis.

Toute tentative est tracée dans l'audit (`HARDWARE_RISK_ACKNOWLEDGED`,
avec la méthode utilisée).

---

## Étape 5 — Confirmation d'effacement (obligatoire, non-dry-run)

Juste après l'étape 4, sauf si `--yes` a été passé :

```
ATTENTION: /dev/sdX sera ENTIEREMENT EFFACE.
Tapez exactement: EFFACER /dev/sdX
```

Le nom du disque doit être tapé **exactement**, avec le chemin complet
(`/dev/sdX`, pas juste `sdX`). Toute autre réponse arrête le script sans
rien écrire.

---

## Étape 6 — Vérification du rôle (si vous utilisez un rôle élevé)

Si vous êtes sous le rôle par défaut (`Technician`), rien à faire ici —
`Technician` a déjà les droits `DEPLOY` nécessaires.

Si vous voulez opérer sous un rôle élevé (par exemple pour que l'identité
de l'opérateur soit tracée nominativement, ou pour enchaîner ensuite sur
une action Forensic/Admin), fournissez le jeton **avant** de lancer
`--disk` :

```bash
sudo SONAR_ROLE=Admin SONAR_ROLE_TOKEN="<jeton>" \
    ./sonar_master.sh --disk /dev/sdX --source ./SONAR_SOURCE --yes \
    --accept-hardware-risk
```

Sans jeton valide, toute tentative de rôle élevé est automatiquement
rétrogradée vers `Technician` (voir `--help`, section "Verrou de rôle",
pour émettre un jeton avec `--role-issue-token`).

---

## Étape 7 — Espace de travail temporaire

`prepare_workspace` crée un répertoire de travail éphémère :
`/tmp/sonar-deploy-XXXXXX` (nom aléatoire), avec un sous-dossier `ventoy/`
et un fichier de log dédié à ce run (`deploy.log`). Rien n'est encore
écrit sur la clé USB à ce stade.

---

## Étape 8 — Récupération et vérification de Ventoy

`download_ventoy_final` cherche, dans l'ordre :

1. Une archive déjà présente localement dans `<SOURCE>/Ventoy/` ou
   directement dans `<SOURCE>/`.
2. Sinon, télécharge la release officielle GitHub de Ventoy (sauf si
   `--no-ventoy-download` est passé, auquel cas l'absence d'archive locale
   est une erreur fatale).

Dans les deux cas, avant toute utilisation :
- **Vérification SHA-256** contre l'empreinte connue et figée dans le
  script (`VENTOY_SHA256`) — refus net si elle ne correspond pas.
- **Vérification GPG optionnelle** si `--gpg-key`/`--gpg-sig` sont fournis.
- Extraction de l'archive, vérification que `Ventoy2Disk.sh` est bien
  présent et exécutable.

---

## Étape 9 — Écriture réelle sur la clé (première opération destructrice)

`install_ventoy_final` exécute `Ventoy2Disk.sh -I -g -s <DISK>` (mode GPT +
Secure Boot). **C'est la première commande qui écrit réellement sur le
périphérique.** Toutes les vérifications précédentes existent précisément
pour qu'on n'arrive à cette ligne qu'en toute connaissance de cause.

---

## Étape 10 — Copie du contenu

`copy_payload_final` monte la partition Ventoy fraîchement créée, puis
copie :

- `ISO/`, `Portable/`, `Scripts/`, `Drivers/`, `macOS/` depuis votre
  dossier source — **récursivement**, donc `ISO/Fetched/` et
  `Portable/Fetched/` produits par `--fetch` (Étape 0bis) sont inclus
  sans configuration supplémentaire
- Le catalogue d'outils et son index
- **`Scripts/sonar-vault.sh`** — coffre chiffré autonome (gpg AES-256),
  sauf si `--no-veracrypt` a été passé (voir `CHANGELOG.md` v3.9.0 pour
  pourquoi ce n'est pas un vrai VeraCrypt intégré au boot)
- **`MANIFEST/BUILD_WATERMARK.txt`** — filigrane de build signé
  (HMAC-SHA256), horodaté, avec l'identité de l'opérateur si authentifié
  (voir v3.10.0)
- Le fond d'écran Ventoy personnalisé, s'il y en a un — voir ci-dessous.

### Protéger le catalogue contre une reproduction anarchique

Un clone `dd` bit-à-bit de la clé reste toujours possible (media bootable
= lisible par définition) — l'objectif de `--protect-catalog` n'est donc
pas d'empêcher la copie, mais de rendre un clone sans valeur du point de
vue de la curation. Avec `--protect-catalog` (rôle VAULT requis,
`SONAR_PROTECT_PASSPHRASE` en variable d'environnement — **jamais** en
argument) :

```bash
sudo SONAR_ROLE=Admin SONAR_ROLE_TOKEN="<jeton>" \
    SONAR_PROTECT_PASSPHRASE="<mot de passe distribué aux clients légitimes>" \
    ./sonar_master.sh --disk /dev/sdX --source ./SONAR_SOURCE --yes \
    --accept-hardware-risk --protect-catalog
```

`MANIFEST/MANIFEST.tsv` (quel outil, pourquoi, SHA-256 — la vraie curation)
est chiffré en place (gpg AES-256) et le fichier en clair retiré. Sans
effet sur le boot ou le dépannage : ni Ventoy (qui scanne `/ISO`
directement) ni `sonar_field.sh` (qui ne lit que `MANIFEST/PROFILES.tsv`)
n'en dépendent. Se déchiffre sur le terrain avec le coffre déjà déployé :

```bash
Scripts/sonar-vault.sh open MANIFEST/MANIFEST.tsv.gpg MANIFEST/MANIFEST.tsv
```

Ce que ça protège déjà **sans rien activer** : `Secure/Keys/role_secret.key`
n'est jamais copié sur la clé — un clone brut reste bloqué en
Technician/Viewer (lecture/diagnostic), aucune escalade possible vers
Admin/Forensic/VAULT.

### Personnaliser le fond d'écran Ventoy

**Désactivé par défaut depuis le 2026-09-15** (`--ventoy-theme` pour
l'activer explicitement). Ce n'est pas une prudence théorique : sur un
HP EliteBook 840 G3 réel, **trois tailles d'image radicalement
différentes** ont été testées le même jour — 1920×1080 RGB (~6 Mo
décodés), 1024×768 RGB (~2,25 Mo), puis 800×600 en PNG indexé/palette
(~480 Ko, ~12x plus petit que la première) — et **les trois ont produit
exactement le même crash GRUB** (`alloc magic is broken`). Conclusion :
la taille de l'image décodée n'est probablement pas la vraie cause ; le
module thème/gfxmenu de Ventoy lui-même semble incompatible avec ce
firmware, indépendamment de l'image fournie — voir `CHANGELOG.md`
v3.25.0/v3.26.0 pour le détail. Réduire encore l'image ne réglera
vraisemblablement rien. N'activez `--ventoy-theme` qu'après un test réel
sur le matériel cible précis, avec un plan de retour en arrière
(`--no-ventoy-theme` ou édition manuelle de `ventoy/ventoy.json` pour
retirer le bloc `"theme"`, comme documenté dans le CHANGELOG).

Si vous l'activez : déposez votre image dans
`SOURCE_DIR/Branding/background.png` (`.jpg`/`.jpeg` acceptés aussi) avant
de lancer `--disk --ventoy-theme`. `sonar_prepare_ventoy_theme` la reprend
automatiquement :

- Si `convert` (ImageMagick) est installé sur la machine de build, le
  titre et le crédit (`SONAR_VENTOY_TITLE`/`SONAR_VENTOY_CREDIT`,
  personnalisables par variable d'environnement — par défaut
  `SONAR - SE` / `Sekou SANOU - Burkina Faso`) sont incrustés en bas de
  l'image sur un bandeau semi-transparent, puis le résultat est copié vers
  `ventoy/theme/background.png` sur la clé et référencé dans
  `ventoy/ventoy.json` (champs officiels du plugin thème de Ventoy :
  `file`, `gfxmode`, `boot_menu_language`, `ventoy_left/top/color`).
- Sans ImageMagick, l'image est copiée telle quelle (sans texte incrusté)
  — jamais bloquant.
- Sans image dans `Branding/` **et** sans `--ventoy-theme`, rien ne se
  passe — comportement Ventoy par défaut inchangé (c'est maintenant le
  cas de figure par défaut).

---

## Étape 11 — Persistance Ventoy

`create_persistence_final` crée `PERSISTENCE_COUNT` fichiers `env<N>.dat`
(5 par défaut) de `PERSISTENCE_SIZE` Go chacun (8 Go par défaut), formatés
en ext4, dans `persistence/` sur la clé. **Ces fichiers ne sont jamais
chiffrés par SONAR** — c'est un choix délibéré (chiffrer casserait le
montage automatique par Ventoy au démarrage).

---

## Étape 12 — Support macOS et couche IA

- `generate_macos_support_final` : prépare les éléments spécifiques macOS.
- Couche IA (optionnelle, `--ai off|auto|local|online`) : inventaire matériel,
  diagnostic, recommandations, et connexion à un serveur Ollama/LLM local si
  détecté. Toujours strictement consultative — n'exécute jamais rien
  automatiquement, ne modifie aucune décision de déploiement.

---

## Étape 13 — Manifestes et vérification post-déploiement

1. `generate_manifests_final` calcule les empreintes SHA-256 de tout ce
   qui a été copié (`MANIFEST/ISO.sha256`, `MANIFEST/FILES.sha256`).
2. **`sonar_post_deploy_verify_final`** (v3.2.0) relit chaque fichier
   *directement depuis la clé montée* et recompare au SHA-256 attendu —
   au-delà de la simple vérification de structure, ça détecte une
   corruption d'écriture (secteur défaillant, contrôleur USB capricieux)
   avant même de considérer le déploiement terminé.

---

## Étape 14 — README et validation finale

1. `generate_readme_final` dépose un `README.md` sur la clé, résumant sa
   configuration.
2. `validate_final` fait une dernière passe de vérification structurelle.
3. Le script affiche le résumé final : nombre d'avertissements, nombre
   d'erreurs de copie. **S'il y a eu ne serait-ce qu'une erreur de copie,
   le script s'arrête en erreur** — un déploiement incomplet n'est jamais
   présenté comme terminé avec succès.

---

## Étape 15 — Après le déploiement

1. **Démontez proprement** avant de débrancher (le script démonte déjà
   ses propres points de montage à la fin d'un run réussi, mais un
   `sync` manuel supplémentaire ne coûte rien).
2. **Vérifiez le filigrane de build** si vous voulez confirmer plus tard
   qu'une clé donnée provient bien de ce build :
   ```bash
   ./sonar_master.sh --verify-watermark /chemin/vers/clé/montée
   ```
3. **Sur le terrain**, le technicien peut utiliser
   `Scripts/sonar-vault.sh` pour chiffrer/déchiffrer ses propres données
   sensibles — voir `README.md`, section "Coffre chiffré autonome".
4. Si une acquisition forensique a eu lieu à partir de cette clé,
   générez la chaîne de possession :
   ```bash
   ./sonar_master.sh --forensic-chain-of-custody <DOSSIER_PREUVES> "N-DOSSIER"
   ```

---

## Résumé visuel de l'ordre des opérations

```
--fetch <profil> (recommandé, Étape 0bis — récupère les outils dans --source)
    │
    ▼
Brancher USB
    │
    ▼
lsblk (identifier /dev/sdX)
    │
    ▼
--dry-run (répétition à blanc obligatoire)
    │
    ▼
preflight_final
    ├─ root ?
    ├─ dépendances système
    ├─ dossier source valide
    ├─ pas le disque système
    └─ taille suffisante
    │
    ▼
Garde-fou matériel (JE COMPRENDS LE RISQUE / --accept-hardware-risk)
    │
    ▼
Confirmation EFFACER /dev/sdX (sauf --yes)
    │
    ▼
prepare_workspace (répertoire temporaire)
    │
    ▼
download_ventoy_final (local ou téléchargement + SHA-256 + GPG optionnel)
    │
    ▼
install_ventoy_final  ◄── PREMIÈRE ÉCRITURE RÉELLE SUR LE DISQUE
    │
    ▼
copy_payload_final (ISO/Portable/Scripts/Drivers/macOS + vault + thème + watermark)
    │
    ▼
create_persistence_final (persistance ext4, jamais chiffrée)
    │
    ▼
generate_macos_support_final + couche IA (optionnelle, consultative)
    │
    ▼
generate_manifests_final (SHA-256 de tout)
    │
    ▼
sonar_post_deploy_verify_final (relecture + recomparaison depuis la clé)
    │
    ▼
generate_readme_final + validate_final
    │
    ▼
Résumé final (0 erreur de copie = succès)
    │
    ▼
Démontage, vérification du filigrane, usage terrain (coffre, CoC forensique)
```
