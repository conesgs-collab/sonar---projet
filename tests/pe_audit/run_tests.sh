#!/bin/bash
# Tests de tools/sonar_pe_audit.sh (audit statique d'un WinPE tiers).
# Arbres de test FABRIQUES ici (aucun binaire tiers, aucune vraie edition d'un PE d'affiliation n'est analysee).
# Sortie : PASS/FAIL/WARN ; code retour = nombre d'echecs.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PA="${DIR}/../../tools/sonar_pe_audit.sh"
fails=0
ok()   { printf 'PASS\t%s\n' "$1"; }
ko()   { printf 'FAIL\t%s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }
[[ -f "$PA" ]] || { ko "PE audit : sonar_pe_audit.sh present"; exit "$fails"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v strings >/dev/null 2>&1 || { printf 'WARN\tPE audit : strings (binutils) absent, tests ignores\n'; exit 0; }

check "PE audit : syntaxe bash valide"                              'bash -n "$PA"'
check "PE audit : une option sans valeur ne boucle pas (regression shift 2)" 'timeout 10 bash "$PA" --baseline >/dev/null 2>&1; [[ $? -ne 124 ]]'
check "PE audit : sans source -> usage, code 2"                     'bash "$PA" >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "PE audit : source introuvable -> code 2"                     'bash "$PA" "$T/absent" >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "PE audit : le fichier d'indicateurs est present et lisible"  '[[ "$(grep -Evc "^[[:space:]]*(#|$)" "${DIR}/../../tools/pe_audit_indicators.txt")" -ge 15 ]]'

# --- arbre propre
mkdir -p "$T/clean/Windows/System32"
printf '@echo off\nwpeinit\n' > "$T/clean/Windows/System32/startnet.cmd"
R="$(bash "$PA" "$T/clean" 2>/dev/null)"; rc=$?
check "PE audit : arbre propre -> code 0"                           '[[ $rc -eq 0 ]]'
check "PE audit : jamais « sain » : le verdict rappelle la limite de l'analyse statique" 'grep -q "ne prouve PAS" <<<"$R" && ! grep -qi "verdict : sain" <<<"$R"'

# --- arbre piege (ISO d'affiliation simulee)
B="$T/bad"; mkdir -p "$B/Windows/System32/drivers/etc" "$B/Windows/System32/Tasks" "$B/Tools" "$B/Users/Public/Desktop"
printf '@echo off\nwpeinit\nstart http://portail.example.cn/?unionid=9911\nD:\\Tools\\promo_setup.exe /S\n' > "$B/Windows/System32/startnet.cmd"
printf '127.0.0.1 localhost\n1.2.3.4 update.microsoft.com.example\n' > "$B/Windows/System32/drivers/etc/hosts"
printf '<Task><Actions><Exec><Command>C:\\Tools\\promo.exe</Command><Arguments>/silent</Arguments></Exec></Actions></Task>\n' > "$B/Windows/System32/Tasks/Updater"
printf '[InternetShortcut]\nURL=http://www.2345.com/?31234\n' > "$B/Users/Public/Desktop/Chrome.url"
{ printf 'MZ fake\nNullsoft Install System v3.08\n'; printf '联盟 推广\n'; printf 'schtasks /create /tn X\n'; printf 'http://track.example.cn/a?channel=88123\n'; iconv -f UTF-8 -t UTF-16LE <<<'总裁联盟'; } > "$B/Tools/promo_setup.exe"
R="$(bash "$PA" "$B" --out "$T/out_bad" 2>/dev/null)"; rc=$?
check "PE audit : arbre piege -> code 20 (indicateurs forts)"        '[[ $rc -eq 20 ]]'
check "PE audit : demarrage : adresse web + identifiant d'affiliation (P010)" 'grep -q "\[P010\] Le script de démarrage ouvre" <<<"$R" && grep -q "unionid=9911" <<<"$R"'
check "PE audit : programme lance depuis un autre lecteur (P010, MEDIUM)"  'grep -q "situé hors du système" <<<"$R"'
check "PE audit : fichier hosts modifie (P040)"                      'grep -q "\[P040\]" <<<"$R"'
check "PE audit : tache planifiee embarquee (P030)"                  'grep -q "\[P030\]" <<<"$R"'
check "PE audit : raccourci Internet (P050)"                         'grep -q "\[P050\]" <<<"$R"'
check "PE audit : mots chinois trouves en UTF-8 ET en UTF-16 (PA01..PA03)" 'grep -q "\[PA01\]" <<<"$R" && grep -q "\[PA03\].*" <<<"$R" && grep -q "(UTF-16)" <<<"$R" && grep -q "(UTF-8)" <<<"$R"'
check "PE audit : installateur embarque + persistance (PI01, PI02)"  'grep -q "\[PI01\]" <<<"$R" && grep -q "\[PI02\]" <<<"$R"'
check "PE audit : escalade « mecanisme d'affiliation probable » (PA00, HIGH)" 'grep -q "\[PA00\] Mécanisme d.affiliation probable" <<<"$R"'
check "PE audit : les preuves citent le fichier (chemin relatif a l'arbre)"   'grep -q "dans   : Tools/promo_setup.exe" <<<"$R"'
check "PE audit : le rapport et le TSV sont ecrits par --out"        '[[ -s "$T/out_bad/pe_audit_report.txt" && -s "$T/out_bad/pe_audit_findings.tsv" ]]'

# --- faux positifs connus (corriges apres l'essai sur notre propre WinPE) : un mot chinois dans un fichier de donnees
#     de \Windows ne doit pas declencher ; un binaire qui se declare Microsoft est exclu (et compte)
F="$T/fp"; mkdir -p "$F/Windows/System32" "$F/Windows/Globalization"
printf 'wpeinit\n' > "$F/Windows/System32/startnet.cmd"
printf 'donnees ICU 联盟 dictionnaire\n' > "$F/Windows/Globalization/icudtl.dat"
{ printf 'MZ'; iconv -f UTF-8 -t UTF-16LE <<<'Microsoft Corporation'; printf 'StartPage schtasks /create\n'; } > "$F/Windows/System32/faux.dll"
mkdir -p "$T/fpbase/Windows/System32"; printf 'wpeinit\n' > "$T/fpbase/Windows/System32/startnet.cmd"
bash "$PA" --make-baseline "$T/fpbase.tsv" "$T/fpbase" >/dev/null 2>&1
R="$(bash "$PA" "$F" --baseline "$T/fpbase.tsv" 2>/dev/null)"; rc=$?
check "PE audit : mot chinois dans un fichier de donnees de \\Windows -> pas de faux positif" '[[ $rc -eq 0 ]] && ! grep -q "\[PA01\]" <<<"$R" && ! grep -q "\[PH03\]" <<<"$R"'
check "PE audit : le nombre de binaires « se declarant Microsoft » est affiche (verification non faite)" 'grep -q "signature NON vérifiée" <<<"$R"'

# --- reference : seuls les fichiers AJOUTES sont examines
mkdir -p "$T/base/Windows/System32"; printf 'x' > "$T/base/Windows/System32/a.dll"
bash "$PA" --make-baseline "$T/base.tsv" "$T/base" >/dev/null 2>&1
check "PE audit : --make-baseline cree une reference chemin+taille"  '[[ -s "$T/base.tsv" ]] && grep -q "windows/system32/a.dll\|Windows/System32/a.dll" "$T/base.tsv"'
V="$T/vendor"; mkdir -p "$V/Windows/System32"; printf 'x' > "$V/Windows/System32/a.dll"; printf 'MZ Nullsoft Install System 联盟 ?unionid=5\n' > "$V/Windows/System32/vendor_tool.exe"
R="$(bash "$PA" "$V" --baseline "$T/base.tsv" 2>/dev/null)"
check "PE audit : avec reference, le fichier ajoute par l'editeur est signale"   'grep -q "1 fichier(s) ajouté(s)" <<<"$R" && grep -q "vendor_tool.exe" <<<"$R" && grep -q "\[PA00\]" <<<"$R"'
exit "$fails"
