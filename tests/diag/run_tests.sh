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

# --- fins de ligne Windows (CRLF) : meme resultat (regression : "uefi\r" != "uefi")
_crlf="$(mktemp)"; sed 's/$/\r/' "${DIR}/no_esp.facts" > "$_crlf"
_crlf_rules="$(mktemp)"; sed 's/$/\r/' "${DIR}/../../tools/diag_rules.txt" > "$_crlf_rules"
check "Diag : faits en CRLF -> meme rapport qu'en LF" '[[ "$(bash "$DIAG" --analyze "$_crlf" --symptom boot --tsv 2>/dev/null | md5sum)" == "$(tsv no_esp boot | md5sum)" ]]'
check "Diag : regles en CRLF -> meme rapport qu'en LF" '[[ "$(bash "$DIAG" --analyze "${DIR}/no_esp.facts" --rules "$_crlf_rules" --symptom boot --tsv 2>/dev/null | md5sum)" == "$(tsv no_esp boot | md5sum)" ]]'
rm -f "$_crlf" "$_crlf_rules"

# --- IA : moteur local injoignable -> repli propre, sans blocage
check "Diag : --ai avec Ollama injoignable -> repli sans blocage (< 20 s)" 'start=$(date +%s); out="$(SONAR_AI_URL=http://127.0.0.1:9/api/generate bash "$DIAG" --analyze "${DIR}/healthy.facts" --ai 2>&1)"; [[ $(( $(date +%s) - start )) -lt 20 ]] && grep -q "injoignable" <<<"$out" && grep -q "commentaire IA indisponible" <<<"$out" && grep -q "SCORE DE SANTE" <<<"$out"'

# --- garde-fous de l'IA : moteur non local refuse
check "Diag : --ai refuse un moteur distant" '[[ "$(SONAR_AI_URL=http://exemple.invalid:11434/api/generate bash "$DIAG" --analyze "${DIR}/healthy.facts" --ai 2>&1 | grep -c "seul un moteur Ollama LOCAL")" -ge 1 ]]'

exit "$fails"
