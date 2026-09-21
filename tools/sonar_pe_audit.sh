#!/bin/bash
# sonar_pe_audit.sh — SONAR-SE : audit STATIQUE d'un WinPE tiers avant de le mettre sur une clé technicien.
#
# Pourquoi : certains WinPE « tout-en-un » (dont des éditions d'affiliation) financent leur gratuité en
# installant des logiciels promotionnels sur la machine du CLIENT, en modifiant la page d'accueil ou en
# ajoutant des tâches planifiées. Le technicien qui boote dessus ne le voit pas ; le client le découvre après.
# Cet outil ouvre l'ISO / le WIM SANS l'exécuter et cherche les endroits où cela se cache.
#
# Ce qu'il examine (rien n'est exécuté, tout est lu) :
#   P010  startnet.cmd / winpeshl.ini / autorun.inf : ce qui se lance au démarrage
#   P020  ruches de registre hors ligne : Run/RunOnce, Winlogon, IFEO, page d'accueil, proxy, services
#   P030  tâches planifiées embarquées
#   P040  fichier hosts modifié
#   P050  raccourcis Internet (.url/.lnk) : liens publicitaires sur le bureau / le menu
#   P060  fichiers ajoutés (contre une référence --baseline) ou placés hors de \Windows
#   P070  indicateurs (tools/pe_audit_indicators.txt) dans ces fichiers : affiliation, page d'accueil,
#         installateurs, persistance, collecte — chaînes ASCII ET UTF-16, mots chinois compris
#   P080  domaines cités par ces fichiers, hors liste de confiance
#
# Ce que le résultat signifie — et ne signifie pas :
#   - « INDICATEURS FORTS » / « À EXAMINER » : des preuves sont montrées, à vous de juger ;
#   - « aucun indicateur » NE VEUT PAS DIRE « sain » : code chiffré, obfusqué ou téléchargé plus tard
#     échappe à une analyse statique. Pour aller plus loin : analyse dynamique (docs/PE_AUDIT.md).
#
# Usage :
#   sonar_pe_audit.sh SOURCE [--baseline REF.tsv] [--out DOSSIER] [--strict] [--max-files N] [--keep]
#   sonar_pe_audit.sh --make-baseline REF.tsv SOURCE        crée la référence d'un WinPE PROPRE
#                                                           (ex. le winpe.wim de l'ADK)
#   SOURCE = ISO, WIM/ESD, ou dossier déjà extrait.   Dépendances : 7z, wimapply (wimtools), strings,
#   hivexregedit (libwin-hivex-perl, facultatif : sans lui P020 est ignoré et le dit).
# Codes retour : 0 aucun indicateur | 10 à examiner | 20 indicateurs forts | 2 usage / prérequis
set -uo pipefail

SONAR_PE_AUDIT_VERSION="1.0.0"
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
SRC=""; BASELINE=""; MAKE_BASELINE=""; OUT=""; STRICT=false; MAX_FILES=3000; KEEP=false

usage() { sed -n '2,/^set -uo pipefail/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; }
say() { echo "[PE-AUDIT] $*" >&2; }
die() { say "ERREUR : $*"; exit "${2:-2}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline)      BASELINE="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --make-baseline) MAKE_BASELINE="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --out)           OUT="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --strict)        STRICT=true; shift ;;
        --max-files)     MAX_FILES="${2:-3000}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --keep)          KEEP=true; shift ;;
        --version)       echo "sonar_pe_audit ${SONAR_PE_AUDIT_VERSION}"; exit 0 ;;
        -h|--help)       usage; exit 0 ;;
        -*)              echo "Option inconnue : $1 (voir --help)" >&2; exit 2 ;;
        *)               SRC="$1"; shift ;;
    esac
done
[[ -n "$SRC" ]] || { usage; exit 2; }
[[ -e "$SRC" ]] || die "source introuvable : $SRC"
[[ "$MAX_FILES" =~ ^[0-9]+$ ]] || die "--max-files doit etre un entier"
IND="${SELF_DIR}/pe_audit_indicators.txt"
[[ -s "$IND" ]] || IND="${SELF_DIR}/../tools/pe_audit_indicators.txt"

