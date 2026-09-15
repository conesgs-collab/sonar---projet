# Changelog — SONAR

Format inspiré de [Keep a Changelog](https://keepachangelog.com/). Ce fichier
est la version lisible de l'historique qui vivait jusqu'ici dans l'en-tête de
`sonar_master.sh`. À partir de maintenant, tout changement notable est décrit
ici ET dans un commit Git séparé — le script n'a plus besoin de porter tout
son propre historique en commentaire.

## [3.17.0-boot-env-step3] — 2026-09-15

### Contexte
Étape 3/6 du recentrage : "intégrer SystemRescue par défaut dans les
profils `boot-repair` et `disk-clone`". En creusant, deux choses très
différentes se cachaient derrière cette phrase — l'une déjà faite sans
le savoir, l'autre une vraie réserve de sécurité laissée ouverte au
commit précédent.

### Trouvé (pas un bug — une vérification de ce qui existait déjà)
- **L'intégration "par défaut" ne demandait aucun nouveau code.**
  `copy_payload_final` (Étape 10 du déploiement) copie déjà
  `SOURCE_DIR/ISO` vers la clé avec `cp -a` (récursif), et le
  `ventoy.json` généré par `generate_ventoy_json_final` fixe déjà
  `VTOY_DEFAULT_SEARCH_ROOT` sur `/ISO` — que Ventoy scanne
  récursivement par défaut. Conséquence directe : tout fichier déposé
  par `--fetch boot-repair` (ou `disk-clone`) dans `ISO/Fetched/`
  atterrit sur la clé et devient une entrée de boot Ventoy sans code de
  "câblage" supplémentaire entre `--fetch` et `--disk`. Vérifié en
  lisant le pipeline existant, pas supposé.
- Décision délibérée de **ne pas** faire déclencher `--fetch`
  automatiquement par `--disk` : `--disk` reste utilisable hors-ligne
  par défaut (cohérent avec `--catalog-download`/`--ai-download`, déjà
  des commandes séparées) — un déploiement ne doit jamais lancer un
  téléchargement réseau à l'insu de l'opérateur.

### Corrigé — vraie réserve de sécurité fermée
- **Signature GPG de SystemRescue vérifiée en direct sur l'ISO
  complète** (1,3 Go, pas seulement sur le fichier `.sha256` comme au
  commit v3.16.0, qui documentait explicitement cette limite). Téléchargé
  intégralement, SHA-256 recontrôlé (identique à la valeur figée dans
  `SONAR_FETCH_MANIFEST_TSV`), signature `.asc` vérifiée contre la clé
  publique officielle (Francois Dupoux, fingerprint `0FF1 1AF0 81E9
  8345 5948 1203 7091 115F 8320 B897`) : `gpg: Good signature`. Les
  deux méthodes de vérification (SHA-256 vendeur + GPG) concordent —
  colonne `NOTES` de l'entrée `SystemRescue` mise à jour en conséquence.

### Ajouté (documentation)
- **`docs/DEPLOYMENT.md`** : nouvelle "Étape 0bis — Récupérer les
  outils des profils", qui explique concrètement le fonctionnement
  ci-dessus (`--fetch-manifest-seal` une fois, puis `--fetch <profil>`
  avant `--disk`) et pourquoi aucune étape de déploiement séparée n'est
  nécessaire. Bandeau d'avertissement en tête de document corrigé (il
  affirmait encore "jamais testé sur boot réel", obsolète depuis
  v3.11.2/v3.12.0) et complété avec la même formule de périmètre que
  `README.md`.

### Non fait dans cette version (volontairement)
- **Étape 4** (WinPE/ADK), **étape 6** (validation matérielle des
  profils) : pas commencées. **Étapes 5 et 7** : reclassées "SONAR
  Field" (second produit, voir ROADMAP.md et le commit dd0aadb) —
  n'appartiennent plus au plan de SONAR lui-même.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit`,
`--self-test` (0 FAIL) sous WSL2 Ubuntu. Vérification SHA-256 + GPG de
SystemRescue effectuée sur un téléchargement réel et complet de l'ISO
(pas simulée, pas déduite) — voir ci-dessus pour l'empreinte de clé et
le résultat exact de `gpg --verify`.

## [3.16.0-fetch-step2] — 2026-09-15

### Contexte
Étape 2/6 du recentrage (voir v3.15.0 et `ROADMAP.md`, section P0bis) :
les profils de dépannage existaient déjà (`--profile`) mais rien ne
pouvait encore récupérer réellement les outils qu'ils citent. Exigence
explicite de l'auteur : "un manifeste non signé est une porte ouverte"
— le SHA-256 attendu de chaque outil doit être vérifié contre un
manifeste lui-même protégé (GPG ou HMAC via le secret de build), pas
juste codé en dur sans garantie.

