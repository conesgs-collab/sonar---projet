#!/bin/bash
# sonar_bitlocker.sh — SONAR-SE : ouvre un volume BitLocker en LECTURE SEULE avec la cle de
# recuperation (48 chiffres) ou le mot de passe que le proprietaire fournit.
#
# Pourquoi cote Linux : le WinPE SONAR-SE ne peut pas embarquer manage-bde (il exige WMI,
# impossible a ajouter sur un hote Windows 10, voir docs/WINPE.md). Depuis SystemRescue /
# Ubuntu / Fedora, cryptsetup (>= 2.3) ou dislocker savent lire BitLocker.
#
# Ce que fait l'outil, et ne fait pas :
#   - il ne CONTOURNE rien : sans la cle de recuperation (ou le mot de passe), il n'ouvre rien ;
#   - il n'ouvre qu'en LECTURE SEULE (aucune option d'ecriture) : on sauvegarde, on ne modifie pas ;
#   - la cle est lue au clavier (invisible) ou sur stdin/fichier ; elle n'est jamais mise dans
#     une ligne de commande (visible par `ps`), ni dans un journal, ni sur disque ;
#   - il journalise l'evenement (peripherique, methode) dans SONAR_AUDIT_FILE si defini, jamais la cle.
#
# Usage (root) :
#   sonar_bitlocker.sh --list                         volumes BitLocker detectes
#   sonar_bitlocker.sh --unlock /dev/sdb3             demande la cle, monte en lecture seule
#   sonar_bitlocker.sh --unlock /dev/sdb3 --key-stdin cle sur stdin (automatisation)
#   sonar_bitlocker.sh --lock /dev/sdb3               demonte et referme (ou --lock-all)
#
# Codes retour : 0 ok | 1 echec (mauvaise cle, montage impossible) | 2 usage / prerequis
set -uo pipefail

SONAR_BL_VERSION="1.0.0"
MOUNT_ROOT="${SONAR_BL_MOUNT_ROOT:-/mnt/sonar-bl}"
ACTION=""; DEVICE=""; KEY_STDIN=false; KEY_FILE=""; ASSUME_YES=false

