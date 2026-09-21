#!/bin/bash
# Tests de tools/sonar_recover.sh.
# Sortie : PASS/FAIL/WARN par verification ; code retour = nombre d'echecs.
#
# Toujours : options, plan (texte deterministe), garde-fous purement logiques.
# Si root + losetup + mkfs.ntfs + ntfs-3g (+ ddrescue pour l'imagerie) : le disque de test est CONSTRUIT ici
# (image de 80 Mo, table de partitions, NTFS, vrais fichiers) — aucun disque reel n'est touche. Sinon : WARN,
# jamais un faux PASS.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC="${DIR}/../../tools/sonar_recover.sh"
fails=0
ok()   { printf 'PASS\t%s\n' "$1"; }
ko()   { printf 'FAIL\t%s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }
[[ -f "$RC" ]] || { ko "Recover : sonar_recover.sh present"; exit "$fails"; }

T="$(mktemp -d)"; export SONAR_RECOVER_MOUNT_ROOT="${T}/mnt"
trap 'losetup -D >/dev/null 2>&1; umount "${T}/rw" 2>/dev/null; rm -rf "$T"' EXIT

check "Recover : syntaxe bash valide"                                  'bash -n "$RC"'
check "Recover : --help annonce la lecture seule"                       'bash "$RC" --help | grep -q "jamais écrite"'
check "Recover : sans commande -> usage, code 2"                        'bash "$RC" >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "Recover : option inconnue -> code 2"                             'bash "$RC" copy --nimporte-quoi >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "Recover : une option sans valeur ne boucle pas (regression shift 2)" 'timeout 10 bash "$RC" copy --source >/dev/null 2>&1; [[ $? -ne 124 ]]'
check "Recover : copy sans --source -> code 2"                          'bash "$RC" copy --dest "$T/d" >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "Recover : copy sans --dest -> code 2"                            'bash "$RC" copy --source /tmp >/dev/null 2>&1; [[ $? -eq 2 ]]'

# --- plan : la methode depend du diagnostic
mkdir -p "$T/diag_fragile" "$T/diag_bl" "$T/diag_ok"
printf '1\tCRITICAL\t99\tD001\tsda\t0\tx\te\tc\ta\tdata-recovery\t-\n#SCORE\t20\n' > "$T/diag_fragile/findings.tsv"
printf '1\tHIGH\t90\tF003\tsda2\t0\tx\te\tc\ta\t-\t-\n#SCORE\t70\n' > "$T/diag_bl/findings.tsv"
printf '1\tHIGH\t80\tB001\t\t1\tx\te\tc\ta\tboot-repair\t-\n#SCORE\t80\n' > "$T/diag_ok/findings.tsv"
P="$(bash "$RC" plan --diag "$T/diag_fragile")"
check "Recover plan : disque mourant -> IMAGE d'abord (ddrescue), pas de chkdsk"  'grep -q "DISQUE FRAGILE" <<<"$P" && grep -q "sonar_recover.sh image" <<<"$P" && grep -q "PAS chkdsk" <<<"$P"'
check "Recover plan : disque mourant -> la copie porte sur l'image, pas le disque" 'grep -q "copy --source disk.img" <<<"$P"'
P="$(bash "$RC" plan --diag "$T/diag_bl")"
check "Recover plan : BitLocker -> ouvrir d'abord avec sonar_bitlocker.sh, cle du proprietaire" 'grep -q "sonar_bitlocker.sh --unlock" <<<"$P" && grep -q "propriétaire" <<<"$P"'
P="$(bash "$RC" plan --diag "$T/diag_ok")"
check "Recover plan : disque sain (demarrage) -> pas d'imagerie inutile"           '! grep -q "DISQUE FRAGILE" <<<"$P" && grep -q "COPIE DES DONNÉES" <<<"$P"'
P="$(bash "$RC" plan)"
check "Recover plan : sans diagnostic -> demande de le lancer, et prudence (image)" 'grep -q "Aucun diagnostic fourni" <<<"$P" && grep -q "DISQUE FRAGILE" <<<"$P"'
check "Recover plan : le plan ne promet rien"                                      'grep -q "ne garantit rien" <<<"$P"'
check "Recover plan : diagnostic introuvable -> code 2"                            'bash "$RC" plan --diag "$T/absent" >/dev/null 2>&1; [[ $? -eq 2 ]]'

# --- vrai disque de test
have=true
for c in losetup mkfs.ntfs ntfs-3g sfdisk; do command -v "$c" >/dev/null 2>&1 || have=false; done
[[ $EUID -eq 0 ]] || have=false
if ! $have; then
    printf 'WARN\tRecover : root/losetup/mkfs.ntfs/ntfs-3g/sfdisk absents : copie, verification et garde-fous sur disque NON testes ici\n'
    exit "$fails"
fi

IMG="$T/disk.img"
truncate -s 80M "$IMG"
printf 'label: dos\nstart=2048, type=7\n' | sfdisk -q "$IMG" >/dev/null 2>&1
L="$(losetup -fP --show "$IMG")"
mkfs.ntfs -F -Q -L TESTDATA "${L}p1" >/dev/null 2>&1
mkdir -p "$T/rw"; ntfs-3g "${L}p1" "$T/rw" 2>/dev/null
mkdir -p "$T/rw/Users/Alice/Documents" "$T/rw/Users/Alice/Pictures" "$T/rw/Users/Alice/Desktop" "$T/rw/Users/Alice/AppData/Local" "$T/rw/Users/Public" "$T/rw/Windows/System32"
printf 'rapport confidentiel\n' > "$T/rw/Users/Alice/Documents/rapport.txt"
printf 'accents\n' > "$T/rw/Users/Alice/Documents/comptes é ü.txt"
head -c 1000000 /dev/urandom > "$T/rw/Users/Alice/Pictures/photo.bin"
printf 'note\n' > "$T/rw/Users/Alice/Desktop/note.txt"
printf 'cache\n' > "$T/rw/Users/Alice/AppData/Local/junk.tmp"
printf 'pub\n' > "$T/rw/Users/Public/pub.txt"
printf 'sys\n' > "$T/rw/Windows/System32/dummy.dll"
sync; umount "$T/rw"; losetup -d "$L"
if [[ ! -s "$IMG" ]] || ! sfdisk -l "$IMG" >/dev/null 2>&1; then printf 'WARN\tRecover : construction du disque de test impossible ici\n'; exit "$fails"; fi
H0="$(sha256sum "$IMG" | awk '{print $1}')"

DEST="$T/out1"
bash "$RC" copy --source "$IMG" --dest "$DEST" >"$T/copy1.log" 2>&1; rc1=$?
check "Recover copy : code 0 sur un disque sans erreur"                          '[[ $rc1 -eq 0 ]]'
check "Recover copy : le dossier utilisateur est copie (Documents, Images, Bureau)" '[[ -s "$DEST/files/Users/Alice/Documents/rapport.txt" && -s "$DEST/files/Users/Alice/Pictures/photo.bin" && -s "$DEST/files/Users/Alice/Desktop/note.txt" ]]'
check "Recover copy : les noms accentues survivent"                              '[[ -s "$DEST/files/Users/Alice/Documents/comptes é ü.txt" ]]'
check "Recover copy : --what user ne copie ni AppData, ni Windows, ni Public"    '[[ ! -e "$DEST/files/Users/Alice/AppData" && ! -e "$DEST/files/Windows" && ! -e "$DEST/files/Users/Public" ]]'
LCK="$(losetup -rf --show -o $((2048*512)) "$IMG")"; mkdir -p "$T/chk"; mount -o ro "$LCK" "$T/chk" 2>/dev/null
check "Recover copy : contenu identique a la source (photo)"                     'cmp -s "$DEST/files/Users/Alice/Pictures/photo.bin" "$T/chk/Users/Alice/Pictures/photo.bin"'
umount "$T/chk" 2>/dev/null; losetup -d "$LCK" 2>/dev/null
check "Recover copy : le manifeste liste chaque fichier avec son SHA-256 et OK"  '[[ "$(grep -c "	OK$" "$DEST/RECOVERY_MANIFEST.tsv")" -eq 4 && "$(awk -F"\t" "\$4==\"Users/Alice/Documents/rapport.txt\" {print \$1}" "$DEST/RECOVERY_MANIFEST.tsv")" == "$(sha256sum "$DEST/files/Users/Alice/Documents/rapport.txt" | awk "{print \$1}")" ]]'
check "Recover copy : le resume dit ce qui n'est PAS tente"                       'grep -q "Non tenté" "$DEST/RECOVERY_SUMMARY.txt" && grep -q "ne garantit pas" "$DEST/RECOVERY_SUMMARY.txt"'
H1="$(sha256sum "$IMG" | awk '{print $1}')"
check "Recover copy : la SOURCE est intacte (hash de l'image identique avant/apres)" '[[ "$H0" == "$H1" ]]'
check "Recover copy : rien n'est reste monte ni attache"                          '! findmnt -rn | grep -q "$T/mnt" && [[ -z "$(losetup -a | grep "$IMG")" ]]'

DEST2="$T/out_all"
bash "$RC" copy --source "$IMG" --dest "$DEST2" --what all >/dev/null 2>&1
check "Recover copy --what all : copie aussi Windows et AppData"                  '[[ -s "$DEST2/files/Windows/System32/dummy.dll" && -s "$DEST2/files/Users/Alice/AppData/Local/junk.tmp" ]]'
DEST3="$T/out_path"
bash "$RC" copy --source "$IMG" --dest "$DEST3" --what Users/Public >/dev/null 2>&1
check "Recover copy --what CHEMIN : ne copie que ce chemin"                        '[[ -s "$DEST3/files/Users/Public/pub.txt" && ! -e "$DEST3/files/Users/Alice" ]]'
check "Recover copy --what CHEMIN inexistant -> refus (code 2)"                    'bash "$RC" copy --source "$IMG" --dest "$T/o4" --what Nope >/dev/null 2>&1; [[ $? -eq 2 ]]'

# --- garde-fous
check "Recover : place insuffisante -> refus AVANT de copier (code 2)"            'SONAR_RECOVER_DEST_FREE_BYTES=1000 bash "$RC" copy --source "$IMG" --dest "$T/o5" >/dev/null 2>&1; [[ $? -eq 2 && ! -d "$T/o5/files" ]]'
mkdir -p "$T/mnt_src"
LCTL="$(losetup -rf --show -o $((2048*512)) "$IMG")"; mount -o ro "$LCTL" "$T/mnt_src" 2>/dev/null
if mountpoint -q "$T/mnt_src"; then
    check "Recover : destination DANS la source -> refus"                          'bash "$RC" copy --source "$T/mnt_src" --dest "$T/mnt_src/x" >/dev/null 2>&1; [[ $? -ne 0 ]]'
    check "Recover : un dossier source deja monte en LECTURE SEULE est accepte"    'bash "$RC" copy --source "$T/mnt_src" --dest "$T/o6" >/dev/null 2>&1; [[ -s "$T/o6/files/Users/Alice/Documents/rapport.txt" ]]'
    umount "$T/mnt_src"; losetup -d "$LCTL"
    # l'outil n'a rien ecrit : verifie AVANT le montage lecture-ecriture de controle (qui, lui, touche l'image)
    H2="$(sha256sum "$IMG" | awk '{print $1}')"
    check "Recover : apres tous les essais de l'outil, l'image source est toujours intacte" '[[ "$H0" == "$H2" ]]'
    LRW="$(losetup -f --show -o $((2048*512)) "$IMG")"; ntfs-3g "$LRW" "$T/mnt_src" 2>/dev/null
    check "Recover : un dossier source monte en LECTURE-ECRITURE -> refus"         'mountpoint -q "$T/mnt_src" && bash "$RC" copy --source "$T/mnt_src" --dest "$T/o7" >/dev/null 2>&1; [[ $? -eq 2 ]]'
    umount "$T/mnt_src" 2>/dev/null; losetup -d "$LRW" 2>/dev/null
else
    losetup -d "$LCTL" 2>/dev/null
    printf 'WARN\tRecover : montage de controle impossible ici, garde-fous source/destination non testes\n'
    H2="$(sha256sum "$IMG" | awk '{print $1}')"
    check "Recover : apres tous les essais de l'outil, l'image source est toujours intacte" '[[ "$H0" == "$H2" ]]'
fi
H0="$(sha256sum "$IMG" | awk '{print $1}')"   # l'image de reference suivante inclut d'eventuels marqueurs du montage rw de controle

# --- verify : detecte l'alteration et l'absence
check "Recover verify : copie saine -> code 0"                                    'bash "$RC" verify --dest "$DEST" >/dev/null 2>&1'
printf 'X' >> "$DEST/files/Users/Alice/Desktop/note.txt"
V="$(bash "$RC" verify --dest "$DEST" 2>&1)"; rcv=$?
check "Recover verify : fichier altere apres coup -> detecte (code 1)"            '[[ $rcv -eq 1 ]] && grep -q "ALTÉRÉ.*note.txt" <<<"$V"'
rm -f "$DEST/files/Users/Alice/Documents/rapport.txt"
V="$(bash "$RC" verify --dest "$DEST" 2>&1)"
check "Recover verify : fichier supprime apres coup -> signale MANQUANT"          'grep -q "MANQUANT.*rapport.txt" <<<"$V"'

# --- imagerie
if command -v ddrescue >/dev/null 2>&1; then
    DI="$T/out_img"
    bash "$RC" image --source "$IMG" --dest "$DI" >/dev/null 2>&1; rci=$?
    check "Recover image : ddrescue produit une image identique a la source (code 0)" '[[ $rci -eq 0 && "$(sha256sum "$DI/disk.img" | awk "{print \$1}")" == "$H0" ]]'
    check "Recover image : la carte de progression et le resume sont ecrits"      '[[ -s "$DI/disk.map" ]] && grep -q "non récupérés" "$DI/IMAGE_SUMMARY.txt"'
    check "Recover image : source = image de destination -> refus"                'bash "$RC" image --source "$DI/disk.img" --dest "$DI" >/dev/null 2>&1; [[ $? -ne 0 ]]'
    bash "$RC" copy --source "$DI/disk.img" --dest "$T/out_from_img" >/dev/null 2>&1
    check "Recover : on peut copier depuis l'image obtenue (chaine image -> copie)" '[[ -s "$T/out_from_img/files/Users/Alice/Documents/comptes é ü.txt" ]]'
else
    printf 'WARN\tRecover : ddrescue absent, imagerie NON testee ici\n'
fi

# --- disque DEFAILLANT simule (device-mapper : un cluster de la photo renvoie des erreurs d'E/S)
if command -v dmsetup >/dev/null 2>&1 && command -v ntfscluster >/dev/null 2>&1; then
    LB="$(losetup -fP --show "$IMG")"
    run="$(ntfscluster -f -F Users/Alice/Pictures/photo.bin "${LB}p1" 2>/dev/null | awk '/VCN +LCN +Length/ {getline; print $2, $3; exit}')"
    lcn="${run% *}"; len="${run#* }"
    if [[ -n "$lcn" && "${len:-0}" -ge 40 ]]; then
        sec_total="$(blockdev --getsz "${LB}p1")"; bad_start=$(( lcn * 8 + 8 * 20 )); bad_len=8
        printf '0 %d linear %s 0\n%d %d error\n%d %d linear %s %d\n' "$bad_start" "${LB}p1" "$bad_start" "$bad_len" \
            "$((bad_start + bad_len))" "$((sec_total - bad_start - bad_len))" "${LB}p1" "$((bad_start + bad_len))" | dmsetup create sonar_bad_test 2>/dev/null
        if [[ -b /dev/mapper/sonar_bad_test ]]; then
            DB="$T/out_bad"
            bash "$RC" copy --source /dev/mapper/sonar_bad_test --dest "$DB" >"$T/bad.log" 2>&1; rcb=$?
            check "Recover disque defaillant : la copie continue, code 1 (erreurs), sans s'arreter"  '[[ $rcb -eq 1 ]] && [[ -s "$DB/files/Users/Alice/Documents/rapport.txt" ]]'
            check "Recover disque defaillant : le fichier illisible est CONSIGNE dans RECOVERY_ERRORS.tsv" 'grep -q "photo.bin" "$DB/RECOVERY_ERRORS.tsv"'
            check "Recover disque defaillant : un fichier partiel n'est PAS presente comme copie reussie" '[[ ! -e "$DB/files/Users/Alice/Pictures/photo.bin" ]] && ! grep -q "photo.bin.*OK" "$DB/RECOVERY_MANIFEST.tsv"'
            check "Recover disque defaillant : les autres fichiers sont copies et verifies"  '[[ -s "$DB/files/Users/Alice/Desktop/note.txt" && "$(grep -c "	OK$" "$DB/RECOVERY_MANIFEST.tsv")" -ge 3 ]]'
            check "Recover disque defaillant : le resume annonce les echecs de lecture"      'grep -Eq "Échecs lecture: [1-9]" "$DB/RECOVERY_SUMMARY.txt"'
            if command -v ddrescue >/dev/null 2>&1; then
                DBI="$T/out_bad_img"
                bash "$RC" image --source /dev/mapper/sonar_bad_test --dest "$DBI" >/dev/null 2>&1; rcbi=$?
                check "Recover disque defaillant : l'imagerie signale des octets NON recuperes (code 1)" '[[ $rcbi -eq 1 ]] && grep -Eq "non récupérés.*: [1-9]" "$DBI/IMAGE_SUMMARY.txt"'
            fi
            dmsetup remove sonar_bad_test 2>/dev/null
        else
            printf 'WARN\tRecover : device-mapper indisponible, disque defaillant NON simule ici\n'
        fi
    else
        printf 'WARN\tRecover : fichier de test trop court pour simuler un secteur defectueux\n'
    fi
    losetup -d "$LB" 2>/dev/null
else
    printf 'WARN\tRecover : dmsetup/ntfscluster absents, disque defaillant NON simule ici\n'
fi
exit "$fails"