W="$(mktemp -d)"
cleanup() { $KEEP && { say "Dossier de travail conserve : $W"; return; }; rm -rf "$W"; }
trap cleanup EXIT
FIND="$W/findings.tsv"; : > "$FIND"
TREES=()                       # racines d'arbres extraits (ISO + chaque image WIM)

finding() {   # finding SEV ID TITRE PREUVE [OU]
    local ev="${4//$'\t'/ }"; ev="${ev//$'\n'/ | }"
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${ev:0:300}" "${5:-}" >> "$FIND"
}

# ---------------------------------------------------------------------------------------------- acquisition
extract_wim() {   # extract_wim FICHIER.wim TAG
    local wim="$1" tag="$2" n i d
    if command -v wimapply >/dev/null 2>&1 && command -v wiminfo >/dev/null 2>&1; then
        n="$(wiminfo "$wim" 2>/dev/null | awk '/^Image Count:/ {print $3; exit}')"; n="${n:-1}"
        for ((i = 1; i <= n; i++)); do
            d="$W/wim_${tag}_${i}"; mkdir -p "$d"
            wimapply "$wim" "$i" "$d" >/dev/null 2>&1 || { rm -rf "$d"; say "image $i de $(basename "$wim") non extraite (wimapply)"; continue; }
            TREES+=("$d")
        done
    elif command -v 7z >/dev/null 2>&1; then
        d="$W/wim_${tag}"; mkdir -p "$d"
        7z x -y -bd -o"$d" "$wim" >/dev/null 2>&1 || die "extraction de $(basename "$wim") impossible (wimtools absent, 7z a echoue)"
        TREES+=("$d")
    else
        die "ni wimapply (wimtools) ni 7z : impossible d'ouvrir un WIM"
    fi
}

