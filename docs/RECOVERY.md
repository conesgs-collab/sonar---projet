# Récupération de données (`tools/sonar_recover.sh`)

SONAR-SE ne réécrit pas de moteur de récupération : `ddrescue`, `ntfs-3g`, TestDisk/PhotoRec sont
éprouvés depuis vingt ans, et une erreur de notre part sur un disque en fin de vie est irréversible.
`sonar_recover.sh` impose **la bonne méthode** à chaque fois et laisse **une preuve** de ce qui a été fait.
Aussi dans SONAR Field : option **r**.

```bash
sonar_recover.sh plan  --diag /chemin/DIAG_2026...          # quelle méthode, dans quel ordre
sonar_recover.sh image --source /dev/sdb --dest /mnt/AUTRE_DISQUE/client1     # ddrescue, 2 passes
sonar_recover.sh copy  --source /mnt/AUTRE_DISQUE/client1/disk.img --dest /mnt/AUTRE_DISQUE/client1
sonar_recover.sh verify --dest /mnt/AUTRE_DISQUE/client1
```

## Règles imposées (et testées)
1. **La source n'est jamais écrite** : montage `ro` (et `noload` pour ext4 : ne pas rejouer le journal),
   image ouverte en lecture seule. Test : le SHA-256 de l'image source est identique avant/après.
2. **Destination hors du disque source et hors de la source** ; un dossier source déjà monté en
   lecture-écriture est refusé.
3. **Place vérifiée avant de copier** (taille + 5 %).
4. **Une seule lecture de la source par fichier** : le SHA-256 est calculé pendant la lecture, la copie est
   relue et comparée (`OK` / `MISMATCH`). Un fichier partiel n'est jamais présenté comme copié.
5. **Une erreur de lecture n'arrête pas tout** : elle va dans `RECOVERY_ERRORS.tsv`, le reste continue.
6. **Le résumé ne promet rien** : il dit ce qui a été copié, ce qui a échoué et ce qui n'a pas été tenté.

## Le plan dépend du diagnostic
| Constat du diagnostic | Ce que le plan impose |
|---|---|
| D001/D002/D003/D005/D006/D008/D009 (disque défaillant) ou pas de diagnostic | **Image d'abord** (`ddrescue`), on travaille sur l'image ; pas de chkdsk/fsck |
| F003 (BitLocker) | ouvrir d'abord avec `sonar_bitlocker.sh` et la clé de récupération du propriétaire |
| F001/F002 (arrêt brutal, hibernation) | montage lecture seule, journal non rejoué : des fichiers récents peuvent manquer |
| Y003/F006/B001 | recherche par signatures (PhotoRec/TestDisk) sur l'image — **pas encore automatisée** |

`--what user` (défaut) copie Bureau, Documents, Images, Vidéos, Musique, Téléchargements, OneDrive de chaque
utilisateur (`Users/*`, `home/*`) ; `--what all` copie tout ; `--what CHEMIN` un sous-chemin.

## Vérifié, et ce qui ne l'est pas
Testé sur un **disque construit** (image de 80 Mo, table de partitions, vrai NTFS, vrais fichiers) : copie,
manifeste, verify (altération et fichier manquant détectés), garde-fous, `ddrescue`, chaîne image → copie,
et un **disque défaillant simulé** (device-mapper : un cluster de la photo renvoie des erreurs d'E/S) — la
copie continue, consigne le fichier illisible, ne le présente pas comme réussi ; l'imagerie annonce les octets
non récupérés. 44 vérifications, stables sur 3 exécutions.

**Non vérifié** : un vrai disque physique en fin de vie (le comportement réel d'un disque mourant est plus
capricieux qu'un secteur simulé) ; ext4/exFAT/APFS (seul NTFS est testé) ; la recherche de fichiers supprimés ;
le chapitre « récupération » du rapport client. Une image `ddrescue` avec des trous copie les trous en zéros :
lisez `IMAGE_SUMMARY.txt` avant de conclure.
