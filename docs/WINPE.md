# WinPE — ce que SONAR - SE fournit, et ce qu'il ne fournit pas

**SONAR - SE ne redistribue aucun WinPE pré-construit — mais peut
maintenant vous aider à en construire un vous-même, automatiquement**
(`tools/Build-SonarSE-WinPE.ps1`, ajouté le 2026-09-15). Distinction
importante, pas cosmétique : voir "Pourquoi cette distinction" plus bas.

## Pourquoi `sonar_master.sh` lui-même ne peut pas le faire

Construire un WinPE demande le **Windows ADK** (Assessment and
Deployment Kit) et son add-on WinPE — un outillage qui n'existe que pour
Windows (`copype.cmd`, `MakeWinPEMedia.cmd`, DISM). `sonar_master.sh`,
lui, exige de tourner **en root sous Linux** (`preflight_final` refuse
net sinon) — c'est la condition de tout le reste du pipeline (montage de
partitions, `mkfs.ext4`, écriture bloc sur le disque). Il n'existe pas
de chemin où ce même script bash piloterait un outillage Windows-only :
ce n'est pas une question d'effort d'implémentation, les deux mondes ne
se recoupent pas dans un seul processus.

**Ce qui a changé (2026-09-15)** : ça ne veut plus dire "impossible à
automatiser du tout" — juste "impossible depuis `sonar_master.sh`
lui-même". Un script **compagnon** en PowerShell
(`tools/Build-SonarSE-WinPE.ps1`), qui tourne côté Windows où le Windows
ADK vit réellement, automatise exactement ce que la section
"construction manuelle" ci-dessous décrivait à la main.

## Construire un WinPE avec le script fourni (recommandé)

Sur une machine Windows, PowerShell en tant qu'administrateur :

```powershell
cd sonar-project
.\tools\Build-SonarSE-WinPE.ps1
```

Le script : télécharge le Windows ADK (Deployment Tools) et l'add-on
WinPE depuis les liens officiels Microsoft s'ils ne sont pas déjà
installés (une fenêtre UAC apparaît — à approuver), puis exécute
`copype`/`MakeWinPEMedia` pour produire `SONAR-SE-WinPE-amd64.iso` avec
`bootrec`, `bcdedit`, `diskpart` et DISM inclus par défaut — c'est
précisément ce qu'il faut pour la réparation côté Windows du profil
`boot-repair` (`bootrec /rebuildbcd`, `bcdedit`, `DISM
/Image:... /Cleanup-Image`).