acquire() {
    local s="$1" lc w k=0
    lc="$(printf '%s' "$s" | tr 'A-Z' 'a-z')"
    if [[ -d "$s" ]]; then
        TREES+=("$s")
        while IFS= read -r w; do k=$((k + 1)); extract_wim "$w" "d$k"; done < <(find "$s" -maxdepth 3 -type f \( -iname '*.wim' -o -iname '*.esd' \) 2>/dev/null | head -5)
    elif [[ "$lc" == *.iso ]]; then
        command -v 7z >/dev/null 2>&1 || die "7z requis pour ouvrir une ISO"
        mkdir -p "$W/iso"; 7z x -y -bd -o"$W/iso" "$s" >/dev/null 2>&1 || die "extraction de l'ISO impossible"
        TREES+=("$W/iso")
        while IFS= read -r w; do k=$((k + 1)); extract_wim "$w" "i$k"; done < <(find "$W/iso" -type f \( -iname '*.wim' -o -iname '*.esd' \) 2>/dev/null | head -5)
    elif [[ "$lc" == *.wim || "$lc" == *.esd ]]; then
        extract_wim "$s" "w"
    else
        die "type de source non reconnu (ISO, WIM/ESD ou dossier) : $s"
    fi
    [[ ${#TREES[@]} -gt 0 ]] || die "rien d'extrait de $s"
}

# liste "chemin<TAB>taille" relative a l'arbre (pour reference / comparaison)
list_tree() { ( cd "$1" && find . -type f -printf '%P\t%s\n' 2>/dev/null | sort ); }

if [[ -n "$MAKE_BASELINE" ]]; then
    acquire "$SRC"
    : > "$MAKE_BASELINE"
    for t in "${TREES[@]}"; do
        # seules les images qui contiennent Windows\System32 servent de reference
        [[ -n "$(find "$t" -maxdepth 2 -ipath '*/windows/system32' -type d 2>/dev/null | head -1)" ]] || continue
        if $STRICT; then ( cd "$t" && find . -type f -print0 2>/dev/null | xargs -0 sha256sum 2>/dev/null | sed 's|  \./|\t|' ) >> "$MAKE_BASELINE"
        else list_tree "$t" >> "$MAKE_BASELINE"; fi
    done
    sort -u -o "$MAKE_BASELINE" "$MAKE_BASELINE"
    echo "Reference creee : $MAKE_BASELINE ($(wc -l < "$MAKE_BASELINE") fichiers, $($STRICT && echo empreintes SHA-256 || echo chemin+taille))"
    exit 0
fi

acquire "$SRC"
say "Arbres analyses : ${#TREES[@]} ($(printf '%s ' "${TREES[@]##*/}"))"

# ---------------------------------------------------------------------------------------------- outils communs
lower() { tr 'A-Z' 'a-z'; }
# fichiers texte : convertit l'UTF-16LE eventuel (BOM FF FE) en UTF-8 pour la lecture
text_of() {
    local f="$1"
    if [[ "$(head -c 2 "$f" 2>/dev/null | od -An -tx1 | tr -d ' ')" == "fffe" ]]; then iconv -f UTF-16LE -t UTF-8 "$f" 2>/dev/null; else cat "$f" 2>/dev/null; fi | tr -d '\r'
}
each_ifind() {   # each_ifind ARBRE MOTIF_IPATH  -> chemins
    find "$1" -ipath "$2" -type f 2>/dev/null
}
rel() { local t="$1" f="$2"; printf '%s' "${f#"$t"/}"; }
relany() { local f="$1" t; for t in "${TREES[@]}"; do case "$f" in "$t"/*) printf '%s' "${f#"$t"/}"; return ;; esac; done; printf '%s' "$f"; }

# ---------------------------------------------------------------------------------------------- P010 demarrage
p010() {
    local t f line
    for t in "${TREES[@]}"; do
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            while IFS= read -r line; do
                line="${line#"${line%%[![:space:]]*}"}"
                [[ -z "$line" || "$line" =~ ^(rem|::|@echo|wpeinit|wpeutil|;|\[) ]] && continue
                case "$(printf '%s' "$line" | lower)" in
                    *http://*|*https://*)  finding HIGH P010 "Le script de démarrage ouvre / appelle une adresse web" "$line" "$(rel "$t" "$f")" ;;
                    *)  # programme lance hors de System32 ou inconnu
                        if [[ "$(printf '%s' "$line" | lower)" =~ (^|[[:space:]]|\")([a-z]:)?[\\/]?[^[:space:]\"]*\.(exe|cmd|bat|vbs|ps1|hta) ]] && \
                           ! [[ "$(printf '%s' "$line" | lower)" =~ (system32|wpeutil|diskpart|bootrec|bcdedit|bcdboot|dism|sfc|robocopy|drvload|ipconfig|ping|cmd\.exe|powershell) ]]; then
                            # chemin absolu vers un AUTRE lecteur (D:\, \\serveur\) = programme apporte de l'exterieur ;
                            # sinon (variable, chemin relatif) = programme fourni par le support : a connaitre, pas alarmant
                            if [[ "$(printf '%s' "$line" | lower)" =~ (^|[^a-z])[a-wyz]:[\\/] || "$line" =~ \\\\[A-Za-z0-9._-]+\\ ]]; then
                                finding MEDIUM P010 "Le script de démarrage lance un programme situé hors du système" "$line" "$(rel "$t" "$f")"
                            else
                                finding INFO P010 "Le script de démarrage lance un programme fourni par le support" "$line" "$(rel "$t" "$f")"
                            fi
                        fi ;;
                esac
            done < <(text_of "$f")
        done < <( { each_ifind "$t" '*/windows/system32/startnet.cmd'; each_ifind "$t" '*/windows/system32/winpeshl.ini'; find "$t" -maxdepth 1 -iname autorun.inf -type f 2>/dev/null; } )
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            line="$(text_of "$f" | grep -Ei '^(open|shellexecute|shell\\[^=]*\\command)=' | head -3 | tr '\n' ' ')"
            [[ -n "$line" ]] && finding MEDIUM P010 "autorun.inf : lance un programme à l'insertion du support" "$line" "$(rel "$t" "$f")"
        done < <(find "$t" -maxdepth 1 -iname autorun.inf -type f 2>/dev/null)
    done
}

# ---------------------------------------------------------------------------------------------- P020 registre
reg_decode() {   # decode les valeurs hex(N):.. d'un .reg en texte (ASCII de l'UTF-16LE) ; laisse le reste
    awk '
    function hx(c) { return index("0123456789abcdef", tolower(c)) - 1 }
    function dec(h,   n, a, i, s, b, v) { n = split(h, a, ","); s = ""; for (i = 1; i <= n; i++) { b = a[i]; if (b == "" || b == "00") continue; v = hx(substr(b, 1, 1)) * 16 + hx(substr(b, 2, 1)); if (v > 31 && v < 127) s = s sprintf("%c", v) } return s }
    { line = $0
      if (match(line, /=hex\(([127])\):/)) { pre = substr(line, 1, RSTART - 1); h = substr(line, RSTART + RLENGTH); gsub(/\\$/, "", h); gsub(/[ \r]/, "", h); print pre "=" dec(h) }
      else print line }'
}
p020() {
    command -v hivexregedit >/dev/null 2>&1 || { finding INFO P020 "Registre non examiné : hivexregedit absent (paquet libwin-hivex-perl)" "installez-le pour contrôler Run/RunOnce, Winlogon, page d'accueil, services" ""; return; }
    local t hive key out name dump
    for t in "${TREES[@]}"; do
        while IFS= read -r hive; do
            [[ -n "$hive" ]] || continue
            name="$(basename "$hive" | lower)"
            case "$name" in
                software)
                    for key in '\Microsoft\Windows\CurrentVersion\Run' '\Microsoft\Windows\CurrentVersion\RunOnce' '\Wow6432Node\Microsoft\Windows\CurrentVersion\Run' \
                               '\Microsoft\Windows NT\CurrentVersion\Winlogon' '\Microsoft\Internet Explorer\Main' '\Microsoft\Windows\CurrentVersion\Internet Settings' \
                               '\Policies\Microsoft\Internet Explorer\Main' '\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'; do
                        reg_scan "$t" "$hive" "SOFTWARE$key" "$key" ;
                    done ;;
                default|ntuser.dat)
                    for key in '\Software\Microsoft\Windows\CurrentVersion\Run' '\Software\Microsoft\Windows\CurrentVersion\RunOnce' '\Software\Microsoft\Internet Explorer\Main' \
                               '\Software\Microsoft\Windows\CurrentVersion\Internet Settings'; do
                        reg_scan "$t" "$hive" "$(basename "$hive")$key" "$key" ;
                    done ;;
                system)
                    reg_scan "$t" "$hive" "SYSTEM\\Setup" '\Setup'
                    dump="$(hivexregedit --export "$hive" '\ControlSet001\Services' 2>/dev/null | reg_decode)"
                    # services dont l'ImagePath sort de System32 / drivers
                    out="$(awk '/^\[/ {k=$0} /^"ImagePath"=/ {print k "  " $0}' <<<"$dump" | grep -Evi 'system32|syswow64|\\drivers\\|\\windows\\|%systemroot%|svchost' | head -5)"
                    [[ -n "$out" ]] && finding MEDIUM P020 "Service dont le binaire est hors de Windows" "$out" "$(rel "$t" "$hive")"
                    ;;
            esac
        done < <(find "$t" \( -ipath '*/windows/system32/config/*' -o -ipath '*/users/*' \) -type f \( -iname SOFTWARE -o -iname SYSTEM -o -iname DEFAULT -o -iname NTUSER.DAT \) 2>/dev/null)
    done
}
reg_scan() {   # reg_scan ARBRE RUCHE ETIQUETTE CLE
    local t="$1" hive="$2" label="$3" key="$4" dump line k v
    dump="$(hivexregedit --export "$hive" "$key" 2>/dev/null | reg_decode)" || return 0
    [[ -n "$dump" ]] || return 0
    k=""
    while IFS= read -r line; do
        case "$line" in
            \[*) k="${line#[}"; k="${k%]}" ;;
            \"*\"=*)
                v="${line#*=}"
                case "$k" in
                    *"Image File Execution Options"*)
                        [[ "$line" == \"Debugger\"=* ]] && finding HIGH P020 "IFEO : un programme est détourné par un « Debugger »" "$k $line" "$(rel "$t" "$hive")" ;;
                    *"\\Winlogon")
                        case "$line" in
                            \"Shell\"=*|\"Userinit\"=*|\"Taskman\"=*)
                                [[ "$(printf '%s' "$v" | lower)" =~ (explorer\.exe|userinit\.exe|cmd\.exe|winpeshl|^\"\"$) ]] || finding HIGH P020 "Winlogon : programme de session inhabituel" "$line" "$(rel "$t" "$hive")" ;;
                        esac ;;
                    *"\\Internet Explorer\\Main"|*"Internet Explorer\\Main")
                        case "$line" in \"Start\ Page\"=*|\"Default_Page_URL\"=*|\"Search\ Page\"=*)
                            finding HIGH P020 "Page d'accueil / de recherche imposée dans le registre" "$line" "$(rel "$t" "$hive")" ;; esac ;;
                    *"Internet Settings"*)
                        case "$line" in \"ProxyServer\"=*|\"AutoConfigURL\"=*)
                            finding MEDIUM P020 "Proxy imposé dans le registre" "$line" "$(rel "$t" "$hive")" ;; esac ;;
                    *"\\Run"|*"\\RunOnce"|*"\\Run\\"*|*"\\RunOnce\\"*)
                        finding MEDIUM P020 "Démarrage automatique (Run/RunOnce)" "$k $line" "$(rel "$t" "$hive")" ;;
                    *"\\Setup")
                        case "$line" in \"CmdLine\"=*) [[ "$(printf '%s' "$v" | lower)" == *setup* || "$(printf '%s' "$v" | lower)" == *winpeshl* || "$v" == '""' ]] || finding MEDIUM P020 "Setup\\CmdLine inhabituel" "$line" "$(rel "$t" "$hive")" ;; esac ;;
                esac ;;
        esac
    done <<<"$dump"
}

