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