### Ajouté
- **`--fetch <profil>`** : télécharge chaque outil unique du profil
  (déduplication déjà faite par `sonar_profile_tools`), vérifie son
  SHA-256 contre `SONAR_FETCH_MANIFEST_TSV`, **supprime le fichier et
  refuse sur non-correspondance**, journalise systématiquement
  (`sonar_audit`, hashchainé) et écrit un rapport
  `SOURCE_DIR/.../FETCH/MANIFEST_FETCH.tsv` (outil, URL, SHA-256,
  horodatage, destination). Un outil sans entrée manifeste (ex.
  `GParted`, bundlé dans l'ISO SystemRescue, pas téléchargé seul) est
  signalé et sauté proprement, pas traité en échec.
- **`--fetch-manifest-seal`** (rôle VAULT) et
  **`--fetch-manifest-verify-seal`** : scelle/vérifie
  `SONAR_FETCH_MANIFEST_TSV` par HMAC-SHA256 (secret de build existant,
  `sonar_hmac_sha256_file` — même mécanisme que le filigrane de build et
  la révocation de jeton, pas un nouveau système de signature). `--fetch`
  refuse de fonctionner tant que ce scellé n'existe pas ou ne correspond
  plus au manifeste embarqué — seule la **création** du scellé exige le
  rôle VAULT, sa **vérification** (lecture) n'exige aucun rôle, comme
  `--verify-manifest`.
- **Manifeste initial, 6 outils, chacun vérifié individuellement avant
  d'être figé** (pas de valeur inventée — voir méthode par outil) :
  - **SystemRescue** 13.02 — SHA-256 récupéré directement depuis le
    fichier `.sha256` officiel (HTTPS, system-rescue.org) ; signature
    GPG `.asc` disponible mais pas re-vérifiée cette session (ISO
    ~1,3 Go, transfert jugé disproportionné pour ce qu'apporterait une
    double vérification quand le SHA-256 vient déjà du vendeur).
  - **TestDisk/PhotoRec** 7.2 (cgsecurity.org, couvre les deux outils
    dans la même archive) — aucun `.sha256`/`.sig` publié par le
    fournisseur ; SHA-256 calculé localement après téléchargement HTTPS
    depuis le domaine officiel (assurance équivalente à ce qu'un
    opérateur humain obtiendrait en téléchargeant manuellement).
  - **ddrescue** 1.30 (GNU) — signature GPG **vérifiée en direct**
    cette session (clé Antonio Diaz, via `gnu-keyring.gpg` officiel de
    gnu.org) : `gpg: Good signature from "Antonio Diaz"`.
  - **ClamAV** 1.5.4 (`.deb`, pas de tarball portable — corrigé après
    recherche initiale erronée) — signature GPG **vérifiée en direct**
    cette session (clé Cisco Talos, via le fichier officiel du dépôt
    `Cisco-Talos/clamav-documentation`) : `gpg: Good signature from
    "Talos (Talos, Cisco Systems Inc.)"`. Extraction sans `dpkg` : `ar x
    clamav*.deb && tar xf data.tar.*` (fonctionne sur SystemRescue/Arch).
  - **Clonezilla** 3.3.3-15 — SHA-256 et signature GPG (clé DRBL)
    **vérifiés en direct** via `CHECKSUMS.TXT`/`CHECKSUMS.TXT.gpg`
    servis par clonezilla.org (pas SourceForge, où seule l'ISO elle-même
    est hébergée) : `gpg: Good signature from "DRBL Project"`.
  - **chntpw** cd140201 — **assurance la plus faible du manifeste,
    signalée explicitement dans la colonne NOTES** : source officielle
    (pogostick.net) en HTTP seul, sans TLS, et sans SHA-256/GPG publiés
    — seul un MD5 est fourni. MD5 recoupé (correspond) lors de la
    constitution de ce manifeste ; SHA-256 calculé localement. Retenu
    quand même faute d'alternative libre équivalente pour cette
    fonction précise (reset de mot de passe Windows hors-ligne).
- Quatre tests de régression `--self-test`, tous hors-réseau : présence
  du module, `--fetch` refuse effectivement sur un manifeste non scellé
  (vérifié par le code de retour ET l'absence de toute tentative de
  téléchargement dans la sortie), le cycle scellement/vérification
  fonctionne avec un rôle VAULT valide, et
  `sonar_fetch_sha256_matches` accepte le bon SHA-256 et rejette un
  SHA-256 incorrect.

### Corrigé (trouvé pendant la vérification manuelle des outils)
- Recherche initiale (avant ce commit) supposait un tarball ClamAV
  portable (`clamav-*.linux.x86_64.tar.gz`) — n'existe pas réellement,
  seuls `.deb`/`.rpm` sont publiés. Corrigé avant d'écrire une URL
  fausse dans le manifeste.
- Deux itérations sur le test `--self-test` "refuse sur manifeste non
  scellé" : la première version cherchait la sous-chaîne
  `Téléchargement` (insensible à la casse) dans la sortie pour prouver
  qu'aucun téléchargement n'avait été tenté, mais cette sous-chaîne
  apparaît aussi, en minuscule, dans le message de refus lui-même
  ("manifeste de **téléchargement** non scellé") — faux négatif.
  Corrigé pour vérifier le code de retour ET la présence littérale de
  `Téléchargement: ` (avec les deux-points), qui n'apparaît que dans la
  ligne de tentative de téléchargement réelle.
- Premier essai de `sonar_fetch_manifest_seal` renvoyait vers
  `--role-bootstrap` en cas de secret de build absent — message
  trompeur (`--role-bootstrap` initialise le secret des **jetons de
  rôle**, pas le secret de **build**, qui a son propre mécanisme
  transparent `sonar_ensure_build_secret`, déjà utilisé par le
  filigrane de build). Corrigé pour appeler `sonar_ensure_build_secret`
  directement, cohérent avec le reste du script.

### Non fait dans cette version (volontairement)
- **Étape 3** (SystemRescue embarqué par défaut dans les profils
  `boot-repair`/`disk-clone`), **étape 4** (WinPE/ADK), **étape 5**
  (menu orienté tâche), **étape 6** (validation matérielle des
  profils) : pas commencées, voir `ROADMAP.md`.
- `--fetch` ne re-vérifie pas les signatures GPG amont à chaque
  exécution (seulement le SHA-256 qu'il gate réellement) — les
  vérifications GPG ci-dessus ont eu lieu une fois, à la constitution
  de ce manifeste. Documenté explicitement en tête de la section
  `SONAR FETCH V1` dans `sonar_master.sh` pour que ça reste clair au
  prochain outil ajouté au manifeste.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit`,
`--self-test` (0 FAIL) sous WSL2 Ubuntu (Python réel). **Test de bout
en bout en conditions réelles** (pas seulement les chemins hors-réseau
du self-test) : `--role-bootstrap` → `--fetch-manifest-seal` (rôle
VAULT) → `--fetch password-reset` → téléchargement réel de
`cd140201.zip` (16,53 Mo) depuis pogostick.net, SHA-256 vérifié
conforme à la valeur figée dans le manifeste, entrée écrite dans
`MANIFEST_FETCH.tsv` et dans le hashchain d'audit. Chacune des 6
signatures/checksums du manifeste a été vérifiée individuellement avant
d'être figée (détail ci-dessus) — aucune valeur de ce manifeste n'a été
inventée ou recopiée sans contrôle direct.

## [3.15.0-profiles-step1] — 2026-09-15

### Contexte
Recentrage stratégique demandé explicitement : SONAR a grandi en surface
(catalogue de 981 outils, couche IA, smart advisor, profil builder) sans
grandir en profondeur (les outils qui dépannent réellement une machine).
Sur les quatre étapes d'une vraie boîte à outils de dépannage —
1) savoir quoi inclure, 2) l'acquérir et le vérifier, 3) l'organiser sur
la clé, 4) prouver ce qui s'y trouve — SONAR était fort sur (3), avait un
peu de (4), et ne faisait **rien** pour (1) et (2). Le catalogue de 981
outils documentait l'écosystème sans jamais dire ce qui allait
réellement sur la clé, et rien ne le téléchargeait de façon ciblée et
vérifiée.

Cette version est l'**étape 1** d'un plan en 6 étapes (voir
`ROADMAP.md`) : remplacer le catalogue comme source de vérité du
déploiement par un petit nombre de profils de dépannage fermés,
documentés, testés. Un commit par étape, comme demandé — celui-ci ne
touche qu'à l'étape 1 (curation), pas au téléchargement (étape 2,
`--fetch`, pas encore implémenté) ni à quoi que ce soit d'autre. Résisté
à la tentation d'élargir.

### Ajouté
- **`--profile [NOM|list]`** : six profils fermés et documentés —
  `boot-repair`, `data-recovery`, `malware`, `disk-clone`,
  `password-reset`, `full` (union des cinq précédents). Pour chacun :
  scénario concret, liste d'outils, et **pourquoi** ceux-là précisément
  (voir `SONAR_PROFILES_TSV` dans `sonar_master.sh`, ou
  `docs/CATALOG.md`). Tous les outils choisis sont librement
  téléchargeables et redistribuables (pas de compte, pas de licence
  commerciale) — condition nécessaire pour que l'étape 2 (`--fetch`)
  puisse les récupérer sans jamais demander d'identifiants tiers.
  Plusieurs des outils cités initialement par l'auteur en exemple
  (R-Studio Portable, Macrium Reflect, EasyUEFI, Malwarebytes, ESET
  Online Scanner) ont été substitués par des équivalents libres pour
  cette raison : SystemRescue (regroupe GParted/TestDisk/ddrescue/ClamAV
  dans un seul support Linux maintenu), TestDisk+PhotoRec
  (cgsecurity.org), GNU ddrescue, ClamAV, Clonezilla, GParted Live,
  chntpw.
- Trois tests de régression `--self-test` : les six profils se
  documentent sans erreur, un nom de profil inconnu est rejeté, et le
  profil `full` contient bien l'union des outils des cinq autres
  (vérifié via la présence de SystemRescue, ClamAV et chntpw dans sa
  sortie).

### Changé (gel, rien de supprimé)
- **Catalogue embarqué (981 outils, `SONAR_CATALOGUE_EMBEDDED`)** :
  gelé comme base de connaissance consultable. `docs/CATALOG.md` et
  `README.md` reformulés pour le dire explicitement — ce catalogue ne
  décide plus de ce qui va sur la clé, les profils `--profile` le
  font. Rien n'est supprimé : `--catalog-download*`,
  `--catalog-seal`/`--catalog-verify-seal` restent fonctionnels.
- **Couche IA (`--ai`, `--ai-download`, `--ollama-audit`, etc.)** et
  **`--smart-advisor`/`--mission-report`** : marqués `[EXPÉRIMENTAL]`
  dans `--help`, sans changement de comportement — gelés, pas
  développés davantage tant que les étapes 1-3 ne sont pas terminées.
- **`--builder [PROFILE]`** (profils MINIMAL/TECHNICIAN/RECOVERY/
  FORENSIC/ADMIN/FULL/CUSTOM) : marqué `[EXPÉRIMENTAL/GELÉ]` dans
  `--help` — concept distinct des nouveaux profils de dépannage
  `--profile`, à ne pas confondre. Ce qu'il construisait avant reste
  disponible, juste plus la direction du projet.
- `README.md` : bandeau de statut corrigé (le déploiement matériel réel
  a depuis réussi — voir v3.11.2/v3.12.0 — l'ancien texte affirmait
  encore "jamais testé sur boot réel") et nouvelle formule explicite :
  *"SONAR construit la clé et trace son origine. Les outils qui
  dépannent sont ceux des profils --profile X. SONAR ne répare rien
  lui-même."*

### Non fait dans cette version (volontairement)
- **Étape 2 (`--fetch`, téléchargement vérifié par manifeste signé
  GPG/HMAC)** : pas commencée. Les URLs/checksums réels des outils
  ci-dessus ont été identifiés par recherche (SystemRescue publie un
  `.sha256` et un `.asc` GPG ; ClamAV publie un `.sig` ; TestDisk/
  PhotoRec sont livrés dans la même archive cgsecurity.org) mais ne
  sont pas encore encodés dans le script — les coder maintenant sans
  les vérifier un par un serait risquer un manifeste signé mais faux,
  pire qu'un manifeste absent.
- **Étapes 3 à 6** (SystemRescue embarqué par défaut, WinPE/ADK, menu
  orienté tâche, validation matérielle des profils) : pas commencées,
  voir `ROADMAP.md`.

### Testé
`bash -n`, `shellcheck --severity=error` (rien, binaire statique
koalaman/shellcheck v0.10.0 — `apt`/`shellcheck` indisponible sans sudo
interactif dans cette session WSL), `--self-audit`, `--self-test`
(0 FAIL, warnings inchangés) — exécutés sous WSL2 Ubuntu (Python réel,
pas le stub WindowsApps). Les six profils vérifiés manuellement en plus
des tests automatisés (`--profile list`, `--profile boot-repair`,
`--profile bogus` pour confirmer le rejet).

## [3.14.0-rbac-security-audit] — 2026-09-15

### Contexte
Revue de sécurité adversariale ciblée sur le module RBAC/verrou de rôle
et la chaîne de signature — le point que le ROADMAP réserve depuis le
début à un "audit de sécurité externe". Pas un substitut à cet audit
(qui demande un regard extérieur par nature), mais une passe sérieuse,
en pensant activement comme un attaquant local, sur exactement le
périmètre que cet audit devra couvrir. Deux failles réelles trouvées et
corrigées, toutes deux dans le modèle de menace que le projet définit
lui-même ("auto-escalade de privilège occasionnelle" par un opérateur
au même niveau OS, pas un attaquant réseau).

### Corrigé
- **Secret HMAC exposé en clair dans la liste des processus** —
  `sonar_role_sign`/`sonar_build_sign` appelaient
  `openssl dgst -sha256 -hmac "$secret"`, qui place le secret
  directement sur la ligne de commande du processus, lisible par
  n'importe quel processus/utilisateur local via `ps`/
  `/proc/<pid>/cmdline` pendant la (brève mais réelle) fenêtre
  d'exécution d'openssl. Un attaquant local captant ce secret pourrait
  ensuite forger n'importe quel jeton de rôle (y compris Admin) ou
  filigrane de build à volonté. Corrigé avec un nouvel helper partagé
  `sonar_hmac_sha256_file` (Python `hmac`/`hashlib`, déjà une dépendance
  dure du script) : seul le **chemin** du fichier secret traverse
  l'argv, jamais ses octets — Python lit le secret lui-même via
  `open()`. `sonar_require_openssl` supprimée (devenue orpheline, plus
  aucun appelant).
- **`--role-revoke-token` sans aucun contrôle de rôle** — n'importe quel
  Technician non authentifié (libre-service, aucun jeton) pouvait
  révoquer le jeton de **n'importe quel autre opérateur** (Admin,
  Forensic, Senior, Expert), parce que `sonar_role_token_id` ne
  nécessite que l'identité/rôle/expiration en clair du jeton (pas sa
  signature) — et ces trois champs sont justement ceux que
  `ROLE_TOKEN_ISSUED` écrit en clair dans `audit.log`. Un vrai déni de
  service contre des opérateurs élevés légitimes. Corrigé : la
  révocation exige désormais un rôle non-libre-service (via
  `sonar_role_is_self_service`, pas une des colonnes déjà appliquées
  (AUDIT/DEPLOY/VAULT) — aucune des trois n'exclut Technician dans
  `policy.tsv`, elles n'auraient donc rien bloqué).
- Bug cosmétique trouvé au passage dans `--self-test` : deux lignes
  utilisaient `echo 'PASS\t...'` (échec silencieux d'interprétation de
  l'échappement, `\t` littéral) au lieu de `printf '...\t...\n'` comme
  les ~40 autres lignes PASS/FAIL/WARN du fichier — corrigé pour rester
  cohérent avec le format tabulé.

### Ajouté
- Nouveau test de régression `--self-test` : confirme qu'une tentative
  de révocation non authentifiée échoue et que le jeton visé reste
  valide — couvre directement la faille ci-dessus pour l'avenir.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit` (14/14),
`--self-test` (0 FAIL, y compris le nouveau test de régression) — validé
en conditions réelles (WSL2 Ubuntu 26.04, Python réel), pas seulement en
isolation. Vérifié explicitement que le nouveau mécanisme HMAC produit
des jetons et filigranes qui se signent et se vérifient correctement
(pas seulement que le code s'exécute sans erreur).


### Contexte
L'auteur pensait que le catalogue de référence (981 outils/73 domaines,
`docs/CATALOG.md`) déclenchait un téléchargement automatique — ce n'est
explicitement pas le cas (voir la note "Ce que ce catalogue est — et
n'est pas" dans ce même document). Décision, après clarification : au
lieu du pipeline IA existant (`--ollama-audit`/`--ai-download`, qui
demande Ollama et reste "best-effort"), construire un second chemin
sans IA, basé sur le gestionnaire de paquets `apt` — le seul qui ait du
sens à intégrer directement dans le script, puisque `preflight_final`
exige déjà que `sonar_master.sh` tourne en root sous Linux (un
équivalent winget/chocolatey ne s'exécuterait jamais dans ce contexte).

### Ajouté
- **`--catalog-download-resolve`** : fait correspondre chaque cellule
  NAME du catalogue (éclatée sur les virgules — beaucoup de cellules
  listent plusieurs outils, ex. "Ubuntu, Debian, Fedora...") aux paquets
  `apt` réellement disponibles (`apt-cache pkgnames`), plus une petite
  table d'alias pour les cas connus où le nom diffère (VS Code → `code`,
  7-Zip → `p7zip-full`, Docker → `docker.io`...). Écrit un rapport complet
  DOMAIN/CATALOG_NAME/APT_PACKAGE/STATUS — aucun téléchargement.
- **`--catalog-download-dry-run`** / **`--catalog-download`** : résout
  puis télécharge (sans installer, `apt-get download`) chaque paquet
  résolu vers `SOURCE_DIR/Portable/AptPackages`.
- Pas d'IA, pas d'URL codée en dur à maintenir — la correspondance se
  fait sur l'index apt local, donc elle reste juste aussi longtemps que
  l'index l'est, sans intervention.

### Couverture — testé en conditions réelles (WSL2 Ubuntu 26.04)
- **258/1003 entrées catalogue résolues** (~26 %) → **187 paquets apt
  uniques téléchargés, 0 échec, 696 Mo** — y compris des outils des
  domaines ajoutés récemment (`adb` pour la téléphonie mobile, `autopsy`
  pour le forensique).
- La couverture partielle est **attendue, pas un défaut** : une grande
  partie du catalogue est du commercial/sous licence (Adobe, JetBrains,
  Cellebrite UFED...) ou des fonctionnalités intégrées à l'OS plutôt que
  des téléchargements discrets (Active Directory, PowerShell...) — rien
  ne peut légalement ou techniquement les récupérer automatiquement,
  quelle que soit la méthode. Le rapport de résolution nomme chaque
  entrée non résolue, donc l'écart reste visible plutôt que masqué.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit` (14/14),
`--self-test` (0 FAIL). Pipeline complet validé en conditions réelles
(pas seulement en isolation) : résolution + téléchargement effectif de
187 paquets sans échec.

## [3.12.0-first-successful-boot] — 2026-09-15

### Contexte
**Premier démarrage physique réussi de SONAR, de bout en bout** — HP
EliteBook 840 G3, SSD externe USB (Realtek RTL9210 NVMe), Secure Boot
activé. Ventoy affiche son menu, Alpine Linux démarre et se connecte
(`root`, mot de passe vide — comportement standard d'Alpine en live boot,
rien à voir avec SONAR). Le P0 "validation matérielle réelle" du
ROADMAP passe enfin du déploiement seul au boot effectif.

Le chemin pour y arriver a traversé plusieurs diagnostics, dans l'ordre :
1. **Secure Boot (0x1A Security Violation)** — résolu par l'enrôlement
   MOK (`ENROLL_THIS_KEY_IN_MOKMANAGER.cer` sur la partition VTOYEFI,
   procédure standard Ventoy, indépendante du mot de passe BIOS).
2. **Détection USB instable en pré-boot** — un cycle démarrage à froid
   (extinction complète, pas juste redémarrage) a résolu la non-détection
   intermittente du pont USB-NVMe par le firmware.
3. **`alloc magic is broken` (crash GRUB)** — voir "Corrigé" ci-dessous,
   c'est le vrai bug SONAR trouvé dans ce lot.

### Corrigé
- **Le fond d'écran Ventoy personnalisé (v3.11.0/3.11.1) faisait planter
  GRUB avant même l'affichage du menu**, avec l'erreur interne
  `alloc magic is broken` (corruption du tas mémoire de GRUB — son
  propre décodeur PNG s'exécute dans la mémoire très contrainte du
  pré-boot, et une image 1920×1080 24bpp (~6 Mo une fois décodée) a
  suffi à le faire échouer sur ce matériel). Confirmé par test A/B en
  direct sur la clé : désactiver le thème (`ventoy.json` sans le bloc
  `"theme"`) a immédiatement débloqué le boot.
  - `Branding/default_background.png` régénéré à **1024×768** (résolution
    VESA classique, sûre en pré-boot) au lieu de 1920×1080 — fichier
    divisé par ~2 (139 Ko → 65 Ko), mémoire décodée divisée par ~2,6.
    Visuel aussi redessiné à la demande de l'auteur : un écran radar/
    sonar vert classique (balayage, anneaux de portée, graduations en
    degrés, quelques échos cibles) — plus cohérent avec le nom du projet
    que le premier essai (dashboard mondial). Toujours généré via Python/
    Pillow pour la même raison que la v3.11.1 : impossible d'extraire les
    octets d'une image collée dans la conversation, donc recréation dans
    l'esprit demandé plutôt qu'une reproduction exacte (32 Ko, 1024×768).
  - `sonar_prepare_ventoy_theme()` : quand ImageMagick est disponible,
    l'image fournie par l'opérateur est maintenant systématiquement
    redimensionnée à `1024x768>` (réduit seulement si plus grand, jamais
    agrandi) avant l'incrustation du titre/crédit — protège aussi les
    futures images personnalisées, pas seulement celle livrée par défaut.
  - `generate_ventoy_json_final` : `gfxmode` par défaut passé de
    `"1920x1080,1024x768,800x600"` à `"1024x768,800x600"`, cohérent avec
    la résolution que le thème cible désormais.
  - Sans ImageMagick (pas de redimensionnement possible), le message de
    log avertit désormais explicitement du risque avec cette référence
    matérielle précise, au lieu de rester silencieux sur le danger.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit` (14/14),
`--self-test` (0 FAIL). Logique de redimensionnement à deux étapes
(resize puis composite, mesure de largeur post-resize) validée en
isolation. **Root cause confirmée en conditions réelles** (test A/B
thème activé/désactivé sur le matériel qui a révélé le bug) — pas
seulement une correction théorique.

## [3.11.2-first-hardware-deploy-fixes] — 2026-09-14

### Contexte
**Premier vrai déploiement `--disk` sur matériel physique** (SSD externe
USB, via WSL2 + passthrough disque brut). Ventoy2Disk.sh a réussi du
premier coup ("Install Ventoy to /dev/sdd successfully finished") — un
vrai jalon, le P0 du ROADMAP le marquait "jamais testé" depuis le début.
Deux bugs réels trouvés dans la foulée, uniquement visibles sur du vrai
matériel (jamais reproductibles en `--dry-run` ni en `--self-test`).

### Corrigé
- **`AI_PROVIDER: unbound variable`** — crash immédiat sous `set -u`.
  `install_ai_layer_final()` lisait `AI_PROVIDER` avant que
  `run_ai_final()` (seul appelant de `ai_detect_provider()`, qui
  l'initialise) n'ait jamais tourné — ordre d'appel inversé dans
  `deploy_single_disk_final`. Le crash survenait systématiquement, sur
  tout déploiement réel non-dry-run. Corrigé sur deux niveaux : valeur
  par défaut (`AI_PROVIDER="${AI_PROVIDER:-none}"`, jamais réellement
  non définie quel que soit l'ordre d'appel futur) et réordonnancement
  (`ai_detect_provider` appelée avant `install_ai_layer_final`, pour que
  `AI_CONFIG.tsv` reflète le fournisseur réellement détecté, pas
  toujours "none").
- **`cp -a` échoue systématiquement sur la partition exFAT de Ventoy** —
  `cp: failed to preserve ownership ... Operation not permitted` sur
  chaque dossier copié (ISO/Portable/Scripts/Drivers/macOS), qu'exFAT ne
  peut par nature pas représenter (pas de notion d'uid/gid). `cp` retourne
  un code non-nul malgré un contenu copié intégralement, et
  `copy_tree_final` interprétait ça à tort comme une copie incomplète
  (`COPY_ERRORS` incrémenté) — sur un vrai déploiement avec du contenu
  dans `SOURCE_DIR`, ça aurait fait échouer `validate_final` même sans le
  crash IA. Corrigé avec `cp -a --no-preserve=ownership`, qui garde le
  reste du mode archive (récursivité, horodatage, liens) et ne renonce
  qu'à l'attribut qu'exFAT ne peut de toute façon pas porter.

### Non corrigé (risque apparenté, pas de preuve)
`sonar_backup_execute`/`sonar_forensic_acquire` utilisent aussi `cp -a`
vers une destination choisie par l'opérateur — si elle est exFAT/FAT/NTFS,
même faux-positif possible. Laissé tel quel : contrairement au cas
Ventoy, la destination peut être un vrai système de fichiers POSIX où
préserver l'ownership a une vraie valeur (fidélité forensique). Corriger
sans preuve concrète aurait dégradé ce que ces fonctions font de mieux
ailleurs — à confirmer par un test réel avant de toucher au code, même
logique que le revert FORENSIC de la v3.10.3.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit` (14/14),
`--self-test` (0 FAIL). **Confirmé sur vrai matériel** : après ces deux
correctifs, run complet rejoué de bout en bout sur le même SSD externe —
`0 avertissement(s), 0 erreur(s) de copie`, vérification post-déploiement
OK (5 fichiers relus et confirmés), validation structurelle OK,
`SONAR MASTER — TERMINÉ`. Débit observé : 243–476 MB/s en écriture selon
les images de persistance. Boot effectif de la clé pas encore testé
(prochaine étape, voir ROADMAP.md).

## [3.11.1-ventoy-default-background] — 2026-09-14

### Contexte
Suite à v3.11.0 : l'auteur a fourni un visuel de référence (dashboard
sombre façon carte du monde/instrument radar) directement dans la
conversation, sans possibilité pour moi de récupérer les octets de
l'image (aucun outil ne me permet de sauvegarder une image collée dans
le chat vers un fichier). Plutôt que bloquer sur cette limite, génération
d'un fond par défaut dans le même esprit (Python/Pillow), livré tel
quel avec le dépôt.

### Ajouté
- **`Branding/default_background.png`** (1920x1080) — premier et seul
  actif binaire du dépôt (le script lui-même reste texte pur,
  auto-vérifiable ; ceci est un fond d'écran GRUB inerte, pas du code).
  Anneaux façon radar, nœuds lumineux reliés (thème réseau/monde),
  bandeau semi-transparent en bas avec « SONAR - SE » et « Sékou SANOU —
  Burkina Faso » déjà incrustés à la génération.
- `sonar_prepare_ventoy_theme` : deuxième source, utilisée quand
  l'opérateur n'a rien fourni dans `SOURCE_DIR/Branding/` — copie ce
  fichier tel quel (déjà finalisé, pas de retraitement ImageMagick).
  L'image fournie par l'opérateur reste toujours prioritaire si présente.

### Limite assumée
Ce n'est **pas** une reproduction du visuel montré par l'auteur — une
recréation dans le même esprit, avec les outils réellement disponibles.
Si l'auteur enregistre son image d'origine dans
`SOURCE_DIR/Branding/background.png`, elle prend le dessus automatiquement
sans aucun changement de configuration.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit` (14/14),
`--self-test` (0 FAIL). Chemin de repli vers l'image par défaut du dépôt
validé en isolation (copie verbatim, sans retraitement).
son propre historique en commentaire.

## [3.11.0-ventoy-branding] — 2026-09-14

### Contexte
À la demande de l'auteur : personnaliser le fond d'écran du menu de
démarrage Ventoy avec un visuel fourni, et y faire apparaître le nom du
projet (« SONAR - SE ») et le crédit développeur (Sékou SANOU — Burkina
Faso).

### Ajouté
- **`sonar_prepare_ventoy_theme(MOUNTPOINT)`** — nouvelle fonction,
  appelée depuis `copy_payload_final` juste avant
  `generate_ventoy_json_final`. Cherche
  `SOURCE_DIR/Branding/background.{png,jpg,jpeg}` (fourni localement par
  l'opérateur — jamais embarqué en binaire dans ce script ou son
  historique Git, même logique que l'archive Ventoy elle-même) :
  - Absent → ne fait rien, comportement Ventoy par défaut inchangé.
  - Présent + `convert` (ImageMagick) disponible sur la machine de build →
    incruste `SONAR_VENTOY_TITLE`/`SONAR_VENTOY_CREDIT` (variables
    d'environnement, défaut `SONAR - SE` / `Sekou SANOU - Burkina Faso`)
    sur un bandeau semi-transparent en bas de l'image, copie le résultat
    vers `ventoy/theme/background.png` sur la clé.
  - Présent + `convert` absent ou échoue → copie l'image telle quelle
    (sans texte), journalise une note. Jamais bloquant : GRUB n'a de toute
    façon aucune notion de « texte à superposer » via `ventoy.json` — le
    titre/crédit ne peuvent exister que comme pixels de l'image elle-même,
    donc dans le pire cas on perd juste l'incrustation, jamais le build.
- `generate_ventoy_json_final` : ajoute désormais un bloc `"theme"` à
  `ventoy.json` si `ventoy/theme/background.png` existe — clés officielles
  du plugin thème Ventoy (`file`, `gfxmode`, `boot_menu_language`,
  `ventoy_left`, `ventoy_top`, `ventoy_color`).
- `--no-ventoy-theme` : nouveau flag pour désactiver complètement l'étape
  (cohérent avec `--no-veracrypt`/`--no-logging`/`--no-readme`).
- `SOURCE_DIR/Branding/` ajouté à la création automatique des
  sous-dossiers source (comme ISO/Portable/Scripts/Drivers/macOS).
- `docs/DEPLOYMENT.md` : nouvelle sous-section « Personnaliser le fond
  d'écran Ventoy », liste de dépendances et sous-dossiers mis à jour
  (incluait déjà `cp` en pratique depuis le correctif RBAC du
  2026-09-14 plus tôt, jamais documenté jusqu'ici — corrigé au passage).

### Limite connue
**Non testé sur un vrai démarrage physique** — même réserve P0 que le
reste du projet (`ROADMAP.md`). Le rendu exact du bandeau de texte dépend
des polices disponibles sur la machine de build au moment de l'exécution
d'ImageMagick ; aucune police n'est imposée explicitement pour rester
portable (voir le code pour le détail).

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit` (14/14).
Logique de `sonar_prepare_ventoy_theme`/`generate_ventoy_json_final`
validée en isolation (4 scénarios : image+ImageMagick OK, pas d'image,
`--no-ventoy-theme`, ImageMagick absent/échoue) — le chemin réel
`--disk` complet reste non exerçable par `--self-test` (nécessite un
périphérique bloc réel, même limite que le reste du déploiement).

## [3.10.5-forensic-policy-decision] — 2026-09-14

### Note
`SONAR_VERSION` n'avait pas été mise à jour pour 3.10.4 ci-dessous (oubli
— l'entrée CHANGELOG existait sans que le script porte le numéro
correspondant). Rattrapé ici ; ce saut de version couvre donc aussi
3.10.4 en pratique, pas seulement ce qui suit.

### Contexte
Suite à la question explicite : les colonnes DESTRUCTIVE et FORENSIC de
`policy.tsv` doivent-elles enfin être appliquées dans le code (via
`sonar_require_role`), ou rester déclaratives ? Décision **volontaire de
ne pas les appliquer maintenant**, documentée avec les raisons concrètes
plutôt que laissée comme un vague "à faire" :

- **FORENSIC** : déjà tenté en v3.10.3, réverté — casse le comportement
  testé et voulu (acquisition en libre-service sans jeton, "le cas le
  plus courant" selon CHANGELOG v3.10.2).
- **DESTRUCTIVE** : `Technician` y est refusé (`-`), mais autorisé sous
  `DEPLOY` (`R`) — qui est le vrai chemin d'écriture disque destructive
  (`--disk`, seul contrôlé par `sonar_require_role DEPLOY`). Appliquer
  DESTRUCTIVE littéralement bloquerait donc le déploiement en libre-service
  que DEPLOY autorise déjà pour ce même rôle — conflit interne entre les
  deux colonnes, pas juste une case non cochée. Aucune couverture
  `--self-test` n'existe sur le chemin d'écriture disque réel (bloqué P0
  matériel) pour valider un changement ici sans risque.

### Modifié
- Commentaire au-dessus de la génération de `policy.tsv` dans
  `sonar_master.sh` : remplacé par une explication détaillée de chaque
  conflit (pas juste "en attente d'audit").
- `ROADMAP.md` : le point P1 "audit de sécurité externe" porte désormais
  ces deux questions concrètes en sous-puces, pour que qui fera cet audit
  n'ait pas à re-découvrir le problème depuis zéro.

### Non fait (délibérément)
Aucun changement de comportement du script. Cette entrée documente une
décision de ne pas coder quelque chose maintenant, pas un correctif.

### Testé
`bash -n`, `--self-audit` (14/14) — changements limités à des
commentaires/documentation, aucune régression possible côté logique.

## [3.10.4-catalog-expansion] — 2026-09-14

### Contexte
À la demande de l'auteur : ajout de CAINE (et distributions forensiques
apparentées) au catalogue de référence, puis élargissement à quatre
domaines jusqu'ici absents — vidéosurveillance/CCTV et téléphonie mobile
étaient explicitement listés « hors périmètre » dans docs/CATALOG.md ;
imprimantes et administration matérielle de serveurs n'étaient couverts
par aucun domaine dédié.

### Ajouté (catalogue de référence, `SONAR_CATALOGUE_EMBEDDED` dans
sonar_master.sh — pas le catalogue structurel `SONAR_EMBEDDED_CATALOG_TSV`
utilisé par `--catalog-seal`/`--catalog-validate-embedded`, resté
inchangé)
- **Domaine 58 (Forensic disque)** : CAINE, DEFT Linux, Tsurugi Linux, SIFT
  Workstation, Guymager, Bulk Extractor.
