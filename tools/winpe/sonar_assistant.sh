#!/bin/sh
# sonar_assistant.sh — SONAR-SE WinPE : assistant de depannage AUTOMATIQUE, le technicien valide ou refuse.
#
# Au lieu d'un menu de 17 outils a choisir et a enchainer soi-meme, l'assistant :
#   1. demande le SYMPTOME (une seule question) ;
#   2. inventorie la machine et pose le DIAGNOSTIC tout seul (lecture seule, aucun accord requis) ;
#   3. en deduit les etapes utiles et les PROPOSE une a une, avec ce qu'elle fait et ce qu'elle modifie ;
#      le technicien repond oui ou non. Chaque etape est preparee : lettre du Windows, volume de l'ESP, cle
#      SONAR, destination de sauvegarde sont trouves automatiquement ;
#   4. journalise chaque decision (etape, oui/non, code retour) — jamais la cle BitLocker.
#
# Regles :
#   - une etape qui MODIFIE quelque chose (BitLocker, reparation du demarrage, sfc, pilotes, sauvegarde vers la cle)
#     est refusee par DEFAUT (o/N) : sans reponse claire, rien n'est fait ; une simple lecture est acceptee par defaut ;
#   - rien n'est jamais lance sans avoir dit ce qu'il allait faire ;
#   - le menu manuel reste disponible (l'assistant rend la main a la fin).
#
# Environnement fourni par startnet.cmd : SONAR_KEY (ex. E:), SONAR_SB, SONAR_ENGINE, SONAR_RULES, SONAR_OUT.
# Tests : SONAR_ASSIST_FACTS = fichier de faits pre-fabrique (au lieu du collecteur WinPE).
KEY="${SONAR_KEY:-}"
SB="${SONAR_SB:-.}"
ENGINE="${SONAR_ENGINE:-$SB/diag_engine.awk}"
RULES="${SONAR_RULES:-$SB/diag_rules.txt}"
OUT="${SONAR_OUT:-${TEMP:-/tmp}}"
STAMP="$(date +%Y%m%d_%H%M%S)"
FACTS="$OUT/ASSIST_$STAMP.facts"
TSV="$OUT/ASSIST_$STAMP.tsv"
REPORT="$OUT/ASSIST_$STAMP.txt"
LOG="$OUT/ASSIST_$STAMP.log"
TMPD="${TEMP:-${TMP:-/tmp}}"
SYMPTOM=""; STEP=0; WINL=""; MODIFIED=0
mkdir -p "$OUT" 2>/dev/null

say()  { printf '%s\n' "$*"; }
log()  { printf '%s\t%s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }
log "SOURCES regles=${SONAR_RULSRC:-?} ; moteur=${SONAR_ENGSRC:-?}"
step() { STEP=$((STEP + 1)); say ""; say "=== ETAPE $STEP : $1"; }

# yn "question" d|n   (d = Oui par defaut : lecture seule ; n = Non par defaut : modifie quelque chose)
yn() {
    _def="$2"
    while :; do
        if [ "$_def" = d ]; then _p="(O/n)"; else _p="(o/N)"; fi
        printf '%s %s : ' "$1" "$_p"
        read -r _a || _a=""
        case "$_a" in
            o|O|y|Y|oui|OUI|Oui) return 0 ;;
            n|N|non|NON|Non)     return 1 ;;
            "") [ "$_def" = d ] && return 0 || return 1 ;;
        esac
        say "  Repondez o (oui) ou n (non)."
    done
}

# decide "ID_ETAPE" "question" d|n : pose la question, journalise la reponse, renvoie 0 si oui
decide() {
    if yn "$2" "$3"; then log "DECISION $1 = OUI"; return 0; fi
    log "DECISION $1 = NON"; say "  -> etape ignoree."; return 1
}

fact() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$FACTS" 2>/dev/null; }
meta() { awk -F'\t' -v k="#$1" '$1 == k { print $2 }' "$TSV" 2>/dev/null; }
has_id() { awk -F'\t' -v id="$1" '!/^#/ && $4 == id { f = 1 } END { exit !f }' "$TSV" 2>/dev/null; }

# tableau des volumes : v|lettre|fs|esp|bitlocker|windows|etat
vol_table() {
    awk -F= '
        $1 ~ /^part\.v[0-9]+\./ { split($1, a, "."); v = a[2]; k = a[3]; val = $0; sub(/^[^=]*=/, "", val); d[v, k] = val; seen[v] = 1 }
        END { for (v in seen) printf "%s|%s|%s|%s|%s|%s|%s\n", v, d[v,"letter"], d[v,"fstype"], d[v,"is_esp"], d[v,"bitlocker"], d[v,"has_windows"], d[v,"fs_state"] }
    ' "$FACTS" 2>/dev/null | sort
}

