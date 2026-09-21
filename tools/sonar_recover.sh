#!/bin/bash
# sonar_recover.sh — SONAR-SE : récupération de données, méthode imposée et prouvée.
#
# Ce n'est PAS un moteur de récupération : les moteurs (ddrescue, ntfs-3g, TestDisk/PhotoRec) sont éprouvés
# depuis vingt ans, une erreur de notre part sur un disque en fin de vie serait irréversible. Cet outil
# impose la BONNE MÉTHODE à chaque fois et laisse une PREUVE de ce qui a été fait.
#
# Règles non négociables (testées) :
#   1. la source n'est jamais écrite : montage en lecture seule uniquement, image ouverte en lecture seule ;
#   2. la destination ne peut pas être sur le disque source ni dans la source ;
#   3. on vérifie la place disponible AVANT de copier ;
#   4. la source n'est lue qu'UNE fois par fichier (le SHA-256 est calculé pendant la lecture), la copie est
#      ensuite relue et comparée : « le fichier stocké = ce qui a été lu » est prouvé, pas supposé ;
#   5. une erreur de lecture n'arrête pas tout : elle est consignée, le reste continue ;
#   6. rien n'est promis : le résumé dit ce qui a été copié, ce qui a échoué, et ce qui n'a pas été tenté.
#
# Usage :
#   sonar_recover.sh plan  [--diag DOSSIER_DIAG|findings.tsv]          quelle méthode, dans quel ordre
#   sonar_recover.sh image --source /dev/sdX --dest DOSSIER            ddrescue en 2 passes vers DOSSIER/disk.img
#   sonar_recover.sh copy  --source SRC --dest DOSSIER [--what user|all|CHEMIN...] [--part N]
#   sonar_recover.sh verify --dest DOSSIER                             relit la copie et compare au manifeste
#   sonar_recover.sh carve --source IMG|DEV --dest DOSSIER [--types jpg,pdf,zip]  fichiers SUPPRIMES : recherche par signatures
#                                                                      (PhotoRec, lecture seule) ; classe CONNU / NOUVEAU
#   SRC = image (.img/.raw), périphérique (/dev/sdb3, /dev/loop0...) ou dossier déjà monté EN LECTURE SEULE.
#   --what user (défaut) : Bureau, Documents, Images, Vidéos, Musique, Téléchargements de chaque utilisateur
#                          Windows (Users/*), sinon /home ; --what all : tout ; --what CHEMIN : ce sous-chemin.
# Sorties dans DEST : RECOVERY_MANIFEST.tsv (sha256, taille, date, chemin, statut), RECOVERY_ERRORS.tsv,
# RECOVERY_SUMMARY.txt. Root requis pour monter. Codes retour : 0 ok | 1 copie avec erreurs | 2 usage/prérequis
set -uo pipefail

SONAR_RECOVER_VERSION="1.0.0"
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
CMD=""; SRC=""; DEST=""; DIAG=""; TYPES=""; WHAT="user"; WHAT_PATHS=(); PART=""; ASSUME_YES=false
MNT_ROOT="${SONAR_RECOVER_MOUNT_ROOT:-/mnt/sonar-recover}"

