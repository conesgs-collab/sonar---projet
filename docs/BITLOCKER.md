# Ouvrir un disque BitLocker (lecture seule)

Un disque chiffré par BitLocker est illisible pour tous les outils de réparation tant qu'il est
verrouillé (le diagnostic le signale : règle `F003`). SONAR-SE sait l'ouvrir **avec la clé de
récupération du propriétaire** — jamais sans.

## Depuis SystemRescue / Linux : `tools/sonar_bitlocker.sh`

```bash
sudo ./sonar_bitlocker.sh --list                 # volumes BitLocker détectés (signature -FVE-FS-)
sudo ./sonar_bitlocker.sh --unlock /dev/sdb3     # demande la clé (saisie invisible), monte en lecture seule
ls /mnt/sonar-bl/sdb3                            # les fichiers du client : sauvegarde possible
sudo ./sonar_bitlocker.sh --lock /dev/sdb3       # démonte et referme (ou --lock-all)
```

Aussi dans SONAR Field : option **b**.

- **Clé attendue** : 48 chiffres (8 groupes de 6, avec ou sans tirets) ou le mot de passe BitLocker.
  Un format de clé invalide est refusé avant toute tentative.
- **Lecture seule imposée** : `cryptsetup bitlkOpen --readonly` puis `mount -o ro` ; il n'existe aucune
  option d'écriture. On sauvegarde, on ne modifie pas.
- **La clé n'apparaît nulle part** : ni dans une ligne de commande (visible par `ps`), ni dans un
  journal, ni sur disque. `SONAR_AUDIT_FILE` reçoit l'événement (périphérique, méthode), pas la clé ;
  SONAR Field écrit en plus dans sa chaîne d'audit.
- **Moteur** : `cryptsetup` ≥ 2.3 (présent dans SystemRescue 13.02 de la clé, avec `dislocker`) ; repli sur `dislocker` s'il est installé.
- **Accord du propriétaire** demandé en interactif avant d'ouvrir.

Vérifié le 2026-09-21 sur un vrai volume BitLocker (XTS-AES 128, protecteur « mot de passe numérique »)
créé sous Windows 10 : bonne clé → ouvert, fichier lu ; mauvaise clé → refusé ; écriture → « système de
fichiers en lecture seule » ; journal sans la clé. Les tests de garde-fous tournent partout ; le test
sur volume réel s'active avec `SONAR_BL_TEST_IMAGE=... SONAR_BL_TEST_OFFSET=... SONAR_BL_TEST_KEY=...`
(le volume n'est pas commité : BitLocker ne se crée que sous Windows).

### Ce qui ne marche pas
- Protecteur **TPM seul** sans clé de récupération : la clé est liée au matériel, on ne peut pas l'ouvrir
  hors de la machine d'origine. Il faut la clé de récupération (compte Microsoft, compte professionnel,
  impression, clé USB).
- **BitLocker To Go** (clés USB) : détection par signature non garantie ; utiliser `--unlock` directement.
- Volume déchiffré mais NTFS « sale » ou en hibernation : le montage en lecture seule peut refuser ;
  l'outil le dit sans rien modifier.

## Depuis le WinPE SONAR-SE : non
`manage-bde` demande WMI, absent du WinPE de base ; l'ajouter passe par `Dism /Add-Package`, impossible
sur un hôte Windows 10 (voir `docs/WINPE.md`). Testé le 2026-09-21 : copier `manage-bde.exe` et ses DLL
tirées de `WinPE-SecureStartup.cab` dans un WinPE en marche donne `0x80040154 Class not registered`
(le fournisseur WMI BitLocker vit dans `WinPE-WMI.cab`). Le déverrouillage passe donc par Linux.