collect() {
    if [ -n "${SONAR_ASSIST_FACTS:-}" ]; then cp "$SONAR_ASSIST_FACTS" "$FACTS"
    else sh "$SB/sonar_diag_winpe.sh" "$FACTS" >/dev/null 2>&1; fi
    awk -f "$ENGINE" -v "FACTS=$FACTS" -v "RULES=$RULES" -v "SYMPTOM=$SYMPTOM" -v MODE=tsv > "$TSV" 2>/dev/null
    awk -f "$ENGINE" -v "FACTS=$FACTS" -v "RULES=$RULES" -v "SYMPTOM=$SYMPTOM" -v MODE=report > "$REPORT" 2>/dev/null
}

summary() {
    say "  Machine : $(fact sys.vendor) $(fact sys.product)   Firmware : $(fact sys.firmware)   Secure Boot : $(fact sys.secureboot)"
    say "  Score de sante : $(meta SCORE)/100   Domaine principal : $(meta VERDICT)"
    awk -F'\t' '!/^#/ && n < 6 { n++; printf "   - [%s] %s\n", $2, $7 }' "$TSV"
    say "  (WinPE : ni SMART ni journaux Windows ne sont mesures ; rapport complet : $REPORT)"
}

pick_windows() {
    WINL=""; _n=0; _list=""
    vol_table > "$TMPD/sonar_vols_a.txt"
    while IFS='|' read -r _v _l _fs _esp _bl _win _st <&4; do
        [ "$_win" = yes ] && [ -n "$_l" ] && { _n=$((_n + 1)); _list="$_list $_l"; }
    done 4< "$TMPD/sonar_vols_a.txt"
    rm -f "$TMPD/sonar_vols_a.txt"
    case "$_n" in
        0) return ;;
        1) WINL="${_list# }"; return ;;
    esac
    say "  Plusieurs installations Windows detectees :$_list"
    while :; do
        printf '  Sur laquelle travailler ? (lettre) : '
        read -r _c || _c=""
        _c="$(printf '%s' "$_c" | tr 'a-z' 'A-Z' | cut -c1)"
        case " $_list " in *" $_c "*) WINL="$_c"; return ;; esac
        [ -z "$_c" ] && return    # pas de reponse : on ne choisit pas a la place du technicien
        say "  Lettre non valable."
    done
}

# ---------------------------------------------------------------------------------------------- deroule
say ""
say "  L'assistant enchaine les etapes ; vous n'avez qu'a repondre oui ou non."
say "  Ce qui est en LECTURE SEULE se fait tout seul ; ce qui MODIFIE quelque chose vous est demande (non par defaut)."
[ -n "$KEY" ] && say "  Cle SONAR-SE : $KEY   -   journal : $LOG" || say "  Cle SONAR-SE non detectee : le journal et le rapport restent dans $OUT (perdus au redemarrage)."
log "ASSISTANT debut cle=${KEY:-aucune}"

step "Symptome"
say "  1) La machine ne demarre plus / demarre mal     2) Ecran bleu / plantages    3) Tres lente"
say "  4) Donnees perdues ou inaccessibles             5) Virus / comportement suspect"
say "  6) Mot de passe Windows perdu                   7) Autre / je ne sais pas"
printf '  Choix [7] : '
read -r _s || _s=""
case "$_s" in 1) SYMPTOM=boot ;; 2) SYMPTOM=bsod ;; 3) SYMPTOM=slow ;; 4) SYMPTOM=data ;; 5) SYMPTOM=virus ;; 6) SYMPTOM=password ;; *) SYMPTOM=other ;; esac
log "SYMPTOME $SYMPTOM"

step "Inventaire et diagnostic (automatique, lecture seule)"
say "  Collecte des disques, volumes, ESP/BCD, BitLocker, firmware..."
collect
summary

# --- BitLocker : d'abord, car un volume verrouille rend les etapes suivantes aveugles
vol_table > "$TMPD/sonar_vols_b.txt"
_bl_any=0
while IFS='|' read -r _v _l _fs _esp _bl _win _st <&4; do
    [ "$_bl" = yes ] && [ -n "$_l" ] && _bl_any=1