usage() { sed -n '2,/^set -uo pipefail/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; }
say() { echo "[SONAR-RECOVER] $*" >&2; }
die() { say "ERREUR : $*"; exit "${2:-2}"; }
audit() { [[ -n "${SONAR_AUDIT_FILE:-}" ]] && printf '%s\tRECOVER_%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$SONAR_AUDIT_FILE" 2>/dev/null || true; }

[[ $# -gt 0 ]] || { usage; exit 2; }
CMD="$1"; shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SRC="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --dest)   DEST="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --diag)   DIAG="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --types)  TYPES="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --part)   PART="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --what)   WHAT="${2:-user}"; shift $(( $# > 1 ? 2 : 1 ))
                  while [[ $# -gt 0 && "${1:0:2}" != "--" ]]; do WHAT_PATHS+=("$1"); shift; done ;;
        --yes)    ASSUME_YES=true; shift ;;
        --version) echo "sonar_recover ${SONAR_RECOVER_VERSION}"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Option inconnue : $1 (voir --help)" >&2; exit 2 ;;
    esac
done

# ------------------------------------------------------------------------------------------------ plan
cmd_plan() {
    local f="" ids="" step=1
    if [[ -n "$DIAG" ]]; then
        if [[ -d "$DIAG" ]]; then f="$DIAG/findings.tsv"; else f="$DIAG"; fi
        [[ -s "$f" ]] || die "diagnostic introuvable : $f (lancez d'abord sonar_diag.sh)"
        ids="$(awk -F'\t' '!/^#/ {print $4}' "$f" | sort -u | tr '\n' ' ')"
    fi
    echo "PLAN DE RECUPERATION (indicatif : le technicien décide)"
    echo "--------------------------------------------------------------"
    if [[ -z "$ids" && -z "$DIAG" ]]; then
        echo "Aucun diagnostic fourni : lancez  sonar_diag.sh --symptom data  puis  plan --diag <dossier>."
        echo "Sans diagnostic, par prudence : considérez le disque comme fragile (image d'abord)."
        echo
    fi
    has() { [[ " $ids " == *" $1 "* ]]; }
    local fragile=false
    for i in D001 D002 D003 D005 D006 D008 D009; do has "$i" && fragile=true; done
    [[ -z "$DIAG" ]] && fragile=true
    if has F003; then
        echo "$step. VOLUME CHIFFRÉ (BitLocker) : ouvrez-le d'abord, en lecture seule, avec la clé de récupération"
        echo "   du propriétaire :  sonar_bitlocker.sh --unlock /dev/sdXN   — sans clé, rien n'est récupérable."
        step=$((step + 1))
    fi
    if $fragile; then
        echo "$step. DISQUE FRAGILE : copiez le disque AVANT tout le reste (chaque lecture l'use) :"
        echo "     sonar_recover.sh image --source /dev/sdX --dest /chemin/DESTINATION_SUR_UN_AUTRE_DISQUE"
        echo "   puis travaillez sur l'image (disk.img), jamais sur le disque d'origine."
        echo "   Ne lancez PAS chkdsk / fsck / réparation sur ce disque."
        step=$((step + 1))
    fi
    if has F001 || has F002; then
        echo "$step. Windows arrêté brutalement ou en hibernation : le montage se fait en lecture seule ; le journal n'est"
        echo "   PAS rejoué (rien n'est écrit). Des fichiers récents peuvent manquer ou être incomplets."
        step=$((step + 1))
    fi
    echo "$step. COPIE DES DONNÉES (lecture seule, SHA-256, erreurs consignées) :"
    echo "     sonar_recover.sh copy --source $($fragile && echo disk.img || echo /dev/sdXN) --dest /chemin/DESTINATION"
    step=$((step + 1))
    if has Y003 || has F006 || has B001; then
        echo "$step. Si des fichiers SUPPRIMÉS ou une partition disparue sont en cause : après la copie, passez à la"
        echo "   recherche par signatures sur l'IMAGE :  sonar_recover.sh carve --source disk.img --dest /chemin/DESTINATION"
        step=$((step + 1))
    fi
    echo "$step. VÉRIFICATION :  sonar_recover.sh verify --dest /chemin/DESTINATION   puis rapport client."
    echo
    echo "Ce plan ne garantit rien : sur un disque défaillant, une partie des données peut être irrécupérable."
}

# ------------------------------------------------------------------------------------------------ garde-fous
disk_of() {   # disque physique parent d'un périphérique ou d'un fichier (pour comparer source et destination)
    local dev="$1" p
    [[ -b "$dev" ]] || { echo ""; return; }
    p="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)"
    [[ -n "$p" ]] && echo "/dev/$p" || echo "$dev"
}
dest_device() {   # périphérique qui porte le dossier destination
    local d="$1" s
    s="$(findmnt -n -o SOURCE --target "$d" 2>/dev/null | head -1)"
    echo "${s%%[*}"
}
free_bytes() { local d="$1"; if [[ -n "${SONAR_RECOVER_DEST_FREE_BYTES:-}" ]]; then echo "$SONAR_RECOVER_DEST_FREE_BYTES"; else df -B1 --output=avail "$d" 2>/dev/null | tail -1 | tr -d ' '; fi; }

check_dest() {
    [[ -n "$DEST" ]] || die "--dest est obligatoire"
    mkdir -p "$DEST" || die "impossible de créer $DEST"
    DEST="$(cd "$DEST" && pwd -P)"
    [[ -w "$DEST" ]] || die "destination non inscriptible : $DEST"
}

# ------------------------------------------------------------------------------------------------ montage en lecture seule
LOOPDEV=""; MOUNTED=""; CLEANUP_MOUNTS=()
cleanup() {
    local m
    for m in "${CLEANUP_MOUNTS[@]:-}"; do [[ -n "$m" ]] && { umount "$m" 2>/dev/null; rmdir "$m" 2>/dev/null; }; done
    [[ -n "$LOOPDEV" ]] && losetup -d "$LOOPDEV" 2>/dev/null
}
trap cleanup EXIT

is_bitlocker() { [[ "$(head -c 11 "$1" 2>/dev/null | tail -c 8 | tr -d '\000')" == "-FVE-FS-" ]]; }

# rend le point de montage lecture seule de la source ; le renseigne dans SRC_ROOT
open_source() {
    local s="$1" dev part cand n=0 mp
    SRC_ROOT=""
    if [[ -d "$s" ]]; then
        if mountpoint -q "$s" 2>/dev/null; then
            findmnt -n -o OPTIONS --target "$s" | tr ',' '\n' | grep -qx ro || die "$s est monté en LECTURE-ÉCRITURE : refus (démontez-le ou laissez SONAR le monter en lecture seule)"
        fi
        SRC_ROOT="$s"; return 0
    fi
    [[ $EUID -eq 0 ]] || die "root requis pour monter la source"
    if [[ -b "$s" ]]; then dev="$s"
    elif [[ -f "$s" ]]; then dev="$(losetup -rfP --show "$s" 2>/dev/null)" || die "losetup a échoué sur $s"; LOOPDEV="$dev"
    else die "source introuvable : $s"; fi
    # losetup -P crée les nœuds de partitions de façon asynchrone : sans attente, une image partitionnée
    # apparaissait parfois comme « sans partition » (constaté : échec intermittent). On attend les nœuds
    # annoncés par la table de partitions (5 s au plus).
    if command -v sfdisk >/dev/null 2>&1; then
        local want got i
        want="$(sfdisk -d "$dev" 2>/dev/null | grep -c 'start=')"
        for ((i = 0; i < 50 && want > 0; i++)); do
            got="$(lsblk -lnpo TYPE "$dev" 2>/dev/null | grep -c '^part$')"
            [[ "$got" -ge "$want" ]] && break
            sleep 0.1
        done
    fi
    # candidats : la partition demandée, sinon les partitions, sinon le périphérique entier
    local -a cands=()
    if [[ -n "$PART" ]]; then
        for cand in "${dev}p${PART}" "${dev}${PART}"; do [[ -b "$cand" ]] && { cands=("$cand"); break; }; done
        [[ ${#cands[@]} -gt 0 ]] || die "partition $PART introuvable sur $dev"
    else
        while IFS= read -r cand; do [[ -b "$cand" ]] && cands+=("$cand"); done < <(lsblk -lnpo NAME,TYPE "$dev" 2>/dev/null | awk '$2=="part" {print $1}')
        [[ ${#cands[@]} -gt 0 ]] || cands=("$dev")
    fi
    mkdir -p "$MNT_ROOT"
    for cand in "${cands[@]}"; do
        if is_bitlocker "$cand"; then say "$cand : volume BitLocker — ouvrez-le d'abord avec sonar_bitlocker.sh (clé de récupération du propriétaire)."; continue; fi
        mp="$MNT_ROOT/$(basename "$cand")-$$"; mkdir -p "$mp"
        # ro strict ; "noload" : ne rejoue PAS le journal ext4 (rejouer = écrire)
        if mount -o ro "$cand" "$mp" 2>/dev/null || mount -o ro,noload "$cand" "$mp" 2>/dev/null; then
            CLEANUP_MOUNTS+=("$mp"); n=$((n + 1))
            if [[ -d "$mp/Users" || -d "$mp/Windows" || -d "$mp/home" ]] || [[ -n "$PART" ]]; then SRC_ROOT="$mp"; SRC_DEV="$cand"; return 0; fi
            [[ -z "$SRC_ROOT" ]] && { SRC_ROOT="$mp"; SRC_DEV="$cand"; }
        else rmdir "$mp" 2>/dev/null; fi
    done
    [[ -n "$SRC_ROOT" ]] || die "aucun volume lisible trouvé sur $s (chiffré ? système de fichiers non reconnu ?)"
}

# ------------------------------------------------------------------------------------------------ copie
user_dirs() {   # imprime les chemins (relatifs à SRC_ROOT) à copier pour --what user
    local u d
    if [[ -d "$SRC_ROOT/Users" ]]; then
        for u in "$SRC_ROOT"/Users/*/; do
            [[ -d "$u" ]] || continue
            case "$(basename "$u")" in "All Users"|"Default"|"Default User"|"Public"|"desktop.ini") continue ;; esac
            for d in Desktop Documents Pictures Videos Music Downloads "OneDrive" Contacts Favorites; do
                [[ -d "${u}${d}" ]] && printf '%s\n' "${u#"$SRC_ROOT"/}${d}"
            done
        done
    fi
    for u in "$SRC_ROOT"/home/*/; do
        [[ -d "$u" ]] || continue
        for d in Desktop Documents Pictures Videos Music Downloads Bureau Documents Images Vidéos Musique Téléchargements; do
            [[ -d "${u}${d}" ]] && printf '%s\n' "${u#"$SRC_ROOT"/}${d}"
        done
    done
}

cmd_copy() {
    [[ -n "$SRC" ]] || die "--source est obligatoire"
    check_dest
    open_source "$SRC"
    local -a roots=(); local p total avail
    case "$WHAT" in
        all)  roots=(".") ;;
        user) while IFS= read -r p; do [[ -n "$p" ]] && roots+=("$p"); done < <(user_dirs | sort -u)
              [[ ${#roots[@]} -gt 0 ]] || die "aucun dossier utilisateur reconnu dans la source (Users/*, home/*) : utilisez --what all ou --what CHEMIN" ;;
        *)    roots=("$WHAT" "${WHAT_PATHS[@]}")
              for p in "${roots[@]}"; do [[ -e "$SRC_ROOT/$p" ]] || die "chemin absent de la source : $p"; done ;;
    esac
    # garde-fou : destination hors de la source
    case "$DEST/" in "$SRC_ROOT"/*) die "la destination est DANS la source : refus" ;; esac
    if [[ -n "${SRC_DEV:-}" ]]; then
        [[ "$(disk_of "$(dest_device "$DEST")")" != "$(disk_of "$SRC_DEV")" || -z "$(disk_of "$SRC_DEV")" ]] || die "la destination est sur le MÊME disque que la source : refus (écrire sur un disque défaillant l'aggrave)"
    fi
    # place : somme des tailles + 5 %
    total=0; for p in "${roots[@]}"; do total=$((total + $(du -sb "$SRC_ROOT/$p" 2>/dev/null | awk '{print $1+0}'))); done
    avail="$(free_bytes "$DEST")"
    if (( total + total / 20 > avail )); then die "place insuffisante sur la destination : $total octets à copier (+5 %), $avail disponibles"; fi
    say "Source montée en lecture seule : $SRC_ROOT — $total octets à copier vers $DEST"
    audit COPY_START "src=$SRC what=$WHAT dest=$DEST bytes=$total"

    local MAN="$DEST/RECOVERY_MANIFEST.tsv" ERR="$DEST/RECOVERY_ERRORS.tsv" ok=0 bad=0 mism=0 bytes=0 rel dst h1 h2 sz mt
    printf 'SHA256\tSIZE\tMTIME\tPATH\tSTATUS\n' > "$MAN"; printf 'PATH\tERROR\n' > "$ERR"
    for p in "${roots[@]}"; do
        while IFS= read -r -d '' f; do
            rel="${f#"$SRC_ROOT"/}"; rel="${rel#./}"; dst="$DEST/files/$rel"
            mkdir -p "$(dirname "$dst")" 2>/dev/null
            # une seule lecture de la source : le flux est écrit ET haché
            if ! h1="$(set -o pipefail; tee "$dst" < "$f" 2>/dev/null | sha256sum | awk '{print $1}')" || [[ -z "$h1" ]]; then
                printf '%s\t%s\n' "$rel" "lecture impossible ou incomplète" >> "$ERR"; rm -f "$dst"; bad=$((bad + 1)); continue
            fi
            touch -r "$f" "$dst" 2>/dev/null
            h2="$(sha256sum "$dst" 2>/dev/null | awk '{print $1}')"
            sz="$(stat -c %s "$dst" 2>/dev/null || echo 0)"; mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
            if [[ "$h1" == "$h2" ]]; then
                printf '%s\t%s\t%s\t%s\tOK\n' "$h1" "$sz" "$mt" "$rel" >> "$MAN"; ok=$((ok + 1)); bytes=$((bytes + sz))
            else
                printf '%s\t%s\t%s\t%s\tMISMATCH\n' "$h1" "$sz" "$mt" "$rel" >> "$MAN"; printf '%s\t%s\n' "$rel" "copie différente de la lecture" >> "$ERR"; mism=$((mism + 1))
            fi
        done < <(find "$SRC_ROOT/$p" -type f -print0 2>/dev/null)
    done
    {
        echo "SONAR-SE — résumé de récupération ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
        echo "Source        : $SRC"
        echo "Sélection     : $WHAT ${roots[*]}"
        echo "Copiés (OK)   : $ok fichier(s), $bytes octets"
        echo "Échecs lecture: $bad   Écarts de copie: $mism   (détail : RECOVERY_ERRORS.tsv)"
        echo "Non tenté     : fichiers supprimés / partitions perdues (recherche par signatures : étape suivante), tout ce qui est hors de la sélection."
        echo "Ce résumé ne garantit pas que les données sont complètes : il décrit ce qui a été lu et copié."
    } | tee "$DEST/RECOVERY_SUMMARY.txt"
    audit COPY_DONE "ok=$ok bad=$bad mismatch=$mism bytes=$bytes"
    [[ $bad -eq 0 && $mism -eq 0 ]]
}

cmd_verify() {
    check_dest
    local MAN="$DEST/RECOVERY_MANIFEST.tsv" ok=0 bad=0 miss=0 h
    [[ -s "$MAN" ]] || die "manifeste absent : $MAN"
    while IFS=$'\t' read -r sha sz mt path status; do
        [[ "$sha" == SHA256 || "$status" != OK ]] && continue
        if [[ ! -f "$DEST/files/$path" ]]; then miss=$((miss + 1)); echo "MANQUANT  $path"; continue; fi
        h="$(sha256sum "$DEST/files/$path" | awk '{print $1}')"
        if [[ "$h" == "$sha" ]]; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "ALTÉRÉ    $path"; fi
    done < "$MAN"
    echo "Vérification : $ok conforme(s), $bad altéré(s), $miss manquant(s)."
    [[ $bad -eq 0 && $miss -eq 0 ]]
}

# ------------------------------------------------------------------------------------------------ image (ddrescue)
cmd_image() {
    [[ -n "$SRC" ]] || die "--source est obligatoire"
    [[ -b "$SRC" || -f "$SRC" ]] || die "la source doit être un périphérique ou un fichier image"
    command -v ddrescue >/dev/null 2>&1 || die "ddrescue absent (paquet gddrescue ; présent dans SystemRescue)"
    check_dest
    local img="$DEST/disk.img" map="$DEST/disk.map" sdisk ddisk
    if [[ -b "$SRC" ]]; then
        sdisk="$(disk_of "$SRC")"; ddisk="$(disk_of "$(dest_device "$DEST")")"
        [[ -z "$sdisk" || "$sdisk" != "$ddisk" ]] || die "la destination est sur le MÊME disque que la source : refus"
        [[ -n "$(findmnt -n "$SRC" 2>/dev/null)" ]] && say "ATTENTION : $SRC est monté ; préférez le démonter avant l'imagerie."
    fi
    [[ "$(readlink -f "$SRC")" != "$(readlink -f "$img")" ]] || die "source et image identiques"
    local size; size="$(blockdev --getsize64 "$SRC" 2>/dev/null || stat -c %s "$SRC")"
    (( size + size / 100 <= $(free_bytes "$DEST") )) || die "place insuffisante : $size octets nécessaires, $(free_bytes "$DEST") disponibles"
    audit IMAGE_START "src=$SRC dest=$img size=$size"
    say "Passe 1 : copie rapide (sans gratter les zones difficiles)"
    ddrescue -n "$SRC" "$img" "$map" || say "ddrescue passe 1 : code $?"
    say "Passe 2 : réessais sur les zones illisibles (3 tentatives)"
    ddrescue -d -r3 "$SRC" "$img" "$map" || say "ddrescue passe 2 : code $?"
    local bad=0 pos size st
    while read -r pos size st _; do
        [[ "$pos" =~ ^0x ]] || continue
        case "$st" in '?'|'*'|'/'|'-') bad=$((bad + size)) ;; esac
    done < "$map"
    { echo "Image : $img"; echo "Octets non récupérés (carte ddrescue) : ${bad}"; } | tee "$DEST/IMAGE_SUMMARY.txt"
    audit IMAGE_DONE "img=$img unrecovered=${bad}"
    [[ "$bad" -eq 0 ]]
}

# ------------------------------------------------------------------------------------------------ carving (fichiers supprimés)
# Recherche par SIGNATURES (PhotoRec) : retrouve des fichiers dont le nom et le dossier ont disparu (supprimés,
# système de fichiers détruit). PhotoRec ne fait que LIRE la source. Les résultats sont classés :
#   CONNU   le SHA-256 correspond à un fichier déjà copié par « copy » (donc pas une découverte)
#   NOUVEAU absent de la copie : candidat « fichier supprimé » — à contrôler à la main
# Limites annoncées dans le résumé : noms et dates d'origine perdus ; un fichier fragmenté peut être corrompu.
find_photorec() {
    local c
    for c in "${SONAR_PHOTOREC:-}" "$(command -v photorec 2>/dev/null)" "$(command -v photorec_static 2>/dev/null)" \
             "$(dirname "$SELF")"/../Portable/TestDisk/*/photorec_static "$(dirname "$SELF")"/../Portable/TestDisk/photorec_static; do
        [[ -n "$c" && -x "$c" ]] && { echo "$c"; return 0; }
    done
    return 1
}

cmd_carve() {
    [[ -n "$SRC" ]] || die "--source est obligatoire"
    [[ -b "$SRC" || -f "$SRC" ]] || die "la source doit être un périphérique ou un fichier image"
    local pr; pr="$(find_photorec)" || die "photorec introuvable (TestDisk : sonar_master.sh --fetch data-recovery, ou paquet testdisk)"
    check_dest
    if [[ -b "$SRC" ]]; then
        [[ "$(disk_of "$SRC")" != "$(disk_of "$(dest_device "$DEST")")" || -z "$(disk_of "$SRC")" ]] || die "la destination est sur le MÊME disque que la source : refus"
    fi
    local out="$DEST/carved" spec="partition_none,fileopt,everything,enable,search" t sel=""
    if [[ -n "$TYPES" ]]; then
        for t in ${TYPES//,/ }; do [[ "$t" =~ ^[a-z0-9]+$ ]] || die "type invalide : $t"; sel="${sel},${t},enable"; done
        spec="partition_none,fileopt,everything,disable${sel},search"
    fi
    (( $(stat -c %s "$SRC" 2>/dev/null || blockdev --getsize64 "$SRC") + 1 <= $(free_bytes "$DEST") * 4 )) || say "ATTENTION : la place disponible peut être insuffisante pour tout ce que la recherche retrouvera"
    rm -rf "$out"; mkdir -p "$out"
    audit CARVE_START "src=$SRC dest=$out types=${TYPES:-all}"
    say "Recherche par signatures (lecture seule de la source) : $pr"
    "$pr" /log /d "$out/" /cmd "$SRC" "$spec" >"$DEST/photorec.out" 2>&1 || { say "photorec a échoué (voir $DEST/photorec.out)"; audit CARVE_FAILED "rc=$?"; exit 1; }
    local M="$DEST/CARVED_MANIFEST.tsv" f h known nnew=0 nknown=0 total=0
    local -A have=()
    if [[ -s "$DEST/RECOVERY_MANIFEST.tsv" ]]; then
        while IFS=$'\t' read -r h _ _ _ st; do [[ "$h" == SHA256 || "$st" != OK ]] || have["$h"]=1; done < "$DEST/RECOVERY_MANIFEST.tsv"
    fi
    printf 'SHA256\tSIZE\tEXT\tPATH\tCLASS\n' > "$M"
    while IFS= read -r -d '' f; do
        h="$(sha256sum "$f" | awk '{print $1}')"; total=$((total + 1))
        if [[ -n "${have[$h]:-}" ]]; then known=CONNU; nknown=$((nknown + 1)); else known=NOUVEAU; nnew=$((nnew + 1)); fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$h" "$(stat -c %s "$f")" "${f##*.}" "${f#"$DEST"/}" "$known" >> "$M"
    done < <(find "$out" -type f -not -name 'report.xml' -not -name '*.log' -print0 2>/dev/null)
    {
        echo "SONAR-SE — résumé de recherche par signatures ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
        echo "Source        : $SRC   Types : ${TYPES:-tous}"
        echo "Fichiers retrouvés : $total   dont déjà présents dans la copie (CONNU) : $nknown   candidats (NOUVEAU) : $nnew"
        echo "Répartition   : $(awk -F'\t' 'NR>1 {c[$3]++} END {for (e in c) printf "%s=%d ", e, c[e]}' "$M")"
        echo "Limites       : noms et dates d'origine PERDUS ; un fichier fragmenté peut être corrompu ; « NOUVEAU » ne prouve pas que"
        echo "                le fichier a été supprimé par le propriétaire. À contrôler avant de le remettre au client."
    } | tee "$DEST/CARVED_SUMMARY.txt"
    audit CARVE_DONE "total=$total new=$nnew known=$nknown"
    return 0
}

case "$CMD" in
    plan)   cmd_plan ;;
    copy)   cmd_copy ;;
    verify) cmd_verify ;;
    image)  cmd_image ;;
    carve)  cmd_carve ;;
    *)      usage; exit 2 ;;
esac
