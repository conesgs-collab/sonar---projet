# Changelog — SONAR

Format inspiré de [Keep a Changelog](https://keepachangelog.com/). Ce fichier
est la version lisible de l'historique qui vivait jusqu'ici dans l'en-tête de
`sonar_master.sh`. À partir de maintenant, tout changement notable est décrit
ici ET dans un commit Git séparé — le script n'a plus besoin de porter tout
son propre historique en commentaire.

## [3.53.0-winpe-antivirus] — 2026-09-22

### Contexte
« notre winpe n'a pas d'outils antivirus integré ». Vrai : ClamAV était déjà dans SONAR-SE (profil `malware`, voir manifeste `--fetch`), mais seulement en build **Linux** (`.deb`, tourne sous SystemRescue) — un technicien qui répare depuis WinPE devait redémarrer sur SystemRescue rien que pour un scan antivirus. Analyse plus large du reste de la boîte à outils WinPE à cette occasion (menu 17 outils + dossier `Portable\` de la clé) : le reste est déjà couvert — CrystalDiskInfo/Mark, Autoruns, Process Explorer, Prime95, HWiNFO/Dism++/BleachBit/Snappy Driver Installer/DriverStoreExplorer/BatteryInfoView/IsMyLcdOK/Memtest86+/chntpw sont déjà dans le manifeste `--fetch` (certains pas encore téléchargés sur cette clé — pas un manque de SONAR, juste un `--fetch malware`/etc. pas encore relancé) ; TestDisk/PhotoRec présents sur la clé sont le build **Linux** (`testdisk_static`/`photorec_static`, ELF) — cohérent avec l'architecture (récupération = territoire Linux/`sonar_recover.sh`, qui dépend de `ddrescue` de toute façon) et sans effet indésirable (extension sans `.exe`, invisibles du lanceur WinPE option 15). Seul vrai manque identifié et corrigé ici : l'antivirus côté WinPE.

### Ajouté
- **ClamAV pour Windows** (`ClamAV-Windows` dans le manifeste `--fetch`, même version 1.5.4 et même clé de signature Cisco Talos que la ligne `ClamAV` Linux existante) : `sonar_fetch_wrap_clamav_win()` aplatit le sous-dossier versionné du zip officiel, retire `clamd/clambc/clamsubmit` (mode démon, débogage, soumission cloud — non voulus ici), les `.pdb` de débogage et les en-têtes/`.lib` de développement (897 Mo → ~100 Mo : `clamscan.exe`/`sigtool.exe`/`freshclam.exe`, les DLL requises — **déjà fournies avec le zip, y compris vcruntime/msvcp : aucun Redistribuable VC++ à installer séparément** —, `certs/`, `conf_examples/`), puis pose `sonar-clamscan.cmd`/`sonar-freshclam.cmd` (même logique que la paire `.sh` Linux : **refuse de tourner sans base de signatures**, message clair plutôt qu'un scan silencieusement vide).
- **Menu WinPE, option 19** : « Analyse antivirus (ClamAV, lecture seule) » — lit `%KEY%\Portable\ClamAV-Windows\`, annonce qu'elle ne modifie/supprime rien, demande la cible (`C:\` par défaut), enregistre le rapport dans `Field-Logs\clamav\`.
- **Assistant guidé** : le cas « virus / comportement suspect » propose maintenant directement l'analyse ClamAV **dans WinPE** (étape `decide()`, oui par défaut car lecture seule) si la clé la fournit et qu'une base de signatures est présente ; sinon message clair (pas de clé/pas de ClamAV/pas de signatures) et renvoi vers SystemRescue comme avant.
- Tests : self-test (`sonar_master.sh`) — fetch/postprocess sur un `.zip` factice (aplatissement, élagage `.pdb`/`clamd.exe`, `.cmd` posés) ; suite assistant (`tests/winpe/run_assistant_tests.sh`, 30 vérifications) — ClamAV absent → renvoi SystemRescue, ClamAV présent + signatures → analyse proposée et lancée sur le bon accord, refus → rien lancé, détection → avertissement affiché ; contrôle statique ajouté à `tests/winpe/run_tests.sh` (option 19, refus sans signatures, lecture seule annoncée) — 53 PASS au total pour la suite WinPE.

### Vérifié (VM VirtualBox, WinPE 26100 réel)
- `clamscan.exe` (build Windows officiel, signature GPG Cisco Talos vérifiée cette session, même clé que la ligne Linux) **se lance sous WinPE sans erreur de DLL manquante** — risque principal identifié à l'avance, maintenant écarté.
- Charge une base de signatures personnalisée (`sigtool`/`.hdb`) et **détecte correctement** un fichier qui y correspond (`Known viruses: N`, `FOUND`, code retour 1) sur un fichier propre : mécanisme de détection par hash prouvé de bout en bout, **sans utiliser le texte EICAR** (systématiquement supprimé par l'antivirus de la machine hôte à chaque écriture sur disque, y compris avec une exclusion Windows Defender ciblée — signal fort que la détection fonctionne, mais rendant ce test précis impraticable sur cet hôte).
- Déployé sur la clé physique : `E:\Portable\ClamAV-Windows\` (~103 Mo, dossier `db\` vide).

### Corrigé (après retour terrain — ISO pas reconstruite la première fois)
Premier déploiement incomplet : le paquet ClamAV avait été copié dans `Portable\`, mais **l'ISO WinPE elle-même
n'avait pas été reconstruite** — la clé démarrait donc encore sur l'ancien menu (1 à 18, sans l'option 19).
Reconstruite (`SHA-256 DCBC5010A194BF4ABFD88E5B42395748CA20A7F7494A5118C463EC11903E0D62`) et **confirmé** que l'option
19 et `:av_scan` sont bien dans `startnet.cmd` de cette ISO (montage DISM en lecture seule). Déployée sur
`E:\ISO\WinPE\SONAR-SE-WinPE-amd64.iso` ; ancienne ISO gardée en secours : `...amd64.iso.bak-v8-20260922`.

### Corrigé — signatures déployées
`database.clamav.net` est derrière une protection anti-bot Cloudflare qui bloque en boucle toute requête automatisée
(confirmé avec `curl`, `Invoke-WebRequest` et un navigateur piloté par automatisation — même la page d'accueil finit
par passer, mais le fichier `.cvd` lui-même redéclenche un défi qui ne se résout jamais) : aucun outil disponible
dans cette session ne peut récupérer ces fichiers. Récupérés par l'opérateur via son propre navigateur (contournement
légitime : navigation humaine normale, pas d'automatisation), puis déposés par Claude dans `Downloads` →
`E:\Portable\ClamAV-Windows\db\` : `main.cvd` (89 Mo, 16 déc 2025), `daily.cvd` (22 Mo, **21 sept 2026** — à jour),
`bytecode.cvd` (275 Ko). En-têtes `ClamAV-VDB:` vérifiés (pas des pages d'erreur), et `clamscan.exe -d db --version`
confirme le chargement (`ClamAV 1.5.4/28130/...`, 28130 = version de `daily.cvd`). L'option 19/l'étape « virus » de
l'assistant sont donc opérationnelles sur la clé dès maintenant — plus besoin de `sonar-freshclam.cmd` pour un
premier usage (utile plus tard pour les mises à jour).

### Vérifié sur matériel réel (HP EliteBook 840 G3), 2026-09-22
Clé rebootée avec l'ISO reconstruite et les signatures déployées : option 19 présente, analyse antivirus lancée
et confirmée fonctionnelle par l'opérateur (« je confirme »). Confirmation générale, pas de détail par écran.

### Non vérifié
- Pas de test EICAR réel (voir plus haut) ni de test sur un fichier réellement infecté : la détection est prouvée par un hash personnalisé, pas par un cas réel de la base ClamAV.
- Les signatures se périment (ClamAV les considère obsolètes après ~7 jours sans mise à jour et peut refuser de charger `main.cvd`/`daily.cvd`) : penser à relancer `sonar-freshclam.cmd` (ou refaire ce téléchargement manuel) périodiquement.
- Les autres outils déjà catalogués mais pas encore sur cette clé (HWiNFO, Dism++, BleachBit, Snappy Driver Installer, DriverStoreExplorer, BatteryInfoView, IsMyLcdOK, Memtest86+, chntpw) restent à récupérer avec `--fetch` si l'opérateur les veut — hors périmètre de cette entrée, qui ne traite que l'antivirus explicitement demandé.

### Comment tester
`bash tests/winpe/run_tests.sh` (Linux/WSL, inclut la suite assistant) ; sous Windows :
`powershell -File tests\winpe\test_menu_diag_sources.ps1 -BusyBox <busybox.exe>`. Sur la clé réelle : lancer
`E:\Portable\ClamAV-Windows\sonar-freshclam.cmd` (Internet requis) puis, depuis le WinPE de la clé, menu option 19
ou symptôme « virus » de l'assistant.


## [3.52.0-native-resolution] — 2026-09-22

### Contexte
Retour terrain après le test réel du 2026-09-21 (WinPE branding/assistant, voir 3.51.0) : « texte un peu petit, l'affichage
n'est pas en adéquation avec ce que j'ai sur la machine, on aurait dit un affichage d'un type très ancien ». Deux endroits
distincts affichent avant le bureau du client, et aucun des deux ne s'adaptait à l'écran réel :
1. Le menu de démarrage Ventoy (GRUB, avant même de choisir une ISO) : `gfxmode` figé à `"800x600,1024x768"` — un choix
   volontairement conservateur (voir 3.40.1/3.41.0), jamais revu depuis que la vraie cause du crash historique
   (`ventoy.json` pointant sur l'image PNG au lieu d'un script `theme.txt`, voir 3.35.0) a été identifiée et corrigée : la
   résolution de l'image n'a **jamais** été la cause du crash (trois tailles radicalement différentes, même échec).
2. La session WinPE elle-même (bannière SONAR, assistant) : **aucun réglage de résolution nulle part**. WinPE retombe sur
   un mode bas par défaut (généralement proche de 1024×768) plutôt que la résolution native de l'écran, même en UEFI —
   comportement documenté de Windows Boot Manager/winload en l'absence de l'élément BCD `highestmode`.

### Corrigé
- **`gfxmode` Ventoy** (`generate_ventoy_json_final()`, `sonar_master.sh`) : `"auto,1024x768,800x600"` au lieu de
  `"800x600,1024x768"`. `auto` laisse GRUB choisir via GOP/EDID du firmware (résolution native de l'écran) ; les deux
  résolutions **prouvées fonctionnelles sur le HP EliteBook 840 G3** restent en repli si `auto` échoue sur un firmware
  donné. Le fond d'écran (`Branding/default_background.png`, canevas 800×600) n'a pas été régénéré : sur un écran plus
  large, GRUB l'agrandira — net progrès par rapport à un menu 4:3 non adapté, mais pas encore optimal (voir "Non vérifié").
- **`highestmode` WinPE** (`Build-SonarSE-WinPE.ps1`, bloc `-BrandBootManager`) : ajouté à `{default}` dans les **deux**
  magasins BCD (BIOS et UEFI), à côté de `bootuxdisabled` déjà présent. Élément BCD standard, documenté Microsoft : force
  le chargeur à utiliser la résolution la plus haute annoncée par le firmware au lieu du mode bas générique choisi par
  défaut. Aucun patch binaire — reste dans le domaine officiellement supporté de `bcdedit`, même prudence que pour le
  renommage du gestionnaire de démarrage (3.40.0).
- Tests : 2 nouveaux contrôles `--self-test` (gfxmode contient `auto` + repli prouvé) et 1 nouveau contrôle statique dans
  `tests/winpe/run_tests.sh` (`highestmode` présent dans la même boucle BCD que `bootuxdisabled`, donc sur les deux
  magasins) — 48 PASS au total pour cette suite ; `--self-audit`/`--self-test` : 0 FAIL (WSL).

### Vérifié
- VM VirtualBox (ISO reconstruite) : `highestmode yes` confirmé présent dans les deux magasins BCD (extraits, lus hors
  ligne avec `bcdedit /store ... /enum ALL`, à côté de `bootuxdisabled Yes` et `description SONAR - SE`). Effet visuel
  confirmé : capture d'écran à 3840×2160 (au lieu de 1024×768 sur toutes les captures précédentes de cette session) — la
  fenêtre WinPE s'affiche nette, à sa taille normale de console, au lieu d'être agrandie/pixelisée.
- **Matériel réel (HP EliteBook 840 G3), 2026-09-22** : clé rebootée après déploiement — retour opérateur : « l'affichage
  est correct ». Confirmation générale (pas de détail écran-par-écran demandé) après le signalement initial (« texte
  petit, affichage d'un type très ancien ») ; couvre a priori l'ensemble du parcours (menu Ventoy → assistant SONAR),
  dans la continuité du signalement lui-même qui était général. Referme le point qui restait non vérifié plus bas.

### Non vérifié
- Pas de confirmation écran-par-écran (menu Ventoy vs assistant WinPE séparément) ni de photo — si un problème plus fin
  réapparaît sur l'un des deux, le distinguer sera utile. Repli toujours disponible si besoin : ISO précédente à
  `E:\ISO\WinPE\SONAR-SE-WinPE-amd64.iso.bak-v7-20260922`, `ventoy.json` précédent à `E:\ventoy\ventoy.json.bak-20260922`
  (`"gfxmode": "800x600,1024x768"`).
- Le fond d'écran Ventoy reste un canevas 4:3 800×600 : à une résolution GRUB plus large, il est agrandi (plus lisible
  qu'avant) mais pas repensé en 16:9 — à revoir seulement si l'opérateur le juge nécessaire.

### Comment tester
Démarrer la clé sur la machine réelle et comparer au ressenti précédent : le menu Ventoy et l'assistant SONAR doivent
remplir l'écran net, texte lisible à taille normale. En cas de régression (écran noir, blocage), remettre
`E:\ISO\WinPE\SONAR-SE-WinPE-amd64.iso.bak-v7-20260922` en place, et/ou `"gfxmode": "800x600,1024x768"` dans
`E:\ventoy\ventoy.json` (ou l'un de ses fichiers `.bak-*`).


## [3.51.0-winpe-assistant] — 2026-09-21

### Contexte
Le WinPE démarrait sur un menu de 17 outils à choisir et enchaîner à la main, avec le clavier et l'habillage par défaut de
Windows. Demande : un WinPE « propre » au nom de SONAR, où les étapes s'enchaînent d'elles-mêmes et où le technicien
n'a qu'à donner son accord ou non, clavier AZERTY français par défaut.

### Ajouté
- **Assistant guidé** (`tools/winpe/sonar_assistant.sh`, embarqué dans l'ISO) : après une bannière SONAR, **Entrée** lance
  l'assistant, **M** ouvre le menu manuel (conservé). L'assistant pose **une seule question** (le symptôme), fait
  **tout seul** l'inventaire et le diagnostic (lecture seule), puis **propose** les étapes utiles une à une : BitLocker
  (déverrouillage), sauvegarde des fichiers vers la clé (sans `AppData`, avant toute réparation), réparation UEFI (`bcdboot`),
  contrôle des fichiers système, etc. La lettre du Windows, le volume de l'ESP et la destination sur la clé sont **trouvés
  automatiquement** ; s'il y a plusieurs Windows, l'assistant **demande** au lieu de deviner.
- **Règle d'accord** : une étape qui **modifie** quelque chose est refusée **par défaut** (o/N) — sans réponse claire,
  rien n'est fait. Toute décision (oui/non, code retour, origine des règles/du moteur) est journalisée sur la clé
  (`Field-Logs\assistant\ASSIST_*.log`) ; **la clé de récupération BitLocker n'apparaît ni à l'écran, ni dans le journal, ni dans le rapport**.
- **Marque SONAR** : bannière ASCII « SONAR SE » (`sonar_banner.txt`) et titre de fenêtre `SONAR - SE` (vus dans la VM de test).
- **Clavier AZERTY français par défaut**, **vérifié sous WinPE 26100 (VM)** : `wpeutil SetKeyboardLayout 040c:0000040c` ne
  change PAS le clavier de la fenêtre déjà ouverte, et une console ouverte *immédiatement* après restait en QWERTY. L'accueil
  patiente donc 6 s puis se **relance dans une nouvelle console** (variable `SONAR_RELAUNCH` : pas de boucle, `wpeinit` une
  seule fois ; si la fenêtre SONAR est fermée, une invite de secours s'ouvre au lieu de quitter le shell WinPE).
- Menu manuel : option **18** (relancer l'assistant) ; le menu de 17 outils reste intégralement disponible.
- Vérification finale de l'ISO : présence de `sonar_assistant.sh` et de la ligne clavier dans `startnet.cmd`.
- Tests : `tests/winpe/run_assistant_tests.sh` (26 vérifications, outils Windows remplacés par des *stubs* qui enregistrent
  l'appel : on vérifie ce qui serait lancé, dans quel ordre, et surtout ce qui ne l'est **pas** quand le technicien refuse) ;
  `tests/winpe/test_menu_diag_sources.ps1` passe de 6 à 10 vérifications **sur un vrai `cmd.exe` avec le vrai BusyBox** (écran
  d'accueil, Entrée → assistant, retour au menu) ; 4 contrôles statiques ajoutés à `tests/winpe/run_tests.sh` (47 PASS au total).

### Vérifié sur un vrai WinPE (VM VirtualBox, ISO reconstruite)
- Démarrage sur la bannière SONAR, fenêtre « SONAR - SE », **AZERTY** (touches q, w, ; → a, z, m ; Maj+1 → 1), Entrée →
  assistant → symptôme → inventaire et diagnostic (score, constats) → retour au menu manuel. Sans disque ni clé dans la VM.

### Non vérifié
- **Fond d'écran** : `winpe.jpg` (image SONAR) a été copié dans l'image et le registre WinPE le référence déjà, mais **rien ne
  s'affiche** (fond bleu uni) sur ce WinPE 26100 : il n'y a pas de shell pour le peindre. Abandonné, non livré.
- **Logo Windows au démarrage** : l'animation de démarrage vient de `bootres.dll`, un fichier signé Microsoft ; le modifier
  casserait Secure Boot. Rien n'a été patché. Dans la VM de test aucun logo n'apparaît ; sur du **vrai matériel / via Ventoy**,
  ce qui s'affiche avant le bureau n'a pas été observé (photo ou description bienvenue).
- Les étapes de l'assistant **avec un vrai disque Windows et une vraie clé** (`manage-bde`, `bcdboot`, `diskpart`, `robocopy`,
  `sfc`, `chkdsk`) sont testées par *stubs* seulement ; le comportement de `read -s` (saisie masquée de la clé BitLocker) dans
  la console WinPE n'est pas vérifié (repli sur `read` visible prévu).
- Le délai de 6 s avant la relance est celui qui a suffi dans la VM ; sur un autre matériel, un WinPE plus lent pourrait
  demander plus (symptôme : accueil en QWERTY ; solution : augmenter `ping -n 6`).
- La fenêtre d'origine (`startnet.cmd`) reste visible derrière la fenêtre SONAR.

### Comment tester
`bash tests/winpe/run_tests.sh` (Linux/WSL) ; sous Windows :
`powershell -File tests\winpe\test_menu_diag_sources.ps1 -BusyBox <busybox.exe>` ; puis reconstruire l'ISO
(`.\tools\Build-SonarSE-WinPE.ps1 -SkipAdkInstall …`), la démarrer, vérifier bannière, clavier (taper `a`, `q`, `1` avec Maj),
Entrée → assistant.

## [3.50.0-winpe-key-rules] — 2026-09-21

### Contexte
Les règles et le moteur du diagnostic WinPE étaient figés dans l'ISO (`Windows\System32\sonar\`, 535 Mo) : modifier une
règle imposait de reconstruire l'ISO et de la redéployer sur chaque clé. Précision sur le contexte de la demande : le WinPE
n'embarque pas `sonar_diag.sh` (script Linux) mais `sonar_diag_winpe.sh` (collecteur), `diag_engine.awk` et `diag_rules.txt`.

### Ajouté
- **Le menu WinPE (option 12) lit les règles et le moteur sur la clé SONAR-SE.** Au lancement du diagnostic, il cherche la
  clé sur les lecteurs **D: à Z:** (celui qui porte `MANIFEST\PROFILES.tsv` ; C: — le disque du client — et X: — le WinPE —
  ne sont plus cherchés). S'il trouve `MANIFEST\DIAG_RULES.txt` et/ou `Scripts\diag_engine.awk`, il les utilise ; sinon la
  copie embarquée reste le **repli** (comportement d'avant, aucune clé n'est requise). Règles et moteur sont choisis
  **séparément**.
- **L'origine est toujours dite** : trois lignes à l'écran (« regles : CLE Z: … — 37 regle(s) », « moteur : INTEGRE dans
  l'ISO »…), et une ligne `Sources : regles = … ; moteur = …` **ajoutée au rapport** enregistré, pour qu'un rapport porte la
  trace de ce qui l'a produit.
- **Garde-fou sur le moteur pris sur la clé** (`tools/winpe/sonar_check_awk.sh`, embarqué dans l'ISO) : un moteur awk est du
  *code*. Les lecteurs D: à Z: peuvent porter la clé USB ou le disque externe du client, et le WinPE tourne en administrateur ;
  un `diag_engine.awk` piégé y serait exécuté. Le moteur de la clé est donc refusé (repli sur l'embarqué, message explicite)
  s'il contient `system(`, un pipe vers/depuis une commande ou une redirection de sortie (les textes entre guillemets sont
  neutralisés avant, sinon le vrai moteur — qui affiche des `|` — était refusé). Les **règles** sont des données : pas de contrôle.
- Tests : `tests/winpe/run_tests.sh` (16 vérifications : le vrai moteur est accepté, 6 moteurs malveillants refusés, garanties
  statiques du build) ; `tests/winpe/test_menu_diag_sources.ps1` (Windows) : **exécute le menu tel que le build l'écrit**
  (extrait par l'analyseur PowerShell) sur un vrai `cmd.exe` avec le vrai `busybox.exe` de l'ISO, 6 scénarios — clé complète,
  règles modifiées sur la clé (le moteur travaille bien avec les 2 règles de la clé), moteur piégé refusé, clé sans fichiers,
  aucune clé. Passent tous.
- Le moteur awk et les règles ne sont **pas modifiés**. `--field-export` déployait déjà `Scripts/diag_engine.awk` et
  `MANIFEST/DIAG_RULES.txt` sur la clé : ce sont ces fichiers-là qui sont lus.

### Changement de comportement à connaître
- La recherche de la clé (`:findkey`, aussi utilisée pour les rapports, les pilotes et les outils portables) ne regarde plus C:.
- Il faut **reconstruire l'ISO une fois** pour embarquer ce nouveau menu ; ensuite, une règle modifiée n'exige plus qu'un
  `--field-export` sur la clé.
- Règles de la clé et collecteur embarqué évoluent séparément : une règle qui s'appuie sur un fait que le collecteur embarqué
  n'émet pas ne se déclenchera simplement pas (le moteur ignore les faits absents) ; un nouveau fait exige de reconstruire l'ISO.

### Non vérifié — nécessite un vrai test avec clé
- **Aucun essai sur un vrai WinPE booté avec la clé branchée** : la logique est exécutée sur `cmd.exe` Windows (pas dans un
  WinPE), avec `wpeinit`/`wpeutil` remplacés par des exécutables inertes et X:/Z: simulés par `subst`.
- **L'ISO n'a pas été reconstruite** : le menu modifié n'est pas dans l'ISO actuellement sur la clé.
- La liste réelle des lettres D:–Z: (le test la restreint à Y/Z), et l'attribution réelle de la lettre de la clé par WinPE.
- Le garde-fou est un filtre statique de jetons littéraux : il arrête un moteur piégé écrit naïvement, pas un adversaire qui
  contrôle déjà la clé SONAR-SE elle-même (la clé reste une racine de confiance).

### Comment tester avec une vraie clé
1. Reconstruire l'ISO : `.\tools\Build-SonarSE-WinPE.ps1 -SkipAdkInstall -OutputIso .\SONAR-SE-WinPE-amd64.iso -ServicedBootWim <boot_serviced.wim>`
   (UAC à accepter), la copier dans `E:\ISO\WinPE\`, et `sonar_master.sh --field-export /mnt/e` pour les fichiers de la clé.
2. Booter le WinPE depuis la clé, menu → **12** : l'écran doit annoncer « regles : CLE X: … » et « moteur : CLE X: … ».
3. Sur la clé, éditer une règle de `MANIFEST\DIAG_RULES.txt` (ex. ajouter/retirer une ligne), **sans toucher à l'ISO**, relancer
   le 12 : le nombre de règles affiché et le `Base : N regles` du rapport doivent suivre la modification.
4. Repli : renommer `MANIFEST\DIAG_RULES.txt` puis relancer : « regles : INTEGREES dans l'ISO ». Débrancher toute clé : « cle
   SONAR-SE non detectee », le diagnostic doit quand même se terminer.
5. Garde-fou : remplacer `Scripts\diag_engine.awk` par un fichier contenant `BEGIN { system("calc.exe") }` : le menu doit annoncer
   « moteur de la cle REFUSE » et utiliser l'embarqué (aucune calculatrice ne doit s'ouvrir). Remettre le vrai moteur ensuite.
6. Regarder la dernière ligne de `Field-Logs\diag\DIAG_*.txt` : `Sources : regles = … ; moteur = …`.

## [3.49.2-audit-lock-and-log-fixes] — 2026-09-21

### Contexte
Audit de sécurité adversarial de `sonar_master.sh` (RBAC, secrets, jetons, hashchain), méthode : lecture puis **rejeu de
chaque hypothèse** sur une racine de confiance isolée. Rapport complet : `docs/SECURITY_AUDIT_2026-09-21.md`
(7 trouvailles significatives + 6 basses ; ce qui est déjà documenté comme volontaire a été écarté).

### Corrigé (2 trouvailles, avec tests de non-régression ; les deux sont vérifiées avant/après)
- **HAUTE — le verrou de rôle se contournait avec une variable d'environnement.** `SONAR_ROLE_LOCK_ENFORCED_SIG` n'était
  jamais initialisée : `SONAR_ROLE=Admin SONAR_ROLE_LOCK_ENFORCED_SIG='Admin::'` donnait le rôle Admin **sans jeton**.
  Affectation simple à la déclaration. Le test échoue sans le correctif (vérifié).
- **MOYENNE — falsification du journal par `SONAR_ROLE_IDENTITY`.** L'identité (variable d'environnement non vérifiée pour
  un rôle libre-service) était ajoutée **après** l'assainissement centralisé : un saut de ligne forgeait une fausse
  élévation Admin dans `audit.log`. Identité assainie à l'ajout.

### NON corrigé — décisions à prendre (détail et correctifs minimaux dans le rapport)
Émission de jeton sans contrôle de rôle ; racine de confiance surchargeable par l'environnement (dont `SONAR_AUDIT_LOG=/dev/null`) ;
chaîne de hachage sans clé (troncature et réécriture complète non détectées) ; `.lock` inutilisable → audit perdu sans arrêter
l'action ; jeton passé en argument de ligne de commande. Non corrigés parce que chacun demande un choix produit ou casserait
des tests et des workflows existants ; aucun n'est traité par ce correctif.

### Non vérifié
Comportement sous `sudo` réel (`env_reset`) ; `hash="UNAVAILABLE"` sans outil SHA-256 ; contrôle des droits de `SONAR_ROLE_TOKEN_FILE`.

## [3.49.1-export-guards] — 2026-09-21

### Corrigé
- **`sonar_export_field_files` : la copie de `sonar_recover.sh` était imbriquée dans le `if` de
  `sonar_bitlocker.sh`.** Sans `tools/sonar_bitlocker.sh`, la récupération de données n'était pas déployée sur la
  clé — et **aucun message ne le disait** (le `else` ne parlait que de BitLocker). Chaque outil a maintenant sa
  propre garde et son propre message. Reproduit avant correctif (clé sans `sonar_recover.sh`), vérifié après dans les
  4 combinaisons présent/absent. Diff de 8 lignes, sans refactor.
- Constaté au passage : `sonar_pe_audit.sh` n'est **pas** déployé sur la clé, volontairement (outil du poste de
  construction), pas un bug.

### Ajouté
- Test de non-régression : pour chacun de `sonar_bitlocker.sh`, `sonar_recover.sh`, `sonar_diag.sh`, on retire
  l'outil de `tools/` et on vérifie que les deux autres sont quand même copiés (et que l'absent ne l'est pas).
  **Vérifié qu'il échoue sur l'ancien code** (« sans tools/sonar_bitlocker.sh, sonar_recover.sh n'a PAS été copié »).
  Ni l'audit ni l'ancien self-test ne pouvaient l'attraper : les deux fichiers sont toujours présents dans le dépôt.

## [3.49.0-recovery-carving] — 2026-09-21

### Ajouté
- `sonar_recover.sh carve` : recherche des fichiers **supprimés** par signatures (PhotoRec, lecture seule de la
  source), classement `CONNU` / `NOUVEAU` par SHA-256 contre la copie déjà faite, résumé qui annonce les limites
  (noms perdus, fragmentation). `plan` renvoie vers `carve` au lieu de « pas encore automatisé ».
- 6 tests : un zip supprimé d'un NTFS est retrouvé octet pour octet ; le zip conservé est reconnu ; source
  intacte ; type invalide refusé. Suite `recover` : 50 vérifications, stables sur 2 exécutions.

### Corrigé grâce à un vrai téléchargement
- L'archive **réelle** de TestDisk (SHA-256 conforme à notre manifeste scellé) était refusée par le post-traitement
  de `--fetch` : GNU tar appelle `lbzip2` pour un `.tar.bz2`, absent d'un système minimal ; le message
  « extraction refusée » ne disait rien. Les fixtures n'avaient pas vu ce cas. Le décompresseur est maintenant
  choisi explicitement (bzip2/lbzip2/pbzip2, gzip, xz, lzip), avec repli sur `7z` et un message qui NOMME l'outil manquant.
  Résultat : `photorec_static` 7.2 fonctionnel après `--fetch`.
- Une erreur de ma part (syntaxe PhotoRec `enable,zip` au lieu de `zip,enable`) faisait ne rien retrouver : le test
  l'a attrapée avant livraison.

### Non vérifié
- Le repli 7z n'a été exercé que sur l'archive TestDisk réelle (pas de fixture `.tar.bz2` sans bzip2).
- Carving : JPEG/PDF/Office, gros volumes, fichiers fragmentés ; toujours pas de vrai disque physique abîmé.

## [3.48.0-data-recovery] — 2026-09-21

### Contexte
« Peut-on construire notre propre système de récupération de données et l'intégrer ? » Réponse : pas un moteur
(ddrescue/ntfs-3g/PhotoRec sont éprouvés, une erreur de notre part sur un disque mourant est irréversible) mais la
**couche de pilotage** qui impose la bonne méthode et laisse une preuve. Première tranche : copie sûre.

### Ajouté
- `tools/sonar_recover.sh` : `plan` (méthode selon le diagnostic), `image` (ddrescue en 2 passes), `copy`
  (lecture seule, SHA-256 calculé à la lecture puis relecture de la copie, erreurs consignées, manifeste,
  résumé qui ne promet rien), `verify`. Garde-fous : source jamais écrite, destination ni sur le même disque
  ni dans la source, place vérifiée avant, source montée en lecture-écriture refusée.
- SONAR Field : option `r` ; `--field-export` déploie le script ; audit + `--self-test` câblés.
- `tests/recover/run_tests.sh` : 44 vérifications sur un disque **construit** (NTFS partitionné) dont un
  **disque défaillant simulé** par device-mapper. `docs/RECOVERY.md`.
- `tools/sonar_pe_audit.sh` + `tools/pe_audit_indicators.txt` + `tests/pe_audit/run_tests.sh` (22 vérifications)
  + `docs/PE_AUDIT.md` : audit **statique** d'un WinPE tiers (démarrage, registre hors ligne, tâches, hosts,
  raccourcis, fichiers ajoutés contre une référence, indicateurs d'affiliation en UTF-8 et UTF-16). Écrit pour
  examiner l'édition d'affiliation « 联盟版 » d'USM, **abandonnée** ensuite comme contraire à SONAR : rien n'a
  été téléchargé ni exécuté, aucune vraie édition n'a été analysée.

### Corrigé en route
- L'audit de notre propre WinPE a d'abord produit **des faux positifs** : valeurs de registre WinPE normales
  (`Shell`, `Userinit`, `CmdLine`) mal décodées (`strtonum` absent de mawk ; `hex(1)` non géré), mot chinois dans un
  fichier de données ICU de Microsoft, notre propre menu signalé. Corrigé (décodage sans `strtonum`, exclusion des
  ruches, des fichiers de données de `\Windows` et des binaires se déclarant Microsoft, programme fourni par le
  support ramené à INFO). Avec la bonne référence (WinPE propre + composants acceptés) : « aucun indicateur ».
- `sonar_recover.sh` : `losetup -P` crée les nœuds de partitions de façon asynchrone ; sans attente, une image
  partitionnée passait parfois pour « sans partition » (échec intermittent constaté). Attente ajoutée.

### Non vérifié
- Un vrai disque physique défaillant ; ext4/exFAT (seul NTFS testé) ; la recherche de fichiers supprimés
  (PhotoRec/TestDisk : étape suivante) ; le chapitre « récupération » du rapport client.

## [3.47.0-fetch-usable] — 2026-09-21

### Contexte
Relecture externe de `sonar_master.sh` : quatre défauts confirmés dans le code (le cinquième point du
rapport — fichiers `tools/` non fournis au relecteur — n'appelle aucune action).

### Corrigé
- **`--fetch` ne rendait pas les outils utilisables** : il vérifiait le SHA-256 mais laissait des `.zip`,
  un `.deb`, une archive source. Nouveau `sonar_fetch_postprocess`, appelé uniquement sur une archive
  déjà vérifiée : zip d'outil → `Portable/<Outil>/` ; zip contenant une ISO (Memtest86+, chntpw) → l'ISO
  dans `ISO/Fetched/` ; ClamAV `.deb` → extrait, élagué (459 → 91 Mo) et lanceurs `sonar-clamscan.sh` /
  `sonar-freshclam.sh` ; `.tar.lz` (ddrescue) → `SOURCE_ONLY`, dit clairement. État dans la colonne `STATE`
  de `MANIFEST_FETCH.tsv` ; récapitulatif des outils `MANUAL`/`SOURCE_ONLY` en fin de `--fetch`.
  Extraction sûre (noms contrôlés avant, `..` et chemins absolus refusés, liens sortants supprimés),
  idempotente, jamais fatale. `docs/DEPLOYMENT.md` corrigé.
- **`--protect-catalog` interrompait le déploiement** : `sonar_protect_catalog_final` retourne 1 (gpg absent,
  rôle insuffisant, passphrase absente) et, sous `set -e`, cela arrêtait `copy_payload_final` après copie des
  fichiers, avant le filigrane et le démontage. L'appel est désormais gardé (`if !`), le déploiement continue
  et un avertissement explicite dit que `MANIFEST.tsv` reste **en clair** (audit `CATALOG_PROTECTION_SKIPPED`).
- **Test `--field-export` sans racine isolée** : il s'exécutait avec `SONAR_ROOT` = le dépôt (risque de créer
  `Secure/`). Il utilise maintenant un dossier temporaire.
- **README** : « 6 profils » → « 8 profils (+ full) ».

### Vérifié
- 176 PASS / 0 FAIL au `--self-test` (WSL), dont 10 nouveaux tests d'extraction (zip→ISO, zip d'outil,
  idempotence, `.tar.lz`, `.exe`, `../` refusé, lien sortant supprimé, ClamAV `.deb` → lanceurs, refus sans
  signatures, lancement avec signatures).
- Sur le **vrai** `.deb` ClamAV 1.5.4 (SHA-256 conforme au manifeste) : extrait et élagué en 11 s ;
  `sonar-clamscan.sh` refuse sans signatures (code 2) ; `clamscan` et `freshclam` réels répondent
  « ClamAV 1.5.4 » depuis la copie portable.
- Le test a aussi trouvé un bug de mon lanceur : `ls db/*.cvd db/*.cld` échoue dès qu'un des deux motifs
  n'existe pas, donc il aurait refusé de tourner avec une base pourtant présente. Corrigé (boucle).

### Non vérifié
- Téléchargement réel des signatures par `freshclam` (~300 Mo) ; zip réels Memtest86+ / chntpw (couverts
  par des fixtures) ; `ddrescue` reste à compiler ou à prendre dans SystemRescue.
- Les colonnes NOTES du manifeste scellé décrivent encore les étapes manuelles : les modifier invaliderait
  le scellé HMAC, donc laissé tel quel.

## [3.46.0-winpe-adk-components] — 2026-09-21

### Contexte
Suite de « le WinPE est très limité » et « débloquer BitLocker ». Cause racine : `Dism /Add-Package` échoue
sur cet hôte Windows 10 pour une image WinPE 26100 (`0x80070057`), donc ni PowerShell, ni WMI, ni
`manage-bde`. Découverte : le **même DISM lancé dans un WinPE 26100 en marche** fonctionne.

### Ajouté
- `Build-SonarSE-WinPE.ps1 -IncludeAdkComponents` (défaut : oui) : servicing dans une VM VirtualBox UEFI
  sans fenêtre (ISO de servicing + ISO des `.cab` de l'ADK + disque de travail VHD), puis récupération de
  la `boot.wim` servie (montage VHD, une élévation) ; suite du build inchangée. Sans VirtualBox : avertit
  et construit l'image sans composants. `-ServicingTimeoutMinutes`, `-ServicedBootWim` (reprise).
  Paquets : WMI, NetFx, Scripting, PowerShell, StorageWMI, DismCmdlets, SecureStartup (+ en-US).
- Menu WinPE : `wpeinit` au démarrage (il manquait : WMI/réseau ne s'initialisaient pas) ; option 6
  affiche `manage-bde -status` ; option 17 PowerShell ; la vérification finale de l'ISO contrôle
  `manage-bde.exe` et `powershell.exe` quand les composants sont demandés.

### Vérifié (VM UEFI, volume BitLocker réel)
- Le servicing automatique (script généré par le build) a fini en ~8 min : 16 paquets « Installed »,
  `SERVICING_OK`, `boot.wim` de 503 Mo.
- WinPE construit avec cette `boot.wim` : `manage-bde -unlock C: -RecoveryPassword …` → « The password
  successfully unlocked volume C: », fichier lu ; `powershell Get-Volume` → volumes listés.

### Vérifié de bout en bout (2026-09-21, build complet accepté sous UAC, ISO 535 Mo)
- `Build-SonarSE-WinPE.ps1 -ServicedBootWim …` : marque BCD, menu 17 options, boîte à outils, ISO et
  vérification finale (qui contrôle menu, BusyBox, `manage-bde.exe`, `powershell.exe`) : tout passe.
- L'ISO finale, bootée en VM UEFI avec le volume BitLocker de test : le menu à 17 options s'affiche ;
  option 6 → « The password successfully unlocked volume C: » ; option 12 → rapport complet (UEFI détecté).
- ISO copiée sur la clé (`E:\ISO\WinPE\`, hash identique).

### Reste non vérifié
- Le servicing en VM lancé *dans le même run* que le reste (deux essais ont échoué sur un UAC refusé
  quand personne n'était devant l'écran) : ses deux moitiés sont prouvées séparément (servicing
  automatique OK, extraction par WSL ; build complet sur la `boot.wim` servie), mais l'étape
  `get.ps1` (montage du VHD) n'a pas tourné.
- Boot sur du matériel réel via Ventoy ; options 13, 14, 15 sur un vrai disque client.
- Un bug rencontré et corrigé : `rmdir` d'un dossier absent écrivait sur stderr et arrêtait le script.

## [3.45.0-bitlocker-unlock] — 2026-09-21

### Contexte
« Débloquer le déverrouillage BitLocker ». Le WinPE ne peut pas : `manage-bde` échoue en
`0x80040154 Class not registered` (fournisseur WMI absent, ajout impossible sans `Dism /Add-Package` —
testé en VM en copiant les fichiers de `WinPE-SecureStartup.cab`). Le déverrouillage est donc fait côté Linux.

### Ajouté
- `tools/sonar_bitlocker.sh` : `--list`, `--unlock`, `--lock`, `--lock-all`. Ouvre un volume BitLocker
  en **lecture seule** avec la clé de récupération (ou le mot de passe) fournie par le propriétaire :
  `cryptsetup bitlkOpen --readonly` + `mount -o ro`, repli `dislocker`. La clé est lue sans écho ou sur
  stdin, jamais en argument de commande, jamais journalisée. Refuse un périphérique sans signature
  `-FVE-FS-`, une clé mal formée, un volume déjà ouvert. Accord du propriétaire demandé en interactif.
- SONAR Field : option `b) BITLOCKER` ; `--field-export` déploie le script ; audit + tests câblés.
- `tests/bitlocker/run_tests.sh` : garde-fous toujours ; volume réel si `SONAR_BL_TEST_IMAGE` est fourni.
- `docs/BITLOCKER.md`.

### Corrigé
- **Boucle infinie** : dans `sonar_diag.sh` (et dans le nouvel outil), une option qui attend une valeur
  et se trouve en dernier argument (`--symptom` seul) faisait `shift 2` sans effet et bouclait à 100 % CPU.
  Corrigé par `shift $(( $# > 1 ? 2 : 1 ))` ; test de non-régression. Le même motif existe dans
  `sonar_master.sh` (27 occurrences) : non corrigé ici.
- Règle `F003` : renvoie vers l'option b de SONAR Field au lieu de « WinPE option 6 » (impossible).

### Vérifié (volume BitLocker réel créé sous Windows 10, XTS-AES 128)
Mauvaise clé refusée ; format invalide refusé ; bonne clé (48 chiffres collés) → ouvert, fichier lu ;
écriture → « Read-only file system » ; volume déjà ouvert refusé ; `--lock` referme ; journal sans la clé.

### Non vérifié
- Exécution sur SystemRescue même : `cryptsetup` (avec `bitlkOpen`) et `dislocker` y sont bien présents (vérifié dans `systemrescue-13.02` de la clé), mais l'outil n'a été exécuté que sous Ubuntu/WSL.
- BitLocker To Go, protecteurs TPM, NTFS sale/hibernation sur un volume déchiffré.

## [3.44.0-client-report] — 2026-09-20

### Contexte
Le rapport technique est fait pour le technicien ; un client n'en tire rien. Demande : que
le client lise une phrase claire pendant que le technicien garde les détails, sans IA, avec
une sortie PDF signée portant le filigrane de build existant.

### Ajouté
- `tools/client_templates.txt` : une phrase de constat et une recommandation prêtes pour
  chacun des 7 profils × 4 gravités (28 cellules), 6 verdicts globaux, 3 textes fixes et des
  surcharges par règle (`@F003` BitLocker, `@D001`, `@F004`, `@F002`, `@M003`, `@M006`).
- `sonar_diag.sh --client-report [DOSSIER|faits]` (`--client-name`, `--format`) : assemble le
  rapport à partir de `findings.tsv` avec `tools/client_report.awk` (awk pur, déterministe).
- `tools/text2pdf.awk` : générateur PDF 1.4 en awk pur (ASCII, polices standard, xref exacte),
  identique sous gawk, mawk et busybox awk ; validé par `qpdf --check` et un rendu poppler.
- Sceau (référence, SHA-256 du contenu, filigrane de build) + signature détachée ECDSA
  (`--sign-key`, `--sign-keygen`, `--verify-client-report`, `--pubkey`).
- SONAR Field : entrée de menu `c) RAPPORT CLIENT` ; `--field-export` déploie les 3 fichiers.
- 34 tests (`Client :`) dont : chaque cellule de gabarit présente, aucun jargon dans le texte
  client, jamais « aucun signe de panne » en diagnostic partiel/WinPE, critique jamais masqué
  par « partiel », PDF bien formé, déterminisme, signature valide / modifiée / mauvaise clé /
  empreinte falsifiée, filigrane présent ou déclaré absent.

### À savoir
- La signature est un fichier `.sig` détaché, pas une signature PDF intégrée reconnue par
  Acrobat. Le filigrane HMAC n'est vérifiable que sur la machine qui détient le secret de build.
- La clé privée de signature ne doit pas se trouver sur la clé SONAR-SE.
- `SONAR_KEY_DIR` permet d'isoler les tests de la vraie clé (les tests l'utilisent : une
  première exécution avait trouvé et lu le filigrane de la clé physique montée sous WSL).

## [3.43.0-winpe-toolbox] — 2026-09-20

### Contexte
Retour terrain : « le WinPE SONAR est très limité ». Cause racine établie :
sur un hôte Windows 10 (19045), DISM ne sait pas servir une image WinPE 26100
(`CPEImg::Attach 0x80070057`), donc aucun `/Add-Package` (PowerShell, WMI,
manage-bde) n'est possible. Au lieu de contourner DISM, la boîte à outils est
copiée dans l'image montée — le seul geste qui fonctionne sur cet hôte.

### Ajouté
- `Build-SonarSE-WinPE.ps1 -IncludeToolbox` (défaut : oui) : embarque BusyBox
  for Windows (busybox-w32 FRP-6075 w64u, **SHA-256 épinglé**, refus si
  différent), le collecteur WinPE, `diag_engine.awk` et `diag_rules.txt` dans
  `Windows\System32\sonar`. La vérification finale de l'ISO contrôle le menu
  ET la présence de la boîte à outils.
- Menu WinPE, options 12 à 16 : diagnostic intelligent (rapport écrit sur la
  clé, `Field-Logs\diag`), réparation UEFI automatique (`bcdboot`, ESP en
  lettre temporaire, confirmation), chargement de pilotes de stockage à chaud
  (`drvload` + re-scan), lanceur d'outils portables de la clé, shell BusyBox.
- `tools/winpe/sonar_diag_winpe.sh` : collecteur WinPE (diskpart, reg, bcdedit,
  fsutil, accès brut aux volumes) qui produit les **mêmes clés de faits** que le
  collecteur Linux ; le moteur de règles est commun.
- Règle `S010` : un diagnostic WinPE n'évalue ni SMART ni journaux ; le libellé
  du score ne dit alors jamais « bon état apparent ». Scénario de test
  `tests/diag/winpe.facts` + 3 assertions.

### Vérifié
- **Boot réel en VM UEFI (VirtualBox) de l'ISO reconstruite** : le menu à 16 options
  s'affiche, la boîte à outils est présente (`Windows\System32\sonar`), le
  collecteur s'exécute, le moteur charge 37 règles et produit le rapport
  (firmware UEFI, machine identifiée, libellé « SMART/matériel non évalués »).
- Ce test VM a révélé et fait corriger 3 défauts que les tests sur hôte ne
  montraient pas : `PEFirmwareType` est ABSENT du registre WinPE tant que
  `wpeutil UpdateBootInfo` ne l'a pas écrit (firmware « ? ») ; `awk -v`
  interprète les antislashs des chemins `X:\windows\...` (0 règle chargée,
  rapport vide mais « 100/100 ») → chemins en barres obliques ; `bcdedit
  /enum` échoue en WinPE (magasin non ouvrable) → le collecteur n'émet plus de
  faux « aucune entrée Windows ».
- Le collecteur a été exécuté (élevé) sur la vraie machine : modèles de
  disques, type de bus, GPT/MBR, volumes, ESP (bootmgfw + BCD), BitLocker par
  signature, état NTFS, espace libre ; la clé SONAR-SE et le lecteur du WinPE
  sont exclus des volumes « client ».
- Pièges trouvés en test réel et corrigés : `dd if=//./C: bs=16` échoue
  (« Invalid argument »), la lecture brute exige `bs=512` ou `head -c` ; le
  modèle de disque est repéré par la ligne « ID » (GUID/8 hexa), pas par un
  libellé, donc indépendant de la langue ; un chiffre juste avant `>` dans un
  `echo` cmd (`volume 3> f`) devient une redirection de handle.

### Non vérifié
- Le boot de l'ISO sur du **matériel réel** via Ventoy (seule une VM a été
  bootée) ; les options 13 (`bcdboot`), 14 (`drvload`) et 15 n'ont pas été
  exécutées sur un vrai disque client — elles ne modifient rien sans
  confirmation, mais leur effet réel reste à constater.
- La détection de la clé (`MANIFEST\PROFILES.tsv`) et l'écriture du rapport
  dans `Field-Logs\diag` n'ont pas été testées en WinPE (aucune clé dans la VM).

## [3.42.1-diag-crlf-safe] — 2026-09-20

### Contexte
Relecture après 3.42.0 : `.gitattributes` ne forçait le LF que pour `*.sh`.
Avec `core.autocrlf=true` (défaut de Git pour Windows), `tools/diag_rules.txt`
et `tests/diag/*.facts` auraient été extraits en CRLF sur un poste Windows,
puis copiés tels quels sur la clé et lus sous Linux : un CR en fin de ligne
fausse silencieusement les comparaisons (`uefi\r` ≠ `uefi`), donc des règles
ne se déclencheraient plus, sans aucune erreur.

### Corrigé
- `.gitattributes` : LF forcé pour `tools/diag_rules.txt`,
  `tests/diag/*.facts` et `*.awk`.
- Le moteur retire lui-même les caractères de contrôle de fin de ligne
  (`[[:cntrl:]]`, portable gawk/mawk/busybox) à la lecture des faits et des
  règles : robuste même si un fichier est édité sous Windows.
- 2 tests de non-régression (faits en CRLF, règles en CRLF ⇒ même rapport).

### Vérifié, et pièges rencontrés
- Contrôle du test : sans le correctif, la règle B001 disparaît avec des
  faits CRLF (0 ligne) ; avec, elle est là (1 ligne) — sous un vrai `gawk`
  Linux (WSL). **Sous Git Bash le même contrôle est vide** : l'`awk` d'MSYS lit
  en mode texte Windows et avale déjà les CR. Un test passé « au vert » sous
  Git Bash n'aurait rien prouvé.
- Deux tentatives d'écriture du `\r` ont mal tourné avant le bon résultat :
  `sed` a inséré un vrai octet CR dans le code (invisible, fonctionnel mais
  fragile), puis `perl -pi` a converti le fichier entier en CRLF. Les deux
  ont été détectés en comptant les octets 0x0d (`tr -cd '\r' | wc -c`), pas
  avec `grep -c $'\r'`, qui compte à tort toutes les lignes dans cet
  environnement. Solution finale sans aucun antislash : classe POSIX.

`--self-audit` 21/21, `--self-test` 114 PASS, 0 FAIL (WSL).

## [3.42.0-intelligent-diagnostic] — 2026-09-20

### Contexte
Demande directe : « construit un diagnostic intelligent ». Existant :
`--diagnostic` (simple relevé de l'hôte) et `--smart-advisor` (contrôle de
l'état de SONAR lui-même) — rien qui analyse la **machine en panne** pour
en déduire une cause probable et un plan d'action.

### Ajouté — `tools/sonar_diag.sh` + `tools/diag_rules.txt`
Trois étages, du plus fiable au plus consultatif :
1. **Collecte** (lecture seule ; partitions montées en `ro`) : SMART SATA et
   NVMe, erreurs d'E/S noyau par disque, cohérence de la table de
   partitions, ESP / `bootmgfw.efi` / BCD, détection BitLocker, état NTFS
   (sale, hibernation), espace libre, machine-check / ECC, bridage
   thermique, températures, usure batterie, entrées UEFI. La clé
   SONAR-SE/Ventoy est exclue de l'analyse.
2. **Moteur de règles déterministe** (awk pur, ~36 règles en données
   éditables) : mêmes faits ⇒ même rapport. Chaque constat porte gravité,
   confiance chiffrée, **faits déclencheurs**, cause probable, action,
   profil SONAR-SE et « à éviter ». Score = `100 − Σ(poids × confiance)`,
   poids affichés. Corrélation : les indices concordants renforcent la
   confiance (SMART FAILED + secteurs en attente + erreurs d'E/S ⇒ 99 %).
   Priorité à la sécurité des données (un disque mourant passe avant toute
   réparation de démarrage, `chkdsk /r`/`fsck` explicitement interdits).
   Plan d'action sans doublon (une étape par profil). Le rapport ne
   rassure jamais à tort : blocage grave ou diagnostic partiel (sans
   root) ⇒ libellé dégradé / « NON CONCLUANT ».
3. **IA locale optionnelle** (`--ai`) : Ollama LOCAL uniquement (un moteur
   distant est refusé), rapport présenté comme donnée et non comme
   instructions, consultatif (le rapport déterministe fait foi).
   Repli propre si Ollama est absent/injoignable.

Intégration : `Scripts/sonar_diag.sh` + `MANIFEST/DIAG_RULES.txt` déployés
par `sonar_export_field_files` (donc `--disk` et `--field-export`),
entrée **d)** dans le menu de SONAR Field (journalisée), commande
`--diag-analyze <faits> [--symptom S] [--ai]` pour rejouer sur le poste du
technicien. Documentation : `docs/DIAGNOSTIC.md`.

### Vérifié
- 31 nouveaux tests (`tests/diag/run_tests.sh`, relayés par `--self-test`) sur
  7 scénarios de faits construits à la main : machine saine (silence,
  100/100), disque mourant, ESP effacée, BitLocker, erreurs machine-check,
  exécution sans root, garde-fous IA. Un test de contrôle prouve que la
  vérification « disque sain non accusé » n'est pas vide (le premier jet
  utilisait `\t` dans `grep -E`, qui ne signifie pas tabulation).
- Collecteur exécuté pour de vrai (WSL root) : 42 faits réels lus,
  règles déclenchées correctement.
- IA réelle testée avec `gemma3` : fonctionne, mais **217 s** sur CPU seul
  (i7-6600U, sans GPU). Trois défauts trouvés en test réel et corrigés :
  délai de 300 s trop court (désormais 900 s, `SONAR_AI_TIMEOUT`), prompt
  condensé + sortie limitée pour réduire le temps, et `python3` — sous
  Git Bash c'est le faux raccourci du Windows Store (présent mais
  inutilisable) — remplacé par un test de bon fonctionnement puis repli
  `sed`. Le message d'erreur accusait à tort « modèle absent » pour un
  simple délai dépassé : il distingue maintenant délai / modèle / autre.
  Sortie réelle observée (gemma3, 4 min 10 s) : correcte sur l'essentiel mais
  avec une **dérive de paraphrase** — « système de fichiers corrompu » alors
  que le rapport dit « marqué sale », et « fin de vie » durci en « erreurs
  critiques ». Confirme le choix de conception (IA consultative, rapport
  déterministe qui fait foi) ; une consigne « reprends les termes exacts »
  a été ajoutée au prompt, **son effet n'a pas été re-mesuré**.
- `--self-audit` 21/21, `--self-test` 112 PASS, 0 FAIL (WSL).

### Limites (voir `docs/DIAGNOSTIC.md`)
Collecte Linux uniquement à ce stade (le WinPE n'a ni PowerShell ni WMI).
SMART derrière certains ponts USB/RAID reste illisible (règle D012 le dit).
Règles = heuristiques de terrain, seuils à ajuster.

## [3.41.0-radar-background] — 2026-09-20

### Contexte
Test réel du 2026-09-20 sur le HP EliteBook 840 G3 : après le fix
`boot_menu` (3.40.1), la clé démarre **toutes les ISO sans demander de
code** et affiche le fond personnalisé en plein écran avec les entrées
de démarrage par-dessus — **confirmé sur matériel**. Ferme le point P0
« thème Ventoy re-testé sur le HP EliteBook 840 G3 ».

### Changé
- Nouveau fond fourni par l'opérateur (radar vert / globe, 736×735) :
  posé sur un canevas noir 800×600 (4:3, comme le `gfxmode` du thème)
  → aucune déformation quand GRUB l'adapte à l'écran ; bandeau
  « SONAR - SE / Sekou SANOU - Burkina Faso » incrusté en bas ; PNG8
  256 couleurs (~139 Ko). Remplace `Branding/default_background.png`
  (l'ancien globe bleu reste dans l'historique git).
- Couleurs du menu alignées sur le radar : entrées `#7dff7d`,
  sélection blanche, panneau sombre teinté vert, texte de version
  Ventoy `#7dff7d`.
- Appliqué sur la clé physique (`background.png.bak-globe-bleu` conservé).

`--self-audit` 20/20, `--self-test` 81 PASS, 0 FAIL (WSL).

## [3.40.1-ventoy-theme-boot-menu] — 2026-09-20

### Contexte
Premier vrai test de boot sur le HP EliteBook 840 G3 depuis le fix
`theme.txt` (v3.35.0) : **plus de crash GRUB** (`alloc magic is broken`
n'apparaît plus — ce fix-là est donc confirmé), mais la clé reste figée
sur le fond d'écran SONAR-SE, sans aucun menu.

### Cause
Le `theme.txt` généré ne contenait que `desktop-image` et `title-text`.
Un thème GRUB2 (gfxmenu) ne dessine un menu que si le composant
`+ boot_menu { ... }` y est déclaré ; sans lui, seul le fond s'affiche.
Le commentaire d'origine dans `sonar_prepare_ventoy_theme` ("une seule
directive nécessaire") était faux — erreur d'analyse de ma part en
3.35.0 : je n'avais vérifié que la disparition du crash, pas l'affichage
effectif du menu. La documentation Ventoy (`plugin_theme.html`) ne donne
pas d'exemple complet de `theme.txt`, donc ce point n'était pas
découvrable par simple lecture.

### Corrigé
- `theme.txt` déclare maintenant `+ boot_menu` (gauche 6 %, haut 10 %,
  50 × 58 %, texte blanc, sélection `#66ccff`), police `Unifont Regular
  16` (nom standard de `unicode.pf2` de GRUB ; un nom inconnu retombe sur
  la première police chargée).
- Panneau sombre semi-transparent derrière le menu (`menu_c.png`, style
  `menu_*`), généré par ImageMagick **seulement s'il est présent** — le
  menu reste fonctionnel sans, juste moins lisible sur le globe.
- Texte de version Ventoy déplacé de 10 %/38 % (au milieu de la zone du
  menu) vers 2 %/96 % (bas de l'écran).
- Test `--self-test` ajouté : échoue si `theme.txt` n'a pas de
  `boot_menu` (`--self-test` : 81 PASS, 0 FAIL ; `--self-audit` : 20/20).
- Appliqué sur la clé physique, avec sauvegardes
  (`theme.txt.bak-20260920`, `ventoy.json.bak-20260920`).

### Non vérifié
**Pas encore reconfirmé par un boot réel.** L'affichage du menu est la
conséquence attendue de `+ boot_menu`, pas un fait observé. Si le menu
reste invisible, retour arrière immédiat : `ventoy.json` → retirer le
bloc `"theme"`.

## [3.40.0-winpe-boot-branding] — 2026-09-18

### Contexte
Demande directe : retirer le logo Windows animé affiché au démarrage de
WinPE et le remplacer par "SONAR - SE".

### Corrigé/Ajouté
`tools/Build-SonarSE-WinPE.ps1` : nouveau paramètre `-BrandBootManager`
(activé par défaut). Avant que `startnet.cmd` ne prenne la main, WinPE
affiche normalement quelques secondes de logo Windows animé, dessiné
par `winload`/`bootmgr` à partir du magasin BCD de l'image. Ce
paramètre :

- Renomme `{bootmgr}` et `{default}` de "Windows Boot Manager"/"Windows
  Setup" vers **"SONAR - SE"** (`bcdedit /store <fichier> /set ...
  description`).
- Désactive l'animation graphique (`bootuxdisabled yes`).
- Appliqué aux **deux** magasins BCD générés par `copype` (BIOS
  `media\Boot\BCD` et UEFI `media\EFI\Microsoft\Boot\BCD`) — Ventoy peut
  chainloader l'un ou l'autre selon le micrologiciel de la machine
  cible.

Délibérément limité à des opérations `bcdedit /store` standard sur le
magasin de l'image en construction (jamais le magasin BCD du système
hôte) — même registre de risque que les autres commandes bcdedit du
menu de réparation. Un remplacement littéral du logo (patch binaire de
`bootres.dll` ou équivalent) a été explicitement écarté : gain cosmétique
marginal (écran visible 2-3 secondes) pour un risque de casser le boot
disproportionné — même discipline que le thème Ventoy (v3.25.0/v3.26.0),
qui a déjà coûté plusieurs heures de diagnostic pour un cas similaire.

### Bloqué puis débloqué : UAC
Cinq tentatives de reconstruction ont échoué avec "L'opération a été
annulée par l'utilisateur" sur les appels `Start-Process -Verb RunAs` —
fenêtre UAC jamais validée (timeout ~2-3 min sans clic, l'opérateur
n'étant pas physiquement devant l'écran). Reconstruction réussie à la
sixième tentative une fois l'opérateur présent pour valider les
invites — pas un bug du script, une contrainte d'interaction humaine
inévitable pour toute élévation Windows.

Test : ISO reconstruite (`-SkipAdkInstall`, `-BrandBootManager` par
défaut). Vérifié au-delà du contrôle automatique du script : copie des
deux magasins BCD hors de l'ISO final (montage lecture seule) puis
`bcdedit /store ... /enum` — confirmé `description` = `SONAR - SE` sur
`{bootmgr}` et `{default}`, `bootuxdisabled` = `Yes` sur `{default}`,
sur les deux magasins (BIOS et UEFI). SHA-256 final :
`edb7a8ca4817442797cad6b692f53f596ddbf70953de0d0c78e35721a21bd6e7`
(378,8 Mo). `sonar_master.sh` non modifié fonctionnellement (seul
`SONAR_VERSION` change).

## [3.39.0-winpe-menu-expansion] — 2026-09-18

### Contexte
Demande directe : identifier puis combler les manques du menu de
réparation WinPE (`tools/Build-SonarSE-WinPE.ps1`, ajouté en 3.36.x).
L'ancien menu (bootrec, bcdedit, diskpart, DISM) laissait plusieurs
scénarios réels sans option dédiée — notamment le blocage le plus
fréquent en pratique (disque BitLocker verrouillé, qui empêche TOUTES
les autres options de fonctionner) et l'absence de tout mécanisme
d'injection de pilotes malgré le dossier `Drivers/` déjà présent sur la
clé.

### Ajouté
Menu étendu de 6 à 11 options :

- **SFC hors ligne** — complémentaire à DISM (composants vs fichiers
  système protégés), pas redondant.
- **Déverrouillage BitLocker** (`manage-bde`) — le blocage le plus
  courant en pratique sur du matériel récent (chiffrement de l'appareil
  activé par défaut).
- **Injection de pilotes** (`Dism /Add-Driver`) — utile quand
  `diskpart`/`bootrec` ne voient aucun disque (contrôleur NVMe/RAID
  récent absent du WinPE de base).
- **Sauvegarde de fichiers utilisateur** (`robocopy`) avant réparation
  risquée.
- **Export des journaux d'événements** (`.evtx`) pour diagnostiquer la
  cause avant de réparer à l'aveugle.
- **Diagnostic réseau** (`ipconfig`/`ping`).

Toutes ces commandes sont des binaires Windows de base déjà présents
dans WinPE — vérifié un par un par remontage DISM en lecture seule de
l'ISO déjà construit AVANT d'écrire le menu (pas supposé) :
`manage-bde` **absent**, `sfc`/`robocopy`/`ipconfig`/`ping`/`bcdedit`
**présents**.

### Trouvé en vérifiant, et traité honnêtement (pas caché)
`manage-bde` nécessite le composant `WinPE-SecureStartup`, ajouté par
`Dism /Add-Package` — la même famille d'opération que
`-IncludePowerShell` (3.24.x), déjà documentée comme cassée sur cet
hôte. Reproduit le même échec exact ("Erreur: 87 — Une erreur
d'initialisation s'est produite") avec `WinPE-SecureStartup`, en
utilisant le même mécanisme robuste que le bloc PowerShell existant
(`Cleanup-Mountpoints`, `call "$setEnvBat"`, `!errorlevel!` en
comparaison numérique) — confirme une incompatibilité générale
ADK/DISM sur cet hôte pour `/Add-Package`, pas un problème spécifique à
BitLocker.

Traitement : nouveau paramètre `-IncludeBitLockerTools` (désactivé par
défaut, même contrat que `-IncludePowerShell`) qui tente l'ajout quand
même — utile sur un hôte où `/Add-Package` fonctionne. **Sans cette
option**, l'entrée BitLocker du menu détecte l'absence de
`manage-bde.exe` au runtime et l'indique clairement au lieu d'échouer
avec un message `cmd.exe` cryptique ("'manage-bde' n'est pas reconnu…").
Les 10 autres options fonctionnent normalement quel que soit ce
paramètre.

Une erreur de méthodologie a été corrigée en cours de route : le tout
premier test de `/Add-Package` sur `WinPE-SecureStartup` a échoué avec
"0xc1510111 — permissions insuffisantes", pas l'erreur 87 attendue —
root cause identifiée (le `boot.wim` de test avait été copié depuis un
ISO monté, donc hérité de l'attribut lecture seule du média source) et
corrigée avant de conclure quoi que ce soit sur la vraie compatibilité
`WinPE-SecureStartup`.

Test : ISO reconstruite avec `-SkipAdkInstall` (sans
`-IncludeBitLockerTools`, valeur par défaut). Vérification automatique
du script (présence du titre du menu) **et** vérification manuelle
approfondie (remontage DISM en lecture seule, `findstr` des 8 nouveaux
libellés + de la ligne de détection `manage-bde.exe`, confirmation que
`manage-bde` est bien absent et que `sfc`/`robocopy` sont bien
présents) — toutes concordantes. SHA-256 final :
`39ffbb2ae6038a2d6d2e374b699eec5974f77a03ff3470609676d32e8adf92e8`
(378,8 Mo). `--self-audit` (20/20) et `--self-test` (80 PASS, 0 FAIL)
de `sonar_master.sh` toujours au vert (fichier non modifié
fonctionnellement, seul `SONAR_VERSION` change).

## [3.38.0-kali-installer] — 2026-09-18

### Contexte
Répond au "Non résolu" de [3.30.0] : remplacement d'un vrai Kali Linux
bootable, jamais retrouvé depuis que `kali-linux-2026.2-virtualbox-
amd64.7z` (appliance VirtualBox, jamais bootable par Ventoy) a été
écarté.

### Recherché avant de trancher
Confirmé sur deux sources officielles indépendantes (`cdimage.kali.org`
et `kali.org/get-kali`) : l'image **live** amd64 (bureau pentest complet
pret a l'emploi au demarrage) n'est distribuee par Kali **qu'en
torrent** — aucune URL HTTP directe n'existe pour elle, sur aucun miroir
officiel. C'est une politique de distribution deliberee de Kali, pas une
panne ou un miroir manquant a chercher plus longtemps — la piste
"trouver un miroir HTTP pour le live" est un cul-de-sac confirme, pas
juste inexploree.

### Corrigé
Ajout de l'image **installer** amd64 (`kali-linux-2026.2-installer-
amd64.iso`, 4,5 Go) au manifeste `--fetch` et au profil `general-os` —
c'est la seule variante Kali disponible en HTTP direct et verifiable
(compatible avec le modele `--fetch` de SONAR). SHA-256 recoupe sur deux
methodes independantes contre `kali.download/base-images/kali-2026.2/
SHA256SUMS` (source officielle vers laquelle `cdimage.kali.org`
redirige).

**Limitation assumée et documentée** (dans le catalogue ET le
CHANGELOG, pas cachée) : c'est une image d'installation Debian, pas un
environnement live — elle installe Kali sur un disque au lieu d'ouvrir
un bureau pentest immédiatement au démarrage. Compromis délibéré :
bootable et vérifiable en HTTP direct plutôt qu'absente du catalogue.
La variante "netinst" (743 Mo, a besoin du réseau pendant
l'installation) et "purple" (Kali Purple, blue team — produit différent)
ont été écartées : la première contredit la philosophie offline-first de
SONAR (terrain à réseau instable), la seconde n'est pas ce qu'un
opérateur attend en demandant "Kali".

Test : URL et SHA-256 vérifiés en direct (`curl` + recoupement
`kali.download`), redirection géographique de `cdimage.kali.org`
confirmée compatible avec le `-fL` déjà utilisé par
`sonar_fetch_one_tool` (même mécanisme que l'entrée Arch Linux
existante). `--self-audit` (20/20) et `--self-test` (80 PASS, 0 FAIL)
exécutés sous WSL après l'ajout.

## [3.37.1-policy-migration] — 2026-09-18

### Contexte
Résout le "Non résolu" laissé par [3.37.0-protect-catalog] : aucun
mécanisme ne détectait un `Secure/Policies/policy.tsv` local périmé sur
une installation existante — `sonar_security_init` ne régénère jamais un
fichier déjà présent, quelle que soit l'ancienneté de son contenu par
rapport au défaut actuel du script.

### Corrigé
`sonar_policy_check_stale()`, appelée à chaque `sonar_security_init` (donc
à chaque invocation du script) :

- Si le fichier sur disque correspond **exactement** (SHA-256) à l'ancien
  défaut permissif d'avant le 2026-09-17 (`Viewer VAULT=R`,
  `Technician VAULT=RW` — voir commit `f457156`) : sauvegarde horodatée
  (`policy.tsv.bak.<timestamp>`), régénération avec le défaut actuel,
  message `[SONAR][SECURITE]` explicite, événement d'audit
  `POLICY_MIGRATED`. Migration automatique **uniquement** sur cette
  signature exacte connue — jamais sur un simple écart de contenu, pour
  ne jamais écraser silencieusement une personnalisation délibérée de
  l'opérateur (une vraie décision produit).
- Sinon, si `Viewer` et/ou `Technician` (rôles libre-service, sans jeton)
  ont un accès VAULT différent de `-` : avertissement
  `[SONAR][ATTENTION]` + audit `POLICY_PERMISSIVE_VAULT_DETECTED`, **sans
  jamais modifier le fichier** — couvre le cas général (un policy.tsv
  personnalisé différemment, ou une future régression du même genre),
  pas seulement le cas historique précis du 2026-09-17.

2 nouveaux tests dans `--self-test` (migration automatique du cas connu
avec sauvegarde vérifiée ; un policy.tsv personnalisé n'est jamais
modifié) + 1 dans `--self-audit`.

Test : reproduit les deux scénarios avec un `policy.tsv` de test écrit à
la main (ancien défaut exact, puis contenu personnalisé) sous un
`SONAR_ROOT` isolé — confirmé migration+sauvegarde dans le premier cas,
fichier intact dans le second. `--self-audit` (20/20) et `--self-test`
(80 PASS, 0 FAIL) exécutés sous WSL. Vérifié que le `policy.tsv` réel de
ce dépôt (déjà à jour depuis [3.37.0-protect-catalog]) n'est ni modifié
ni dupliqué en sauvegarde par ce changement.

## [3.37.0-protect-catalog] — 2026-09-18

### Contexte
Demande directe (protection contre la "reproduction anarchique" de la
clé). Rappel physique incontournable : un clone `dd` bit-à-bit d'un
disque USB bootable en clair est impossible à empêcher techniquement —
tout ce qui est nécessaire au boot doit rester lisible. L'objectif
réaliste n'est donc pas "impossible à copier" mais "copie sans valeur" :
protéger ce qui n'est PAS nécessaire au boot/dépannage plutôt que
d'ajouter une couche qui casserait Ventoy ou `sonar_field.sh`.

Vérifié avant d'ajouter quoi que ce soit : `Secure/Keys/role_secret.key`
n'est déjà jamais copié sur la clé (`copy_payload_final` ne copie que
ISO/Portable/Scripts/Drivers/macOS/manifestes/vault/champ/filigrane) — un
clone brut n'a donc déjà aucun moyen d'escalader vers Admin/Forensic/
VAULT. Le filigrane de build (`BUILD_WATERMARK.txt`, HMAC-SHA256 + registre
local, v3.x antérieure) couvrait déjà la traçabilité. Le seul manque réel :
`MANIFEST/MANIFEST.tsv` (curation complète — quel outil, pourquoi, SHA-256)
circule en clair sur toute clé, clonée ou non.

### Corrigé
`--protect-catalog` (opt-in, rôle VAULT requis) : chiffre
`MANIFEST/MANIFEST.tsv` en place avec `gpg --symmetric --cipher-algo
AES256` avant la fin de `copy_payload_final`, retire le fichier en clair.
Mot de passe jamais en argument — `SONAR_PROTECT_PASSPHRASE` uniquement
(même discipline que le fix `ai_query_local`/`ollama_query` de la session
précédente). Validation fail-fast dans `parse_args_final` : `--protect-
catalog` sans la variable d'environnement arrête le script avant même de
commencer, plutôt que de déployer silencieusement une clé non protégée.
Vérifié que ni Ventoy (scanne `/ISO` directement) ni `sonar_field.sh`
(ne lit que `MANIFEST/PROFILES.tsv`) ne lisent `MANIFEST.tsv` — le
chiffrer ne casse donc jamais le boot ni le dépannage de terrain.
Déchiffrable avec le coffre déjà déployé (`Scripts/sonar-vault.sh open`,
même format gpg AES-256 — aucun nouvel outil à distribuer).

4 nouveaux tests dans `--self-test` (opt-out sans effet par défaut, refus
sans rôle VAULT, aller-retour chiffrement/déchiffrement réel) + 1 dans
`--self-audit` (présence de la fonction).

### Trouvé en testant (hors périmètre de la demande, corrigé séparément)
Le test "refuse sans rôle VAULT" a d'abord échoué à tort : il dépendait
de `Secure/Policies/policy.tsv`, qui existait déjà sur cette machine avec
d'ANCIENNES valeurs (`Technician VAULT=RW`) — antérieures au durcissement
RBAC de la session du 2026-09-17. `sonar_security_init` ne régénère
jamais un fichier déjà présent, donc ce fichier local (gitignored, jamais
committé) était resté silencieusement périmé malgré le fix déjà en place
dans le script : la protection VAULT n'était donc *pas réellement active*
sur cette installation avant ce test. Fichier supprimé et régénéré avec
les valeurs correctes ; test durci pour ne plus jamais dépendre d'un
`policy.tsv` ambiant (`SONAR_POLICY_FILE` pointé explicitement vers une
racine isolée). **Non résolu** : `sonar_security_init` n'a toujours pas
de mécanisme de migration/versionning pour détecter un `policy.tsv` local
périmé sur une installation existante — seul un fichier absent déclenche
la régénération. Impact réel limité (fichier local non versionné, jamais
distribué avec la clé), mais reste un angle mort pour toute autre
installation de développement plus ancienne.

Test : `--self-audit` (19/19) et `--self-test` (77 PASS, 0 FAIL, 3 WARN
pré-existants sans rapport) exécutés sous WSL après correction.

## [3.36.12-selftest-stderr-visible] — 2026-09-17

### Contexte
Item [13] du plan de correctifs (audit externe DeepSeek) : des dizaines
de sous-tests de `sonar_self_test_v2` invoquent `"$self" --flag`
avec `2>/dev/null` — c'est précisément ce mécanisme qui a masqué le bug
`BASH_SOURCE[0]` (3.36.0) pendant plusieurs versions : l'échec réel
partait silencieusement sur stderr, et le rapport ne montrait qu'un
`FAIL` sans cause.

### Analysé avant de corriger
Deux motifs différents cohabitent : (a) `2>&1` (capture stdout+stderr
ensemble dans une variable) — déjà visible, rien à faire ; (b)
`>/dev/null 2>&1` en test booléen `if ... ; then PASS ; else FAIL` — ce
motif-là perd vraiment stderr. Seulement **7 occurrences exactes** de
(b) dans tout le fichier ; parmi elles, 4 sont des tests qui **attendent**
un échec par construction (profil invalide, jeton absent...) — y
afficher stderr n'aiderait pas au diagnostic (l'échec EST le résultat
correct). Les **3 restantes** sont des smoke tests où un succès est le
résultat normal — un échec y est une régression potentielle qui mérite
d'être expliquée.

### Corrigé
`--module-status`, `--recovery-execute collect`, `--verify-hashchain` :
stderr capturé (`2>&1 >/dev/null`, dans cet ordre — capture stderr seul
sans re-exécuter la commande) et affiché entre parenthèses si le test
échoue. Les 4 tests "attend un échec" et les nombreux `2>&1`/`2>/dev/null`
sur simple capture de sortie propre (jetons, JSON) laissés inchangés —
retirer la suppression seulement là où l'échec silencieux n'est PAS le
comportement attendu, comme demandé par ce point du plan.

Test : simulé un échec avec message stderr, confirmé que le message
apparaît bien dans le `FAIL` au lieu de disparaître.

## [3.36.11-tsv-tab-guard] — 2026-09-17

### Contexte
Item [12] du plan de correctifs (audit externe DeepSeek) : les 4 TSV
embarqués en heredoc (`SONAR_CATALOGUE_EMBEDDED`, `SONAR_PROFILES_TSV`,
`SONAR_FETCH_MANIFEST_TSV`, `SONAR_EMBEDDED_CATALOG_TSV`) contiennent de
vraies tabulations en dur. `.gitattributes` force LF mais pas les
tabulations — un éditeur qui les convertit en espaces casse
`awk -F'\t'` (et donc chaque outil qui en dépend) sans erreur visible.

### Corrigé
`sonar_structural_self_audit` (`--self-audit`) vérifie désormais chacun
des 4 TSV : extrait le bloc via ses marqueurs heredoc, `awk -F'\t'
'NF<2'` sur chaque ligne non vide — échoue bruyamment en nommant le TSV
et la ligne fautive si une tabulation manque. `awk` plutôt que
`grep -P '\t'` (trop permissif — suffirait avec une seule tabulation
n'importe où dans la ligne).

Test : corruption simulée (tabulations → espaces sur une ligne de
`SONAR_PROFILES_TSV`) sur une copie du script, confirmé que
`--self-audit` la détecte et nomme la ligne exacte. 14 → 18 vérifications
dans `--self-audit`.

## [3.36.10-selftest-extraction-guarded] — 2026-09-17

### Contexte
Item [11] du plan de correctifs (audit externe DeepSeek) : les ~12
sous-tests de `sonar_self_test_v2` qui isolent une fonction unique
utilisent `source <(sed -n '/^func() {/,/^}/p' "$self")`. Fonctionne
aujourd'hui, mais casserait silencieusement si un heredoc À L'INTÉRIEUR
de la fonction contenait un `}` en début de ligne : la plage `sed` se
refermerait prématurément, `source` chargerait une fonction tronquée
(syntaxiquement invalide en isolation — heredoc jamais fermé), et le
sous-test tournerait sur un comportement partiel au lieu de la fonction
réelle.

### Corrigé
Nouvelle fonction `sonar_selftest_extract_fn SELF FUNCNAME` : fait la
même extraction `sed`, mais vérifie que l'extrait n'est pas vide,
contient bien l'en-tête `FUNCNAME() {`, et passe `bash -n` — sinon
échoue bruyamment (message sur stderr, code de sortie non nul) au lieu
de laisser passer un extrait tronqué. Les 12 points d'appel remplacés
uniformément (`source <(sed -n ...)` → `source <(sonar_selftest_extract_fn
"$self" FUNCNAME)`).

Option alternative du plan (`if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
main_final "$@"; fi` + sourcer tout le script) écartée : changement
d'architecture bien plus large pour un gain équivalent — le garde-fou
ciblé résout le risque réel sans toucher à la structure d'exécution du
script.

Test ajouté (vérification manuelle, pas dans le self-test lui-même :
tester le garde-fou DANS le harnais qu'il garde serait circulaire) :
simulé un fichier avec une fonction contenant un heredoc `}` en début de
ligne — confirmé que l'extrait brut serait tronqué (comme décrit) et que
`sonar_selftest_extract_fn` le détecte et refuse de le sourcer.

## [3.36.9-ai-prompt-stdin-not-argv] — 2026-09-17

### Contexte
Item [10] du plan de correctifs (audit externe DeepSeek) : `ai_query_local`
passait le prompt IA à `python3 -c` en argv, visible via `/proc/<pid>/
cmdline`/`ps` pendant l'exécution — même catégorie de problème déjà
corrigée pour les secrets HMAC (v3.14.0), pas appliquée ici.

### Trouvé en plus — une deuxième occurrence non signalée par l'audit
En corrigeant, une fonction **distincte** avec le même défaut :
`ollama_query()` (utilisée par la résolution IA du catalogue,
`--ai-download`) passait aussi son prompt en argv à `python3 -`. L'audit
externe n'avait signalé que `ai_query_local`.

### Corrigé
Les trois branches d'`ai_query_local` (ollama, llama.cpp, openai-compatible)
et `ollama_query` : model/prompt transitent maintenant par stdin (première
ligne = model, reste = prompt, préservant sauts de ligne/guillemets/
accents) au lieu d'argv. Vérifié par aller-retour JSON (round-trip) que
le contenu — y compris multi-ligne et caractères spéciaux — survit
intact, et par `ps` que le prompt n'apparaît plus dans la ligne de
commande du processus `python3`.

Test ajouté : vérifie que les deux fonctions contiennent bien
`stdin.read()` (pas de détection négative fragile sur le motif exact du
bug — positive sur la présence du correctif).

### Non résolu
- `sonar_hmac_sha256_file` (ligne ~491) utilise aussi `sys.argv[2]` mais
  intentionnellement : c'est le CHEMIN du secret qui transite en argv,
  jamais les octets de la clé eux-mêmes (lus via `open()` dans le script
  Python) — déjà correct depuis v3.14.0, non touché ici.

## [3.36.8-post-deploy-verify-relative-paths] — 2026-09-17

### Contexte
Item [8] du plan de correctifs (audit externe DeepSeek) : la réécriture
`sed -E` de `sonar_post_deploy_verify_final` (qui ramène les chemins
absolus du manifeste au point de montage courant, différent à chaque
vérification) cherche la DERNIÈRE occurrence de `ISO/`, `Portable/`,
etc. dans un chemin — si un fichier réel se nomme par exemple
`Portable/ISO/README.txt` (un dossier `ISO` imbriqué dans `Portable`),
la réécriture matcherait la mauvaise occurrence.

### Corrigé — à la source, pas rendu plus précis
`generate_manifests_final` fait maintenant `cd` vers le point de montage
avant `find` : les manifestes (`ISO.sha256`, `FILES.sha256`) contiennent
directement des chemins relatifs (`ISO/foo.iso`) au lieu de chemins
absolus ancrés sur un point de montage temporaire qui change à chaque
appel. `sonar_post_deploy_verify_final` n'a alors plus besoin de
réécrire quoi que ce soit avant de relancer `sha256sum -c` — la classe
de bug entière disparaît plutôt que d'être rendue plus précise.

Test : cas reproduit manuellement hors self-test (aucun test existant
n'exerce le pipeline `--disk` complet — nécessite un vrai périphérique
bloc, P0 non résolu documenté dans ROADMAP.md) — un dossier
`Portable/ISO/README.txt` et un `ISO/foo.iso` vérifiés sans ambiguïté
avec le nouveau format, confirmé que l'ancien regex aurait mal géré ce
cas précis.

## [3.36.7-winpe-menu-build-fixed] — 2026-09-17

### Contexte
Le menu de réparation WinPE (3.36.0) rapportait un montage DISM et un
remplacement de `startnet.cmd` réussis, mais un vrai test de boot en VM
VirtualBox a montré que le menu n'apparaissait pas — l'ISO déployée
(SHA-256 `6ad61eab...`) démarrait sur `wpeinit` brut. Plusieurs heures
de diagnostic méthodique cette session pour isoler la cause exacte,
plusieurs fausses pistes écartées une à une avant la bonne.

### Diagnostiqué et écarté (dans l'ordre)
1. Cache de métadonnées côté clé USB — écarté : le bug se reproduisait
   aussi sur le disque local (`SONAR_SOURCE`), pas seulement sur `E:\`.
2. `MakeWinPEMedia.cmd` sans le flag `/f` (invite interactive "overwrite
   it" jamais répondue) — plausible, testé, insuffisant seul : le bug
   persistait même avec `/f`.
3. Verrou VirtualBox sur le fichier ISO (VM de test restée allumée avec
   le fichier attaché en lecteur virtuel) — réel et confirmé (la VM
   tournait bien avec le fichier attaché), mais insuffisant seul : le
   bug persistait même après extinction de la VM.
4. Montages DISM orphelins (plusieurs `check_*_wim` restés montés depuis
   des diagnostics précédents, verrouillant le `boot.wim` de préparation)
   — réel, corrigé (`Dism /Unmount-Image` explicite sur chacun), mais
   insuffisant seul.

### Root cause confirmée
Appeler `oscdimg.exe` (directement ou via `MakeWinPEMedia.cmd`) à
travers une élévation PowerShell (`Start-Process -Verb RunAs`)
produisait un ISO dont le `boot.wim` restait inchangé, malgré un
"100% complete" affiché par oscdimg lui-même — confirmé par test
comparatif direct : la même commande, sans élévation, produit un ISO
correct de façon systématique et reproductible. oscdimg ne fait que lire
un dossier source et écrire un fichier ISO — il n'a jamais eu besoin de
droits administrateur ; seuls `copype` et le montage DISM (menu de
réparation) en ont réellement besoin.

### Corrigé
`tools/Build-SonarSE-WinPE.ps1` : `oscdimg.exe` appelé directement
(reconstruction des paramètres `-bootdata` depuis `<stageDir>\bootbins`,
sans passer par `MakeWinPEMedia.cmd`), sans élévation. Ajouté au passage :
vérification automatique post-génération (remontage du `boot.wim` final,
recherche du texte du menu) — si le menu n'est pas présent, le script
échoue bruyamment au lieu de rapporter un faux succès comme avant. Deux
bugs PowerShell annexes corrigés en cours de route : `$ErrorActionPreference
= "Stop"` transformait la sortie stderr normale d'oscdimg (sa barre de
progression) en erreur terminale (`ErrorAction Continue` localisé autour
de cet appel) ; l'écriture du log oscdimg pouvait échouer sur un fichier
verrouillé par un résidu d'exécution précédente (non-bloquant désormais,
`try/catch`).

### Confirmé
ISO régénérée (378,8 Mo, SHA-256
`529d841c9dbef6570a0acf64f0a3d6d20f09e37688fd97009cea427acf57f5ff`),
vérification automatique du menu réussie, déployée sur la clé physique
(`E:\ISO\WinPE\`, hash identique confirmé).

### Non résolu
- Pas encore testé par un vrai boot matériel (seule une vérification de
  contenu post-génération).
- Cause exacte de l'échec sous élévation non comprise en profondeur
  (contournée, pas expliquée) — hypothèse non vérifiée : une différence
  de contexte utilisateur/jeton d'accès entre le processus élevé et le
  processus courant affectant la résolution du chemin de destination ou
  un verrou implicite posé par le sous-système d'élévation lui-même.

## [3.36.6-bios-password-gap-documented] — 2026-09-17

### Contexte
L'auteur a signalé un trou de couverture : le déblocage de mot de passe
BIOS/UEFI (superviseur/allumage), distinct du mot de passe de compte
Windows déjà couvert par `chntpw`.

### Recherché et écarté — CmosPwd (malgré une licence légitime)
CmosPwd (Christophe Grenier, cgsecurity.org — même auteur/domaine que
TestDisk/PhotoRec déjà dans ce manifeste) décode/efface le mot de passe
stocké en CMOS. GPL, provenance vérifiable. **Écarté quand même** :
téléchargé et testé sur cette machine, **Windows Defender l'a détecté
et bloqué à l'écriture en temps réel** (`HackTool:Win32/CmosPwd.A`,
confirmé via `Get-MpThreat`). N'importe quel antivirus sur la machine
d'un technicien ferait pareil — un outil qu'aucun antivirus ne laisse
tourner n'a pas sa place ici, licence ou pas. Première fois que ce
projet écarte un outil pour ce motif précis (utilisabilité réelle) plutôt
que pour la licence ou la provenance.

### Ajouté — limite documentée (pas d'outil, `sonar_profile_caveat`)
`password-reset` : même mécanisme que la divulgation de la limite WinPE
(`--profile password-reset` affiche maintenant "LIMITE CONNUE"). Couvre :
distinction compte Windows (chntpw, couvert) vs BIOS/UEFI (non couvert) ;
voies officielles vérifiées par recherche — Dell (code de déverrouillage
via Service Tag + code de défi, support.dell.com), HP (aucune procédure,
remplacement de carte mère), Lenovo (aucune procédure pour un mot de
passe superviseur ThinkPad, service agréé requis) ; et une précision
souvent absente des guides en ligne : le retrait de pile CMOS efface
bien le mot de passe sur carte mère de bureau, mais PAS de façon fiable
sur portable (stockage souvent hors CMOS classique). Test ajouté :
vérifie que le profil affiche bien cette limite.

## [3.36.5-catalog-counter-1003-was-never-real] — 2026-09-17

### Contexte
Un audit externe (DeepSeek) a demandé la construction d'un script de
vérification permanent pour le compteur "981 vs 1003" — sans savoir
que le correctif README/sonar_master.sh (voir 981 outils plus haut,
commit `dae77fd`) avait déjà eu lieu dans cette même session. En
vérifiant l'état actuel avant de construire cet outil, `docs/CATALOG.md`
s'est révélé être le seul fichier vivant manqué par ce premier
correctif (toujours à 1003 à deux endroits, plus une liste de 7 profils
au lieu de 9 — même angle mort que README.md avant correction).

### Corrigé — mesure directe sur l'historique Git, pas sur une affirmation
Mesuré le heredoc `SONAR_CATALOGUE_EMBEDDED` sur plusieurs commits de
l'historique (`20b766c` premier boot physique réussi, `e87379a`,
`f167395`, `8a5973e`, HEAD~1) : **981 lignes de données partout,
jamais 1003**. La ligne CHANGELOG affirmant "981 → 1003 (mesuré via
--catalog-download-resolve)" ne correspond à aucun état réel retrouvé
dans cet historique — origine non identifiée, possiblement une mesure
faite sur la lignée de développement divergente mentionnée ailleurs
dans ce fichier (`SONAR_PROJECT_v3.11.0.zip`), jamais ce dépôt-ci.
Traité comme une correction de compteur erroné, pas comme la
suppression d'entrées réelles à tracer (aucune preuve que le catalogue
ait jamais compté 1003 entrées ici).

`docs/CATALOG.md` : "1003 outils" → "981 outils" (deux occurrences),
liste des 7 profils → 9 (même distinction dépannage/distributions
généralistes que README.md). `sonar_master.sh` (`--help`, section
`--profile`) : même correction, une occurrence manquée par le
correctif précédent.

### Non résolu
- L'outil de vérification permanent demandé par l'audit externe
  (`check-catalog-counter.sh`) n'a pas été construit — la correction
  manuelle, une fois vérifiée par mesure directe, a rendu le problème
  immédiat sans objet. Pourrait avoir de la valeur comme garde-fou
  anti-régression future (CI/pre-commit), pas traité comme urgent ici.

## [3.36.4-build-secret-warning] — 2026-09-17

### Contexte
Item [7] du plan de correctifs (audit externe DeepSeek) : le secret HMAC
de build (`sonar_ensure_build_secret`) est créé silencieusement au
premier usage — aucune cérémonie, aucune trace d'un « propriétaire » du
secret. Sur une machine fraîche, le premier utilisateur contrôle la
racine de confiance. Deux options proposées : (a) exiger un rôle VAULT
pour créer le secret, (b) avertissement explicite sans changer le
comportement. Question posée à l'auteur plutôt que tranchée seule, comme
demandé pour ce point précis du plan.

### Décidé — option (b)
Option (a) écartée après vérification des points d'appel :
`sonar_ensure_build_secret` est appelée non seulement par
`--fetch-manifest-seal` (déjà gaté VAULT depuis 3.36.2), mais aussi par
`sonar_generate_build_watermark`, exécutée à **chaque `--disk` normal**.
Exiger VAULT ici aurait cassé le tout premier build sur une machine
fraîche pour tout Technician self-service — personne n'a de rôle élevé
avant ce premier build. Un changement bien plus disruptif que ce que ce
point du plan demandait.

### Corrigé — avertissement explicite à la création
`sonar_ensure_build_secret` affiche désormais deux lignes `[SONAR]
[ATTENTION]` lors de la création automatique du secret : quel fichier a
été créé, et une recommandation de l'administrer explicitement sur une
machine partagée. Le comportement (création silencieuse au premier
usage) est inchangé ; seule la transparence change.

Test ajouté : vérifie que `BUILD_SECRET_CREATED` est bien journalisé
dans `audit.log` lors de la première utilisation (déjà le cas
fonctionnellement, non testé jusqu'ici). Le test de non-régression
3.36.2 (`--fetch-manifest-seal` refusé sans jeton) reste vert, inchangé
par ce correctif.

## [3.36.3-fetch-timeout-hashchain-flock] — 2026-09-17

### Contexte
Suite du plan de correctifs issu de l'audit externe (DeepSeek), items
de robustesse opérationnelle (priorité 2 du plan).

### Corrigé — `sonar_fetch_one_tool` sans timeout réseau
`curl -fL --retry 3 --retry-delay 5 -C -` n'avait ni `--connect-timeout`
ni `--max-time`. Sur un réseau instable (contexte réel constaté cette
session), un serveur qui accepte la connexion puis ne répond plus
bloquait `--fetch` indéfiniment, sans message. Ajouté :
`--connect-timeout 20 --max-time 3600` (1h — suffisant pour le plus
gros outil du manifeste, SystemRescue ~1,3 Go, sur une connexion
lente). Test ajouté : vérification structurelle de la présence des
deux options dans l'appel curl.

### Corrigé — `sonar_verify_hashchain` sans `flock`
`sonar_audit` prend un `flock -x 201` avant d'écrire une entrée ;
`sonar_verify_hashchain` lisait le même fichier sans ce verrou — une
vérification concurrente à une écriture pouvait lire un état
intermédiaire incohérent et signaler une rupture inexistante (faux
positif). Corrigé avec le même verrou, scopé à la seule boucle de
lecture (l'englober dans tout `sonar_verify_hashchain` aurait causé un
auto-blocage : le `sonar_audit` final de la fonction prend lui-même ce
verrou). Test ajouté : peuple un hashchain réel dans un ROOT isolé,
vérifie que la vérification confirme un log non-altéré.

### Découvert en testant (sans rapport avec le correctif ci-dessus)
Le hashchain local de développement (`Secure/Logs/`, gitignore, jamais
commité) contenait une **corruption physique réelle** : un bloc de
plusieurs centaines d'octets nuls insérés entre deux entrées légitimes
du 16/09 (14h07 → 18h16) — signature typique d'une écriture interrompue
brutalement (un des nombreux processus tués/plantés cette session,
probablement pendant un `--fetch` la veille). Le mécanisme de détection
a correctement signalé la rupture — preuve qu'il fonctionne. En creusant
manuellement, une erreur d'isolation `SONAR_ROOT` dans une commande de
debug ad-hoc (hors self-test) a aussi pollué ce même journal avec deux
fausses entrées de test. Les deux (corruption + pollution) sauvegardées
puis le journal réinitialisé localement — données de développement, pas
des preuves d'un déploiement terrain réel ; aucun impact sur ce dépôt
Git (fichiers gitignore).

## [3.36.2-vault-role-enforced] — 2026-09-17

### Contexte
Un audit externe (analyse indépendante fournie par l'auteur, méthode
DeepSeek) a passé le projet en revue et signalé, entre autres, deux
failles de modèle de sécurité. Les deux ont été vérifiées directement
dans le code (grep, pas de confiance aveugle) avant correction — les
deux se sont révélées exactes.

### Corrigé — rôle VAULT non appliqué (le plus grave des deux)
`policy.tsv` donnait `VAULT=R` à Viewer et `VAULT=RW` à Technician — les
deux rôles libre-service, sans jeton. `sonar_role_can` traite R/RW/
CONFIRM comme équivalents (une seule valeur, "-", est un refus) : donc
`--fetch-manifest-seal`, `--field-pin-set` et `--catalog-seal`
n'exigeaient **aucune élévation réelle**, malgré le `[rôle VAULT]`
affiché dans `--help` et malgré l'argument central du projet
("un manifeste non signé est une porte ouverte", v3.16.0). N'importe
quel opérateur local pouvait resceller un manifeste falsifié ou définir
un nouveau PIN de terrain sans preuve d'identité.

Root cause plus profonde découverte en creusant : le test qui semblait
couvrir ce chemin (`--role-issue-token Vault ...`) utilisait "Vault"
comme nom de RÔLE — qui n'existe pas (`known="Viewer Technician Senior
Forensic Admin Expert"` dans `sonar_role_issue_token`). L'émission de
jeton échouait donc silencieusement, `SONAR_ROLE=Vault` retombait sur
Technician via le downgrade de `sonar_role_enforce_lock`, et le test ne
passait que parce que Technician avait alors un accès VAULT non
restreint — le bug masquait sa propre détection.

**Corrigé** : `policy.tsv` — Viewer et Technician passent à `VAULT=-`
(Senior/Forensic/Admin/Expert, qui exigent déjà un jeton signé,
inchangés à `RW`). Les 5 tests concernés (scellement de manifeste,
4× `--field-pin-set`) émettent désormais un vrai jeton `Admin` au lieu
du rôle inexistant "Vault". **Ajouté** : un test de non-régression
explicite — `--fetch-manifest-seal` doit être refusé pour un rôle
libre-service sans jeton.

**Effet de bord corrigé en cohérence** : `sonar_catalog_verify_seal`
exigeait aussi VAULT, alors que **vérifier** un scellé ne crée aucune
confiance nouvelle (contrairement à le créer) — incohérent avec
`sonar_fetch_manifest_verify_seal`, jamais gaté. Le gate a été retiré
de la vérification ; sans ce retrait, `--smart-advisor` aurait
signalé une fausse alerte "[CRITICAL] catalogue altéré" pour tout
opérateur non-élevé alors que le vrai problème aurait été un refus de
rôle, pas une falsification.

**Changement de comportement à connaître** : définir un PIN de terrain
(`--field-pin-set`) ou sceller un manifeste exige maintenant
`--role-bootstrap` + `--role-issue-token <Senior|Forensic|Admin|Expert>`
au préalable — ce n'était pas le cas avant ce correctif. Le PIN déjà
défini sur la clé physique (niveau "Technicien", PIN existant) n'est
pas affecté ; seuls les futurs appels à `--field-pin-set` le sont.

### Corrigé — identité non authentifiée journalisée comme si elle l'était
`sonar_role_enforce_lock` retourne avant de toucher `SONAR_ROLE_IDENTITY`
pour les rôles libre-service — donc `SONAR_ROLE_IDENTITY=X` positionné
via l'environnement par l'opérateur lui-même (sans preuve) finissait
dans l'audit comme `identity=X`, indistinguable d'une identité issue
d'un jeton signé (rôles élevés). **Corrigé** : `sonar_audit` marque
maintenant explicitement `identity=X (auto-declaree, non authentifiee)`
quand le rôle actif est libre-service.

### Non résolu
- Le fond de la question posée par l'audit externe (item #6 : dérive
  documentaire README 981↔1003 outils, 7 vs 9 profils) n'est pas encore
  traité.
- DESTRUCTIVE/FORENSIC restent volontairement non appliqués (voir
  commentaire existant dans `sonar_security_init`, inchangé par ce
  correctif).
- Racine de confiance auto-générée (`sonar_ensure_build_secret`) : pas
  de garde-fou ajouté, signalé par l'audit externe, pas traité ici.

## [3.36.1-ventoy-background-globe] — 2026-09-17

### Contexte
L'auteur a proposé deux images pour le fond du menu de boot Ventoy : un
globe bleu stylisé (sans texte), et un tableau de bord radar complet
(panneaux, cartes du monde, graphiques) avec "SONAR - SE" et le crédit
déjà incrustés dans l'image.

### Décidé — le globe reste le fond actif, le tableau de bord est conservé en réserve
Deux problèmes techniques avec le tableau de bord comme fond ACTIF :
1. Le script (`sonar_prepare_ventoy_theme()`) incruste automatiquement
   son propre bandeau titre/crédit sur toute image fournie via
   `SOURCE_DIR/Branding/background.png` — avec cette image, le texte
   apparaîtrait en double (une fois dans l'image, une fois via le
   bandeau généré).
2. La liste des ISO du menu Ventoy s'affiche par-dessus le fond à partir
   d'environ 38% depuis le haut (`ventoy_top` dans `ventoy.json`) — sur
   le tableau de bord, cette zone est la plus chargée visuellement
   (radar + graphiques), ce qui nuirait à la lisibilité de la liste.

Le globe (fond sombre, peu chargé dans cette zone) reste donc le fond
actif sur `SOURCE_DIR/Branding/background.png` et sur la clé physique
(`E:\ventoy\theme\background.png`). Le tableau de bord est conservé tel
quel dans `Branding/alt_dashboard_background.jpg` (pas branché dans le
pipeline `--disk`) — réutilisable ailleurs (présentation du projet) sans
perdre le travail.

## [3.36.0-hardware-drivers-maintenance-tools-winpe-menu] — 2026-09-17

### Corrigé — `--self-test` rapportait 29 FAIL quand lancé sans `./`
Cause racine unique pour des clusters en apparence sans rapport (role-lock/
tokens, chain-of-custody, profils de depannage, fetch manifest, SONAR
Field) : `sonar_self_test_v2()` calcule `self="${BASH_SOURCE[0]}"` puis
reinvoque le script directement, `"$self" --flag`, pour des dizaines de
sous-tests. Quand l'utilisateur lance le harnais avec `bash
sonar_master.sh --self-test` (sans `./` ni chemin absolu), `BASH_SOURCE[0]`
vaut le nom nu `sonar_master.sh` — sans aucun `/`. Un nom de commande sans
`/` n'est jamais cherche dans le repertoire courant : bash le cherche dans
`$PATH`, ne l'y trouve pas, et l'invocation echoue silencieusement (l'erreur
« command not found » part sur stderr, deja redirige vers `/dev/null` par
la quasi-totalite de ces sous-tests). Resultat : chaque sous-test qui
delegue a une reinvocation de `"$self"` echoue, dans des clusters qui n'ont
rien de fonctionnel en commun — la seule chose qu'ils partagent est ce
mecanisme de reinvocation. `bash ./sonar_master.sh --self-test` (chemin
avec `/`) ne declenchait pas le bug, ce qui masquait la regression pour
quiconque avait pris l'habitude du `./`.

Corrige en calculant `self` comme un chemin absolu —
`"${SONAR_SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"` — qui contient
toujours un `/` et fonctionne donc quel que soit l'appel initial. Voir
`sonar_self_test_v2()` dans `sonar_master.sh`. Verifie : `ERRORS=0` avec
`bash sonar_master.sh --self-test` et `bash ./sonar_master.sh --self-test`.

### Contexte
Discussion sur ce que SONAR-SE devrait couvrir pour rester pertinent
"au regard du monde aujourd'hui" : confiance vérifiable (provenance
signée/hachée) plutôt que quantité brute d'outils, et robustesse
hors-ligne. Suite logique : combler des trous concrets de couverture
signalés par l'auteur — écran, pilotes, alimentation, et un WinPE plus
accessible qu'une invite `cmd.exe` brute.

### Ajouté — 7 nouveaux outils verifies (URL + SHA-256 calcule localement)
- **hardware-diagnostic** : IsMyLcdOK (pixels morts), HWiNFO (capteurs
  materiels/rails d'alimentation — freeware NON-COMMERCIAL pour la
  partie 64 bits/ARM64, a signaler a l'operateur), BatteryInfoView
  (diagnostic batterie portable), Snappy Driver Installer Origin
  (pilotes hors-ligne, pack embarque), DriverStoreExplorer/RAPR
  (nettoyage du magasin de pilotes Windows).
- **boot-repair** : Dism++ (interface graphique DISM/SFC), BleachBit
  (nettoyage disque/registre, alternative saine a CCleaner).

Ecarte deliberement : outils d'« activation » Windows/Office (KMSPico,
Microsoft Activation Scripts...) — ce sont des outils de contournement
de licence (piratage logiciel), incompatibles avec la discipline de
provenance verifiee de tout ce manifeste. Seule alternative legitime :
`slmgr.vbs`, deja integre a Windows, pour du depannage d'activation
sur une licence reellement possedee.

### Ajouté — menu de reparation dans WinPE (`tools/Build-SonarSE-WinPE.ps1`)
Nouveau parametre `-AddRepairMenu` (active par defaut) : remplace
`startnet.cmd` par un menu batch numerote (reparation du demarrage via
bootrec, bcdedit, diskpart, DISM ScanHealth/RestoreHealth, invite
libre) au lieu du `cmd.exe` brut — evite au technicien de memoriser la
syntaxe exacte de chaque commande. Implemente en montage DISM + simple
remplacement de fichier (pas de `/Add-Package`), donc non concerne par
la limite connue de `-IncludePowerShell` (bug DISM Erreur 87).

### Corrigé — `Remove-Item` PowerShell peu fiable dans le script WinPE
`Remove-Item -Recurse -Force` sur le dossier de stage WinPE
(`$env:TEMP\sonar-se-winpe-build\winpe_amd64`) echouait de facon
reproductible avec « Un objet n'existe pas a l'emplacement specifie
C:\Users\CEPC~1. » (chemin tronque dans le message, cause exacte non
confirmee — profil dont le nom d'utilisateur contient un espace,
donc alias 8.3 `CEPC~1` dans `%TEMP%`). `cmd /c rmdir /s /q` sur le
meme chemin reussit systematiquement ; le script utilise maintenant
cette methode.

### Découvert (non causé par ce changement) — régression `--self-test`
`bash sonar_master.sh --self-test` rapporte 29 FAIL (role-lock/tokens,
chain-of-custody, documentation des profils, scellement du manifeste
fetch, PIN/export SONAR Field). **Confirmé pré-existant** : testé sur
le commit HEAD précédent (avant tout changement de cette session, via
`wsl -u root`), même résultat exact. Cause racine non identifiée cette
session — plusieurs clusters de tests sans rapport fonctionnel échouent
ensemble, ce qui suggère une cause commune (variable d'environnement,
helper partagé par le harnais de self-test, ou dépendance manquante
dans cet environnement WSL) plutôt que neuf bugs indépendants. Flaggé
pour investigation dédiée séparée — voir tâche associée.

### Non résolu
- Le menu de reparation WinPE n'a pas encore ete teste par un vrai
  boot (seul le remplacement de `startnet.cmd` dans l'image a ete
  confirme reussi).
- La regression `--self-test` (29 FAIL) ci-dessus reste a diagnostiquer.
- HWiNFO : verifier avec l'operateur si un usage commercial de la cle
  SONAR-SE necessiterait une licence, la version freeware actuelle
  etant limitee a un usage non-commercial pour sa partie 64 bits/ARM64.

## [3.35.0-ventoy-theme-real-root-cause-found] — 2026-09-16

### Contexte
L'auteur a partagé deux vidéos YouTube sur la personnalisation Ventoy
en demandant de s'en inspirer. La première (IT-Connect/Florian) est un
tuto Ventoy général, sans rapport direct. La seconde ("Personnaliser
votre clé USB multi-boot Ventoy", Les Tutoriels d'Amine, 2020) utilise
de vrais thèmes GRUB2 communautaires (gnome-look.org) via le plugin
thème officiel de Ventoy — ce qui a mené à consulter la documentation
officielle (ventoy.net/en/plugin_theme.html) pour comprendre comment
ces thèmes complets sont structurés, en comparaison de l'approche
"juste une image de fond" utilisée jusqu'ici par SONAR-SE.

### Trouvé — la vraie cause du crash "alloc magic is broken"
La documentation officielle du plugin thème Ventoy est explicite :
la clé `"file"` du bloc `theme` dans `ventoy.json` doit pointer vers
un fichier **`theme.txt`** (script de thème GRUB2, ex. `"file":
"/ventoy/theme/blur/theme.txt"`), **jamais directement vers une image**.

Or `generate_ventoy_json_final()` pointait `"file"` directement sur
`/ventoy/theme/background.png` — une image, pas un script. GRUB
tentait alors de PARSER les octets binaires du PNG comme s'il
s'agissait d'un script de directives de thème. Ça explique
parfaitement ce qui avait été observé (et documenté comme "non
résolu") en v3.25.0/v3.26.0 : **trois tailles d'image radicalement
différentes (6 Mo, 2,25 Mo, 480 Ko décodés) ont produit le crash
identique** — parce que la taille de l'image n'a jamais été la
variable en cause. Le problème était structurel dès la première
octet lue, pas une question de mémoire allouée pour décoder une image.

### Corrigé
- `sonar_prepare_ventoy_theme()` : génère maintenant un `theme.txt`
  minimal (`desktop-image: "background.png"` + `title-text: ""`,
  syntaxe GRUB2 standard) à côté de l'image, en plus de l'image
  elle-même.
- `generate_ventoy_json_final()` : `"file"` pointe désormais vers
  `/ventoy/theme/theme.txt` au lieu de `/ventoy/theme/background.png`
  directement.
- Deux nouveaux tests `--self-test` (aucune couverture automatisée
  n'existait avant pour cette zone) : vérifient structurellement que
  `theme.txt` est généré avec la directive `desktop-image`, et que
  `ventoy.json` référence bien `theme.txt` et non l'image brute.
  Confirment que SONAR produit les bons fichiers — pas encore que GRUB
  les accepte réellement, seul un vrai boot le confirmera.

### Appliqué sur la clé physique, en attente de test réel
`E:\ventoy\theme\theme.txt` créé et `E:\ventoy\ventoy.json` mis à jour
manuellement pour pointer vers lui (même changement que produirait
`--disk`, appliqué directement sans reformater Ventoy). **Pas encore
rebooté sur le HP EliteBook 840 G3** — après trois échecs confirmés
sur cette même machine (v3.25.0/v3.26.0), cette découverte reste une
piste forte et bien étayée par la documentation officielle, pas une
victoire déclarée avant un vrai test.

### Testé
`bash -n` + `--self-audit` (14 PASS, 0 FAIL) + `--self-test` (0
ERRORS, les 2 nouveaux tests PASS) sous WSL2.

### Non résolu
Confirmation par un vrai boot sur matériel réel — à faire dès que
possible. Si ça fonctionne, `--ventoy-theme` pourra repasser d'opt-in
à activé par défaut ; si ça échoue encore, ce sera la première fois
que l'hypothèse "mauvaise structure du fichier référencé" (plutôt que
"taille d'image" ou "firmware incompatible") aura été testée et
écartée avec preuve, pas juste supposée.

## [3.34.0-peripherals-network-profile] — 2026-09-16

### Contexte
Suite directe de v3.33.0 (même jour) : demande d'élargir la couverture
à des domaines hors PC — serveurs, imprimantes, téléphonie mobile,
caméras de surveillance. Analyse faite avant d'agir plutôt que de
promettre une couverture que le mécanisme de SONAR ne peut pas tenir.

### Trouvé — une limite architecturale réelle, pas juste un manque d'outils
Le mécanisme de SONAR (`--disk` construit une clé Ventoy ; la machine
en panne boote dessus ; on répare depuis cet environnement) suppose
que la cible **peut booter sur une clé USB PC**. Ça exclut par nature
trois des quatre domaines demandés :
- **Imprimante** : pas de port de boot USB au sens PC — le dépannage
  se fait depuis un PC déjà fonctionnel (spouleur, pilotes, interface
  web de l'imprimante). Rien à ajouter : `SFC`/`DISM`/pilotes déjà
  couverts côté Windows.
- **Téléphone** : OS et architecture totalement différents d'un PC. On
  ne boote pas un téléphone sur une clé USB PC. Diagnostic uniquement
  possible depuis un PC fonctionnel, câble branché.
- **Caméra de surveillance** : appareil réseau, se diagnostique par le
  réseau depuis un PC fonctionnel, jamais en bootant dessus.
- **Serveur** : seul cas qui reste un vrai scénario de boot — un
  serveur est un PC pour ce que couvrent boot-repair/data-recovery/
  disk-clone. Extension quasi gratuite (mêmes outils), pas encore
  documentée formellement dans un profil dédié cette session.

### Ajouté
- **Nouveau profil `peripherals-network`** (8e profil) — explicitement
  documenté comme différent des sept autres par nature : s'utilise
  depuis un PC déjà démarré normalement, câble branché sur un
  téléphone, pas depuis le menu de boot Ventoy. `--profile
  peripherals-network` et `--help` le précisent en toutes lettres pour
  ne pas laisser croire à une couverture qui n'existe pas.
- **Android Platform Tools** (adb + fastboot) : diagnostic/réparation
  basique d'un téléphone Android (redémarrage forcé, effacement cache,
  réinstallation firmware officiel) depuis un PC fonctionnel. Officiel
  Google (`dl.google.com`), SHA-256 vérifié pour de vrai via le
  mécanisme `--fetch` réel. iOS explicitement hors de portée (aucun
  outil libre équivalent, écosystème Apple verrouillé) — documenté
  plutôt que passé sous silence.

### Écarté / reporté
`nmap` (scan réseau pour la détection de caméras) : licence et source
officielle vérifiées (licence custom proche de mais non compatible
GPLv2, nmap.org/dist) mais téléchargement du binaire portable Windows
(dernière version portable : 7.92, 2021 — les versions plus récentes
ne publient qu'un installeur .exe) échoué deux fois pour instabilité
réseau côté serveur nmap.org (timeout, connexion réinitialisée) — pas
un problème de licence, juste pas abouti cette session.

### Testé
`bash -n` + `--self-audit` (14 PASS, 0 FAIL) + `--self-test` (0
ERRORS, "All eight troubleshooting profiles..." PASS, union de
`--profile full` étendue pour confirmer `Android Platform Tools`).
Récupéré via le vrai mécanisme `--fetch-manifest-seal` puis `--fetch
peripherals-network` (pas un test manuel isolé). Déployé sur la clé
physique (`E:\Portable\AndroidPlatformTools\`, adb.exe/fastboot.exe
confirmés présents) sans toucher à `persistence/` (40 Go intact) ni à
`ISO/` (inchangé). `--field-export` relancé, 8 profils confirmés
présents sur la clé.

### Non résolu
`nmap` à retenter (candidat solide, juste pas abouti). Extension
serveur (RAID/`mdadm`, notes IPMI) identifiée comme quasi gratuite
mais pas encore formalisée en profil dédié.

## [3.33.0-six-more-verified-tools] — 2026-09-16

### Contexte
Suite d'une demande d'élargir la couverture d'outils à partir d'un
document PDF fourni par l'auteur (liste de ~35 outils de diagnostic/
réparation PC, 10 catégories). Recherche faite pour chaque candidat
avant intégration — même discipline que Memtest86+/CrystalDiskInfo.

### Ajouté
- **Process Explorer** et **Autoruns** (Microsoft Sysinternals,
  download.sysinternals.com, EULA freeware sans compte) — profil
  `malware` : triage manuelle de processus/persistance, complément
  Windows-side de ClamAV.
- **BlueScreenView** (NirSoft, freeware personnel/commercial) — profil
  `boot-repair` : identifie le pilote responsable d'un écran bleu à
  partir des .dmp.
- **Rufus** (GPLv3, github.com/pbatard/rufus, binaires signés
  Authenticode "Akeo Consulting" en plus du téléchargement direct) —
  profil `boot-repair` : création de clé USB Windows amorçable quand
  le diagnostic conclut à une réinstallation.
- **CrystalDiskMark** (même éditeur/licence MIT que CrystalDiskInfo) —
  profil `hardware-diagnostic` : vitesses réelles de disque,
  complémentaire à l'attribut SMART seul.
- **Prime95** (GIMPS, freeware avec EULA spécifique — pas open source
  au sens strict, clause notable sans rapport avec cet usage) — profil
  `hardware-diagnostic` : stress-test CPU/alimentation, détecte les
  plantages sous charge que Memtest86+ seul ne révèle pas.
- **Idempotence de `--fetch`** (`sonar_fetch_one_tool`) : si le fichier
  cible existe déjà avec le bon SHA-256, plus de re-téléchargement.
  Découvert en pratique : sans ce garde-fou, chaque `--fetch` sur un
  profil incluant SystemRescue (1,3 Go, déjà présent et valide) le
  retéléchargeait intégralement à chaque exécution.

### Écarté après recherche (mêmes critères que Kaspersky/Avast/Kali)
`MediCat USB`, `Hiren's BootCD PE`, `Ultimate Boot CD` (suggérés par le
document comme environnements de démarrage) : même compromis de
licence que Kaspersky/Avast déjà écarté — gros bundle sans garantie de
provenance individuelle. `Malwarebytes`, `RogueKiller`, `AdwCleaner`,
`Revo Uninstaller Pro`, `Recuva`, `Macrium Reflect`, `Victoria SSD/HDD`,
`HWiNFO64`, `CPU-Z`/`GPU-Z`, `Advanced IP Scanner` : non recherchés en
profondeur cette session (proprietaires, statut de licence/téléchargement
direct non vérifié) — candidats pour une prochaine session si voulu.
`Wireshark` : licence/source vérifiées (GPLv2, wireshark.org,
signatures GPG), mais intégration reportée — capture de paquets depuis
un environnement de secours sans gestionnaire de paquets est plus
complexe que les .exe portables ajoutés ici, mérite un traitement
séparé. `SFC`/`DISM`/`CHKDSK` déjà couverts : binaires Windows/WinPE
de base, rien à télécharger.

### Testé
`bash -n` + `--self-audit` (14 PASS, 0 FAIL) + `--self-test` (0
ERRORS) sous WSL2. Les 6 outils récupérés et vérifiés pour de vrai via
`--fetch-manifest-seal` puis `--fetch malware`/`--fetch boot-repair`/
`--fetch hardware-diagnostic` (mécanisme réel du script, pas un test
manuel isolé) — un échec réseau transitoire sur Rufus (connexion
réinitialisée par GitHub) corrigé par une simple relance, confirmant
au passage que le nouveau garde-fou d'idempotence fonctionne
(SystemRescue/TestDisk/BlueScreenView reconnus déjà présents sans
retéléchargement). Déployés sur la clé physique
(`E:\Portable\{ProcessExplorer,Autoruns,CrystalDiskMark,Prime95}\`,
`rufus-4.15.exe`, `bluescreenview.zip`) sans toucher à `persistence/`
(40 Go intact) ni à `ISO/` (inchangé, aucun de ces 6 outils n'est une
ISO). `--field-export` relancé, profils à jour sur la clé.

### Non résolu
Domaines demandés mais architecturalement incompatibles avec le
mécanisme de SONAR (boot direct sur la machine en panne) : imprimantes,
téléphonie mobile, caméras de surveillance. Voir discussion en session
— nécessiteraient un profil différent, utilisé depuis un PC qui
fonctionne déjà (câble/réseau), pas depuis le menu de boot Ventoy.
Piste concrète identifiée mais pas implémentée : Android Platform
Tools (adb/fastboot, dl.google.com, licence Android SDK) pour le volet
téléphonie Android — iOS restant hors de portée par nature.

## [3.32.0-recovered-tooling-from-divergent-lineage] — 2026-09-16

### Contexte
L'auteur a signalé une archive locale, `SONAR_PROJECT_v3.11.0.zip`,
demandant de s'inspirer du travail précédent. Vérification faite avant
d'agir : `git log --all` sur ce dépôt ne trouve ces chemins nulle part
— l'archive vient d'une lignée du projet distincte, qui a divergé avant
d'atteindre ce dépôt (dont le premier commit local est
"v3.4.0-role-lock-identity") et qui n'a jamais été fusionnée ici.
Comparaison complète des deux arborescences : l'archive a poussé plus
loin sur la maturité de projet (script de release signé GPG, connexion
GitHub sécurisée, plan de découpage modulaire écrit) ; ce dépôt-ci a
poussé plus loin sur la capacité réelle (WinPE, branding Ventoy,
validation matérielle, catalogue 1003 outils). Aucune des deux lignées
n'est un sur-ensemble de l'autre.

### Ajouté
- **`scripts/setup-github.sh`** (récupéré, inchangé sur le fond) :
  connecte le dépôt local à un remote GitHub — active le hook
  pre-commit, configure `origin` (via `gh` CLI si authentifié, sinon
  instructions manuelles), stage les fichiers. **Ne pousse jamais rien
  automatiquement** — s'arrête à `git add`, affiche les étapes
  manuelles restantes. Un seul exemple de tag codé en dur (version
  3.10.1 périmée) généralisé en placeholder.
- **`scripts/release.sh`** (récupéré, une correction) : génère une
  release signée GPG (tarball + SHA-256 + signature détachée),
  vérifie les signatures produites, affiche les instructions de
  vérification pour l'utilisateur final. Référence corrigée :
  `--health-check` (n'existe plus dans le script actuel) remplacé par
  `--self-audit && --self-test` (les vraies commandes de validation
  actuelles). Exemple de version mis à jour (3.10.1 → 3.31.0).
- **`lib/README.md`** (récupéré, mis à jour) : plan de découpage
  modulaire déjà détaillé (`core.sh`/`security.sh`/`deploy.sh`/
  `operational.sh`/`catalog.sh`/`reports.sh`, ordre d'extraction, règle
  "un commit par module + self-test après chaque module", garde-fou
  "pas avant que la CI soit verte" — correspond exactement à la
  décision de séquençage déjà prise dans ce dépôt). Compteur de lignes
  mis à jour (4 385 → 5 608 lignes actuelles) ; estimations par module
  explicitement marquées comme datant du plan d'origine, à
  recalculer au moment réel du découpage plutôt que recopiées comme si
  elles étaient à jour.

### Changé
- `ROADMAP.md` : les deux items P1 (découpage modulaire) et P2
  (signature GPG des releases) référencent maintenant ces outils
  récupérés et leur provenance exacte.

### Non fait (délibérément)
`docs/USER_GUIDE.md` (périmé — écrit avant SONAR Field, `--fetch`,
`--profile`, aurait fallu le réécrire plutôt que le copier) et
`docs/HARDWARE_TEST_MATRIX.md` (modèle vierge utile pour de futurs
tests, mais contient une hypothèse déjà démontrée fausse cette session
— "persistance montée automatiquement au boot", contredit par la
validation SystemRescue de v3.29.0) laissés de côté sans les
intégrer tels quels. `PRESENTATION_SONAR.html`,
`docs/DEPLOYMENT.html` et `.github/workflows/ci-windows.yml.stub` non
évalués (hors du périmètre demandé).

### Testé
`bash -n` sur les deux scripts récupérés (syntaxe correcte). Pas de
changement dans `sonar_master.sh` cette entrée — uniquement de
nouveaux fichiers indépendants (outillage), aucune validation
`--self-audit`/`--self-test` nécessaire au-delà de la confirmation
qu'aucun fichier suivi n'a été modifié par erreur.

## [3.31.0-crystaldiskinfo-added] — 2026-09-16

### Contexte
Suite de v3.30.0 (même jour) : élargissement de `hardware-diagnostic`
avec un deuxième outil, plus recherche sur trois autres candidats
demandés explicitement (antivirus type Kaspersky/Bitdefender/Avast,
remplacement de Kali).

### Ajouté
- **CrystalDiskInfo 9.9.2** dans `hardware-diagnostic` : licence MIT
  confirmée (`github.com/hiyohiyo/CrystalDiskInfo`), SHA-256 calculé
  localement après téléchargement réel depuis SourceForge (aucune
  somme officielle publiée par l'éditeur — même schéma de confiance
  que Clonezilla, déjà dans ce manifeste). Variante portable choisie
  délibérément (pas l'installeur : le site officiel liste des variantes
  "Ads"/bundlées à éviter). Lit les attributs SMART d'un disque —
  complète Memtest86+ en distinguant une RAM défaillante d'un disque en
  fin de vie. Nécessite Windows/WinPE (binaire .exe), ne fonctionne pas
  depuis SystemRescue.

### Recherché, pas ajouté (obstacles réels documentés)
- **Bitdefender Rescue CD** : confirmé mort. L'URL "officielle" qui
  circule (`download.bitdefender.com/rescue_cd/...`) renvoie une 404
  vérifiée en direct — produit retiré depuis 2019, seuls des miroirs
  tiers non vérifiables (ArchiveOS, MajorGeeks) le proposent encore.
- **Kaspersky Rescue Disk** : toujours activement distribué et gratuit
  sans compte, mais le téléchargement réel est derrière une page
  rendue en JavaScript (Next.js) qui génère l'URL du fichier
  dynamiquement — pas d'URL stable trouvée après plusieurs tentatives
  (config JSON référencé mais non résolu, chemins CDN connus testés en
  404). Même catégorie de blocage que Malwarebytes/ESET Online Scanner,
  déjà écartés pour la même raison en v3.16.0.
- **Avast Rescue Disk** : statut ambigu — les sources qui le donnent
  actif sont des agrégateurs tiers (FileCR), pas avast.com directement ;
  semble généré depuis l'application Avast installée plutôt que
  distribué en ISO autonome, ce qui l'exclurait du modèle `--fetch`
  (téléchargement direct sans dépendance à un autre logiciel installé).
- **Remplacement de `kali-linux-2026.2-virtualbox-amd64.7z`** (déjà sur
  la clé physique, 3,9 Go) : découvert que ce fichier est une appliance
  VirtualBox compressée, **pas une image bootable** — Ventoy ne peut
  jamais la démarrer, 3,9 Go inutilisables tels quels. L'ISO "live"
  officielle (`kali-linux-2026.2-live-amd64.iso`, celle qu'il fallait)
  n'est actuellement distribuée qu'en torrent sur le miroir principal
  (`cdimage.kali.org/current/` liste le `.torrent` mais pas le `.iso`
  en HTTP direct) — incompatible avec le modèle `--fetch` (URL HTTP(S)
  fixe et vérifiable). L'ISO "installer" est bien en HTTP direct mais
  n'offre pas la même expérience live-boot.

### Testé
`bash -n` + `--self-audit` (14 PASS, 0 FAIL) + `--self-test` (0
ERRORS, union de `--profile full` étendue pour confirmer
`CrystalDiskInfo`). `--fetch-manifest-seal` puis `--fetch
hardware-diagnostic` exécutés pour de vrai (2 outils vérifiés, 0
échec). CrystalDiskInfo extrait et déposé sur la clé physique
(`E:\Portable\CrystalDiskInfo\`, ~8,7 Mo) sans toucher à `persistence/`
(40 Go intact) ni au reste du contenu existant. `--field-export`
relancé, profils à jour sur la clé.

### Non résolu
Kaspersky (blocage technique du téléchargement), Avast (statut
ambigu), Bitdefender (mort), et un vrai remplacement Kali live restent
non résolus — pistes documentées ci-dessus si quelqu'un veut reprendre
l'investigation (ex. : résoudre l'API Kaspersky, ou accepter l'ISO
"installer" Kali en compromis).

## [3.30.0-hardware-diagnostic-profile] — 2026-09-16

### Contexte
Demande explicite : couvrir « tous les domaines de l'informatique »
comme MediCat, en élargissant le nombre d'outils sur la clé.
Recherche faite avant d'agir : la page de licence officielle de MediCat
confirme noir sur blanc *"We do not own, license, or claim rights to
any third-party software included in this project"* — leur étendue
vient précisément de l'absence de garantie de licence individuelle,
exactement le compromis déjà écarté pour SONAR-SE (voir ROADMAP.md,
section "SONAR - SE v1"). Décision confirmée par l'auteur : élargir
`--fetch` domaine par domaine, avec vérification individuelle de
provenance à chaque ajout — plus lent, mais chaque outil reste
garanti authentique.

### Ajouté
- **Nouveau profil `hardware-diagnostic`** (7e profil, avant : 6) :
  couvre un domaine jusqu'ici totalement absent — diagnostic RAM
  (plantages/écrans bleus aléatoires sans cause logicielle évidente).
  Aucun des 6 profils existants ne couvrait ce scénario.
- **Memtest86+ v8.10** ajouté à `SONAR_FETCH_MANIFEST_TSV` : GPLv2,
  dépôt officiel `memtest86plus/memtest86plus` (GitHub), à ne pas
  confondre avec MemTest86 (PassMark, rebrand commercial). SHA-256
  vérifié à deux niveaux : publié sur memtest.org (fichier
  `sha256sum.txt` du domaine officiel, récupéré par `curl` brut plutôt
  que via un outil de résumé IA — pour une valeur cryptographique, la
  transcription doit être déterministe, pas passer par un modèle
  intermédiaire) et recalculé localement après téléchargement réel :
  les deux correspondent exactement.
- Compteur du catalogue embarqué corrigé partout où il apparaît comme
  affirmation vivante (pas historique/datée) : 981 → **1003** outils
  (mesuré via `--catalog-download-resolve`, pas juste recopié) —
  `sonar_master.sh`, `README.md`, `docs/CATALOG.md`.

### Changé
- `SONAR_PROFILE_NAMES` : `hardware-diagnostic` ajouté entre
  `password-reset` et `full`.
- `sonar_profile_scenario "full"` : "cinq scenarios" → "six scenarios"
  (le nombre de profils réels, hors `full` lui-même).
- `--help` (section `--profile`) et `docs/CATALOG.md` : liste des 7
  profils et compteur catalogue mis à jour.
- `--self-test` : boucle de couverture des profils étendue à
  `hardware-diagnostic` (7 profils testés, message "six" → "seven"),
  vérification de `--profile full` étendue pour confirmer la présence
  de `Memtest86+` dans l'union.
- `ROADMAP.md` : sous-entrée datée sous "Étape 1" documentant cet
  ajout et la décision de séquençage (élargissement vérifié plutôt
  qu'imitation MediCat).

### Testé
`bash -n` + `--self-audit` (14 PASS, 0 FAIL) + `--self-test` (0 ERRORS,
"All seven troubleshooting profiles document scenario + tools" PASS,
union de `--profile full` confirmée). `--fetch-manifest-seal` puis
`--fetch hardware-diagnostic` exécutés pour de vrai : téléchargement
réel, SHA-256 vérifié par le script lui-même (pas seulement en test
manuel), fichier `.zip` extrait, ISO déposée sur la clé physique
(`E:\ISO\Memtest86+_v8.10.iso`, 6,2 Mo) sans toucher à `persistence/`
(toujours 40 Go) ni au reste d'`ISO/` (34,33 → 34,34 Go, delta exact
de l'ajout). `--field-export` relancé : les 7 profils, dont
`hardware-diagnostic`, confirmés présents sur la clé
(`MANIFEST/PROFILES_SCENARIOS.tsv`).

### Non résolu
Un seul domaine ajouté (mémoire) sur les nombreux possibles (réseau,
SMART/santé disque, UEFI/BIOS, pilotes...) — élargissement à poursuivre
domaine par domaine si voulu, même méthode de vérification à chaque
fois.

## [3.29.0-sonar-field-real-boot-validation] — 2026-09-16

### Contexte
Suite immédiate de v3.28.0 (même jour) : cette dernière validait la
logique de `sonar_field.sh` sur des fichiers réels, mais via WSL2 (qui
monte les partitions différemment d'un vrai rescue Linux bootée) —
le "Non résolu" explicitement noté était de savoir si SystemRescue,
une fois réellement démarré, monte automatiquement la partition de
données à un chemin que `sonar_field_locate` détecte
(`/mnt/*`, `/media/*/*`, `/run/media/*/*`).

### Testé — vrai boot SystemRescue en VM
Construit un disque de test minimal (200 Mo, une seule partition
FAT32, sans Ventoy — suffisant pour isoler la question du montage
automatique) contenant les vrais fichiers produits par
`--field-export` (profils, `sonar_field.sh`, un PIN de test). Attaché
à une VM VirtualBox, bootée pour de vrai sur l'ISO SystemRescue déjà
présente sur la clé physique (pas une image jetable).

**Résultat : SystemRescue ne monte rien automatiquement en mode
console** — `lsblk` après le boot confirme qu'aucune partition n'a de
`MOUNTPOINT` renseigné. Le gap d'auto-détection déjà listé dans
"Pas encore fait" est donc confirmé réel, pas juste une prudence
théorique.

Suite du test, montage manuel (`mount /dev/sdb1 /mnt/sonarfield`,
le repli déjà annoncé par le script lui-même) puis `sonar_field.sh`
exécuté **avec un clavier réellement tapé dans la VM** (pas de stdin
simulé) : PIN accepté, identité saisie, menu à 6 profils affiché,
profil `boot-repair` consulté, journal/hashchain écrits sur la
partition puis relus (`cat Field-Logs/hashchain.log`) — comportement
identique à la validation WSL2 de v3.28.0, confirmant que cette
dernière n'était pas un artefact de l'environnement de test.

Incident de méthode rencontré et corrigé en cours de route : les
premières commandes tapées via `VBoxManage controlvm keyboardputstring`
sont sorties déformées (`mkdir` → `,kdir`, `/` → `!`, `sonarfield` →
`sonqrfield`) — la VM avait `loadkeys fr` (AZERTY) actif alors que
`keyboardputstring` envoie des scancodes positionnels US (QWERTY).
Corrigé en renvoyant `loadkeys us` (tapé lui-même via la substitution
inverse Q↔A le temps que la disposition change), avant de reprendre
les commandes normalement.

### Changé
- `ROADMAP.md` : la case "boot réel de l'environnement de secours"
  passe de "pas encore fait" à fait, avec le résultat (négatif sur
  l'auto-montage, positif sur tout le reste une fois monté).
- `sonar_field.sh` (embarqué dans `sonar_master.sh`) : aucun changement
  de code — ce round de test visait à vérifier le comportement
  existant, pas à le modifier. Le message d'erreur de
  `sonar_field_locate` ("Montez-la manuellement puis relancez") s'avère
  être le chemin normal sur SystemRescue en mode console, pas un cas
  de repli rare.
- SONAR_VERSION -> 3.29.0-sonar-field-real-boot-validation

### Non résolu
Auto-détection de la partition clé reste à construire (scan `lsblk`
par label/contenu, ou lancer `startx` + un gestionnaire de fichiers qui
monte automatiquement — SystemRescue le propose mais ce n'est pas le
mode par défaut). Priorité basse : le repli manuel fonctionne et est
déjà documenté à l'écran par le script lui-même.

## [3.28.0-sonar-field-real-hardware-validation] — 2026-09-16

### Contexte
Jusqu'ici, `sonar_field.sh` n'avait été validé qu'en bac à sable
(`--self-test`, sur des répertoires temporaires générés par le même
run) — jamais exécuté depuis les fichiers réellement exportés sur une
clé physique. Objectif de cette session : un test de bout en bout réel,
pas simulé.

### Ajouté
- `sonar_master.sh --field-export <MONTAGE>` : nouvelle commande
  indépendante qui met à jour SONAR Field (`MANIFEST/PROFILES*.tsv`,
  `Scripts/sonar_field.sh`, `MANIFEST/FIELD_PINS.tsv` si un PIN est
  défini) sur une clé déjà déployée, **sans repasser par `--disk`** —
  ne touche ni Ventoy ni `ISO/`/`Portable/`. Comblait un vrai manque :
  avant cette commande, la seule façon de rafraîchir SONAR Field sur
  une clé existante était de refaire un `--disk` complet (donc
  potentiellement retoucher Ventoy), ce qui était disproportionné pour
  juste mettre à jour un PIN ou le script lui-même.
- Couverture `--self-test` pour `--field-export` (argument manquant
  rejeté ; écriture réelle des trois fichiers vérifiée).

### Testé — validation réelle sur la clé physique (pas en bac à sable)
1. Deux PINs de terrain définis via `--field-pin-set` (Technicien/ALL,
   Stagiaire/boot-repair+data-recovery).
2. Déployés sur la clé physique via `--field-export /mnt/e` (WSL2, clé
   montée en E: côté Windows) — `MANIFEST/PROFILES.tsv`,
   `PROFILES_SCENARIOS.tsv`, `FIELD_PINS.tsv` et `Scripts/sonar_field.sh`
   confirmés présents et corrects sur la clé.
3. `sonar_field.sh` exécuté **directement depuis la clé physique**
   (pas une copie temporaire) : PIN Technicien → menu complet (6
   profils), profil `boot-repair` consulté → outils localisés
   correctement sur la clé réelle (`SystemRescue` trouvé,
   `GParted`/`TestDisk` signalés absents car empaquetés dans l'ISO, pas
   en fichiers séparés — comportement honnête, pas un faux positif) →
   message "LIMITE CONNUE" WinPE correctement affiché (aucun WinPE
   présent sur cette clé).
4. PIN Stagiaire → menu correctement filtré à 2 profils seulement
   (boot-repair, data-recovery) — confirmé que le filtrage par niveau
   fonctionne en conditions réelles, pas juste en test unitaire.
5. 3 PIN erronés consécutifs → accès refusé, journalisé
   `FIELD_ACCESS_DENIED` avec l'identité `non-identifie` (correcte :
   l'identifiant n'est demandé qu'après un PIN valide).
6. **Hashchain recalculé indépendamment** (sha256 manuel, hors du
   script) à partir des deux premières lignes du journal réel —
   correspond exactement aux hachages écrits par `sonar_field.sh` sur
   la clé. Confirme que le mécanisme d'intégrité n'est pas cosmétique.
7. Clé remise dans un état propre après le test : PINs et journaux de
   test retirés (`MANIFEST/FIELD_PINS.tsv`, `Field-Logs/*.log`) —
   `PROFILES*.tsv` et `Scripts/sonar_field.sh` laissés en place
   (contenu légitime, pas des artefacts de test).

### Non résolu
Cette validation couvre la logique de `sonar_field.sh` lui-même sur
des données réelles, mais pas encore la couche "environnement de
secours" : est-ce que SystemRescue (l'ISO réellement présente sur la
clé) monte automatiquement la partition de données Ventoy à l'un des
chemins que `sonar_field_locate` cherche (`/mnt/*`, `/media/*/*`,
`/run/media/*/*`) une fois réellement booté ? Non testé ici (le test
utilisait WSL2, qui monte différemment) — nécessiterait un vrai boot
(matériel ou VM) de l'ISO SystemRescue avec la clé attachée.

## [3.27.0-winpe-powershell-known-limitation] — 2026-09-16

### Contexte
Suite de la reconstruction WinPE (v3.25.0/v3.26.0, session précédente) :
tentative d'ajouter PowerShell à l'image WinPE de base via
`tools/Build-SonarSE-WinPE.ps1 -IncludePowerShell` (montage DISM +
`/Add-Package` des composants WinPE-WMI/NetFx/Scripting/PowerShell).

### Trouvé — quatre bugs réels dans le script, un problème d'environnement non résolu
En tentant de faire fonctionner `-IncludePowerShell`, quatre bugs
distincts et réels ont été identifiés et corrigés dans le script
lui-même (indépendants du blocage final) :
1. La redirection `> log 2>&1` passée à `Start-Process -Verb RunAs`
   dans `-ArgumentList` ne produisait AUCUN fichier log, même vide —
   ShellExecuteEx ne la propage pas de façon fiable au processus
   enfant élevé. Corrigé en faisant porter la redirection par le
   `.cmd` lui-même.
2. `if errorlevel 1` ne détecte pas un échec DISM : DISM retourne
   souvent son HRESULT brut comme code de sortie (ex. 0xC1420127), qui
   a le bit de signe posé et est donc négatif une fois interprété par
   cmd.exe — `if errorlevel 1` (comparaison signée ≥) est alors
   silencieusement faux. Un `/Mount-Image` raté a ainsi laissé passer
   tous les `/Add-Package` suivants sans jamais échouer, et le script a
   rapporté un succès complet à tort alors que rien n'avait été
   modifié. Corrigé avec `if !errorlevel! neq 0` (comparaison numérique
   directe) + `setlocal enabledelayedexpansion`.
3. `exit /b` exécuté dans un bloc parenthésé redirigé `( ... ) > log
   2>&1` termine tout l'interprète cmd.exe avant qu'il ait fini de
   traiter la redirection — le fichier log n'était alors jamais créé.
   Corrigé en déplaçant la logique dans une sous-routine appelée via
   `call :main > log 2>&1`.
4. Tout échec après un `/Mount-Image` réussi laissait l'image montée
   en lecture/écriture, ce qui faisait échouer la tentative suivante
   dès le `/Mount-Image` avec "l'image est déjà montée" (0xC1420127) —
   un échec en cascade sur un état orphelin. Corrigé avec un chemin
   `:fail_mounted` qui démonte (`/Discard`) systématiquement avant de
   sortir en erreur.

Une fois ces quatre bugs corrigés, le vrai blocage est apparu, non lié
au script : `Dism /Add-Package` échoue systématiquement dès le premier
paquet avec "Erreur: 87" (HRESULT 0x80070057) sur `CPEImg::Attach`, le
fournisseur DISM chargé pour les images WinPE hors ligne — alors que
le montage lui-même réussit sans problème. Écarté par test direct :
chemin avec espaces (rejoué avec chemin court 8.3 sans espaces, même
échec), version de DISM utilisée (rejoué avec le DISM système
10.0.19041.3636 ET celui de l'ADK 10.0.26100.2454, même échec dans les
deux cas), montage orphelin (rejoué sur montage propre vérifié via
`Dism /Get-MountedWimInfo`, même échec), antivirus (aucune détection
Defender à l'horodatage du test). Hypothèse non confirmée :
incompatibilité entre ce moteur DISM (ADK décembre 2024, ère
Windows 11 24H2) et l'hôte de test (Windows 10 22H2, build 19045) pour
le fournisseur PE spécifiquement.

### Changé
- `tools/Build-SonarSE-WinPE.ps1` : les quatre corrections ci-dessus.
  `-IncludePowerShell` passe d'activé par défaut à **désactivé par
  défaut** (image minimale, cmd.exe seul — celle qui fonctionne
  réellement, déjà validée). Reste disponible en option explicite pour
  qui veut retenter sur un autre hôte/ADK, avec échec propre garanti
  (démontage automatique, pas de corruption ni de montage orphelin
  laissé derrière).
- Docstring du script mis à jour avec le détail de la limite connue.

### Testé
Build complet de l'image minimale (sans PowerShell) rejoué de bout en
bout après le changement de défaut : copype + génération ISO réussis,
ISO produite (380 Mo, SHA-256 vérifié). `-IncludePowerShell` testé
plusieurs fois avec chaque hypothèse de correctif ci-dessus — chaque
correction validée individuellement (log produit, échec correctement
détecté, montage correctement nettoyé) avant de conclure que le
blocage restant est un problème d'environnement, pas de script.

### Non résolu
Le blocage `CPEImg::Attach` / Erreur 87 sur `-IncludePowerShell` reste
non résolu. Piste la plus probable (non testée) : installer un ADK
plus ancien (~10.1.19041 ou ~10.1.22621) correspondant mieux à la
version de l'hôte Windows 10 utilisé pour le test.

## [3.26.0-ventoy-theme-root-cause-ruled-out] — 2026-09-15

### Contexte
Suite immédiate de v3.25.0 (quelques minutes plus tôt, même session).
Après avoir désactivé le thème par défaut suite à l'échec du correctif
1024×768, l'hypothèse de travail restait "c'est une question de taille
d'image décodée, juste le seuil de v3.12.0 était trop optimiste".
Testée directement : l'image par défaut a été régénérée en **PNG
indexé/palette 800×600** (1 octet/pixel au lieu de 3 pour RGB
truecolor, ~480 Ko décodés au lieu de ~2,25 Mo) — une réduction de
~12x par rapport à ce qui avait crashé quelques minutes plus tôt.
Réappliquée sur la clé physique, rebootée sur le même HP EliteBook
840 G3.

### Trouvé — la théorie "taille d'image" ne tient plus
**Même crash**, `alloc magic is broken`, identique aux deux essais
précédents. Sur les trois tailles testées le même jour (6 Mo, 2,25 Mo,
480 Ko décodés — un facteur 12 entre la plus grande et la plus petite),
**aucune différence de comportement observée**. Au passage, l'hypothèse
RGBA (canal alpha doublant la mémoire décodée, Pillow générant du RGBA
par défaut) a aussi été vérifiée directement dans les octets du PNG
(`color_type=2` = RGB pur, pas d'alpha) et écartée avant même ce
troisième test.

**Conclusion révisée** : la taille de l'image décodée n'est
probablement pas la cause du crash, ou en tout cas pas la cause
principale. L'explication la plus plausible maintenant est une
incompatibilité du module thème/gfxmenu de Ventoy lui-même avec le
firmware de cette machine précise — un problème potentiellement côté
Ventoy/GRUB, hors de portée d'une correction dans `sonar_master.sh`
(code tiers qu'on ne maintient pas).

### Changé
- Pipeline de génération du thème (`sonar_prepare_ventoy_theme`) :
  cible maintenant 800×600 + `-colors 256`/PNG8 (palette) au lieu de
  1024×768 RGB truecolor. Gardé malgré l'échec du test : c'est
  strictement moins coûteux en mémoire décodée (jamais une régression),
  même si ce n'est plus présenté comme "le correctif" — juste une
  amélioration qui ne suffit pas à elle seule. Validé fonctionnellement
  (pipeline complet resize+incrustation+palette testé avec une vraie
  image 1920×1080 via ImageMagick réel, sortie confirmée en PNG indexé
  800×450 — voir "Testé").
- `gfxmode` par défaut dans `ventoy.json` : `"800x600,1024x768"` (ordre
  inversé, la résolution la plus petite d'abord).
- Avertissements `--help`/logs mis à jour pour refléter la vraie
  histoire (trois tailles testées, même crash) plutôt que de laisser
  entendre qu'une image plus petite réglerait le problème.
- `docs/DEPLOYMENT.md`, `ROADMAP.md` : section et entrées mises à jour
  avec la conclusion révisée. Hypothèse RGBA retirée de "Dette
  technique connue" (vérifiée fausse, pas juste non testée).
- **Clé physique (`E:`) à nouveau remise dans son état fonctionnel
  connu** (thème retiré) après confirmation du troisième crash.

### Testé
Re-test réel sur HP EliteBook 840 G3 (même machine que les deux essais
précédents) : image 800×600 indexée réappliquée → **crash confirmé une
troisième fois** ; thème retiré → boot confirmé de nouveau fonctionnel.
Séparément, le pipeline `sonar_prepare_ventoy_theme` lui-même (chemin
opérateur, pas le chemin "prebaked") a été testé fonctionnellement sous
WSL2 avec ImageMagick réel : image 1920×1080 en entrée → sortie
800×450 (ratio préservé) confirmée en PNG indexé (`color_type=3`) via
lecture directe des octets IHDR — le code fait ce qu'il est censé
faire, même si ça ne résout pas le crash sous-jacent. `bash -n`,
`shellcheck --severity=error` (rien), `--self-audit`, `--self-test`
(0 FAIL) sous WSL2 Ubuntu.

### Non résolu
Cause racine toujours inconnue. Best guess actuel : bug/incompatibilité
Ventoy 1.1.17 × ce firmware précis, pas quelque chose que
`sonar_master.sh` peut corriger. Le thème reste opt-in
(`--ventoy-theme`), avec avertissement honnête. Piste pour une
prochaine fois : reporter en amont à Ventoy, ou tester sur un second
modèle de machine pour savoir si c'est spécifique à ce HP EliteBook.

## [3.25.0-ventoy-theme-disabled-by-default] — 2026-09-15

### Contexte
Suite directe de v3.12.0 (2026-09-15, plus tôt le même jour). Cette
version-là avait corrigé le crash GRUB (`alloc magic is broken`) en
réduisant le fond d'écran Ventoy de 1920×1080 à 1024×768, avec un
avertissement honnête dans le CHANGELOG : la correction n'avait été
"validée qu'en isolation" (logique de redimensionnement testée hors
ligne), pas par un vrai reboot avec le thème corrigé réactivé — le
premier boot réussi s'était fait thème désactivé.

Cette session, l'auteur a demandé de vérifier si le thème "SONAR - SE"
s'affichait vraiment. Réponse : non, la clé physique n'avait même plus
de thème actif du tout (désactivé depuis le 14/09, jamais réappliqué
avec le correctif). **Réappliqué pour de vrai** (image 1024×768 +
bloc `theme` dans `ventoy.json`) et rebooté sur le même HP EliteBook
840 G3 qui avait révélé le bug initial.

### Trouvé — la correction précédente ne suffit pas
**Même crash** `alloc magic is broken`, avec l'image 1024×768
pourtant considérée sûre. Ce n'est pas juste "pas encore vérifié" comme
avant — c'est maintenant vérifié et **négatif**. La théorie initiale
("taille décodée trop grande pour le tas GRUB en pré-boot", 1920×1080
≈ 6 Mo décodé) reste plausible en soi, mais le seuil de sécurité
supposé (1024×768) ne l'est pas, ou la cause n'est pas uniquement la
taille décodée — piste non explorée à ce stade : Pillow (utilisé pour
générer `Branding/default_background.png`) produit du RGBA par défaut
(4 octets/pixel) plutôt que RGB (3 octets/pixel), ce qui changerait la
taille décodée réelle sans changer les dimensions ni la taille du
fichier sur disque.

### Changé — sécurité par défaut, pas juste une note
- **`INCLUDE_VENTOY_THEME` passe de `true` à `false` par défaut.** Le
  thème personnalisé (celui-là précisément, mais aussi tout thème
  opérateur par le même mécanisme) n'est plus inclus automatiquement à
  chaque `--disk` — un dépôt utilisé tel quel, sans cette version,
  aurait produit une clé qui plante au démarrage sur au moins une
  machine réelle confirmée.
- **`--ventoy-theme`** (nouveau) : active explicitement le thème, avec
  un avertissement clair dans `--help` sur ce qui a été trouvé.
  `--no-ventoy-theme` conservé pour compatibilité (sans effet, déjà le
  défaut).
- `docs/DEPLOYMENT.md` : section "Personnaliser le fond d'écran Ventoy"
  réécrite en conséquence — plus de "non testé sur un vrai démarrage
  physique" (c'est faux maintenant, c'est *testé et négatif*), remplacé
  par l'avertissement précis et la procédure de retour en arrière.
- `ROADMAP.md` : nouvelle entrée dans "Validation matérielle réelle"
  documentant ce re-test négatif, et nouvelle entrée dans "Dette
  technique connue" pour la cause racine non résolue (piste RGBA/RGB à
  vérifier en premier lors d'un prochain cycle de test matériel).
- **Clé physique (`E:`) remise dans un état qui boote** : thème
  réappliqué puis retiré à nouveau après confirmation du crash — la clé
  est revenue à son état fonctionnel connu (pas de thème) avant la fin
  de cette session.

### Testé
Re-test réel sur HP EliteBook 840 G3 (même machine que v3.12.0) :
thème réactivé (image 1024×768 + bloc `theme` conforme à
`generate_ventoy_json_final`) → **crash confirmé** ; thème retiré →
boot confirmé de nouveau fonctionnel. `bash -n`,
`shellcheck --severity=error` (rien), `--self-audit`, `--self-test`
pour le changement de défaut lui-même — à faire avant de commiter (voir
ci-dessous).

### Non résolu
Cause racine du crash toujours inconnue avec certitude. Prochaine piste
à tester (nécessite un autre cycle de reboot matériel) : régénérer
`default_background.png` en RGB (sans canal alpha) plutôt que RGBA, et/
ou tester une résolution encore plus petite (800×600).

## [3.24.0-winpe-builder] — 2026-09-15

### Contexte
Referme le principal écart réel identifié dans la décision de
positionnement SONAR-SE v1 (commit précédent, quelques minutes plus
tôt) : WinPE. Pas en redistribuant une image pré-construite (rejeté
explicitement, voir `docs/WINPE.md`), mais en automatisant sa
construction — ce que le script `sonar_master.sh` (Linux+root) ne peut
structurellement pas faire lui-même, mais qu'un script compagnon
Windows peut, puisque cette session dispose d'un accès PowerShell réel
sur la machine hôte.

### Ajouté
- **`tools/Build-SonarSE-WinPE.ps1`** (nouveau) : télécharge et installe
  le Windows ADK (Deployment Tools) + l'add-on WinPE depuis les liens
  officiels Microsoft (élévation UAC requise, une fois par
  installateur) s'ils ne sont pas déjà présents, puis exécute
  `copype`/`MakeWinPEMedia` (élévation requise aussi, le montage DISM
  l'exige) pour produire une ISO WinPE amd64 avec `bootrec`, `bcdedit`,
  `diskpart` et DISM inclus par défaut. Paramètres `-OutputIso`,
  `-WorkDir`, `-SkipAdkInstall`. Documentation intégrée
  (`Get-Help -Full`).
- `docs/WINPE.md` : réécrit pour refléter ce changement — le script est
  maintenant le chemin recommandé, la construction manuelle devient une
  section de référence, et une nouvelle section "Pourquoi cette
  distinction" explique précisément pourquoi SONAR-SE construit pour
  l'opérateur sans jamais redistribuer une image déjà construite
  (limite de licence du Windows ADK, pas de paresse).
- `--profile boot-repair`/`full` et `sonar_field.sh` : le message
  "LIMITE CONNUE" pointe maintenant vers le script plutôt que vers un
  simple renvoi de documentation ; `sonar_field.sh` détecte en plus
  dynamiquement si un WinPE est déjà présent sur la clé bootée
  (`ISO/*winpe*`) et l'affiche au lieu de la limite si c'est le cas.
- `README.md`/`ROADMAP.md` (étape 4) mis à jour en conséquence.

### Testé
Bout en bout, en conditions réelles, sur cette machine :
`bash -n`/`shellcheck --severity=error` (rien)/`--self-audit`/
`--self-test` (0 FAIL) pour `sonar_master.sh` sous WSL2 Ubuntu. Pour le
script PowerShell : ADK Deployment Tools installé avec succès (silencieux
après une élévation UAC), add-on WinPE installé, `copype` puis
`MakeWinPEMedia` exécutés avec succès (élévation requise), ISO produite
(398 Mo, `SHA256=6ad61eabac27a9bfe2f15562f4c6a755664ae9cf767494808be4058479ecf3ed`),
**attachée à une VM VirtualBox et
démarrée avec succès** — invite de commande WinPE (`X:\Windows\
System32>`) confirmée fonctionnelle par l'opérateur.

### Non fait dans cette version
- Personnalisation de l'image (pilotes, paquets optionnels WinPE-*) —
  le script produit une image WinPE de base, suffisante pour
  `bootrec`/`bcdedit`/`diskpart`/DISM mais pas enrichie davantage.
- Test du WinPE construit sur du **matériel physique réel** (seulement
  VM cette session) — cohérent avec la même limite déjà notée pour
  `sonar_field.sh` en v3.21.0.

## [3.23.0-sonar-se-v1] — 2026-09-15

### Contexte
Demande explicite : officialiser le nom de produit "SONAR - SE" (déjà
utilisé pour le thème Ventoy) partout, et positionner SONAR-SE comme
alternative "plus professionnelle" à MediCat/Hiren's BootCD. Avant
d'exécuter, vérifié la prémisse implicite ("plus complet" = imiter leur
volume d'outils) — et corrigée : MediCat et Hiren's BootCD PE
atteignent leur ampleur en redistribuant des centaines d'outils tiers
sans revendiquer de licence dessus (leurs propres mentions légales
l'affirment explicitement — "non affiliés, n'endossons aucune
licence"). Adopter cette approche casserait la vraie différence de
SONAR-SE : chaque outil `--fetch` est vérifié et sa provenance
documentée.

### Changé
- Nom de produit "SONAR - SE" officialisé : titre `README.md`, bannière
  `usage_final()` (`--help`), messages de fin de déploiement
  (`SONAR MASTER — moteur unique/TERMINÉ` → `SONAR - SE — ...`, au
  passage retiré la mention obsolète "catalogue conservé" qui référait
  à l'ancien paradigme où le catalogue 981 était la source de vérité).
  Le fichier reste `sonar_master.sh` — renommage de produit, pas de
  dépôt.
- **`docs/WINPE.md`** : nouvelle section documentant Hiren's BootCD PE
  et MediCat USB comme alternatives **manuelles** à un WinPE construit
  soi-même (l'opérateur les télécharge et les dépose lui-même, même
  mécanisme que pour un WinPE fait main) — explicitement **jamais**
  ajoutés à `--fetch`, avec la raison (licence non garantie par ces
  deux projets pour les outils qu'ils embarquent, contrairement à
  chaque entrée du manifeste `--fetch`).
- `ROADMAP.md` : nouvelle section "SONAR - SE v1" documentant cette
  décision de positionnement pour ne pas avoir à la retrancher plus
  tard.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit`,
`--self-test` (0 FAIL — aucun test ne dépendait des anciennes chaînes
"SONAR MASTER") sous WSL2 Ubuntu. Vérifié manuellement que `--help`
affiche bien la nouvelle bannière.

## [3.22.0-sonar-field-accreditation] — 2026-09-15

### Contexte
Comble la partie explicitement laissée ouverte par la v1
(v3.21.0, quelques minutes plus tôt) : l'accréditation par niveau,
héritée de l'ancienne étape 7 du recentrage. Objectif inchangé depuis
la demande initiale : "chaque technicien s'identifie et n'accède qu'aux
outils/profils correspondant à son niveau d'accréditation."

### Changé (remplace le mécanisme v1, pas un ajout à côté)
- **`--field-pin-set <NIVEAU> <PIN> [PROFILS]`** (au lieu de
  `--field-pin-set <PIN>`) : `PROFILS` = `ALL` (défaut) ou une liste
  séparée par des virgules parmi les 6 profils. Rejouer avec le même
  `NIVEAU` met à jour sa ligne (PIN et/ou profils) sans toucher aux
  autres niveaux déjà définis. Valide que chaque profil listé existe
  réellement (refuse `profil-bidon` avec un message explicite) et que
  le niveau/PIN ne sont pas vides ou trop courts (<4 caractères).
- **`MANIFEST/FIELD_PINS.tsv`** (remplace `FIELD_PIN.sha256`) : une
  ligne par niveau (`NIVEAU\tSHA256(PIN)\tPROFILS`), plusieurs niveaux
  coexistent sur la même clé.
- **`sonar_field.sh`** : le PIN saisi détermine maintenant à la fois
  l'identité journalisée (`Field:technicien(NIVEAU)`) et les profils
  affichés — le menu est filtré en conséquence (un niveau restreint à
  `boot-repair,data-recovery` ne voit même pas les 4 autres profils,
  pas seulement un accès bloqué après coup). Sans aucun PIN configuré :
  comportement inchangé (accès libre, avertissement explicite).
- 6 nouveaux tests de régression `--self-test` : validation niveau/PIN/
  profil inconnu, accumulation de plusieurs niveaux sans écrasement,
  et surtout un test de bout en bout confirmant que le menu affiché
  diffère réellement selon le PIN saisi (niveau restreint vs niveau
  `ALL`).

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit`,
`--self-test` (0 FAIL, 11 tests SONAR Field au total dont les 6
nouveaux) sous WSL2 Ubuntu. Le test de bout en bout le plus important
vérifie le comportement observable réel (quels profils apparaissent
dans le menu selon le PIN), pas seulement que les fonctions s'exécutent
sans erreur.

## [3.21.0-sonar-field-v1] — 2026-09-15

### Contexte
Première implémentation de **SONAR Field**, le second produit décidé
plus tôt cette session (voir commit dd0aadb et ROADMAP.md). Devenue
possible maintenant que l'étape 3 (SystemRescue embarqué) est faite :
on peut enfin écrire l'interface d'un environnement de boot qui existe
réellement sur la clé, plutôt que de la deviner.

Portée volontairement limitée pour ce premier jet : un guide + un
journal, pas un orchestrateur qui exécute des commandes destructrices
tout seul — cohérent avec la règle de fond du projet ("ne rien faire
qu'on ne puisse pas expliquer après coup").

### Ajouté
- **`sonar_field.sh`** (nouveau, embarqué dans `sonar_master.sh` et
  généré sur la clé via `sonar_export_field_files`, appelée depuis
  `copy_payload_final` — même mécanisme de distribution que
  `sonar-vault.sh`) :
  - Localise la partition de la clé (argument, ou recherche sous
    `/mnt`/`/media`/`/run/media`).
  - **Identification par PIN** (optionnel) : si
    `MANIFEST/FIELD_PIN.sha256` existe, exige le bon PIN (3 essais,
    accès refusé et journalisé sinon) puis demande un identifiant
    texte libre pour le journal. Sans PIN configuré, prévient
    explicitement que l'accès n'est pas verrouillé plutôt que de le
    prétendre en silence.
  - **Menu orienté tâche** : liste les 6 profils avec leur scénario,
    affiche pour le profil choisi ses outils + pourquoi + où ils se
    trouvent sur la clé (recherche dans `ISO/`/`Portable/`) — ne lance
    jamais rien automatiquement, le technicien exécute lui-même les
    commandes, comme fait manuellement pendant la validation de
    l'étape 6.
  - **Journal** : `Field-Logs/{audit,hashchain}.log` sur la clé, même
    format exact que `sonar_master.sh`
    (`TS\tROLE\tEVENT\tDETAILS[\tHASH]`, même construction de hash
    chaîné) — un cas (préparation + intervention) se relit comme une
    seule histoire continue.
- **`--field-pin-set <PIN>`** (rôle VAULT — voir note ci-dessous) :
  définit le PIN de terrain, copié dans `MANIFEST/FIELD_PIN.sha256` au
  prochain `--disk`. Refuse un PIN de moins de 4 caractères.
- **`sonar_export_field_files`** : dépose `MANIFEST/PROFILES.tsv` et
  `MANIFEST/PROFILES_SCENARIOS.tsv` (export TSV de
  `SONAR_PROFILES_TSV` et de `sonar_profile_scenario()`) — mêmes
  données que `--profile`, jamais dupliquées à la main.
- 7 tests de régression `--self-test` : présence des fonctions, le
  script généré passe `bash -n`, les exports TSV existent, smoke test
  du menu (avertissement PIN absent + sortie propre), validation
  longueur PIN, écriture du fichier de hash.

### Trouvé en testant (pas un bug introduit ici — comportement existant)
- La colonne `VAULT` de `policy.tsv` est en réalité en libre-service
  pour tous les rôles authentifiés sauf `Viewer` (`Technician` a déjà
  `RW` dessus) — pas un gardien "rôle élevé" comme le nom pourrait le
  laisser penser. Comportement déjà utilisé tel quel par
  `sonar_catalog_seal`/`sonar_fetch_manifest_seal` avant ce commit,
  donc pas une régression de cette version ni quelque chose à corriger
  ici — juste documenté pour ne pas se refaire piéger. Un premier test
  de régression supposait le contraire (Technician refusé) et a été
  corrigé pour tester la vraie garantie fournie (validation de longueur
  du PIN) plutôt qu'une hypothèse fausse sur le RBAC.

### Non fait dans cette version
- Accréditation par niveau (Technician/Senior/Admin avec des profils
  différents) — v1 répond à "qui a touché la clé", pas encore à "qui a
  le droit de quoi". Reste la partie non close de l'ancienne étape 7.
- Auto-détection robuste de la partition clé (scan `lsblk` par label/
  contenu) — v1 cherche sous des points de montage usuels ou prend un
  chemin en argument.
- Lancement effectif des outils — resterait volontairement soumis à
  confirmation explicite même automatisé un jour.
- Test de `sonar_field.sh` sur un vrai boot SystemRescue — validé en
  local (génération + exécution simulée) cette session, pas encore sur
  la clé réellement bootée.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit`,
`--self-test` (0 FAIL, 7 nouveaux tests inclus) sous WSL2 Ubuntu.
Scénario complet manuel en plus des tests automatisés : mauvais PIN×3
→ refus journalisé (`FIELD_ACCESS_DENIED`), bon PIN → accès accordé
avec identité + menu affiché (`FIELD_ACCESS_GRANTED`), journal
`Field-Logs/audit.log` vérifié ligne par ligne.

## [3.20.0-hardware-validation-complete] — 2026-09-15

### Contexte
Étape 6/6 du recentrage, dernier scénario : `malware`. Avec `boot-repair`
et `data-recovery` déjà validés (v3.19.0), c'est le **3e sur 3**
scénarios minimum exigés par `ROADMAP.md` — **étape 6 close**.

Une tentative sur machine physique réelle (pas la VM) a été faite en
premier, avec la vraie clé SONAR (`E:`, déployée le 2026-09-14) mise à
jour pour l'occasion (SystemRescue + ClamAV copiés dessus, dossier
`E:\TestMalware\` avec les 3 fichiers EICAR). Le démarrage physique a
posé plus de difficultés que prévu (clavier, navigation) sans qu'on
puisse établir clairement la cause avant d'abandonner cette voie pour
la session de VM déjà en place — **non résolu**, à reprendre une
prochaine fois si un test matériel physique complet du scénario reste
souhaité. La clé physique reste équipée (ClamAV + EICAR dessus) pour
cette prochaine tentative.

### Testé — `malware` : SUCCÈS après plusieurs corrections en cascade
Sur le même disque de test VM que les scénarios précédents (partition
`SONARP2`, fichiers témoins déjà validés), 3 fichiers EICAR standard
déposés hors-VM via WSL (`eicar.com`, `facture_suspecte.exe` — extension
trompeuse, `sous_dossier/eicar_cache.scr` — sous-dossier + extension
trompeuse). ClamAV livré à la VM via une image ISO de données
(`sonar_data.iso`, générée avec `genisoimage`, attachée comme second
lecteur — plus propre que de le re-télécharger depuis la VM, ça
préserve la vérification SHA-256/GPG déjà faite au `--fetch`).

Trois obstacles réels rencontrés et résolus dans l'ordre — chacun
maintenant documenté dans la colonne `NOTES` du manifeste
(`SONAR_FETCH_MANIFEST_TSV`, entrée `ClamAV`) pour que la prochaine
tentative n'ait pas à les redécouvrir :
1. **Espace insuffisant sur le système live** : l'extraction complète
   du `.deb` (~300 Mo, essentiellement de la documentation) remplissait
   l'overlay en RAM d'une VM à 2 Go — `No space left on device` en
   plein milieu de `tar xf`. Corrigé en passant la VM à 4 Go de RAM
   (redémarrage nécessaire, pas de correctif à chaud).
2. **Chemin du binaire réel différent de l'hypothèse initiale** :
   `usr/local/bin/clamscan`, pas `usr/bin/clamscan` comme documenté
   jusqu'ici — trouvé via `find`, pas deviné.
3. **Bibliothèque partagée introuvable puis base de signatures
   absente** : `error while loading shared libraries: libclamav.so.12`
   (corrigé avec `LD_LIBRARY_PATH=<extrait>/usr/local/lib`), puis un
   premier scan "réussi" à 0 fichier scanné (base de signatures vide —
   le paquet ne l'inclut pas). Corrigé avec `freshclam --datadir=...`
   (téléchargement réseau depuis la VM) puis `clamscan --database=...`
   pointé explicitement dessus (le chemin système par défaut,
   `/usr/local/share/clamav`, n'existe pas hors d'une vraie
   installation).

**Résultat final : 3/3 fichiers EICAR détectés**, y compris les deux à
extension trompeuse (`.exe`, `.scr`) et celui en sous-dossier — confirme
que la détection se fait bien par signature de contenu, pas par nom ou
emplacement.

### Corrigé (documentation)
- `SONAR_FETCH_MANIFEST_TSV`, entrée `ClamAV` : NOTES enrichies avec le
  chemin réel du binaire et la séquence complète
  `LD_LIBRARY_PATH`/`freshclam`/`--database` — évite de refaire ce
  parcours de découverte la prochaine fois.

### Non résolu
- Démarrage physique réel de la clé sur machine physique : difficultés
  rencontrées (clavier, navigation), cause non identifiée, abandonné
  au profit de la VM pour cette session. La clé physique (`E:`) reste
  équipée pour une prochaine tentative.

### Testé (méta)
Même limite que les scénarios précédents : manipulations interactives
dans SystemRescue effectuées par l'opérateur humain (moi ne pouvant pas
piloter une TUI/GUI à distance) ; accès disque physique brut à la vraie
clé USB depuis une VM explicitement refusé par le mode auto de cet
environnement (catégorie "Irreversible Local Destruction") — décision
de sécurité respectée sans tentative de contournement, option laissée à
l'utilisateur (exécuter la commande lui-même hors de cette session) non
retenue cette fois par manque de temps/énergie.

## [3.19.0-hardware-validation-partial] — 2026-09-15

### Contexte
Étape 6/6 du recentrage : validation matérielle des profils, protocole
détaillé dans `docs/VALIDATION-ETAPE6.md` (commit 827b296). Exécutée en
conditions réelles cette session, sur VM VirtualBox 7.2.16 (nouvellement
installée, SHA-256 vérifié contre `SHA256SUMS` officiel avant
installation) : 2 scénarios sur les 3 minimum exigés par `ROADMAP.md`
(`boot-repair`, `data-recovery`) — `malware` reste à faire. Étape 6
**pas encore close**, gardée ouverte dans `ROADMAP.md`.

Disque de test préparé via WSL2 (accès root natif `wsl -u root`, sans
sudo interactif) : image 2 Go, table GPT, 2 partitions ext4
(`SONARP1` vide, `SONARP2` avec 5 fichiers témoins de 1 MiB) — converti
en VDI et attaché à une VM avec l'ISO SystemRescue (récupérée via
`--fetch boot-repair`, SHA-256 déjà vérifié au commit 730a1c5) comme
support de boot.

### Testé — `boot-repair` : SUCCÈS COMPLET, vérifié bit-exact
- Panne injectée : premier Mo du disque écrasé (`dd if=/dev/zero`),
  détruisant l'en-tête GPT et la table de partitions.
- Réparation : `testdisk /dev/sda` (via SystemRescue sur la clé SONAR)
  → type **EFI GPT** → **Analyse** → **Recherche rapide**. Les 2
  partitions retrouvées **du premier coup**, avec leurs labels de
  filesystem d'origine intacts (`SONARP1`/`SONARP2`) — pas besoin de
  recherche approfondie. "Write" pour réécrire la table.
- Vérification : après remontage, les 5 fichiers témoins comparés par
  SHA-256 à leurs empreintes d'avant la casse — **5/5 identiques, octet
  pour octet**.
- Surprise : aucune — le scénario s'est déroulé exactement comme prévu
  par le protocole.

### Testé — `data-recovery` : succès après correction de méthodologie
- Panne injectée : suppression normale (`rm`) des 5 fichiers témoins
  sur la partition déjà réparée.
- **Première tentative (PhotoRec) : 0 fichier récupéré — et c'est
  attendu, pas un échec de l'outil.** PhotoRec récupère par
  reconnaissance de signature de format (en-tête JPEG/PDF/ZIP/...) ; les
  fichiers témoins étaient des données `/dev/urandom` sans aucun format
  reconnaissable. Erreur de méthodologie de test (le protocole
  recommandait déjà des formats reconnaissables pour cette raison même
  — pas suivi lors de la préparation du disque cette session), pas un
  problème du profil `data-recovery`.
- **Deuxième tentative (TestDisk, mode "List") : succès.** Pour
  ext2/3/4, TestDisk n'a pas de commande "Undelete" séparée — "List"
  affiche directement les entrées du répertoire, y compris les fichiers
  supprimés dont les blocs n'ont pas encore été réécrits, sélectionnables
  et copiables (`a` sélectionne tout, `C` copie). Les 5 fichiers
  retrouvés avec leur taille exacte (1 048 576 octets chacun) ;
  "Copy done: 5 ok, 0 failed".
- **Limite explicite de cette validation** : contrairement au scénario
  `boot-repair`, le SHA-256 des fichiers copiés n'a **pas** été
  reconfirmé bit-exact cette session (arrêt des manipulations
  manuelles avant cette dernière étape). Taille exacte + rapport "0
  failed" de l'outil sont des signaux forts mais pas une preuve
  cryptographique — à refaire une prochaine session pour clore ce point
  proprement.
- Surprise réelle et utile à retenir : **PhotoRec et TestDisk
  "List/Undelete" ne sont pas interchangeables** — le choix du bon
  outil dépend de la nature de la perte (structure de répertoire encore
  intacte vs fichier reconnaissable par signature). Le profil
  `data-recovery` documente déjà les deux outils ; cette session
  confirme que c'est délibéré, pas redondant.

### Non fait dans cette version
- Scénario `malware` (le 3e minimum exigé) : pas encore exécuté.
- Vérification SHA-256 bit-exacte du scénario `data-recovery` : à
  refaire (voir "Limite explicite" ci-dessus).
- Étape 6 reste `[ ]` non cochée dans `ROADMAP.md` — au moins un
  scénario supplémentaire nécessaire pour la clore.

### Testé (méta)
VM VirtualBox créée et pilotée via `VBoxManage` (CLI) pour la
préparation (disque, ISO, réseau boot) ; les manipulations interactives
dans TestDisk/PhotoRec elles-mêmes (navigation clavier, choix de menu)
ont été effectuées par l'opérateur humain via la fenêtre VirtualBox,
Claude ne pouvant pas piloter une interface graphique/TUI interactive à
distance — cohérent avec la limite déjà documentée sur l'exécution de
cette étape.

## [3.18.0-winpe-step4-documented-gap] — 2026-09-15

### Contexte
Étape 4/6 du recentrage : WinPE via Windows ADK, "la pièce qui
différencie MediCat/Hiren's BootCD/Strelec" selon les mots de l'auteur.
Confirmé, comme anticipé dès la formulation du plan initial : construire
un WinPE demande le Windows ADK (`copype.cmd`, `MakeWinPEMedia.cmd`,
DISM), un outillage qui n'existe que sous Windows, alors que
`sonar_master.sh` exige de tourner en root sous Linux
(`preflight_final`). Ce n'est pas un manque d'effort d'implémentation —
les deux mondes ne se recoupent pas, il n'existe littéralement pas de
chemin où ce script piloterait cet outillage. Instruction explicite de
l'auteur pour ce cas précis : "documenter explicitement que SONAR ne
fournit pas de WinPE et que l'opérateur doit en fournir un" plutôt que
de sauter l'étape en silence.

### Ajouté (documentation, aucune tentative d'implémentation)
- **`docs/WINPE.md`** (nouveau) : explique pourquoi c'est impossible
  depuis ce script, ce qui en dépend concrètement (la réparation côté
  Windows du profil `boot-repair` — `bootrec`/`bcdedit`/`DISM` — reste
  hors de portée sans WinPE ; `boot-repair` couvre déjà la réparation
  côté Linux via SystemRescue, donc reste utile mais partiel), le guide
  pas-à-pas pour que l'opérateur construise le sien (ADK + add-on WinPE,
  `copype amd64 <dossier>`, `MakeWinPEMedia /iso <dossier>
  <fichier.iso>`), comment l'ajouter à une clé SONAR (dépôt dans
  `SOURCE_DIR/ISO/WinPE/` — même mécanisme de copie récursive que
  `--fetch`, aucune commande SONAR spécifique), et pourquoi une
  distribution d'un WinPE pré-construit dans ce dépôt a été rejetée
  (licence : un WinPE embarque des composants Microsoft sous licence
  propre à chaque poste de build).
- **`sonar_profile_caveat()`** (`sonar_master.sh`) : les profils
  `boot-repair` et `full` affichent désormais une section "LIMITE
  CONNUE" directement dans `--profile <nom>`, pas seulement dans un
  fichier séparé qu'un opérateur pressé pourrait manquer.
- `README.md`/`docs/DEPLOYMENT.md` : pointeurs explicites vers
  `docs/WINPE.md` à l'endroit où l'opérateur prépare son `--source`.
- Un test de régression `--self-test` : confirme que `--profile
  boot-repair` mentionne bien la limite WinPE dans sa sortie.

### Testé
`bash -n`, `shellcheck --severity=error` (rien), `--self-audit`,
`--self-test` (0 FAIL, nouveau test inclus) sous WSL2 Ubuntu.

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

---

**Note sur les entrées suivantes** : les changements ci-dessous (jusqu'à
`[3.3.0-role-lock]`) sont réels — pas des doublons ni du bruit — mais
n'ont pas de numéro de version individuel identifiable. Ils viennent
d'une migration verbatim de l'historique qui vivait à l'origine dans
l'en-tête de `sonar_master.sh`, où ils n'étaient déjà pas versionnés
séparément (juste accumulés chronologiquement). Plutôt que d'inventer
des numéros de version que je ne peux pas vérifier, ils restent groupés
ici, dans l'ordre chronologique (plus récent en premier, comme le reste
du fichier), entre leurs deux vrais points d'ancrage connus :
`[3.10.2-audit-integrity]` (2026-08-18) au-dessus et
`[3.3.0-role-lock]` (2026-08-16) en dessous.

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

## Non résolu / dette connue (état au 2026-08-14, à la toute première
version de ce fichier — PÉRIMÉ, conservé pour l'historique)

Cette liste décrivait la dette connue au moment de la toute première
version de `sonar_master.sh` (`3.1.0-final-integrated` et antérieur,
juste en dessous). Presque tous ces points ont depuis été traités ou
invalidés par des entrées bien plus récentes **au-dessus** dans ce même
fichier (rappel : le plus récent est en haut) — notamment le premier
boot réel (`3.11.2`/`3.12.0`), la validation matérielle complète
(`3.19.0`/`3.20.0`), le HMAC (`3.6.0`, déjà noté barré ci-dessous), et
la chaîne de possession forensique (voir plus haut, "Ajouté"). **Pour
l'état réellement actuel de la dette technique, voir `ROADMAP.md`**, la
seule source tenue à jour sur ce sujet — pas cette section.

- ~~Jamais testé sur du vrai matériel.~~ Faux depuis `3.11.2`/`3.12.0`
  (premier boot réel) et confirmé à plus grande échelle en
  `3.19.0`/`3.20.0`.
- Hachage à clé (SHA-256), pas un HMAC formel. ~~Résolu en v3.6.0~~
- Aucun audit de sécurité externe / pentest. (Toujours vrai à ce jour.)
- Fichier monolithique (~3800 lignes à l'époque, nettement plus
  aujourd'hui) — refactor modulaire toujours pas fait, voir `ROADMAP.md`
  P1 pour la décision de séquençage actuelle (CI d'abord).
- Pas de chaîne de distribution signée (GPG) des releases. (Toujours
  vrai à ce jour.)
- Portabilité Windows/macOS en trompe-l'œil (mentions PowerShell, cœur
  100% Bash). (Nuancé depuis : `tools/Build-SonarSE-WinPE.ps1` est un
  vrai script PowerShell compagnon, mais reste un outil séparé, pas une
  portabilité du script principal.)
- ~~Pas de documentation utilisateur ni de modèle de chaîne de
  possession (chain of custody) pour le module forensique.~~ Le modèle
  de chaîne de possession existe depuis l'entrée juste au-dessus
  (`--forensic-chain-of-custody`). La documentation utilisateur au-delà
  du `--help` intégré reste, elle, non faite (voir `ROADMAP.md` P2).