done 4< "$TMPD/sonar_vols_b.txt"
if [ "$_bl_any" = 1 ]; then
    step "Volume(s) chiffre(s) BitLocker"
    while IFS='|' read -r _v _l _fs _esp _bl _win _st <&4; do
        [ "$_bl" = yes ] && [ -n "$_l" ] || continue
        say "  Le volume $_l: est chiffre (BitLocker) : il est illisible tant qu'il n'est pas deverrouille."
        say "  Action : manage-bde -unlock $_l: avec la cle de recuperation du PROPRIETAIRE. Ne modifie pas le disque."
        if decide "BITLOCKER_$_l" "  Deverrouiller $_l: ?" n; then
            if ! command -v manage-bde >/dev/null 2>&1; then say "  manage-bde est absent de cette image : utilisez SystemRescue (SONAR Field, option b)."; continue; fi
            printf '  Cle de recuperation (48 chiffres, tirets acceptes) : '
            read -r -s _k || read -r _k || _k=""
            say ""
            _k="$(printf '%s' "$_k" | tr -d ' -')"
            if [ "${#_k}" -eq 48 ] && ! printf '%s' "$_k" | grep -q '[^0-9]'; then
                _k="$(printf '%s' "$_k" | sed 's/\(......\)/\1-/g; s/-$//')"
                manage-bde -unlock "$_l:" -RecoveryPassword "$_k"; _rc=$?
                log "BITLOCKER_UNLOCK $_l rc=$_rc"; MODIFIED=1
            else
                say "  Format invalide (48 chiffres attendus) : rien n'a ete tente."; log "BITLOCKER_UNLOCK $_l format-invalide"
            fi
            _k=""
        fi
    done 4< "$TMPD/sonar_vols_b.txt"
    rm -f "$TMPD/sonar_vols_b.txt"
    say "  Nouvelle lecture des volumes..."
    collect
    summary
else
    rm -f "$TMPD/sonar_vols_b.txt"
fi

pick_windows
if [ -n "$WINL" ]; then say ""; say "  Windows cible : $WINL:\\Windows"; log "WINDOWS_CIBLE $WINL"
else say ""; say "  Aucun Windows lisible detecte sur les disques."; fi

_fragile=0
for _i in D001 D002 D003 D005 D006 D008 D009; do has_id "$_i" && _fragile=1; done

# --- Pilotes de stockage : aucun Windows visible et des pilotes sur la cle
if [ -z "$WINL" ] && [ -n "$KEY" ] && [ -n "$(find "$KEY/Drivers" -name '*.inf' 2>/dev/null | head -1)" ]; then
    step "Pilotes de stockage"
    say "  Aucun Windows visible : un controleur (NVMe / Intel VMD-RST / RAID) manque peut-etre au WinPE."
    say "  Action : charger les pilotes (.inf) de $KEY\\Drivers dans ce WinPE (drvload) puis relire les disques. Rien n'est ecrit sur le disque."
    if decide "PILOTES" "  Charger les pilotes de la cle ?" n; then
        find "$KEY/Drivers" -name '*.inf' 2>/dev/null | while read -r _f; do drvload "$_f"; done
        printf 'rescan\n' > "$TMPD/sonar_dp_rescan.txt"; diskpart /s "$TMPD/sonar_dp_rescan.txt" >/dev/null 2>&1
        log "PILOTES charges"; MODIFIED=1
        collect; pick_windows; summary
        [ -n "$WINL" ] && say "  Windows cible : $WINL:\\Windows"
    fi
fi

# --- Sauvegarde AVANT toute reparation (donnees en danger ou symptome lie aux donnees)
if [ -n "$WINL" ]; then
    if [ "$_fragile" = 1 ] || [ "$SYMPTOM" = data ] || [ "$SYMPTOM" = boot ] || [ "$SYMPTOM" = bsod ]; then
        step "Sauvegarde des fichiers utilisateur"
        if [ -z "$KEY" ]; then
            say "  Aucune cle SONAR-SE detectee : pas de destination pour la sauvegarde (branchez-la puis relancez l'assistant)."
        else
            say "  Action : copier $WINL:\\Users vers $KEY\\Recovery\\$STAMP\\Users (robocopy, sans les dossiers AppData)."
            say "  Ne modifie pas le disque du client. Place libre sur la cle : $(df -k "$KEY/" 2>/dev/null | awk 'NR==2 {printf "%d Mo", $4/1024}')"
            [ "$_fragile" = 1 ] && say "  ATTENTION : le disque montre des signes de defaillance. Pour un disque mourant, preferez l'IMAGERIE sous Linux (SystemRescue : sonar_recover.sh image) avant de lire davantage."
            if decide "SAUVEGARDE" "  Lancer la sauvegarde ?" n; then
                robocopy "$WINL:\\Users" "$KEY\\Recovery\\$STAMP\\Users" /E /R:1 /W:1 /XJ /XD AppData /NP /NFL /NDL /LOG+:"$OUT/ASSIST_${STAMP}_robocopy.log"
                _rc=$?
                if [ "$_rc" -ge 8 ]; then say "  Sauvegarde terminee AVEC ERREURS (code $_rc) : voir le journal."; else say "  Sauvegarde terminee (code $_rc)."; fi
                log "SAUVEGARDE rc=$_rc"
            fi
        fi
    fi
fi

