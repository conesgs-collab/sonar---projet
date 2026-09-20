#!/bin/sh
# sonar_diag_winpe.sh — collecte "lite" du diagnostic intelligent SONAR-SE pour
# le WinPE (busybox ash). Ecrit des faits cle=valeur, les MEMES cles que
# tools/sonar_diag.sh (Linux), puis le moteur commun (diag_engine.awk) conclut.
#
# Ce que WinPE permet (et ne permet pas) : pas de PowerShell, pas de WMI, pas de
# smartctl. On lit donc ce que diskpart, reg, bcdedit, fsutil et un acces brut
# aux volumes donnent : disques, volumes, ESP/BCD, BitLocker, etat du systeme
# de fichiers, hibernation, firmware/Secure Boot, entrees UEFI. Pas de SMART
# ni de journaux noyau : une regle (S010) le dit au technicien et renvoie vers
# SystemRescue. Lecture seule ; seule une lettre de lecteur temporaire est
# attribuee a l'ESP (en memoire, retiree ensuite).
#
# Usage : busybox sh sonar_diag_winpe.sh FAITS_SORTIE
OUT="${1:-facts.txt}"
: > "$OUT"
TMP="${TEMP:-${TMP:-.}}"
DP="$TMP/sonar_dp_$$.txt"

emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }
clean() { tr -d '\r'; }
rq() { reg query "$1" /v "$2" 2>/dev/null | clean | awk -v v="$2" '$1==v {sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+/, ""); print; exit}'; }

# diskpart : execute un script de commandes, renvoie la sortie sans CR.
dp() { printf '%s\n' "$@" > "$DP"; diskpart /s "$DP" 2>&1 | clean; }

# --------------------------------------------------------------- SYSTEME
emit sys.collector winpe

# Dans WinPE, la valeur PEFirmwareType n'existe PAS tant que "wpeutil
# UpdateBootInfo" ne l'a pas ecrite (constate en VM UEFI : absente avant, 0x2
# apres). Sur un Windows installe (test), wpeutil est absent : on deduit du chargeur.
wpeutil UpdateBootInfo >/dev/null 2>&1
fw="$(rq 'HKLM\SYSTEM\CurrentControlSet\Control' PEFirmwareType)"
case "$fw" in
    0x1) emit sys.firmware bios ;;
    0x2) emit sys.firmware uefi ;;
    *)   cur="$(bcdedit /enum '{current}' 2>/dev/null | clean)"
         if printf '%s' "$cur" | grep -qi 'winload\.efi'; then emit sys.firmware uefi
         elif printf '%s' "$cur" | grep -qi 'winload\.exe'; then emit sys.firmware bios
         else emit sys.firmware unknown; fi ;;
esac
FW="$(awk -F= '$1=="sys.firmware" {print $2}' "$OUT")"

sb="$(rq 'HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State' UEFISecureBootEnabled)"
case "$sb" in 0x1) emit sys.secureboot on ;; 0x0) emit sys.secureboot off ;; *) emit sys.secureboot unknown ;; esac

cpu="$(rq 'HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0' ProcessorNameString | sed 's/^ *//')"
[ -n "$cpu" ] && emit sys.cpu_model "$cpu"
ram="$(free -m 2>/dev/null | awk '/^Mem:/ {print $2; exit}')"
[ -n "$ram" ] && emit sys.ram_mb "$ram"
ven="$(rq 'HKLM\HARDWARE\DESCRIPTION\System\BIOS' SystemManufacturer)"
prod="$(rq 'HKLM\HARDWARE\DESCRIPTION\System\BIOS' SystemProductName)"
[ -n "$ven" ] && emit sys.vendor "$ven"
[ -n "$prod" ] && emit sys.product "$prod"