# ---------------------------------------------------------------------------------------------- P030 taches, P040 hosts, P050 raccourcis
p030() {
    local t f cmd
    for t in "${TREES[@]}"; do
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            cmd="$(text_of "$f" | grep -Eio '<Command>[^<]*</Command>|<Arguments>[^<]*</Arguments>' | sed 's/<[^>]*>//g' | tr '\n' ' ')"
            [[ -n "$cmd" ]] || continue
            case "$(printf '%s' "$f" | lower)" in *"/tasks/microsoft/"*) continue ;; esac
            finding MEDIUM P030 "Tâche planifiée embarquée" "$cmd" "$(rel "$t" "$f")"
        done < <(find "$t" -ipath '*/windows/system32/tasks/*' -type f 2>/dev/null)
    done
}
p040() {
    local t f lines
    for t in "${TREES[@]}"; do
        f="$(find "$t" -ipath '*/windows/system32/drivers/etc/hosts' -type f 2>/dev/null | head -1)"
        [[ -n "$f" ]] || continue
        lines="$(text_of "$f" | sed 's/#.*//' | awk 'NF>=2 && $1 !~ /^(127\.0\.0\.1|::1)$/ {print}' | head -5)"
        [[ -n "$lines" ]] && finding HIGH P040 "Fichier hosts modifié (redirection de noms de domaine)" "$lines" "$(rel "$t" "$f")"
        lines="$(text_of "$f" | sed 's/#.*//' | awk 'NF>=2 && $1 ~ /^(127\.0\.0\.1|::1)$/ && $2 != "localhost" {print}' | head -5)"
        [[ -n "$lines" ]] && finding MEDIUM P040 "hosts : noms redirigés vers la machine locale (blocage de domaines)" "$lines" "$(rel "$t" "$f")"
    done
}
p050() {
    local t f u
    for t in "${TREES[@]}"; do
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            case "$(printf '%s' "$f" | lower)" in */windows/winsxs/*|*/windows/servicing/*) continue ;; esac
            u="$( { text_of "$f"; strings -a "$f" 2>/dev/null; strings -a -el "$f" 2>/dev/null; } | grep -Eio 'https?://[^ "<>]+' | sort -u | head -2 | tr '\n' ' ')"
            [[ -n "$u" ]] && finding MEDIUM P050 "Raccourci Internet embarqué (lien pouvant servir à la publicité)" "$u" "$(rel "$t" "$f")"
        done < <(find "$t" -type f \( -iname '*.url' -o -iname '*.lnk' \) 2>/dev/null | head -400)
    done
}

# ---------------------------------------------------------------------------------------------- P060 fichiers a examiner
CAND="$W/candidates.txt"; : > "$CAND"
p060() {
    local t f p tl added=0 changed=0 outside=0 n=0
    local -A base=()
    if [[ -n "$BASELINE" ]]; then
        [[ -s "$BASELINE" ]] || die "reference introuvable ou vide : $BASELINE"
        while IFS=$'\t' read -r p s; do base["$(printf '%s' "$p" | lower)"]="$s"; done < "$BASELINE"
    fi
    for t in "${TREES[@]}"; do
        [[ -n "$(find "$t" -maxdepth 2 -ipath '*/windows/system32' -type d 2>/dev/null | head -1)" ]] || {
            # arbre sans Windows (ISO nue) : tout est a examiner sauf les WIM eux-memes
            while IFS= read -r f; do case "$(printf '%s' "$f" | lower)" in *.wim|*.esd|*.iso|*.sdi|*.efi|*.mui) continue ;; esac; printf '%s\n' "$f" >> "$CAND"; done < <(find "$t" -type f 2>/dev/null | head -"$MAX_FILES")
            continue; }
        while IFS=$'\t' read -r p s; do
            f="$t/$p"; tl="$(printf '%s' "$p" | lower)"
            if [[ -n "$BASELINE" ]]; then
                if [[ -z "${base[$tl]+x}" ]]; then added=$((added + 1)); printf '%s\n' "$f" >> "$CAND"
                elif [[ "${base[$tl]}" != "$s" ]]; then changed=$((changed + 1)); printf '%s\n' "$f" >> "$CAND"; fi
            else
                # sans reference : ce qui est hors de \Windows, plus les scripts / raccourcis / infos textes de \Windows\System32
                case "$tl" in
                    windows/*)
                        case "$tl" in windows/system32/*.cmd|windows/system32/*.bat|windows/system32/*.vbs|windows/system32/*.ps1|windows/system32/*.ini|windows/system32/*.url|windows/system32/*.reg) printf '%s\n' "$f" >> "$CAND" ;; esac ;;
                    *) outside=$((outside + 1)); printf '%s\n' "$f" >> "$CAND" ;;
                esac
            fi
        done < <(list_tree "$t")
    done
    n="$(wc -l < "$CAND")"
    if [[ -n "$BASELINE" ]]; then
        finding INFO P060 "Comparaison avec la référence : ${added} fichier(s) ajouté(s), ${changed} modifié(s)" "$(head -8 "$CAND" | sed "s|^$W/||" | tr '\n' ' ')" ""
    else
        finding INFO P060 "Sans référence (--baseline) : ${outside} fichier(s) hors de \\Windows examinés + scripts de System32" "utilisez --make-baseline sur un WinPE propre pour isoler exactement ce que l'éditeur a ajouté" ""
    fi
    if [[ "$n" -gt "$MAX_FILES" ]]; then
        head -"$MAX_FILES" "$CAND" > "$CAND.cut"; mv "$CAND.cut" "$CAND"
        finding INFO P060 "Analyse limitée aux ${MAX_FILES} premiers fichiers sur ${n}" "relancez avec --max-files ${n}" ""
    fi
    # Filtrage : on ne cherche pas de mots d'affiliation dans les ruches (traitees par P020), dans les fichiers de
    # donnees de \Windows, ni dans les binaires qui se DECLARENT Microsoft. Attention : « se declarer » n'est pas
    # « etre signe » (pas de verification Authenticode ici) : le nombre est affiche pour que ce soit visible.
    local kept="$W/cand.kept" nms=0 ndata=0 tl msu
    : > "$kept"; msu="$(utf16 'Microsoft Corporation')"
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        tl="$(printf '%s' "$f" | lower)"
        case "$tl" in */windows/system32/config/*) continue ;; esac
        case "$tl" in
            */windows/*)
                case "$tl" in
                    *.dat|*.resx|*.xsd|*.xml|*.mui|*.nls|*.cat|*.mum|*.manifest|*.ttf|*.fon|*.txt|*.htm|*.html|*.aspx|*.config|*.json|*.msc|*.mof|*.inf|*.png|*.jpg|*.ico|*.bmp|*.gif|*.cur|*.lex|*.dic|*.gpd|*.ppd|*.sdb|*.tlb|*.rc|*.aspx.resx)
                        ndata=$((ndata + 1)); continue ;;
                esac ;;
        esac
        if [[ "$(head -c 2 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == "4d5a" ]] && LC_ALL=C grep -aqP -- "$msu" "$f" 2>/dev/null; then nms=$((nms + 1)); continue; fi
        printf '%s\n' "$f" >> "$kept"
    done < "$CAND"
    mv "$kept" "$CAND"
    [[ $nms -gt 0 || $ndata -gt 0 ]] && finding INFO P060 "Exclus des indicateurs : ${nms} binaire(s) qui se déclarent « Microsoft Corporation » (signature NON vérifiée), ${ndata} fichier(s) de données de \\Windows" "un binaire peut mentir sur son éditeur : le contrôle Authenticode reste à faire à part" ""
    # installateurs embarques : signatures d'archives auto-extractibles / MSI (OLE)
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        case "$(printf '%s' "$f" | lower)" in *.msi) finding MEDIUM PI00 "Paquet MSI embarqué" "$(basename "$f")" "$(relany "$f")"; continue ;; esac
    done < "$CAND"
}

# ---------------------------------------------------------------------------------------------- P070 indicateurs, P080 domaines
utf16() { printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE 2>/dev/null | od -An -v -tx1 | tr -d ' \n' | sed 's/../\\x&/g'; }
declare -A HIT=()          # ID -> premiere preuve (pour l'escalade)
p070() {
    [[ -s "$IND" ]] || { finding INFO P070 "Indicateurs non chargés" "pe_audit_indicators.txt introuvable" ""; return; }
    local sev typ id pat lab f n hits seen
    local -A once=()
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        line="${line%$'\r'}"
        sev="${line%% :: *}"; rest="${line#* :: }"; typ="${rest%% :: *}"; rest="${rest#* :: }"
        id="${rest%% :: *}"; rest="${rest#* :: }"; pat="${rest%% :: *}"; lab="${rest#* :: }"
        [[ -n "$id" && -n "$pat" ]] || continue
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            n=""
            if [[ "$typ" == kw ]]; then
                if LC_ALL=C grep -aqF -- "$pat" "$f" 2>/dev/null; then n="UTF-8"
                else
                    u="$(utf16 "$pat")"
                    [[ -n "$u" ]] && LC_ALL=C grep -aqP -- "$u" "$f" 2>/dev/null && n="UTF-16"
                fi
                [[ -n "$n" ]] && hits="mot « ${pat} » (${n})"
            else
                hits="$( { strings -a -n 6 "$f" 2>/dev/null; strings -a -el -n 6 "$f" 2>/dev/null; } | grep -Eio -- "$pat" 2>/dev/null | head -1)"
                [[ -n "$hits" ]] && n=1
            fi
            if [[ -n "$n" ]]; then
                [[ -n "${once[$id:${f}]+x}" ]] && continue; once[$id:$f]=1
                # au plus 3 fichiers cites par indicateur
                seen="${HIT_COUNT[$id]:-0}"; HIT_COUNT[$id]=$((seen + 1))
                HIT[$id]="${HIT[$id]:-$hits}"
                [[ "$seen" -lt 3 ]] && finding "$sev" "$id" "$lab" "$hits" "$(relany "$f")"
            fi
        done < "$CAND"
        [[ "${HIT_COUNT[$id]:-0}" -gt 3 ]] && finding INFO "$id" "$lab : ${HIT_COUNT[$id]} fichiers au total (3 cités)" "" ""
    done < "$IND"
    # escalade : affiliation + (installateur ou identifiant d'affiliation dans une URL) => mecanisme probable
    if [[ -n "${HIT[PA01]:-}${HIT[PA02]:-}${HIT[PA03]:-}" ]] && [[ -n "${HIT[PI01]:-}${HIT[PU01]:-}" ]]; then
        finding HIGH PA00 "Mécanisme d'affiliation probable : mots d'affiliation/promotion + installateur ou identifiant de canal dans une URL" "${HIT[PA03]:-${HIT[PA01]:-${HIT[PA02]}}} ; ${HIT[PI01]:-${HIT[PU01]}}" ""
    fi
}
declare -A HIT_COUNT=()
p080() {
    local allow='(^|\.)(microsoft|windows|windowsupdate|live|msn|office|bing|w3|digicert|verisign|globalsign|sectigo|usertrust|entrust|symcb|symcd|thawte|apache|gnu|frippery|github|openssl|mozilla|sourceforge|nirsoft|sysinternals|python|iana|example|localhost|localdomain)\.(com|org|net|info|gov|edu)$|^(localhost)$'
    local f d list
    list="$( while IFS= read -r f; do [[ -f "$f" ]] && { strings -a -n 8 "$f" 2>/dev/null; strings -a -el -n 8 "$f" 2>/dev/null; } ; done < "$CAND" | grep -Eio 'https?://[A-Za-z0-9.-]+' | sed 's|^[a-zA-Z]*://||' | lower | sort | uniq -c | sort -rn | grep -Ev "$allow" | head -40)"
    [[ -n "$list" ]] && finding INFO P080 "Domaines cités par les fichiers examinés (hors liste de confiance)" "$(awk '{printf "%s(%s) ", $2, $1}' <<<"$list" | head -c 280)" ""
}

# ---------------------------------------------------------------------------------------------- execution
p010; p020; p030; p040; p050; p060; p070; p080

# ---------------------------------------------------------------------------------------------- rapport
NH=$(awk -F'\t' '$1=="HIGH"' "$FIND" | wc -l); NM=$(awk -F'\t' '$1=="MEDIUM"' "$FIND" | wc -l); NI=$(awk -F'\t' '$1=="INFO"' "$FIND" | wc -l)
REPORT="$W/report.txt"
{
    echo "=============================================================="
    echo "  SONAR-SE - AUDIT STATIQUE D'UN WINPE TIERS"
    echo "=============================================================="
    echo "Source     : $SRC"
    if [[ -n "$BASELINE" ]]; then echo "Référence  : $BASELINE"; else echo "Référence  : (aucune - sans --baseline l analyse est moins précise)"; fi
    echo "Mode       : lecture seule, rien n'a été exécuté"
    echo
    if [[ $NH -gt 0 ]]; then echo "VERDICT : INDICATEURS FORTS ($NH) — ne pas mettre ce WinPE sur une clé de dépannage client avant examen."
    elif [[ $NM -gt 0 ]]; then echo "VERDICT : À EXAMINER ($NM point(s)) — des éléments méritent un contrôle humain."
    else echo "VERDICT : aucun indicateur détecté par ces contrôles statiques."
         echo "          Cela ne prouve PAS que le WinPE est sain : code chiffré, obfusqué ou téléchargé plus tard échappe à une analyse statique."; fi
    echo
    for s in HIGH MEDIUM INFO; do
        [[ "$(awk -F'\t' -v s=$s '$1==s' "$FIND" | wc -l)" -gt 0 ]] || continue
        echo "--- $s ------------------------------------------------------------"
        awk -F'\t' -v s=$s '$1==s {printf "[%s] %s\n      preuve : %s\n", $2, $3, ($4==""?"-":$4); if ($5 != "") printf "      dans   : %s\n", $5}' "$FIND"
        echo
    done
    echo "Limites : heuristiques (tools/pe_audit_indicators.txt) ; un indicateur n'est pas une preuve, une absence n'est pas un blanc-seing."
} > "$REPORT"
cat "$REPORT"
if [[ -n "$OUT" ]]; then mkdir -p "$OUT" && cp "$REPORT" "$OUT/pe_audit_report.txt" && cp "$FIND" "$OUT/pe_audit_findings.tsv" && say "Rapport : $OUT/pe_audit_report.txt"; fi
[[ $NH -gt 0 ]] && exit 20
[[ $NM -gt 0 ]] && exit 10
exit 0