- **Domaine 70 (nouveau) — Vidéosurveillance / CCTV** : ONVIF Device
  Manager, ZoneMinder, Shinobi, Blue Iris, Agent DVR (iSpy), Synology
  Surveillance Station, Milestone XProtect, Hikvision SADP Tool, Dahua
  ConfigTool, Dahua SmartPSS.
- **Domaine 71 (nouveau) — Téléphonie mobile** : ADB, Fastboot, Android SDK
  Platform Tools, Odin, Heimdall, SP Flash Tool, Apple Configurator 2,
  libimobiledevice, 3uTools, scrcpy, Cellebrite UFED, MSAB XRY.
- **Domaine 72 (nouveau) — Imprimantes** : CUPS, Windows Print Management
  Console, HP Smart, Epson Connect, Brother iPrint&Scan, Canon IJ Network
  Tool, PaperCut, PrinterLogic, Ghostscript.
- **Domaine 73 (nouveau) — Serveurs (matériel & admin distante)** : Dell
  iDRAC, HPE iLO, Lenovo XClarity, ipmitool, Supermicro IPMI/BMC, Redfish
  API tools, Dell Update Package, HPE Service Pack for ProLiant.
- Total : 936 → **981 outils**, 69 → **73 domaines**. `docs/CATALOG.md` et
  `README.md` régénérés/mis à jour en conséquence.

