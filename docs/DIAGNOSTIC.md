# Diagnostic intelligent SONAR-SE

Un technicien qui branche la clé sur une machine en panne n'a pas besoin d'une
liste de 981 outils : il a besoin qu'on lui dise **ce qui est probablement
cassé, dans quel ordre agir, et ce qu'il ne faut surtout pas faire**.
`tools/sonar_diag.sh` fait exactement ça, hors-ligne, en lecture seule.

## Lancer

Sur la machine en panne, clé bootée sur un Linux (SystemRescue, Ubuntu live…) :

```bash
sudo Scripts/sonar_diag.sh                    # pose la question du symptôme
sudo Scripts/sonar_diag.sh --symptom boot     # sans question
```

Ou depuis SONAR Field (`Scripts/sonar_field.sh`) : entrée **d) DIAGNOSTIC
INTELLIGENT**, journalisée dans l'audit de la clé.

Le rapport est enregistré sur la clé (`Field-Logs/diag/DIAG_<date>/` :
`report.txt`, `findings.tsv`, `facts.tsv`). Symptômes : `boot` (ne démarre
plus), `bsod` (écrans bleus/plantages), `slow`, `data` (données inaccessibles),
`password`, `virus`, `other`.

Sans `sudo`, le diagnostic est **partiel** (SMART, montages et journaux noyau
illisibles) et le rapport le dit : il affiche « NON CONCLUANT » plutôt qu'un
« bon état » trompeur.

## Comment ça raisonne (trois étages)

1. **Collecte** — des faits mesurables, jamais d'interprétation : SMART
   (SATA et NVMe), erreurs d'E/S du noyau par disque, cohérence de la table de
   partitions, présence de l'ESP / `bootmgfw.efi` / BCD, détection BitLocker,
   état NTFS (sale, hibernation), espace libre, erreurs machine-check et ECC,
   bridage thermique, températures, usure de la batterie, entrées UEFI. Les
   partitions sont montées en **lecture seule** ; rien n'est écrit sur la
   machine diagnostiquée. La clé SONAR-SE elle-même est exclue de l'analyse.
2. **Moteur de règles déterministe** (`tools/diag_rules.txt`, ~35 règles,
   éditable) — mêmes faits, même rapport, toujours. Chaque constat porte :
   la **gravité**, une **confiance en %**, les **faits qui l'ont déclenché**,
   la cause probable, l'action, le **profil SONAR-SE** à utiliser et une
   mise en garde **« à éviter »**.
3. **IA locale, optionnelle** (`--ai`) — un Ollama tournant sur la machine
   reformule le rapport en langage simple. Consultative : le rapport
   déterministe fait foi, le moteur refuse tout serveur non local, et le
   rapport est présenté au modèle comme une *donnée*, pas comme des
   instructions.

### Ce qui le rend « intelligent »

- **Corrélation** : un disque avec `SMART FAILED` + secteurs en attente +
  erreurs d'E/S noyau n'est pas trois alertes, c'est un constat unique à 99 %
  de confiance ; les indices concordants renforcent la confiance
  (`RENFORTS` dans les règles).
- **Priorité de sécurité des données** : un disque mourant passe avant toute
  réparation de démarrage, et le rapport interdit explicitement `chkdsk /r`,
  `fsck` ou une réinstallation qui achèveraient le disque.
- **Symptôme** : un constat lié au symptôme signalé gagne +10 de confiance et
  est marqué comme tel.
- **Plan d'action ordonné, sans doublon** : une étape par profil SONAR-SE,
  l'action du constat le plus grave en tête.
- **Honnêteté** : le score de santé est `100 − Σ(poids de gravité × confiance)`
  avec les poids affichés ; il ne rassure jamais à tort (blocage grave ou
  diagnostic partiel → libellé dégradé) ; « aucun constat » précise que cela
  prouve l'absence de signes connus, pas l'absence de panne.

## Rejouer sur un autre poste (`--analyze`)

Les faits (`facts.tsv`) sont un simple fichier `clé<TAB>valeur` (ou
`clé=valeur`). On peut donc les rejouer n'importe où, par exemple sur le PC du
technicien où tourne Ollama :

```bash
./sonar_master.sh --diag-analyze facts.tsv --symptom boot --ai
# ou directement :
tools/sonar_diag.sh --analyze facts.tsv --symptom boot --ai
```

## Écrire ou modifier une règle

Une ligne dans `diag_rules.txt`, champs séparés par ` :: ` :

```
ID :: GRAVITE :: SYMPTOMES :: QUAND :: RENFORTS :: BASE :: TITRE :: CAUSE :: ACTION :: PROFIL :: A_EVITER
```

Exemple (règle réelle) :

```
B002 :: HIGH :: boot :: part.*.is_esp == yes && part.*.bootmgfw == no && win.partitions > 0 :: - :: 88 :: La partition EFI {@} ne contient plus bootmgfw.efi :: … :: … :: boot-repair :: -
```

- `QUAND` : conditions reliées par ` && `, opérateurs `== != > >= < <= ~ !~
  exists missing`. Un `*` dans une clé (`part.*.is_esp`) s'évalue **une fois par
  instance** (un constat par partition/disque) ; `{@}` est le nom de
  l'instance dans les textes.
- `RENFORTS` : `condition=>+N` séparés par ` ;; `.
- Après toute modification : `tests/diag/run_tests.sh` (aussi exécuté par
  `sonar_master.sh --self-test`). Ajouter un scénario `tests/diag/*.facts` et
  ses assertions pour chaque nouvelle règle.

## Limites connues (honnêtement)

- **WinPE : collecte « lite »**. Le WinPE n'a ni PowerShell ni WMI
  (`Add-Package` y échoue sur un hôte Windows 10, voir `docs/WINPE.md`) ; le
  diagnostic y tourne donc avec BusyBox for Windows embarqué
  (`tools/winpe/sonar_diag_winpe.sh` + le **même** `diag_engine.awk`, option 12
  du menu). Il lit disques, volumes, ESP/BCD, BitLocker, état NTFS,
  hibernation, firmware/Secure Boot, mais **ni SMART ni journaux** : la règle
  `S010` le signale et le libellé du score ne dit jamais « bon état apparent »
  dans ce mode. Pour SMART/mémoire/journaux, démarrer SystemRescue.
- SMART derrière certains ponts USB ou contrôleurs RAID reste illisible
  (constat `D012` l'indique au lieu de le taire).
- La détection « sale / hibernation » NTFS s'appuie sur `ntfs-3g.probe`
  (présent dans SystemRescue) ; sans lui, l'état n'est pas déterminé.
- Les règles sont des heuristiques de terrain, pas une garantie : un rapport
  « sain » n'exclut pas une panne intermittente.
- Les seuils (60 °C disque, 90 °C CPU, 60 % batterie…) sont des valeurs
  usuelles, à ajuster dans `diag_rules.txt` selon l'expérience.
