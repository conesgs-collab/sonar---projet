# WinPE — ce que SONAR fournit, et ce qu'il ne fournit pas

**SONAR ne construit pas de WinPE et n'en fournit aucun par défaut.**
Ce n'est pas un oubli ni une fonctionnalité repoussée à plus tard : c'est
une limite technique structurelle, documentée ici explicitement plutôt
que laissée dans le flou (voir `ROADMAP.md`, étape 4).

## Pourquoi c'est impossible à automatiser depuis ce script

Construire un WinPE demande le **Windows ADK** (Assessment and
Deployment Kit) et son add-on WinPE — un outillage qui n'existe que pour
Windows (`copype.cmd`, `MakeWinPEMedia.cmd`, DISM). `sonar_master.sh`,
lui, exige de tourner **en root sous Linux** (`preflight_final` refuse
net sinon) — c'est la condition de tout le reste du pipeline (montage de
partitions, `mkfs.ext4`, écriture bloc sur le disque). Il n'existe pas
de chemin où ce même script piloterait un outillage Windows-only : ce
n'est pas une question d'effort d'implémentation, les deux mondes ne se
recoupent pas.

C'est précisément la pièce qui différencie des projets comme
MediCat/Hiren's BootCD/Strelec — et c'est pour ça qu'elle est nommée
explicitement ici plutôt que silencieusement absente.

## Ce qui en dépend

Le profil `boot-repair` (`--profile boot-repair`) ne couvre aujourd'hui
que la réparation **côté Linux** (SystemRescue : GParted, TestDisk,
ddrescue, shell). La réparation **côté Windows** proprement dite —
`bootrec /rebuildbcd`, `bcdedit`, `sfc /scannow`, `DISM
/Image:... /Cleanup-Image` — a besoin d'un environnement Windows PE
pour s'exécuter hors du système cible endommagé. Sans WinPE fourni par
l'opérateur, `boot-repair` reste utile (beaucoup de cas de boot cassé se
réparent depuis Linux : table de partitions, bootloader GRUB, disque
copié secteur par secteur) mais ne couvre pas la famille de pannes qui
exige spécifiquement les outils Windows.

## Construire votre propre WinPE (sur une machine Windows)

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

## Alternative plus rapide : ISO communautaires déjà construites

Construire son propre WinPE prend du temps. Deux projets communautaires
distribuent déjà un environnement WinPE prêt à l'emploi, chargé d'outils
de dépannage :

- **[Hiren's BootCD PE](https://www.hirensbootcd.org/download/)** — ISO
  unique (~3 Go), maintenu par la communauté, sans logiciel piraté.
- **[MediCat USB](https://medicatusb.com/)** — plus large (WinPE +
  collection d'ISO bootables + utilitaires portables), déjà pensé pour
  Ventoy.

**SONAR ne redistribue ni l'un ni l'autre, et ne les ajoutera jamais à
`--fetch`.** Pas par principe rigide, mais parce que les deux projets le
disent eux-mêmes explicitement dans leurs mentions légales : ils ne sont
« affiliés à, ni endossés par » aucun des éditeurs des outils tiers
qu'ils embarquent, et ne revendiquent aucune licence dessus. C'est un
choix assumé et raisonnable pour un projet communautaire — mais
`--fetch` de SONAR vérifie et documente la provenance (SHA-256, souvent
signature GPG amont) de chaque outil qu'il télécharge ; automatiser la
redistribution d'un bloc dont la licence de chaque composant est
explicitement non-garantie casserait cette garantie pour tout ce qu'il
distribue, pas seulement pour ce bloc-là.

**Ce que vous pouvez faire à la place** : télécharger l'un ou l'autre
vous-même, sous votre propre responsabilité (comme pour un WinPE
construit à la main), puis l'ajouter à votre clé avec le même mécanisme
que ci-dessous.

## L'ajouter à une clé construite par SONAR

Aucune commande SONAR spécifique n'est nécessaire — le mécanisme déjà en
place pour `--fetch` (voir `docs/DEPLOYMENT.md`, Étape 0bis) s'applique
tel quel :

```bash
mkdir -p SONAR_SOURCE/ISO/WinPE
cp /chemin/vers/winpe_amd64.iso SONAR_SOURCE/ISO/WinPE/
./sonar_master.sh --disk /dev/sdX --source ./SONAR_SOURCE ...
```

`copy_payload_final` copie `SOURCE_DIR/ISO` récursivement, et Ventoy
scanne `/ISO` récursivement par défaut (`VTOY_DEFAULT_SEARCH_ROOT`) —
l'ISO apparaît dans le menu de boot sans configuration supplémentaire.
**SONAR ne vérifie ni le SHA-256 ni la provenance d'un WinPE que vous
fournissez vous-même** (contrairement aux outils de `--fetch`, qui sont
tous vérifiés contre un manifeste scellé) : c'est un fichier que vous
avez construit vous-même, sur votre propre machine, sous votre propre
responsabilité.

## Alternatives déjà envisagées, et pourquoi elles ne remplacent pas ce guide

- **Utiliser le WinRE déjà présent sur la machine cible** (si elle en a
  encore un fonctionnel) : gratuit, aucune construction nécessaire, mais
  suppose que la machine cible dispose encore d'un WinRE intact — souvent
  précisément ce qui manque quand le boot est cassé.
- **Distribuer un WinPE pré-construit dans le dépôt** : rejeté
  délibérément. Un WinPE embarque des composants Microsoft sous licence
  propre à chaque poste de build — le redistribuer dans un dépôt public
  serait un problème de licence, pas seulement technique.