### Précision de portée
Cet ajout est purement documentaire — une liste de référence, pas de
nouveau code exécutable. Il ne modifie ni le module forensique
(`--forensic-acquire`, `--forensic-chain-of-custody`), ni le RBAC, ni
aucun comportement du script. Les outils listés (gestion de flotte
mobile, administration de caméras IP/NVR, impression, hors-bande serveur)
sont ceux d'un technicien IT en contexte autorisé (parc dont il a la
charge) — cohérent avec le positionnement du projet depuis le début
(« maintenance informatique », cf. README).

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit` (14/14),
`--self-test` (0 FAIL).

## [3.10.3-role-lock-hardening] — 2026-09-14

### Contexte
Revue de code ciblée sur `sonar_master.sh` (8 angles : bugs ligne-à-ligne,
invariants de sécurité absents ailleurs qu'à leur point de correction
d'origine, cohérence inter-fonctions, duplication, simplification,
efficacité, profondeur des correctifs). Deux failles réelles confirmées
directement dans le code, plus plusieurs bugs de robustesse liés à
`set -euo pipefail`.

### Corrigé — sécurité
- **Contournement du verrou de rôle via `--disk ... --role Admin`** :
  `sonar_role_enforce_lock` est appelée une première fois avant le parsing
  des flags CLI (avec les valeurs par défaut), puis une seconde fois dans
  `parse_final_args` une fois `--role`/`--role-token` lus — mais son garde
  `SONAR_ROLE_LOCK_ENFORCED` (booléen "déjà exécuté") transformait ce
  second appel en no-op systématique, donc le token n'était **jamais
  vérifié** pour le rôle demandé en CLI. Corrigé : le garde est maintenant
  une signature `(rôle, token, fichier de token)` — un second appel avec
  un rôle/token différent du premier redéclenche bien la vérification.
- **Filigrane de build non protégé contre l'injection** : `DISK_LABEL`/`VOL`
  et l'identité opérateur étaient écrits tels quels (sans neutralisation
  tab/retour-ligne) dans `BUILD_WATERMARK.txt` et le registre TSV — seul
  l'appel `sonar_audit` séparé bénéficiait de la neutralisation centrale
  de la v3.10.2, pas ces deux écritures directes. Un nouvel helper partagé
  `sonar_sanitize_value` est appliqué **avant la signature HMAC** (pas
  après, pour que la signature couvre exactement ce qui est écrit), et
  réutilisé pour le `case_id` de `--forensic-chain-of-custody`.
- **Trim des espaces/CRLF d'un jeton de rôle** appliqué uniquement quand le
  jeton venait d'un fichier (`SONAR_ROLE_TOKEN_FILE`), pas de la valeur
  directe (`--role-token`/env) — corrigé, même traitement dans les deux cas.
- **Hashchain sans verrou** : deux exécutions concurrentes de SONAR
  pouvaient lire le même hash "précédent" et produire deux entrées
  chaînées au même prédécesseur, que `--verify-hashchain` aurait signalé
  comme une falsification. Verrouillage `flock` best-effort ajouté autour
  de la séquence lecture-puis-écriture.

### Corrigé — robustesse (`set -euo pipefail`)
- La quasi-totalité du dispatch final (`case "${1:-}" in ... exit $? ;;`)
  appelait les fonctions comme instructions nues : quand une fonction
  retournait légitimement un code non-nul (falsification détectée par
  `--verify-hashchain`, scellé de catalogue non conforme...), le trap ERR
  se déclenchait **avant** `exit $?`, remplaçant un message de diagnostic
  utile par une "ERREUR FATALE" générique. Les ~26 branches concernées
  utilisent maintenant le même style `if fn; then exit 0; else exit $?; fi`
  que les branches déjà correctes du même bloc.
- `sonar_embedded_catalog_validate` capturait `rc=$?` après une commande
  `awk` non protégée — un schéma de catalogue invalide déclenchait le
  même abandon prématuré (avant capture du code et nettoyage du fichier
  temporaire). Corrigé avec `awk ... || rc=$?`.
- `preflight_final` (chemin de déploiement `--disk`) ne vérifiait jamais
  la présence de `cp` avant de commencer à écrire sur le disque cible,
  contrairement à `sonar_backup_execute`/`sonar_forensic_acquire` (déjà
  corrigés en v3.9.0) — ajouté à la liste de dépendances préflight.
- `BUILD_INFO.tsv` était généré via un heredoc non-quoté contenant des
  `\t` littéraux (un heredoc n'interprète jamais les séquences d'échappement)
  au lieu de vraies tabulations — remplacé par des appels `printf`,
  cohérent avec le reste des manifestes TSV du script.

### Non retenu (testé puis réverté)
Une première tentative de cette session ajoutait `sonar_require_role
FORENSIC` à `sonar_backup_execute`, `sonar_forensic_acquire` et
`sonar_forensic_chain_of_custody`, en s'appuyant sur la colonne FORENSIC
de `policy.tsv` (Technician: `-`). `--self-test` a immédiatement révélé
que ce garde cassait un comportement volontaire et déjà testé : une
acquisition forensique sous le rôle Technician par défaut (sans jeton)
est le "cas le plus courant" documenté dans la section v3.10.2
ci-dessous, pas un accès à bloquer. Réverté ; seul `sonar_recovery_execute`
garde un contrôle (`sonar_require_role DIAGNOSE`, colonne où Technician a
déjà `R`, donc sans régression).

### Ajouté
- `.gitattributes` forçant `eol=lf` sur `*.sh` et `hooks/pre-commit` — sans
  ça, `core.autocrlf=true` (réglage par défaut de Git pour Windows) aurait
  fini par convertir le script en CRLF au checkout et faire échouer la
  vérification "LF-only" de `--self-audit`.

### Testé
- `bash -n` : OK. `shellcheck --severity=error` : aucun résultat.
- `--self-audit` : 14/14 PASS.
- `--self-test` : 39 PASS, 6 WARN (environnement de test sans dossier
  source — attendu), **0 FAIL**.

## [3.10.2-audit-integrity] — 2026-08-18

### Contexte
En poursuivant l'audit systématique (cette fois côté sécurité plutôt que
"drapeaux morts"), test d'une hypothèse : les champs texte libre fournis
par l'opérateur (`case_id` de `--forensic-chain-of-custody`, notamment)
finissent-ils sans validation dans le journal d'audit tabulé ? Un jeton de
rôle a déjà cette protection (liste de caractères autorisés validée à
l'émission) — mais `case_id` n'en avait aucune.

### Bug fonctionnel trouvé en premier (pas celui qu'on cherchait)
En préparant le test d'injection, `--forensic-chain-of-custody` a planté
**silencieusement** (aucun message, code de sortie 1) sur le cas le plus
courant : une acquisition faite sous le rôle `Technician` par défaut, sans
jeton, donc sans identité associée. Cause : deux pipelines
`grep ... | ... | tail`/`head` retournaient un code non-nul quand `grep` ne
trouvait rien (cas normal — pas d'entrée "identity=" à trouver), et sous
`set -e` + `pipefail`, une assignation nue `var="$(...)"` sur un tel
pipeline fait avorter toute la fonction — **avant même** d'atteindre le
`if [[ -n "$audit_line" ]]` censé gérer gracieusement ce cas (`INCONNU`).
Même piège traqué plusieurs fois ce soir, cette fois dans une fonction
jamais testée sans identité jusqu'ici (le test automatisé de v3.8.0
utilisait toujours un jeton nominatif). Corrigé (`|| true` sur les deux
pipelines concernés).

### Vulnérabilité réelle confirmée ensuite
Une fois ce bug corrigé, l'injection a bien fonctionné : un `case_id`
contenant des tabulations/retours à la ligne littéraux se retrouvait tel
quel dans `audit.log`, cassant la structure à 4 colonnes attendue, et
**avec un retour à la ligne, créait une ligne entièrement séparée qui
ressemblait à une entrée d'audit distincte et plausible** (ex:
`2099-01-01T00:00:00Z	Admin	FAKE_ENTRY	injected=true`).

**Bonne nouvelle en testant plus loin** : `--verify-hashchain` a
immédiatement détecté la falsification (4 ruptures identifiées, dont la
ligne injectée) — le hashchain n'est pas contourné, car il calcule
l'empreinte sur la chaîne `details` complète, non tronquée. Mais un
`cat`/`awk` naïf du journal brut, avant de penser à lancer la
vérification, aurait été trompé.

### Corrigé
- `sonar_audit` neutralise désormais **centralement** toute tabulation ou
  retour à la ligne dans `event` et `details` (remplacés par un espace)
  avant écriture dans `audit.log` ET `hashchain.log` — protection
  automatique pour tout appelant actuel ou futur, pas seulement
  `case_id` (couvre aussi, par exemple, le label disque du filigrane de
  build).
- Deux nouveaux tests fonctionnels dans `--self-test` : chaîne de
  possession sur une acquisition sans identité (le vrai bug), et
  neutralisation d'une tentative d'injection tab/newline (structure à 4
  colonnes préservée, hashchain intact).

### Testé
- Acquisition sans identité → chaîne de possession fonctionne
  normalement (confirmé, alors qu'elle plantait silencieusement avant).
- Injection avec tabulations seules → contenu neutralisé en une ligne
  propre à 4 colonnes.
- Injection avec retour à la ligne → confirmé qu'avant le correctif, une
  ligne factice séparée était bien créée ; après le correctif, tout reste
  sur une seule ligne, structure intacte.
- self-audit et self-test : aucune régression, 2 nouveaux tests PASS dès
  le premier lancement.



### Contexte
Suite aux deux drapeaux morts trouvés ce soir (module status, VeraCrypt),
audit systématique du fichier entier : toutes les variables assignées par
un flag CLI vérifiées référencées ailleurs (aucune autre trouvée), puis
recherche des fonctions définies mais jamais appelées. Une seule trouvée :
`sonar_require_cmd` — contrairement aux deux bugs précédents, ce n'est pas
un mensonge (rien n'affirmait qu'elle s'exécutait), juste du code orphelin
laissé par une convention de nommage plus ancienne (`require_cmd_final`
existe déjà et fait le même travail, en version "fatale" pour le préflight).

### Corrigé
- `sonar_require_cmd` (variante non-fatale, retourne un code au lieu de
  tuer tout le script — le même style que `sonar_require_openssl`) câblée
  en vérification amont dans `sonar_backup_execute` et
  `sonar_forensic_acquire`, avant toute copie de données.
- Avant : ces fonctions présumaient silencieusement `cp`/`find`/`sort`
  disponibles ; un outil manquant aurait produit un échec confus **après**
  avoir déjà copié des données (potentiellement des gigaoctets de preuves
  forensiques), pas avant.
- Après : échec nét et explicite avant toute écriture si un outil critique
  manque.

### Testé
- Cas normal : `--forensic-acquire` fonctionne toujours identiquement.
- `find` masqué du `PATH` (1292 binaires réels reconstruits, `find` exclu) :
  échec propre avec message clair (`Required command not found: find`),
  code 127, **et confirmation qu'aucun dossier `SONAR_EVIDENCE_*` n'a été
  créé** — la copie n'a jamais commencé.
- self-audit et self-test inchangés (aucune régression).



### Contexte
Suite à la question sur les mécanismes anti-copie : rappel honnête d'abord —
rien en logiciel pur n'empêche un `dd` bit-à-bit d'une clé USB une fois
qu'elle existe (aucune puce sécurisée sur un support USB grand public). Ce
qui est réellement faisable : rendre une copie **traçable** jusqu'à son
build d'origine, pas l'empêcher.

### Ajouté
- Filigrane de build signé (`sonar_generate_build_watermark`), déposé sur
  chaque clé réellement déployée dans `MANIFEST/BUILD_WATERMARK.txt` :
  identifiant de build aléatoire, horodatage, identité de l'opérateur
  (si authentifié via le verrou de rôle), label du disque, signature
  HMAC-SHA256.
- **Secret de signature dédié**, volontairement séparé de celui du verrou de
  rôle (`SONAR_BUILD_SECRET_FILE` ≠ `SONAR_ROLE_SECRET_FILE`) — deux domaines
  de sécurité différents (qui peut agir vs. quel build est-ce), ne doivent
  jamais partager la même clé.
- `--verify-watermark <FICHIER|DOSSIER>` : recalcule la signature contre le
  secret local, confirme ou infirme l'authenticité, et croise un registre
  local (jamais copié sur la clé) pour retrouver le contexte du build.
- Registre local `Secure/Keys/build_registry.tsv` (horodatage, build id,
  opérateur, label) — reste uniquement sur la machine de l'admin.

### Corrigé (trouvé en écrivant le test, pas en l'écrivant puis en le lisant)
En écrivant le test fonctionnel de détection de falsification, un appel à
`sonar_verify_build_watermark` sur un filigrane volontairement corrompu
(censé échouer — c'est le test) était placé en instruction nue sous
`set -e`, ce qui faisait avorter tout le sous-shell de test **avant** de
pouvoir capturer son code de sortie — répétition, dans le code de test
cette fois, du même piège traqué plusieurs fois dans le script lui-même
depuis v3.2.1. Corrigé avec l'idiome sûr `if CMD; then rc=0; else rc=$?; fi`
au lieu d'un `$?` nu ou d'un `|| true` (qui aurait aussi perdu le vrai code
de sortie, `true` devenant la dernière commande de la liste).

### Testé
- Génération réelle d'un filigrane, contenu vérifié (build id, opérateur,
  label, signature).
- Vérification authentique → confirmée, registre local retrouvé.
- Filigrane falsifié (label modifié après coup) → authenticité rejetée,
  détecté correctement.
- Vérification sur une "machine" sans le secret local (cas réaliste : la
  clé retrouvée par quelqu'un d'autre) → métadonnées lisibles, authenticité
  explicitement non vérifiable, pas de fausse confirmation.
- self-audit 14/14, self-test 0 erreur, stable sur deux exécutions
  indépendantes consécutives.



### Contexte
`INCLUDE_VERACRYPT` existait depuis l'en-tête d'origine ("VeraCrypt: Oui")
mais **n'était consulté nulle part** — un drapeau mort, comme le statut
"Physical disk deployment NOT TOUCHED" corrigé en v3.2.1. Avant de coder un
correctif, vérification du fonctionnement réel de la persistance Ventoy :
elle attend un fichier ext4 brut monté directement au démarrage (aucune
intégration VeraCrypt native — voir ventoy.net/en/plugin_persistence.html).
**Chiffrer ce fichier aurait cassé le démarrage de la persistance tout en
donnant une fausse impression de sécurité** — un correctif pire que le bug.

### Ajouté
- `sonar_generate_vault_helper` : déploie `Scripts/sonar-vault.sh` sur la clé
  — un coffre chiffré autonome (gpg AES-256), exécuté plus tard sur le
  terrain par le technicien, **totalement indépendant** de la chaîne de
  démarrage/persistance Ventoy. Ne peut donc jamais casser le boot.
  - `sonar-vault.sh create <source> <coffre.enc>` / `open <coffre.enc> <sortie>`
  - Mot de passe jamais stocké, jamais écrit sur disque, saisie masquée
  - Refuse d'écraser un fichier existant ; refuse si confirmation ≠ mot de
    passe initial
  - Détecte `veracrypt` s'il est présent sur la machine où le script est
    *exécuté* (pas celle qui a construit la clé) et prévient clairement
    que ce script ne le pilote pas automatiquement, en repli sur gpg
- En-tête et aide corrigés : plus aucune mention de "VeraCrypt: Oui" pour
  quelque chose qui n'existe pas.

### Testé
- Round-trip réel : création d'un coffre, vérification par `file` que le
  contenu est bien `AES with 256-bit key salted & iterated`, contenu en
  clair absent du blob, ouverture avec le bon mot de passe restitue le
  contenu exact.
- Mauvais mot de passe → échec de déchiffrement confirmé.
- Refus d'écraser un coffre existant → confirmé.
- Mots de passe non concordants à la création → rejeté.
- Nouveau test fonctionnel automatisé dans `--self-test` : génère le script,
  fait un vrai aller-retour chiffrement/déchiffrement, compare le fichier
  récupéré à l'original (`diff`).
- self-audit 13/13, self-test 0 erreur.



### Contexte
Dette connue depuis le début du module forensique : `sonar_forensic_acquire`
copie les preuves et calcule les SHA-256, mais rien ne formalisait ça en
document de chaîne de possession exploitable — la dette explicitement notée
dans la roadmap ("pas de modèle de chaîne de possession"). Devenu réalisable
proprement maintenant que l'identité de l'opérateur se propage à tout
l'audit (v3.7.0) et que le hashchain est vérifiable à la demande (v3.2.0).

### Ajouté
- `--forensic-chain-of-custody <DOSSIER_PREUVES> [N_DOSSIER]` : génère un
  document de chaîne de possession à partir d'une acquisition existante.
  Croise automatiquement :
  - l'entrée d'audit `FORENSIC_ACQUIRE` correspondante (opérateur, identité,
    horodatage) ;
  - une empreinte SHA-256 de méta-intégrité sur la liste de hachage
    elle-même (détecte une modification de la liste après coup) ;
  - le statut du hashchain d'audit au moment de la génération (INTACT /
    COMPROMIS).
  Laisse un tableau à compléter manuellement pour les transferts de
  possession ultérieurs (transport, stockage, remise à un tiers) — hors du
  contrôle de SONAR par nature, mais ancré aux preuves cryptographiques que
  l'outil peut effectivement attester.
- Accessible aussi via le launcher interactif (option 19).
- Nouveau test fonctionnel bout-en-bout dans `--self-test` : émet un jeton
  Forensic nominatif, effectue une acquisition, génère la chaîne de
  possession, vérifie que le document lie bien l'identité de l'opérateur et
  le statut du hashchain.

### Testé
- Flux complet manuel : jeton `e.legrand` (rôle Forensic) → acquisition de 2
  fichiers → génération avec numéro de dossier `DOSSIER-2026-042` → document
  vérifié contenant `Operateur: Forensic (identity=e.legrand)`, empreinte de
  méta-intégrité, statut `INTACT`.
- Dossier invalide (pas une acquisition SONAR) → rejeté proprement, message
  clair, hashchain resté intact après l'échec.
- self-audit 12/12, self-test 0 erreur (9 tests fonctionnels sur le verrou
  de rôle et la chaîne de possession).



### Contexte
Depuis v3.4.0, l'identité authentifiée (`SONAR_ROLE_IDENTITY`) n'apparaissait
que dans les événements du verrou de rôle lui-même
(`ROLE_ELEVATION_GRANTED`). Toute action effectuée *ensuite* sous ce rôle —
un diagnostic, une sauvegarde, une acquisition forensique, un vrai
déploiement `--disk` — ne traçait que le rôle, pas la personne. Ça limitait
la valeur réelle des jetons nominatifs pour la traçabilité d'ensemble.

### Changé
- `sonar_audit` ajoute désormais automatiquement `identity=<nom>` à *toute*
  entrée d'audit dès qu'une identité authentifiée est active pour la
  session — pas seulement aux événements de verrou. Source unique de
  vérité : les appelants n'ont plus besoin (et ne doivent plus) l'inclure
  manuellement.
- Suppression de la duplication manuelle dans `ROLE_ELEVATION_GRANTED`
  (redondante avec le nouveau comportement automatique).
- Nouveau test fonctionnel dans `--self-test` : émet un jeton, exécute une
  action sans rapport avec le verrou de rôle (`--diagnostic`), vérifie que
  l'entrée d'audit résultante porte bien `identity=`.

### Testé
- Confirmé manuellement : un jeton émis pour `j.dupont`, utilisé pour lancer
  `--diagnostic`, produit une entrée `DIAGNOSTIC_REPORT` portant
  `identity=j.dupont` dans le journal d'audit.
- Hashchain vérifié intact malgré le changement de format des `details`
  (4 entrées, aucune rupture).
- self-audit 11/11, self-test 0 erreur (7 tests fonctionnels sur le verrou
  de rôle, dont le nouveau).



### Contexte
Dette technique documentée depuis v3.4.0 : la signature des jetons de rôle
était un hachage à clé maison (`sha256(secret|identity|role|expiry)`), pas un
HMAC formel — trade-off explicitement assumé faute d'`openssl` confirmé
disponible. `openssl` s'est avéré présent ; plus de raison de garder la
version plus faible.

### Changé
- `sonar_role_sign` utilise désormais un **vrai HMAC-SHA256** (RFC 2104, via
  `openssl dgst -sha256 -hmac`) au lieu du hachage à clé maison.
- Nouveau garde `sonar_require_openssl` : échec **net et explicite** si
  `openssl` est absent au moment de signer/vérifier un jeton — jamais de
  repli silencieux vers une construction plus faible. Le bootstrap du
  secret n'en a pas besoin (généré via `sha256sum`, inchangé) ; seules
  l'émission et la vérification de jeton l'exigent.
- `openssl` ajouté à la liste vérifiée par `--dependencies-report`.

### Testé
- Signature vérifiée : 64 caractères hex (SHA-256), format HMAC standard.
- Jeton légitime accordé, jeton avec signature falsifiée rejeté (motif
  "signature invalide").
- Absence d'`openssl` simulée par un `PATH` complet (1292 binaires du
  système réel) reconstruit sans lui : `--role-bootstrap` fonctionne toujours
  (n'en dépend pas), `--role-issue-token` échoue proprement avec message
  explicite (pas de crash silencieux, pas de repli affaibli).
- self-audit 11/11, self-test 0 erreur, pipeline `--disk --dry-run` sur
  `/dev/loop` : EXIT 0.



### Contexte
Aucun accès à du matériel physique pour valider un vrai boot Ventoy pour le
moment (bloqué côté opérateur, pas résolu). En attendant, il fallait combler
un vrai trou : rien n'avertissait l'opérateur d'un **vrai** déploiement
(`--disk` sans `--dry-run`) que ce build n'a jamais été validé sur du
matériel réel — le statut `NOT_TESTED` n'apparaissait que dans des rapports
consultés à part (`--self-test`, `--release-report`), jamais au moment où ça
compte : au moment d'écrire sur un vrai périphérique.

### Ajouté
- Garde-fou runtime `sonar_require_hardware_risk_ack` : tout déploiement réel
  affiche un avertissement explicite et exige soit la phrase tapée
  `JE COMPRENDS LE RISQUE`, soit `--accept-hardware-risk` /
  `SONAR_HARDWARE_RISK_ACK=true` pour l'automatisation.
- **Séparé de `--yes`** volontairement : scripter `--yes` seul (confirmation
  d'effacement) ne suffit plus à sauter cet acquiescement précis — les deux
  gardes sont indépendants et tous deux nécessaires pour un déploiement réel
  entièrement non interactif.
- Entrée d'audit `HARDWARE_RISK_ACKNOWLEDGED` (méthode : flag/env, interactif,
  ou refusé).
- Testé en conditions réelles sur `/dev/loop` (déploiement non-dry-run) :
  refus par défaut confirmé, acceptation par phrase tapée confirmée,
  acceptation par flag confirmée, traçabilité dans l'audit confirmée.

### Non résolu
Ceci est un **filet logiciel**, pas un remplacement du test matériel réel —
voir `ROADMAP.md` (P0, toujours ouvert, en attente d'accès à du matériel).



### Ajouté
- Jetons de rôle **par identité** (`identity:role:expiry:signature`) au lieu
  d'un jeton unique partagé par rôle.
- `--role-issue-token <ROLE> <IDENTITE> [JOURS=30]` — jeton nominatif avec
  expiration intégrée.
- `--role-revoke-token <JETON>` — révocation individuelle, sans effet sur les
  autres porteurs du même rôle, sans rotation du secret racine.
- `sonar_const_time_eq` — comparaison de signature best-effort à temps
  constant (remplace `[[ == ]]`, qui court-circuite au premier octet
  différent).
- L'identité authentifiée apparaît dans `--security-status` et dans les
  entrées d'audit `ROLE_ELEVATION_GRANTED`.
- 3 nouveaux tests fonctionnels dans `--self-test` : jeton nominatif accordé,
  jeton révoqué rejeté, jeton expiré (forgé et re-signé) rejeté.

### Corrigé
- Aucun (fonctionnalité pure sur la base v3.3.0).

## [3.3.0-role-lock] — 2026-08-16

### Ajouté
- Verrou de rôle : `SONAR_ROLE=Admin` / `--role Admin` sans jeton valide est
  désormais rétrogradé automatiquement vers `Technician`.
- `--role-bootstrap` — initialise le secret local une seule fois (chmod 600).
- `--role-issue-token <ROLE>` (v1, remplacé en 3.4.0) — émission par rôle.
- Garde-fou de non-régression dans `--self-audit` / `--self-test` contre le
  pattern `|| return` dangereux réintroduit.

### Sécurité
- **Faille corrigée** : avant ce correctif, n'importe qui pouvait s'attribuer
  n'importe quel rôle (y compris Admin/VAULT/FORENSIC) simplement en
  définissant la variable d'environnement `SONAR_ROLE`, sans aucune
  authentification.

## [3.2.1-smart-advisor] — 2026-08-15

### Corrigé
- **Bug critique trouvé par test réel** (`--dry-run` sur un vrai périphérique
  bloc, pas par relecture de code) : le pattern `[[ condition ]] || return`
  sans code de sortie explicite fait hériter à `return` le code d'échec du
  test quand la condition est fausse. Sous `set -e`, ceci terminait le script
  **silencieusement**, sans aucun message d'erreur, dès qu'une fonction
  utilisant ce pattern était appelée en instruction simple.
- Impact réel confirmé : tout `--dry-run` avortait sans un mot (via
  `generate_readme_final`), de même pour `--no-ai-assistant`, `--ai off`, ou
  `--persistence 0`.
- Corrigé dans `install_ai_layer_final`, `run_ai_final`,
  `create_persistence_final`, `generate_readme_final`.

## [3.2.0-smart-advisor] — 2026-08-15

### Ajouté
- **Smart Advisor** (`--smart-advisor`) — moteur de règles déterministe
  (aucun LLM impliqué) corrélant dépendances, intégrité du hashchain,
  fraîcheur du manifeste, couverture de validation du catalogue, scellé et
  rôle en un verdict priorisé avec raisonnement explicite.
- **Vérification réelle du hashchain** (`--verify-hashchain`) — recalcule
  toute la chaîne pour détecter une falsification a posteriori du journal
  d'audit (fonctionnalité absente jusque-là : on ajoutait des entrées sans
  jamais les vérifier).
- **Scellé d'intégrité du catalogue embarqué** (`--catalog-seal` /
  `--catalog-verify-seal`, rôle VAULT).
- **Vérification post-déploiement** intégrée au pipeline `--disk` : relit
  chaque fichier copié directement depuis la clé montée et compare au
  SHA-256, là où `validate_final` ne vérifiait que la structure.
- **Rapport de mission unifié** (`--mission-report`).

## [Renommage] — NEXUS → SONAR

Le projet s'appelait initialement NEXUS. Renommage global de toutes les
fonctions, variables d'environnement, bannières et messages.

## [3.1.0-final-integrated] et antérieur

Fusion de `nexus_master.sh` et `NEXUS_MASTER_FINAL_V3.sh` : racine
d'exécution stable, suivi des points de montage avec démontage automatique,
persistance via `dd` au lieu de `truncate`, correctifs de robustesse divers,
couche opérationnelle V2 (launcher, diagnostic, self-test, recovery/backup
plans, forensic workspace, diagnostic réseau, builder, rapports).

---

## Non résolu / dette connue

Ce qui manque encore pour que l'outil soit considéré mature — voir aussi
`ROADMAP.md` :

- **Jamais testé sur du vrai matériel.** Tout ce qui est validé l'a été en
  `--dry-run` et sur `/dev/loop`, jamais un vrai boot Ventoy/Secure Boot.
- Hachage à clé (SHA-256), pas un HMAC formel. ~~Résolu en v3.6.0~~
- Aucun audit de sécurité externe / pentest.
- Fichier monolithique (~3800 lignes) — refactor modulaire à faire une fois
  la CI en place (jamais avant, pour garder un filet de sécurité).
- Pas de chaîne de distribution signée (GPG) des releases.
- Portabilité Windows/macOS en trompe-l'œil (mentions PowerShell, cœur 100% Bash).
- Pas de documentation utilisateur ni de modèle de chaîne de possession
  (chain of custody) pour le module forensique.