Testé de bout en bout le 2026-09-15 : installation ADK silencieuse
(`/quiet`, élévation UAC une fois par installateur), `copype`/
`MakeWinPEMedia` élevés (le montage DISM l'exige), ISO résultante
(398 Mo) démarrée avec succès sur VM VirtualBox — invite de commande
WinPE fonctionnelle confirmée.

`-OutputIso <chemin>` pour construire directement dans
`SONAR_SOURCE\ISO\WinPE\` ; `-SkipAdkInstall` si l'ADK est déjà présent.
Voir l'aide intégrée (`Get-Help .\tools\Build-SonarSE-WinPE.ps1 -Full`).

**`-BrandBootManager` (activé par défaut, ajouté le 2026-09-18)** :
avant même que `startnet.cmd` ne prenne la main, WinPE affiche
normalement le logo Windows animé pendant quelques secondes (écran
noir avec points tournants, dessiné par `winload`/`bootmgr` à partir du
magasin BCD). Cette option renomme les entrées `{bootmgr}`/`{default}`
du magasin BCD (BIOS **et** UEFI, Ventoy pouvant chainloader l'un ou
l'autre) de "Windows Boot Manager"/"Windows Setup" vers **"SONAR - SE"**,
et désactive l'animation graphique (`bootuxdisabled yes`). Opérations
`bcdedit /store <fichier>` standard sur le magasin BCD de l'image en
cours de construction (pas le magasin BCD du système hôte) — même
registre de risque que les autres commandes bcdedit du menu de
réparation, **pas** un patch binaire de ressource comme l'aurait été un
remplacement littéral du logo (`bootres.dll`) : ça, ça reste hors de
portée sans un risque de casser le boot pour un gain cosmétique
marginal (l'écran est visible 2-3 secondes). `-BrandBootManager:$false`
restaure le comportement Windows par défaut.

Vérifié le 2026-09-18 par copie des deux magasins BCD hors de l'ISO
final (montage lecture seule + `bcdedit /store ... /enum`) :
`description` = `SONAR - SE` sur `{bootmgr}` et `{default}`,
`bootuxdisabled` = `Yes` sur `{default}`, confirmé sur les deux
magasins (BIOS et UEFI).

**`-AddRepairMenu` (activé par défaut, ajouté le 2026-09-17, étendu le
2026-09-18)** : remplace `startnet.cmd` par un menu batch numéroté au
lieu du `cmd.exe` brut — le technicien n'a plus besoin de mémoriser la
syntaxe exacte de chaque commande :

1. Réparer le démarrage (`bootrec`)
2. Configuration de boot (`bcdedit`)
3. Gestion des disques/partitions (`diskpart`)
4. Vérifier/réparer une image Windows hors ligne (DISM ScanHealth/RestoreHealth)
5. Vérifier les fichiers système hors ligne (`sfc /scannow /offbootdir=...`) — complémentaire à DISM, pas redondant : DISM répare le magasin de composants, SFC remplace les fichiers système protégés corrompus
6. Déverrouiller un disque BitLocker (`manage-bde`) — voir limitation ci-dessous
7. Injecter des pilotes dans le disque cible (`Dism /Add-Driver`) — utile quand `diskpart`/`bootrec` ne voient aucun disque (contrôleur NVMe/RAID récent absent du WinPE de base)
8. Sauvegarder des fichiers utilisateur (`robocopy`) avant une réparation risquée
9. Exporter les journaux d'événements (`.evtx`) pour diagnostiquer *pourquoi* le démarrage a échoué avant de réparer à l'aveugle
10. Diagnostic réseau (`ipconfig`/`ping`)
11. Invite de commandes libre (`cmd.exe`)

Toutes ces commandes (y compris `manage-bde`, `sfc`, `robocopy`,
`ipconfig`) sont des binaires Windows de base déjà présents dans WinPE,
**sauf `manage-bde`** — voir juste en dessous. Implémenté en simple
remplacement de fichier après montage DISM (pas de `/Add-Package` pour
le menu lui-même), donc non concerné par la limite connue de
`-IncludePowerShell` ci-dessus.

**Limitation connue : BitLocker (`manage-bde`)** — contrairement aux
dix autres options, `manage-bde.exe` n'est PAS inclus dans le WinPE de
base ; il nécessite le composant `WinPE-SecureStartup`, ajouté via
`Dism /Add-Package` comme PowerShell. Confirmé le 2026-09-18 sur cet
hôte (ADK 10.1.26100.2454) : **même échec exact** que
`-IncludePowerShell` ("Erreur: 87 — Une erreur d'initialisation s'est
produite"), reproduit sur `WinPE-SecureStartup` avec le même mécanisme
robuste (`Cleanup-Mountpoints`, `call "$setEnvBat"`, `!errorlevel!`) —
confirmant qu'il s'agit d'une incompatibilité générale ADK/DISM sur cet
hôte, pas un problème spécifique à BitLocker. `-IncludeBitLockerTools`
(désactivé par défaut) tente quand même l'ajout — utile si vous
reconstruisez sur un hôte où `/Add-Package` fonctionne. **Sans cette
option**, l'entrée BitLocker du menu détecte l'absence de
`manage-bde.exe` et l'indique clairement au lieu d'échouer avec un
message `cmd.exe` cryptique ; les dix autres options fonctionnent
normalement dans tous les cas.

ISO reconstruite et vérifiée le 2026-09-18 avec ce menu étendu :
SHA-256 `edb7a8ca4817442797cad6b692f53f596ddbf70953de0d0c78e35721a21bd6e7`
(378,8 Mo, inclut aussi le renommage BCD `-BrandBootManager` ci-dessus)
— les 8 nouveaux libellés (`:sfc_menu`, `:bitlocker_menu`,
`:bitlocker_recovery`, `:bitlocker_bek`, `:driver_menu`, `:backup_menu`,
`:eventlog_menu`, `:network_menu`) et la détection `manage-bde.exe`
confirmés présents dans `startnet.cmd` via remontage DISM en lecture
seule de l'ISO final, en plus de la vérification automatique du script.

**Bug de génération corrigé le 2026-09-17 (plusieurs heures de diagnostic)**
Le premier ISO produit ce jour-là (SHA-256 `6ad61eab...`, décrit ici comme
"testé et déployé") s'est révélé, après un vrai test de boot en VM
VirtualBox, ne PAS contenir le menu malgré un montage DISM et un
remplacement de `startnet.cmd` rapportés comme réussis dans le log de
build. Root cause confirmée par isolation méthodique (chaque hypothèse
testée et écartée une à une : verrou VirtualBox sur le fichier ISO,
montages DISM orphelins, absence du flag `/f` sur `MakeWinPEMedia.cmd`,
fichier de destination déjà existant) : **lancer `oscdimg.exe`
(directement ou via `MakeWinPEMedia.cmd`) à travers une élévation
PowerShell (`Start-Process -Verb RunAs`) produisait un ISO dont le
`boot.wim` restait inchangé**, malgré un "100% complete" affiché par
oscdimg lui-même. oscdimg n'a jamais eu besoin de droits administrateur
(il ne fait que lire un dossier et écrire un fichier) ; seuls `copype` et
le montage DISM en ont réellement besoin. Le script appelle maintenant
`oscdimg.exe` directement, sans élévation, et **vérifie automatiquement**
après génération que le menu est bien présent dans le `boot.wim` final
(remontage + `findstr`) — si ce n'est pas le cas, le script échoue
bruyamment au lieu de rapporter un faux succès.

Confirmé le 2026-09-17 (après correctif) : ISO régénérée (378,8 Mo,
SHA-256 `529d841c9dbef6570a0acf64f0a3d6d20f09e37688fd97009cea427acf57f5ff`),
vérification automatique du menu réussie, déployée sur la clé physique
(hash identique confirmé côté clé). **Pas encore testé par un vrai boot
matériel** (seule une vérification de contenu post-génération, pas un
démarrage réel). Utiliser `-AddRepairMenu:$false` pour revenir au
`cmd.exe` brut.

**`-IncludePowerShell` (optionnel, désactivé par défaut)** : tente
d'ajouter PowerShell à l'image (au-delà de cmd.exe/bootrec/bcdedit/
diskpart/DISM déjà présents). Testé le 2026-09-16 sur un hôte
Windows 10 22H2 avec l'ADK de décembre 2024 : le montage réussit mais
`Dism /Add-Package` échoue systématiquement ("Erreur: 87", HRESULT
0x80070057 sur le fournisseur DISM des images WinPE hors ligne) — cause
probable non confirmée, incompatibilité entre ce moteur DISM récent et
un hôte Windows 10 plus ancien. Voir `CHANGELOG.md` (entrée
3.27.0-winpe-powershell-known-limitation) pour le détail des pistes
écartées. L'option reste disponible pour qui veut retenter sur un autre
hôte ou avec un ADK plus ancien ; en cas d'échec, le script s'arrête
proprement (démontage automatique, pas de montage orphelin laissé).

**`-IncludeToolbox` (activé par défaut, ajouté en 3.43.0)** : le WinPE de
base est « très limité » — cmd.exe et quelques outils, sans PowerShell ni
WMI, et `Dism /Add-Package` est impossible sur un hôte Windows 10 (voir
« LIMITE CONNUE » de l'aide du script). Plutôt que de contourner DISM, la
boîte à outils est **copiée** dans l'image montée (`Windows\System32\sonar`) :

| Option du menu | Ce qu'elle fait |
|---|---|
| 12 Diagnostic intelligent | Collecte lecture seule (disques, volumes, ESP/BCD, BitLocker, NTFS sale, hibernation, firmware) puis moteur de règles commun avec Linux : score, causes, plan d'action. Rapport enregistré sur la clé (`Field-Logs\diag`). Pas de SMART ni de journaux (règle `S010`). |
| 13 Réparation UEFI | `bcdboot <Windows>\Windows /s S: /f UEFI` sur l'ESP choisie (lettre `S:` temporaire, retirée ensuite), avec confirmation. |
| 14 Pilote de stockage | `drvload` d'un `.inf` ou d'un dossier (`Drivers\` de la clé), puis re-scan diskpart : pour les NVMe / Intel VMD-RST invisibles. Session uniquement, rien d'écrit sur le disque. |
| 15 Outils portables | Liste et lance les `.exe` de `Portable\` sur la clé. |
| 16 Shell BusyBox | `ls`, `grep`, `awk`, `vi`, `tar`, `dd`, `hexdump`… |

Provenance de BusyBox : busybox-w32 (Ron Yorston) build FRP-6075 `w64u`,
téléchargé depuis frippery.org, **SHA-256 épinglé** dans le script (un fichier
différent est refusé) et signature GPG vérifiée à la mise en place.
`-IncludeToolbox:$false` pour une image sans BusyBox.

## Pourquoi cette distinction (construire pour vous ≠ redistribuer)

SONAR-SE **n'embarque et ne télécharge jamais** de WinPE pré-construit
dans son propre manifeste (`--fetch`) — le script ci-dessus construit
l'image **sur votre machine, à partir de vos propres téléchargements
Microsoft**, sous votre responsabilité, exactement comme si vous
suiviez la procédure manuelle plus bas. Ce n'est pas une case à cocher
qu'on aurait pu remplir plus tôt : les licences du Windows ADK
n'autorisent pas SONAR-SE à redistribuer une image WinPE déjà
construite à d'autres utilisateurs — seul l'opérateur qui la construit
lui-même, avec ses propres téléchargements ADK, est dans les clous.
**SONAR-SE ne vérifie ni le SHA-256 ni la provenance de l'ISO produite
via un manifeste scellé** (contrairement aux outils de `--fetch`) : le
script vous donne son empreinte SHA-256 à la fin, pour votre propre
traçabilité, pas pour une vérification automatisée par SONAR-SE.

C'est aussi pour ça qu'empaqueter Hiren's BootCD PE ou MediCat USB (qui,
eux, redistribuent des composants tiers sans garantir leur licence —
voir plus bas) reste explicitement écarté : ce serait retomber dans le
flou que cette distinction évite.

## Ce qui en dépend

Le profil `boot-repair` (`--profile boot-repair`) couvre par défaut la
réparation **côté Linux** (SystemRescue : GParted, TestDisk, ddrescue,
shell) — beaucoup de cas de boot cassé se réparent déjà comme ça (table
de partitions, bootloader GRUB, disque copié secteur par secteur). La
réparation **côté Windows** proprement dite exige un WinPE : avec
`tools/Build-SonarSE-WinPE.ps1`, ce n'est plus qu'une commande à lancer
avant le `--disk`, plus une limite à contourner.

## Construction manuelle (référence — ce que le script automatise)

1. Installez le [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install)
   puis l'**add-on WinPE** (téléchargement séparé, même page — sans lui,
   `copype`/`MakeWinPEMedia` ne trouvent pas leurs fichiers source).
2. Ouvrez *Deployment and Imaging Tools Environment* en administrateur.
3. Créez l'environnement de travail :
   ```
   copype amd64 C:\winpe_amd64
   ```
4. Personnalisez si besoin (montage de l'image, ajout de pilotes/
   paquets via DISM — voir la documentation Microsoft, hors périmètre de
   ce guide).
5. Générez l'ISO :
   ```
   MakeWinPEMedia /iso C:\winpe_amd64 C:\winpe_amd64\winpe_amd64.iso
   ```

Référence complète : [copype command line options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/copype-command-line-options),
[makewinpemedia command line options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/makewinpemedia-command-line-options).

## Alternative : ISO communautaires déjà construites (déconseillé, voir pourquoi)

Deux projets communautaires distribuent un WinPE déjà construit et
chargé d'outils :

- **[Hiren's BootCD PE](https://www.hirensbootcd.org/download/)** — ISO
  unique (~3 Go), maintenu par la communauté, sans logiciel piraté.
- **[MediCat USB](https://medicatusb.com/)** — plus large (WinPE +
  collection d'ISO bootables + utilitaires portables), déjà pensé pour
  Ventoy.

**SONAR-SE ne redistribue ni l'un ni l'autre, et ne les ajoutera jamais
à `--fetch`.** Pas par principe rigide, mais parce que les deux projets
le disent eux-mêmes explicitement dans leurs mentions légales : ils ne
sont « affiliés à, ni endossés par » aucun des éditeurs des outils tiers
qu'ils embarquent, et ne revendiquent aucune licence dessus. C'est un
choix assumé et raisonnable pour un projet communautaire — mais
`--fetch` de SONAR-SE vérifie et documente la provenance (SHA-256,
souvent signature GPG amont) de chaque outil qu'il télécharge ;
automatiser la redistribution d'un bloc dont la licence de chaque
composant est explicitement non-garantie casserait cette garantie pour
tout ce qu'il distribue, pas seulement pour ce bloc-là. Avec le script
de construction ci-dessus disponible, cette alternative a encore moins
de raison d'être utilisée qu'avant.

## L'ajouter à une clé construite par SONAR-SE

Aucune commande SONAR-SE spécifique n'est nécessaire — le mécanisme déjà
en place pour `--fetch` (voir `docs/DEPLOYMENT.md`, Étape 0bis)
s'applique tel quel :

```bash
mkdir -p SONAR_SOURCE/ISO/WinPE
cp /chemin/vers/SONAR-SE-WinPE-amd64.iso SONAR_SOURCE/ISO/WinPE/
./sonar_master.sh --disk /dev/sdX --source ./SONAR_SOURCE ...
```

`copy_payload_final` copie `SOURCE_DIR/ISO` récursivement, et Ventoy
scanne `/ISO` récursivement par défaut (`VTOY_DEFAULT_SEARCH_ROOT`) —
l'ISO apparaît dans le menu de boot sans configuration supplémentaire.

## Alternatives déjà envisagées, et pourquoi elles ne remplacent pas ce guide

- **Utiliser le WinRE déjà présent sur la machine cible** (si elle en a
  encore un fonctionnel) : gratuit, aucune construction nécessaire, mais
  suppose que la machine cible dispose encore d'un WinRE intact — souvent
  précisément ce qui manque quand le boot est cassé.
- **Distribuer un WinPE pré-construit dans le dépôt** : rejeté
  délibérément, et toujours d'actualité malgré le script de
  construction ci-dessus — voir "Pourquoi cette distinction". Un WinPE
  embarque des composants Microsoft sous licence propre à chaque poste
  de build ; le redistribuer dans un dépôt public resterait un problème
  de licence, pas seulement technique.
