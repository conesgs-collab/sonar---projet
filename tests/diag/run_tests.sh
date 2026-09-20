#!/bin/bash
# Tests du moteur de diagnostic intelligent (tools/sonar_diag.sh --analyze).
# Sortie : une ligne PASS/FAIL par verification ; code retour = nombre d'echecs.
# Chaque scenario (*.facts) est un jeu de faits construit a la main : le moteur
# est deterministe, donc le resultat attendu est exact.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIAG="${DIR}/../../tools/sonar_diag.sh"
fails=0

ok()   { printf 'PASS\t%s\n' "$1"; }
ko()   { printf 'FAIL\t%s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

tsv()    { bash "$DIAG" --analyze "${DIR}/$1.facts" --tsv ${2:+--symptom "$2"} 2>/dev/null; }
report() { bash "$DIAG" --analyze "${DIR}/$1.facts" ${2:+--symptom "$2"} 2>/dev/null; }
field()  { awk -F'\t' -v id="$2" '$4==id {print $'"$3"'}' <<<"$1" | head -1; }
meta()   { awk -F'\t' -v k="#$2" '$1==k {print $2}' <<<"$1"; }

[[ -f "$DIAG" ]] || { ko "sonar_diag.sh present"; exit "$fails"; }

# --- base de regles saine
T="$(tsv healthy)"
check "Diag : aucune regle invalide dans diag_rules.txt" '[[ "$(meta "$T" BADRULES)" == "0" ]]'
check "Diag : la base contient au moins 30 regles"        '(( $(meta "$T" RULES) >= 30 ))'

# --- machine saine : silence et 100/100
check "Diag : machine saine -> aucun constat"  '[[ -z "$(awk -F"\t" "\$1 !~ /^#/" <<<"$T")" ]]'
check "Diag : machine saine -> score 100"      '[[ "$(meta "$T" SCORE)" == "100" ]]'

# --- disque mourant : le plus grave d'abord, correlation, plan sans doublon
T="$(tsv failing_disk boot)"; R="$(report failing_disk boot)"
check "Diag : SMART FAILED -> D001 est le constat n.1 (CRITICAL)" '[[ "$(awk -F"\t" "NR==1 {print \$2\"/\"\$4}" <<<"$T")" == "CRITICAL/D001" ]]'
check "Diag : D001 renforce par 3 indices concordants (confiance >= 95)" '(( $(field "$T" D001 3) >= 95 ))'
check "Diag : verdict = Disque"               '[[ "$(meta "$T" VERDICT)" == "Disque" ]]'
check "Diag : score critique (< 40)"          '(( $(meta "$T" SCORE) < 40 ))'
check "Diag : preuves listees pour D001"      'grep -q "disk.sda.smart_overall=FAILED" <<<"$T"'
check "Diag : mise en garde chkdsk/fsck"      'grep -q "Ne PAS lancer chkdsk" <<<"$R"'
check "Diag : plan = une seule etape data-recovery (pas de doublon)" '[[ "$(grep -c "\[profil data-recovery\]" <<<"$(sed -n "/PLAN D.ACTION/,/A NE PAS FAIRE/p" <<<"$R")")" == "1" ]]'
check "Diag : libelle critique"               'grep -q "(critique)" <<<"$R"'
check "Diag : symptome signale ajoute +10 a D002 (lie au symptome)" 'grep -q "lie au symptome signale" <<<"$R"'

# --- meme faits => meme rapport (determinisme)
check "Diag : deterministe (2 executions identiques)" '[[ "$(report failing_disk boot | md5sum)" == "$(report failing_disk boot | md5sum)" ]]'

# --- ESP absente : demarrage, aucun accuse a tort le disque
T="$(tsv no_esp boot)"
check "Diag : ESP absente -> B001 (HIGH)"     '[[ "$(field "$T" B001 2)" == "HIGH" ]]'
check "Diag : verdict = Demarrage"            '[[ "$(meta "$T" VERDICT)" == "Demarrage" ]]'
check "Diag : disque sain non accuse (aucun constat D0xx)" '! awk -F"\t" "\$4 ~ /^D0/ {f=1} END {exit !f}" <<<"$T"'
check "Diag : (controle du test) un constat D0xx est bien detecte sur le disque mourant" 'awk -F"\t" "\$4 ~ /^D0/ {f=1} END {exit !f}" <<<"$(tsv failing_disk boot)"'
check "Diag : profil boot-repair recommande"  '[[ "$(field "$T" B001 11)" == "boot-repair" ]]'

# --- BitLocker : jamais rassurant
T="$(tsv bitlocker boot)"; R="$(report bitlocker boot)"
check "Diag : BitLocker -> F003 (HIGH)"       '[[ "$(field "$T" F003 2)" == "HIGH" ]]'
check "Diag : BitLocker -> libelle non rassurant" '! grep -q "bon etat apparent" <<<"$R"'
check "Diag : BitLocker -> ne pas reinitialiser le TPM" 'grep -q "TPM" <<<"$R"'

# --- ecrans bleus : materiel
T="$(tsv memory_bsod bsod)"
check "Diag : machine-check -> M001 est le n.1"   '[[ "$(awk -F"\t" "NR==1 {print \$4}" <<<"$T")" == "M001" ]]'
check "Diag : verdict = Materiel"                '[[ "$(meta "$T" VERDICT)" == Materiel* ]]'
check "Diag : batterie usee detectee (M006)"     '[[ -n "$(field "$T" M006 4)" ]]'
check "Diag : preuves sans doublon (battery.health_pct une fois)" '[[ "$(grep -o "battery.health_pct=" <<<"$(field "$T" M006 8)" | wc -l)" == "1" ]]'

# --- sans root : jamais conclu a tort
T="$(tsv partial_noroot)"; R="$(report partial_noroot)"
check "Diag : sans root -> D999 signale"          '[[ -n "$(field "$T" D999 4)" ]]'
check "Diag : sans root -> NON CONCLUANT (pas 'bon etat')" 'grep -q "NON CONCLUANT" <<<"$R" && ! grep -q "bon etat apparent" <<<"$R"'

# --- portabilite du moteur : meme rapport sous gawk, mawk et busybox awk.
# (busybox awk = celui du WinPE SONAR-SE ; mawk = awk par defaut de Debian)
ENGINE="${DIR}/../../tools/diag_engine.awk"
ref_run() { $1 -f "$ENGINE" -v FACTS="${DIR}/$2.facts" -v RULES="${DIR}/../../tools/diag_rules.txt" -v SYMPTOM="$3" -v MODE="$4" 2>&1; }
for _alt in "mawk" "busybox awk"; do
    _bin="${_alt%% *}"
    if command -v "$_bin" >/dev/null 2>&1; then
        _ok=true
        for _sc in "failing_disk boot" "no_esp boot" "bitlocker boot" "memory_bsod bsod" "healthy"; do
            set -- $_sc
            [[ "$(ref_run "awk" "$1" "${2:-}" report | md5sum)" == "$(ref_run "$_alt" "$1" "${2:-}" report | md5sum)" ]] || _ok=false
            [[ "$(ref_run "awk" "$1" "${2:-}" tsv | md5sum)" == "$(ref_run "$_alt" "$1" "${2:-}" tsv | md5sum)" ]] || _ok=false
        done
        $_ok && ok "Diag : moteur identique sous '$_alt' (5 scenarios, rapport + tsv)" || ko "Diag : sortie DIFFERENTE sous '$_alt'"
    else
        printf 'WARN\tDiag : %s absent, compatibilite non verifiee\n' "$_alt"
    fi
done

# --- fins de ligne Windows (CRLF) : meme resultat (regression : "uefi\r" != "uefi")
_crlf="$(mktemp)"; sed 's/$/\r/' "${DIR}/no_esp.facts" > "$_crlf"
_crlf_rules="$(mktemp)"; sed 's/$/\r/' "${DIR}/../../tools/diag_rules.txt" > "$_crlf_rules"
check "Diag : faits en CRLF -> meme rapport qu'en LF" '[[ "$(bash "$DIAG" --analyze "$_crlf" --symptom boot --tsv 2>/dev/null | md5sum)" == "$(tsv no_esp boot | md5sum)" ]]'
check "Diag : regles en CRLF -> meme rapport qu'en LF" '[[ "$(bash "$DIAG" --analyze "${DIR}/no_esp.facts" --rules "$_crlf_rules" --symptom boot --tsv 2>/dev/null | md5sum)" == "$(tsv no_esp boot | md5sum)" ]]'
rm -f "$_crlf" "$_crlf_rules"


# --- collecte WinPE : le rapport ne rassure jamais sur ce qu'il n'a pas mesure
T="$(tsv winpe boot)"; R="$(report winpe boot)"
check "Diag : WinPE -> S010 signale les limites (SMART/journaux)" '[[ -n "$(field "$T" S010 4)" ]]'
check "Diag : WinPE -> jamais 'bon etat apparent'"             '! grep -q "bon etat apparent" <<<"$R" && grep -q "SMART/materiel non evalues" <<<"$R"'
check "Diag : WinPE -> la cle SONAR-SE n'est pas analysee comme volume client" '! grep -q "part.v4" "${DIR}/winpe.facts"'

# ============================================================================
# RAPPORT CLIENT (--client-report) : phrases pretes, jamais rassurant a tort, PDF signe
# ============================================================================
CT="$(mktemp -d)"
export SONAR_DIAG_NOW="2026-09-20T12:00:00Z" SONAR_KEY_DIR=""
TPL="${DIR}/../../tools/client_templates.txt"
crt() {   # crt SCENARIO [SYMPTOME] -> texte client sur stdout ; PDF/txt dans $CT/$1
    local sc="$1" sy="${2:-}"; mkdir -p "$CT/$sc"
    bash "$DIAG" --client-report "${DIR}/${sc}.facts" --out "$CT/$sc" --format txt ${sy:+--symptom "$sy"} >/dev/null 2>&1
    cat "$CT/$sc/${sc}_client.txt" 2>/dev/null
}

# --- base de phrases complete : chaque profil x chaque gravite
_miss=""
for _p in data-recovery boot-repair hardware-diagnostic disk-clone malware password-reset general; do
    for _s in CRITICAL HIGH MEDIUM INFO; do
        grep -q "^${_p} :: ${_s} :: " "$TPL" || _miss="$_miss ${_p}/${_s}"
    done
done
check "Client : chaque profil a une phrase pour chaque gravite (28 cellules)${_miss:+ [manque :$_miss]}" '[[ -z "$_miss" ]]'
_vmiss=""; for _v in sain surveiller degrade critique partiel winpe; do grep -q "^_VERDICT :: ${_v} :: " "$TPL" || _vmiss="$_vmiss $_v"; done
check "Client : les 6 verdicts globaux sont ecrits${_vmiss:+ [manque :$_vmiss]}" '[[ -z "$_vmiss" ]]'
# tout profil utilise par une regle du moteur doit avoir ses phrases
_rp="$(awk -F' :: ' '!/^#/ && NF>5 && $10 != "-" {print $10}' "${DIR}/../../tools/diag_rules.txt" | sort -u)"
_pm=""; for _p in $_rp; do grep -q "^${_p} :: CRITICAL :: " "$TPL" || _pm="$_pm $_p"; done
check "Client : tout profil cite par diag_rules.txt a ses phrases${_pm:+ [manque :$_pm]}" '[[ -z "$_pm" ]]'

# --- le bon verdict pour chaque situation, et jamais rassurant a tort
R="$(crt failing_disk boot)"
check "Client : disque mourant -> verdict critique"                    'grep -q "risque sérieux de panne" <<<"$R"'
check "Client : disque mourant -> sauvegarde d abord dans les recommandations" 'grep -qi "fichiers" <<<"$R" && grep -q "Éteignez" <<<"$R"'
check "Client : aucun jargon technique dans le rapport client"        '! grep -Eqi "smart|sda|nvme|bcdedit|/dev/|\bGPT\b|\bESP\b|disk\.|fsck|chkdsk" <<<"$R"'
check "Client : renvoie le detail au technicien"                       'grep -q "détail technique reste chez le technicien" <<<"$R"'
R="$(crt healthy)"
check "Client : machine saine -> verdict sain"                         'grep -q "aucun signe de panne" <<<"$R"'
R="$(crt no_esp boot)"
check "Client : ESP absente -> demarrage a reparer, sans effacer les donnees" 'grep -q "sans effacer vos données" <<<"$R"'
R="$(crt bitlocker boot)"
check "Client : BitLocker -> demande la cle de recuperation"          'grep -q "clé de récupération de 48 chiffres" <<<"$R"'
R="$(crt partial_noroot)"
check "Client : diagnostic partiel -> jamais 'aucun signe de panne'"  '! grep -q "aucun signe de panne" <<<"$R" && grep -q "qu.en partie" <<<"$R"'
R="$(crt winpe boot)"
check "Client : WinPE -> jamais 'aucun signe de panne'"               '! grep -q "aucun signe de panne" <<<"$R" && grep -q "n.a pas pu être mesuré" <<<"$R"'
# un constat critique l'emporte sur "partiel" : on ne cache jamais un disque mourant
sed 's/^sys.diag_root.*/sys.diag_root\tno/' "${DIR}/failing_disk.facts" > "$CT/fd_noroot.facts"
grep -q '^sys.diag_root' "$CT/fd_noroot.facts" || printf 'sys.diag_root\tno\n' >> "$CT/fd_noroot.facts"
cp "$CT/fd_noroot.facts" "${CT}/fdn.facts"
R="$(bash "$DIAG" --client-report "${CT}/fdn.facts" --out "$CT/fdn" --format txt --symptom boot >/dev/null 2>&1; cat "$CT/fdn/fdn_client.txt" 2>/dev/null)"
check "Client : disque mourant + partiel -> reste CRITIQUE (jamais masque)" 'grep -q "risque sérieux de panne" <<<"$R"'

# --- deterministe
_a="$(SONAR_DIAG_NOW=2026-09-20T12:00:00Z bash "$DIAG" --client-report "${DIR}/failing_disk.facts" --out "$CT/da" --symptom boot >/dev/null 2>&1; md5sum < "$CT/da/failing_disk_client.pdf")"
_b="$(SONAR_DIAG_NOW=2026-09-20T12:00:00Z bash "$DIAG" --client-report "${DIR}/failing_disk.facts" --out "$CT/db" --symptom boot >/dev/null 2>&1; md5sum < "$CT/db/failing_disk_client.pdf")"
check "Client : PDF deterministe (memes faits + meme instant => memes octets)" '[[ -n "$_a" && "$_a" == "$_b" ]]'

# --- structure du PDF : en-tete, fin, table xref exacte
PDF="$CT/da/failing_disk_client.pdf"
pdf_check() {
    local f="$1" off n i o head
    [[ "$(head -c 8 "$f")" == "%PDF-1.4" ]] || return 1
    tail -c 6 "$f" | grep -q '%%EOF' || return 1
    off="$(tail -c 60 "$f" | awk '/^startxref/ {getline; print; exit}')"
    [[ -n "$off" ]] || return 1
    [[ "$(tail -c +$((off + 1)) "$f" | head -1)" == "xref" ]] || return 1
    n="$(tail -c +$((off + 1)) "$f" | sed -n '2p' | awk '{print $2}')"
    for ((i = 1; i < n; i++)); do
        o="$(tail -c +$((off + 1)) "$f" | sed -n "$((3 + i))p" | awk '{print $1+0}')"
        head="$(tail -c +$((o + 1)) "$f" | head -1)"
        [[ "$head" == "$i 0 obj" ]] || return 1
    done
    return 0
}
check "Client : PDF bien forme (en-tete, %%EOF, chaque decalage xref pointe sur son objet)" 'pdf_check "$PDF"'
if command -v qpdf >/dev/null 2>&1; then
    check "Client : qpdf --check ne trouve aucune erreur"    'qpdf --check "$PDF" >/dev/null 2>&1'
else
    printf 'WARN\tClient : qpdf absent, validation externe du PDF non faite\n'
fi
check "Client : PDF en ASCII pur (accents ecrits en octal, aucun octet >= 128)" '[[ "$(LC_ALL=C tr -d "\000-\177" < "$PDF" | wc -c)" == "0" ]]'
check "Client : accents WinAnsi presents (\\351 = e accent aigu)"          'grep -aq "\\\\351" "$PDF"'

# --- meme PDF sous mawk et busybox awk
for _alt in "mawk" "busybox awk"; do
    _bin="${_alt%% *}"
    if command -v "$_bin" >/dev/null 2>&1; then
        _ok=true
        _fa="$CT/da/failing_disk_client.pdf"
        _fi="$CT/da/../da_findings.tsv"; bash "$DIAG" --analyze "${DIR}/failing_disk.facts" --symptom boot --tsv > "$_fi" 2>/dev/null
        _mk="$CT/alt.mk"
        awk -f "${DIR}/../../tools/client_report.awk" -v FINDINGS="$_fi" -v FACTS="${DIR}/failing_disk.facts" -v TEMPLATES="$TPL" -v FORMAT=markup -v CLIENT=X -v DATE=2026-09-20 -v REF=SE-T > "$_mk"
        _r1="$(LC_ALL=C awk -f "${DIR}/../../tools/text2pdf.awk" -v TITLE=t -v FOOT=f -v PDFDATE=20260920120000 < "$_mk" | md5sum)"
        _r2="$(LC_ALL=C $_alt -f "${DIR}/../../tools/text2pdf.awk" -v TITLE=t -v FOOT=f -v PDFDATE=20260920120000 < "$_mk" | md5sum)"
        _c1="$(LC_ALL=C awk -f "${DIR}/../../tools/client_report.awk" -v FINDINGS="$_fi" -v FACTS="${DIR}/failing_disk.facts" -v TEMPLATES="$TPL" -v FORMAT=txt -v DATE=2026-09-20 | md5sum)"
        _c2="$(LC_ALL=C $_alt -f "${DIR}/../../tools/client_report.awk" -v FINDINGS="$_fi" -v FACTS="${DIR}/failing_disk.facts" -v TEMPLATES="$TPL" -v FORMAT=txt -v DATE=2026-09-20 | md5sum)"
        [[ "$_r1" == "$_r2" && "$_c1" == "$_c2" ]] && ok "Client : rapport et PDF identiques sous '$_alt'" || ko "Client : sortie DIFFERENTE sous '$_alt' (pdf $_r1/$_r2, txt $_c1/$_c2)"
    else
        printf 'WARN\tClient : %s absent, compatibilite non verifiee\n' "$_alt"
    fi
done

# --- filigrane de build : present quand connu, "non disponible" sinon (jamais invente)
printf 'SONAR_BUILD_ID=%s\nSONAR_BUILD_TIMESTAMP=2026-09-14T17:45:56Z\nSONAR_BUILD_OPERATOR=Technician\nSONAR_BUILD_LABEL=IT-TOOLKIT\nSONAR_BUILD_SIGNATURE=%s\n' \
    "59cb9076cf1249f08b35cc5a555d371057e0418f3381a23147c30d3a14441f10" "67ad5358efc866a540b01406151b412328eab165839f97ac40edcea719b22b8f" > "$CT/wm.txt"
bash "$DIAG" --client-report "${DIR}/healthy.facts" --out "$CT/w1" --watermark "$CT/wm.txt" >/dev/null 2>&1
check "Client : le filigrane de build est dans le PDF (id, operateur, signature HMAC)" 'grep -aq "59cb9076cf1249f08b35cc5a555d371057e0418f3381a23147c30d3a14441f10" "$CT/w1/healthy_client.pdf" && grep -aq "Technician" "$CT/w1/healthy_client.pdf" && grep -aq "67ad5358efc866a5" "$CT/w1/healthy_client.pdf"'
check "Client : le filigrane est aussi dans la version texte"                          'grep -q "Build ID *: 59cb9076" "$CT/w1/healthy_client.txt"'
bash "$DIAG" --client-report "${DIR}/healthy.facts" --out "$CT/w2" --watermark "$CT/absent.txt" >/dev/null 2>&1
check "Client : sans filigrane, le sceau le dit (rien d'invente)"                     'grep -aq "non disponible" "$CT/w2/healthy_client.pdf" && ! grep -aq "Build ID" "$CT/w2/healthy_client.pdf"'

# --- signature (openssl) : valide, puis modification detectee
if command -v openssl >/dev/null 2>&1; then
    bash "$DIAG" --sign-keygen "$CT/keys" >/dev/null 2>&1
    check "Client : --sign-keygen cree une cle privee 0600 et une cle publique" '[[ -s "$CT/keys/client_sign.key" && -s "$CT/keys/client_sign.pub.pem" && "$(stat -c %a "$CT/keys/client_sign.key" 2>/dev/null || echo 600)" == "600" ]]'
    check "Client : --sign-keygen refuse d'ecraser une cle existante"           '! bash "$DIAG" --sign-keygen "$CT/keys" >/dev/null 2>&1'
    bash "$DIAG" --client-report "${DIR}/failing_disk.facts" --out "$CT/s1" --symptom boot --watermark "$CT/wm.txt" --sign-key "$CT/keys/client_sign.key" >/dev/null 2>&1
    S="$CT/s1/failing_disk_client.pdf"
    check "Client : PDF signe : .sig et .sha256 crees"                          '[[ -s "$S.sig" && -s "$S.sha256" ]]'
    check "Client : signature valide avec la cle publique (code 0)"             'bash "$DIAG" --verify-client-report "$S" --pubkey "$CT/keys/client_sign.pub.pem" >/dev/null 2>&1'
    check "Client : sans cle publique, l'authenticite n'est PAS declaree verifiee (code 3)" 'bash "$DIAG" --verify-client-report "$S" >/dev/null 2>&1; [[ $? -eq 3 ]]'
    cp "$S" "$CT/tamper.pdf"; cp "$S.sig" "$CT/tamper.pdf.sig"; cp "$S.sha256" "$CT/tamper.pdf.sha256"
    sed -i 's/risque sérieux/RISQUE sérieux/; s/(risque/(RISQUE/' "$CT/tamper.pdf"; printf 'x' >> "$CT/tamper.pdf"
    check "Client : un PDF modifie est refuse (code 1)"                         'bash "$DIAG" --verify-client-report "$CT/tamper.pdf" --pubkey "$CT/keys/client_sign.pub.pem" >/dev/null 2>&1; [[ $? -eq 1 ]]'
    # empreinte recalculee par un faussaire mais signature conservee : la signature echoue
    ( cd "$CT" && sha256sum tamper.pdf > tamper.pdf.sha256 )
    check "Client : empreinte falsifiee + ancienne signature -> refuse (code 1)" 'bash "$DIAG" --verify-client-report "$CT/tamper.pdf" --pubkey "$CT/keys/client_sign.pub.pem" >/dev/null 2>&1; [[ $? -eq 1 ]]'
    bash "$DIAG" --sign-keygen "$CT/keys2" >/dev/null 2>&1
    check "Client : mauvaise cle publique -> refuse (code 1)"                   'bash "$DIAG" --verify-client-report "$S" --pubkey "$CT/keys2/client_sign.pub.pem" >/dev/null 2>&1; [[ $? -eq 1 ]]'
else
    printf 'WARN\tClient : openssl absent, signature non testee\n'
fi
bash "$DIAG" --client-report "${DIR}/healthy.facts" --out "$CT/u1" >/dev/null 2>&1
check "Client : sans cle de signature, le rapport dit clairement NON SIGNE"      'grep -aq "NON SIGNE" "$CT/u1/healthy_client.pdf" && [[ ! -e "$CT/u1/healthy_client.pdf.sig" ]]'
check "Client : sans signature, la verification n'affirme pas l'authenticite (code 3)" 'bash "$DIAG" --verify-client-report "$CT/u1/healthy_client.pdf" >/dev/null 2>&1; [[ $? -eq 3 ]]'
_nm=$'A\\nB\tC'
bash "$DIAG" --client-report "${DIR}/healthy.facts" --out "$CT/n1" --client-name "$_nm" --format txt >/dev/null 2>&1
check "Client : nom du client injecte sans risque (antislash, tabulation)" 'grep -q "^Client : A[n]*BC$" "$CT/n1/healthy_client.txt"'
rm -rf "$CT"; unset SONAR_DIAG_NOW SONAR_KEY_DIR

# --- IA : moteur local injoignable -> repli propre, sans blocage
check "Diag : --ai avec Ollama injoignable -> repli sans blocage (< 20 s)" 'start=$(date +%s); out="$(SONAR_AI_URL=http://127.0.0.1:9/api/generate bash "$DIAG" --analyze "${DIR}/healthy.facts" --ai 2>&1)"; [[ $(( $(date +%s) - start )) -lt 20 ]] && grep -q "injoignable" <<<"$out" && grep -q "commentaire IA indisponible" <<<"$out" && grep -q "SCORE DE SANTE" <<<"$out"'

# --- garde-fous de l'IA : moteur non local refuse
check "Diag : --ai refuse un moteur distant" '[[ "$(SONAR_AI_URL=http://exemple.invalid:11434/api/generate bash "$DIAG" --analyze "${DIR}/healthy.facts" --ai 2>&1 | grep -c "seul un moteur Ollama LOCAL")" -ge 1 ]]'

exit "$fails"