if [ "$FW" = uefi ]; then
    fwe="$(bcdedit /enum firmware 2>/dev/null | clean)"
    # En WinPE, bcdedit ne peut souvent pas ouvrir le magasin ("could not be
    # opened") : sans liste d'entrees lisible, on n'emet RIEN plutot qu'un
    # faux "aucune entree Windows".
    nent="$(printf '%s\n' "$fwe" | grep -Eic '^(identifier|identificateur)')"
    if [ "${nent:-0}" -gt 0 ]; then
        emit boot.efi_entries "$nent"
        if printf '%s\n' "$fwe" | grep -Eqi 'Windows Boot Manager|Gestionnaire de d.marrage Windows'; then
            emit boot.windows_entry yes; else emit boot.windows_entry no; fi
    fi
fi

# ---------------------------------------------------------------- DISQUES
DISKS="$(dp 'list disk' | awk '($1=="Disk" || $1=="Disque") && $2 ~ /^[0-9]+$/ {print $2}')"
if [ -z "$DISKS" ]; then
    emit sys.diag_root no          # diskpart muet : pas les droits (ou pas de disque)
else
    emit sys.diag_root yes
    for d in $DISKS; do
        out="$(dp "select disk $d" 'detail disk')"
        # Independant de la langue : la ligne "ID" est la seule dont la valeur est
        # un GUID {...} (GPT) ou 8 chiffres hexa (MBR). Le modele est la ligne
        # non vide juste avant, le type de bus (SATA, NVMe, USB...) la ligne juste apres.
        # Le separateur ":" peut etre precede d'une espace insecable (francais).
        parsed="$(printf '%s\n' "$out" | awk '
            NF { if (!idl && $0 ~ /:[ \t]*(\{[0-9A-Fa-f-]+\}|[0-9A-Fa-f]{8})[ \t]*$/) { idl = 1; gid = $0; sub(/^[^:]*:[ \t]*/, "", gid); next }
                 if (idl == 1) { typ = $0; sub(/^[^:]*:[ \t]*/, "", typ); idl = 2 }
                 else if (!idl) prev = $0 }
            END { print prev "|" gid "|" typ }')"
        model="${parsed%%|*}"; rest="${parsed#*|}"; gid="${rest%%|*}"; typ="${rest#*|}"
        emit "disk.d$d.model" "${model:-Disque $d}"
        emit "disk.d$d.tran" "$(printf '%s' "${typ:--}" | tr 'A-Z' 'a-z')"
        case "$gid" in '{'*) emit "disk.d$d.ptable" gpt ;; ?*) emit "disk.d$d.ptable" mbr ;; esac
    done
fi

# ---------------------------------------------------------------- VOLUMES
# Colonnes lues d'apres la ligne de tirets de l'en-tete : independant de la
# langue (l'ordre des colonnes de diskpart ne change pas, seuls les libelles).
VOLS="$(dp 'list volume' | awk '
    /^[ \t]*-+([ \t]+-+)+[ \t]*$/ {
        n = 0; s = $0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "-" && !inrun) { n++; st[n] = i; inrun = 1 }
            if (c != "-") { if (inrun) { en[n] = i - 1 }; inrun = 0 }
        }
        if (inrun) en[n] = length(s)
        hdr = 1; next
    }
    hdr && NF == 0 { exit }
    hdr {
        for (k = 1; k <= n; k++) { f = substr($0, st[k], (k < n ? st[k+1] - st[k] : 200)); gsub(/^[ \t]+|[ \t]+$/, "", f); v[k] = f }
        gsub(/[^0-9]/, "", v[1])
        print v[1] "|" v[2] "|" v[3] "|" v[4] "|" v[6] "|" v[7] "|" v[8]
    }')"

WIN=0; ESP=0
SYSDRV="$(printf '%s' "${SystemDrive:-X:}" | tr 'a-z' 'A-Z' | cut -c1)"

# lettre libre pour monter temporairement l'ESP
free_letter() {
    for L in Z Y X W V U T S R; do
        [ "$L" = "$SYSDRV" ] && continue
        [ -d "$L:/" ] || { echo "$L"; return; }
    done
}