usage() { sed -n '2,/^set -uo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
say() { echo "[SONAR-BL] $*" >&2; }
die() { say "ERREUR : $*"; exit "${2:-1}"; }

audit() {   # jamais de cle ici
    [[ -n "${SONAR_AUDIT_FILE:-}" ]] || return 0
    printf '%s\tBITLOCKER_%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$SONAR_AUDIT_FILE" 2>/dev/null || true
}

# --- detection : signature "-FVE-FS-" a l'offset 3 (lisible meme verrouille), ou blkid
is_bitlocker() {
    local d="$1"
    [[ -b "$d" ]] || return 1
    [[ "$(head -c 11 "$d" 2>/dev/null | tail -c 8 | tr -d '\000')" == "-FVE-FS-" ]] && return 0
    [[ "$(blkid -o value -s TYPE "$d" 2>/dev/null)" == "BitLocker" ]]
}

list_devices() {
    local d
    lsblk -lnpo NAME,TYPE 2>/dev/null | awk '$2=="part" || $2=="disk" || $2=="lvm" || $2=="crypt" || $2=="loop" {print $1}' | while read -r d; do
        is_bitlocker "$d" && echo "$d"
    done
}

cmd_list() {
    local d n=0 name state size label
    while read -r d; do
        [[ -n "$d" ]] || continue
        name="sonarbl_$(basename "$d")"
        state="verrouille"; [[ -e "/dev/mapper/$name" || -d "$MOUNT_ROOT/$(basename "$d")/.dislocker" ]] && state="OUVERT (lecture seule) -> $MOUNT_ROOT/$(basename "$d")"
        size="$(lsblk -dno SIZE "$d" 2>/dev/null)"; label="$(lsblk -dno LABEL "$d" 2>/dev/null)"
        printf '%s\t%s\t%s\t%s\n' "$d" "${size:--}" "${label:--}" "$state"; n=$((n + 1))
    done < <(list_devices)
    [[ $n -gt 0 ]] || say "Aucun volume BitLocker detecte (BitLocker To Go sur cle USB : essayer --unlock directement)."
    return 0
}

# --- cle : format de recuperation = 8 groupes de 6 chiffres
valid_recovery_format() { [[ "$1" =~ ^[0-9]{6}(-[0-9]{6}){7}$ ]]; }

read_key() {
    local k=""
    if $KEY_STDIN; then IFS= read -r k || true
    elif [[ -n "$KEY_FILE" ]]; then [[ -r "$KEY_FILE" ]] || die "fichier de cle illisible : $KEY_FILE" 2; IFS= read -r k < "$KEY_FILE" || true
    else
        [[ -t 0 ]] || die "pas de terminal : utilisez --key-stdin ou --key-file" 2
        read -r -s -p "Cle de recuperation (48 chiffres, avec ou sans tirets) ou mot de passe : " k; echo >&2
    fi
    k="${k//[$'\r\n']/}"
    [[ -n "$k" ]] || die "cle vide" 2
    # 48 chiffres collés -> on remet les tirets ; sinon (mot de passe, ou deja avec tirets) tel quel
    if [[ "$k" =~ ^[0-9]{48}$ ]]; then k="${k:0:6}-${k:6:6}-${k:12:6}-${k:18:6}-${k:24:6}-${k:30:6}-${k:36:6}-${k:42:6}"; fi
    if [[ "$k" =~ ^[0-9-]+$ ]] && ! valid_recovery_format "$k"; then
        die "format de cle de recuperation invalide : il faut 8 groupes de 6 chiffres (ex. 123456-123456-...)" 2
    fi
    KEY="$k"
}

cryptsetup_ok() {
    command -v cryptsetup >/dev/null 2>&1 || return 1
    local v; v="$(cryptsetup --version 2>/dev/null | awk '{print $2}')"
    [[ -n "$v" ]] && [[ "$(printf '%s\n2.3.0\n' "$v" | sort -V | head -1)" == "2.3.0" ]]
}

cmd_unlock() {
    local d="$DEVICE" b name mnt method=""
    [[ -n "$d" ]] || die "--unlock demande un peripherique (ex. /dev/sdb3)" 2
    [[ $EUID -eq 0 ]] || die "root requis (lecture brute des peripheriques)" 2
    [[ -b "$d" ]] || die "$d n'est pas un peripherique bloc" 2
    is_bitlocker "$d" || die "$d ne porte pas de signature BitLocker (-FVE-FS-) : refus" 2
    b="$(basename "$d")"; name="sonarbl_$b"; mnt="$MOUNT_ROOT/$b"
    [[ -e "/dev/mapper/$name" ]] && die "$d est deja ouvert ($mnt). Utilisez --lock d'abord." 1

    if ! $ASSUME_YES && [[ -t 0 && "$KEY_STDIN" != true && -z "$KEY_FILE" ]]; then
        echo "Ce deverrouillage exige la cle de recuperation fournie par le PROPRIETAIRE du disque." >&2
        read -r -p "Le proprietaire a-t-il donne son accord ? (o/N) : " a
        [[ "$a" == o || "$a" == O || "$a" == oui ]] || die "annule (pas d'accord du proprietaire)" 1
    fi

    if cryptsetup_ok; then
        method="cryptsetup"
        read_key
        if ! printf '%s' "$KEY" | cryptsetup bitlkOpen --readonly "$d" "$name" --key-file=- >/dev/null 2>&1; then
            unset KEY
            audit UNLOCK_FAILED "dev=$d method=$method"
            die "ouverture refusee : cle incorrecte, ou protecteur non pris en charge (TPM seul, sans cle de recuperation)" 1
        fi
        unset KEY
        mkdir -p "$mnt" || die "creation de $mnt impossible" 1
        if ! mount -o ro "/dev/mapper/$name" "$mnt" 2>/tmp/sonar_bl_mount.$$; then
            say "montage impossible : $(head -1 /tmp/sonar_bl_mount.$$)"; rm -f /tmp/sonar_bl_mount.$$
            cryptsetup close "$name" >/dev/null 2>&1; rmdir "$mnt" 2>/dev/null
            audit MOUNT_FAILED "dev=$d method=$method"
            die "le volume est dechiffre mais son systeme de fichiers ne se monte pas (hibernation / arret brutal ? voir le diagnostic)" 1
        fi
        rm -f /tmp/sonar_bl_mount.$$
    elif command -v dislocker >/dev/null 2>&1; then
        method="dislocker"
        say "cryptsetup >= 2.3 absent : repli sur dislocker (il demandera la cle lui-meme)."
        mkdir -p "$mnt/.dislocker" || die "creation de $mnt impossible" 1
        if ! dislocker -V "$d" -p -- "$mnt/.dislocker" >/dev/null; then
            audit UNLOCK_FAILED "dev=$d method=$method"; rmdir "$mnt/.dislocker" "$mnt" 2>/dev/null
            die "ouverture refusee par dislocker" 1
        fi
        if ! mount -o ro,loop "$mnt/.dislocker/dislocker-file" "$mnt" 2>/dev/null; then
            fusermount -u "$mnt/.dislocker" 2>/dev/null; rmdir "$mnt/.dislocker" "$mnt" 2>/dev/null
            audit MOUNT_FAILED "dev=$d method=$method"
            die "volume dechiffre mais montage impossible" 1
        fi
    else
        die "ni cryptsetup (>= 2.3) ni dislocker : demarrez SystemRescue / Ubuntu / Fedora, ou installez l'un des deux" 2
    fi
    audit UNLOCKED "dev=$d method=$method mount=$mnt readonly=yes"
    echo "OUVERT en lecture seule : $mnt   (methode : $method)"
    echo "Pour refermer : $0 --lock $d"
}

cmd_lock() {
    local d="$1" b name mnt
    b="$(basename "$d")"; name="sonarbl_$b"; mnt="$MOUNT_ROOT/$b"
    [[ $EUID -eq 0 ]] || die "root requis" 2
    mountpoint -q "$mnt" 2>/dev/null && { umount "$mnt" || die "demontage de $mnt impossible (fichiers ouverts ?)" 1; }
    if [[ -e "/dev/mapper/$name" ]]; then cryptsetup close "$name" || die "fermeture de $name impossible" 1; fi
    if [[ -d "$mnt/.dislocker" ]]; then fusermount -u "$mnt/.dislocker" 2>/dev/null || umount "$mnt/.dislocker" 2>/dev/null; rmdir "$mnt/.dislocker" 2>/dev/null; fi
    rmdir "$mnt" 2>/dev/null || true
    audit LOCKED "dev=$d"
    echo "Referme : $d"
}

cmd_lock_all() {
    local m d rc=0
    for m in /dev/mapper/sonarbl_*; do
        [[ -e "$m" ]] || continue
        cmd_lock "/dev/${m#/dev/mapper/sonarbl_}" || rc=1
    done
    return $rc
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)      ACTION=list; shift ;;
        --unlock)    ACTION=unlock; DEVICE="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --lock)      ACTION=lock; DEVICE="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --lock-all)  ACTION=lockall; shift ;;
        --key-stdin) KEY_STDIN=true; shift ;;
        --key-file)  KEY_FILE="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --yes)       ASSUME_YES=true; shift ;;
        --version)   echo "sonar_bitlocker ${SONAR_BL_VERSION}"; exit 0 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Option inconnue : $1 (voir --help)" >&2; exit 2 ;;
    esac
done

case "$ACTION" in
    list)    [[ $EUID -eq 0 ]] || die "root requis (lecture des signatures)" 2; cmd_list ;;
    unlock)  cmd_unlock ;;
    lock)    [[ -n "$DEVICE" ]] || die "--lock demande un peripherique" 2; cmd_lock "$DEVICE" ;;
    lockall) cmd_lock_all ;;
    *)       usage; exit 2 ;;
esac