# --- Reparation du demarrage UEFI
_esp_v=""
vol_table > "$TMPD/sonar_vols_c.txt"
while IFS='|' read -r _v _l _fs _esp _bl _win _st <&4; do
    [ "$_esp" = yes ] && [ -z "$_esp_v" ] && _esp_v="${_v#v}"
done 4< "$TMPD/sonar_vols_c.txt"
rm -f "$TMPD/sonar_vols_c.txt"
_boot_needed=0
for _i in B001 B002 B003 B004; do has_id "$_i" && _boot_needed=1; done
[ "$SYMPTOM" = boot ] && _boot_needed=1
if [ -n "$WINL" ] && [ "$_boot_needed" = 1 ]; then
    step "Reparation du demarrage"
    if [ "$(fact sys.firmware)" = uefi ] && [ -n "$_esp_v" ]; then
        say "  Constat : $(awk -F'\t' '!/^#/ && $4 ~ /^B00[1-4]$/ {print $7; exit}' "$TSV")"
        say "  Action : reconstruire les fichiers de demarrage (bootmgfw.efi + BCD) de l'ESP (volume $_esp_v) a partir de $WINL:\\Windows"
        say "           (bcdboot). Ne touche PAS aux donnees. Une lettre temporaire est donnee a l'ESP puis retiree."
        if decide "BOOT_UEFI" "  Reparer le demarrage UEFI ?" n; then
            _sl=""
            for _c in S T U V W Y Z; do [ -d "$_c:/" ] || { _sl="$_c"; break; }; done
            if [ -z "$_sl" ]; then say "  Aucune lettre libre pour l'ESP : abandon."; log "BOOT_UEFI aucune-lettre"
            else
                printf 'select volume %s\nassign letter=%s\n' "$_esp_v" "$_sl" > "$TMPD/sonar_dp_esp1.txt"
                diskpart /s "$TMPD/sonar_dp_esp1.txt" >/dev/null 2>&1
                bcdboot "$WINL:\\Windows" /s "$_sl:" /f UEFI; _rc=$?
                printf 'select volume %s\nremove letter=%s\n' "$_esp_v" "$_sl" > "$TMPD/sonar_dp_esp2.txt"
                diskpart /s "$TMPD/sonar_dp_esp2.txt" >/dev/null 2>&1
                log "BOOT_UEFI bcdboot rc=$_rc esp=$_esp_v"; MODIFIED=1
                [ "$_rc" -eq 0 ] && say "  Demarrage reconstruit. Redemarrez pour verifier." || say "  bcdboot a echoue (code $_rc)."
            fi
        fi
    else
        say "  Firmware BIOS/CSM ou ESP introuvable : la reparation automatique n'est faite que pour UEFI."
        say "  Utilisez le menu manuel, option 1 (bootrec)."
    fi
fi

# --- Systeme de fichiers arrete brutalement : controle en LECTURE SEULE
if [ -n "$WINL" ] && has_id F001; then
    step "Verification du systeme de fichiers (lecture seule)"
    say "  $WINL: a ete arrete brutalement. Action : chkdsk $WINL: SANS reparation (aucun /f). Ne modifie rien."
    if decide "CHKDSK" "  Lancer la verification ?" d; then chkdsk "$WINL:"; log "CHKDSK rc=$?"; fi
fi

# --- Fichiers systeme (modifie : repare)
if [ -n "$WINL" ] && { [ "$SYMPTOM" = boot ] || [ "$SYMPTOM" = bsod ]; }; then
    step "Fichiers systeme Windows"
    say "  Action : sfc /scannow hors ligne sur $WINL:\\Windows. Peut REMPLACER des fichiers systeme corrompus et durer longtemps."
    if decide "SFC" "  Lancer sfc ?" n; then sfc /scannow "/offbootdir=$WINL:\\" "/offwindir=$WINL:\\Windows"; log "SFC rc=$?"; MODIFIED=1; fi
fi

# --- Ce que WinPE ne fait pas
case "$SYMPTOM" in
    virus)    step "Analyse antivirale"; say "  Le WinPE n'a pas d'antivirus hors ligne. Demarrez SystemRescue depuis la cle (profil malware : ClamAV, disque en lecture seule)." ;;
    password) step "Mot de passe Windows"; say "  Demarrez SystemRescue (profil password-reset). Un accord ecrit du proprietaire de l'appareil est necessaire." ;;
esac

step "Fin"
say "  Rapport : $REPORT"
say "  Journal des decisions : $LOG"
log "ASSISTANT fin modifie=$MODIFIED"
if [ "$MODIFIED" = 1 ]; then
    if decide "REDEMARRAGE" "  Redemarrer maintenant pour verifier ?" n; then wpeutil reboot; fi
fi
say "  Retour au menu manuel."
exit 0