echo "$VOLS" > "$TMP/sonar_vols_$$.txt"
while IFS='|' read -r vn ltr lbl fs size stat info; do
    [ -z "$vn" ] && continue
    case "$fs" in UDF|CDFS) continue ;; esac   # lecteur optique (l'ISO WinPE elle-meme)
    inst="v$vn"
    # la cle SONAR-SE elle-meme et le lecteur du WinPE ne sont pas des volumes client
    if [ -n "$ltr" ]; then
        if [ -f "$ltr:/MANIFEST/PROFILES.tsv" ]; then emit sonar.key_letter "$ltr"; continue; fi
        [ "$ltr" = "$SYSDRV" ] && continue
    fi
    emit "part.$inst.fstype" "${fs:--}"
    [ -n "$ltr" ] && emit "part.$inst.letter" "$ltr"
    sz="$(printf '%s' "$size" | awk '{n=$1+0; u=toupper($2); if (u ~ /^(KB|KO)/) n=n/1048576; else if (u ~ /^(MB|MO)/) n=n/1024; else if (u ~ /^(TB|TO)/) n=n*1024; printf "%d", n}')"
    emit "part.$inst.size_gb" "${sz:-0}"

    isesp=no
    case "$info" in Syst*|SYST*) [ "$fs" = FAT32 ] && isesp=yes ;; esac
    emit "part.$inst.is_esp" "$isesp"

    # lettre temporaire pour l'ESP
    tmpl=""
    if [ "$isesp" = yes ] && [ -z "$ltr" ]; then
        tmpl="$(free_letter)"
        if [ -n "$tmpl" ]; then dp "select volume $vn" "assign letter=$tmpl" >/dev/null; ltr="$tmpl"; fi
    fi

    if [ "$isesp" = yes ]; then
        ESP=$((ESP + 1))
        if [ -n "$ltr" ]; then
            [ -f "$ltr:/EFI/Microsoft/Boot/bootmgfw.efi" ] && emit "part.$inst.bootmgfw" yes || emit "part.$inst.bootmgfw" no
            [ -f "$ltr:/EFI/Microsoft/Boot/BCD" ] && emit "part.$inst.bcd" yes || emit "part.$inst.bcd" no
        fi
    fi

    # BitLocker : signature "-FVE-FS-" a l'offset 3 du volume, lisible meme verrouille
    bl=no
    if [ -n "$ltr" ]; then
        sig="$(head -c 11 "//./$ltr:" 2>/dev/null | tail -c 8 | tr -d '\0')"
        [ "$sig" = "-FVE-FS-" ] && bl=yes
    fi
    emit "part.$inst.bitlocker" "$bl"

    # Windows installe ? (le WinPE lui-meme est sur $SystemDrive : exclu)
    if [ -n "$ltr" ] && [ "$ltr" != "$SYSDRV" ] && [ "$bl" = no ] && [ "$isesp" = no ]; then
        if [ -f "$ltr:/Windows/System32/config/SYSTEM" ]; then
            WIN=$((WIN + 1))
            emit "part.$inst.has_windows" yes
            pct="$(df -k "$ltr:/" 2>/dev/null | awk 'NR==2 && $2>0 {printf "%d", ($4*100)/$2}')"
            [ -n "$pct" ] && emit "part.$inst.free_pct" "$pct"
            dq="$(fsutil dirty query "$ltr:" 2>/dev/null | clean)"
            if printf '%s' "$dq" | grep -Eqi 'not dirty|pas .*(sale|erron|modif)'; then st=ok
            elif printf '%s' "$dq" | grep -Eqi 'dirty|sale|erron'; then st=dirty
            else st=""; fi
            if [ -f "$ltr:/hiberfil.sys" ]; then
                hs="$(head -c 4 "$ltr:/hiberfil.sys" 2>/dev/null | tr 'A-Z' 'a-z')"
                [ "$hs" = "hibr" ] && st=hibernated
            fi
            [ -n "$st" ] && emit "part.$inst.fs_state" "$st"
        else
            emit "part.$inst.has_windows" no
        fi
    fi

    [ -n "$tmpl" ] && dp "select volume $vn" "remove letter=$tmpl" >/dev/null
done < "$TMP/sonar_vols_$$.txt"
rm -f "$TMP/sonar_vols_$$.txt"

emit win.partitions "$WIN"
emit esp.count "$ESP"
rm -f "$DP"
