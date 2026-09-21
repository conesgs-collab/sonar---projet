#!/bin/bash
# Tests de tools/winpe/sonar_assistant.sh : l'assistant WinPE enchaine les etapes, le technicien valide ou refuse.
#
# Les outils Windows (manage-bde, bcdboot, diskpart, robocopy, sfc, chkdsk, drvload, wpeutil) sont remplaces par des
# STUBS qui enregistrent l'appel : on verifie QUOI serait lance, dans QUEL ordre, et surtout ce qui ne l'est PAS.
# Le moteur de diagnostic et les regles sont les vrais ; les faits sont fabriques (SONAR_ASSIST_FACTS).
# Ce n'est pas un WinPE : voir CHANGELOG pour ce qui reste a verifier avec une vraie clé.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="${DIR}/../../tools/winpe/sonar_assistant.sh"
ENGINE="${DIR}/../../tools/diag_engine.awk"
RULES="${DIR}/../../tools/diag_rules.txt"
fails=0
ok()   { printf 'PASS\t%s\n' "$1"; }
ko()   { printf 'FAIL\t%s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }
[[ -f "$A" ]] || { ko "Assistant : sonar_assistant.sh present"; exit "$fails"; }
command -v sh >/dev/null 2>&1 || { printf 'WARN\tAssistant : sh absent\n'; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STUBS="$T/stubs"; mkdir -p "$STUBS"
for c in manage-bde bcdboot diskpart robocopy sfc chkdsk drvload wpeutil; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "$CALLS"\n[ "%s" = diskpart ] && [ "$1" = "/s" ] && { echo "  [diskpart-script] $(tr "\\n" ";" < "$2")" >> "$CALLS"; }\nexit 0\n' "$c" "$c" > "$STUBS/$c"
    chmod +x "$STUBS/$c"
done

check "Assistant : syntaxe sh valide"                                        'sh -n "$A"'

# ---- faits fabriques
# 1) demarrage casse : UEFI, Windows sur C:, ESP (v2) sans bootmgfw ni BCD
cat > "$T/f_boot.facts" <<'EOF'
sys.collector=winpe
sys.diag_root=yes
sys.firmware=uefi
sys.secureboot=on
sys.vendor=HP
sys.product=EliteBook 840 G3
disk.d0.model=TOSHIBA MQ01ABD100V
disk.d0.tran=sata
part.v1.fstype=NTFS
part.v1.letter=C
part.v1.size_gb=237
part.v1.is_esp=no
part.v1.bitlocker=no
part.v1.has_windows=yes
part.v1.free_pct=40
part.v2.fstype=FAT32
part.v2.size_gb=1
part.v2.is_esp=yes
part.v2.bootmgfw=no
part.v2.bcd=no
part.v2.bitlocker=no
win.partitions=1
esp.count=1
EOF
# 2) disque chiffre BitLocker sur D:
cat > "$T/f_bl.facts" <<'EOF'
sys.collector=winpe
sys.diag_root=yes
sys.firmware=uefi
part.v1.fstype=NTFS
part.v1.letter=D
part.v1.is_esp=no
part.v1.bitlocker=yes
part.v2.fstype=FAT32
part.v2.is_esp=yes
part.v2.bootmgfw=yes
part.v2.bcd=yes
part.v2.bitlocker=no
win.partitions=0
esp.count=1
EOF
# 3) deux Windows (C: et E:)
sed 's/^win.partitions=1/win.partitions=2/' "$T/f_boot.facts" > "$T/f_two.facts"
printf 'part.v3.fstype=NTFS\npart.v3.letter=E\npart.v3.is_esp=no\npart.v3.bitlocker=no\npart.v3.has_windows=yes\n' >> "$T/f_two.facts"

# run FACTS "reponses" -> $T/out.txt ; CALLS enregistre ; KEY=$T/key
run() {   # run facts answers [key]
    local facts="$1" answers="$2" key="${3-$T/key}"
    rm -rf "$T/out" "$T/key"; mkdir -p "$T/out" "$T/key/Field-Logs" "$T/key/Drivers"; : > "$T/calls.txt"
    printf '%b' "$answers" | env CALLS="$T/calls.txt" PATH="$STUBS:$PATH" SONAR_KEY="$key" SONAR_SB="$T" SONAR_ENGINE="$ENGINE" SONAR_RULES="$RULES" \
        SONAR_OUT="$T/out" SONAR_ASSIST_FACTS="$facts" TEMP="$T" sh "$A" > "$T/out.txt" 2>&1
    RC=$?
}
calls() { cat "$T/calls.txt"; }
logf() { cat "$T"/out/ASSIST_*.log 2>/dev/null; }

# ---- A. le technicien refuse tout : RIEN ne doit etre lance
run "$T/f_boot.facts" '1\nn\nn\nn\nn\nn\n'
check "Assistant : symptome + diagnostic sans accord requis, rapport et TSV produits"   '[[ -n "$(find "$T/out" -name 'ASSIST_*.txt' -size +0)" && -n "$(find "$T/out" -name 'ASSIST_*.tsv' -size +0)" ]] && grep -q "Score de sante" "$T/out.txt"'
check "Assistant : tout refuse -> AUCUN outil modifiant n'est lance"                    '[[ ! -s "$T/calls.txt" ]]'
check "Assistant : tout refuse -> les refus sont journalises (NON)"                     'logf | grep -q "DECISION BOOT_UEFI = NON" && logf | grep -q "DECISION SAUVEGARDE = NON"'
check "Assistant : rend la main au menu (code 0)"                                       '[[ $RC -eq 0 ]] && grep -q "Retour au menu manuel" "$T/out.txt"'

# ---- B. aucune reponse (entree vide / fin de saisie) : les etapes qui modifient sont refusees PAR DEFAUT
run "$T/f_boot.facts" '1\n'
check "Assistant : sans reponse, rien qui MODIFIE n'est lance (defaut = non)"           '[[ ! -s "$T/calls.txt" ]]'

# ---- C. reparation du demarrage acceptee, le reste refuse
run "$T/f_boot.facts" '1\nn\no\nn\nn\n'
check "Assistant : constat B00x -> reparation UEFI proposee, preparee automatiquement" 'grep -q "Reparer le demarrage UEFI" "$T/out.txt" && grep -q "volume 2" "$T/out.txt" && grep -q "C:.Windows" "$T/out.txt"'
check "Assistant : bcdboot lance sur le bon Windows et le bon ESP (C:\\Windows -> S:, UEFI)" 'calls | grep -q "^bcdboot C:.Windows /s S: /f UEFI"'
check "Assistant : lettre temporaire donnee a l'ESP (volume 2) PUIS retiree"             'calls | grep -q "select volume 2;assign letter=S" && calls | grep -q "select volume 2;remove letter=S"'
check "Assistant : l'ordre est respecte (assign, bcdboot, remove)"                        '[[ "$(calls | grep -nE "assign letter|^bcdboot|remove letter" | cut -d: -f1 | tr "\n" " ")" == "2 3 5 " || "$(calls | grep -cE "assign letter|^bcdboot|remove letter")" -eq 3 ]]'
check "Assistant : la sauvegarde refusee n'est PAS lancee"                               '! calls | grep -q "^robocopy"'
check "Assistant : la decision OUI est journalisee"                                      'logf | grep -q "DECISION BOOT_UEFI = OUI" && logf | grep -q "BOOT_UEFI bcdboot rc=0"'
check "Assistant : apres une modification, propose le redemarrage (non par defaut)"      'grep -q "Redemarrer maintenant" "$T/out.txt" && ! calls | grep -q "^wpeutil reboot"'

# ---- D. sauvegarde acceptee : vers la cle, sans AppData, avant la reparation
run "$T/f_boot.facts" '1\no\nn\nn\nn\n'
check "Assistant : sauvegarde proposee AVANT la reparation (donnees d'abord)"            '[[ "$(grep -n "ETAPE.*Sauvegarde" "$T/out.txt" | cut -d: -f1)" -lt "$(grep -n "ETAPE.*Reparation du demarrage" "$T/out.txt" | cut -d: -f1)" ]]'
check "Assistant : robocopy C:\\Users -> cle\\Recovery\\<date>\\Users, /XJ, sans AppData" 'calls | grep -qE "^robocopy C:.Users .*Recovery.*Users /E /R:1 /W:1 /XJ /XD AppData"'

# ---- E. plusieurs Windows : le technicien choisit, l'assistant ne devine pas
run "$T/f_two.facts" '1\nE\nn\no\nn\nn\n'
check "Assistant : deux Windows -> demande laquelle, utilise le choix (E:)"              'grep -q "Plusieurs installations Windows" "$T/out.txt" && calls | grep -q "^bcdboot E:.Windows /s S: /f UEFI"'
run "$T/f_two.facts" '1\n\nn\nn\nn\nn\n'
check "Assistant : deux Windows, pas de choix -> aucune etape sur un Windows devine"     '! calls | grep -qE "^(bcdboot|robocopy|sfc|chkdsk)"'

# ---- F. BitLocker : cle saisie, jamais journalisee
K="123456-234567-345678-456789-567890-678901-789012-890123"
run "$T/f_bl.facts" "7\no\n$K\nn\n"
check "Assistant : volume chiffre detecte et propose en premier"                         'grep -q "ETAPE 3 : Volume(s) chiffre(s) BitLocker" "$T/out.txt" && grep -q "D: est chiffre" "$T/out.txt"'
check "Assistant : manage-bde -unlock D: -RecoveryPassword <cle formatee>"                'calls | grep -q "^manage-bde -unlock D: -RecoveryPassword $K"'
check "Assistant : la cle n'apparait NI dans le journal NI dans le rapport NI a l'ecran" '! grep -rq "123456-234567" "$T/out" && ! grep -q "123456" "$T/out.txt"'
run "$T/f_bl.facts" "7\no\n123456-abc\nn\n"
check "Assistant : cle au mauvais format -> rien n'est tente"                             '! calls | grep -q "^manage-bde"'
run "$T/f_bl.facts" "7\nn\nn\n"
check "Assistant : deverrouillage refuse -> manage-bde non lance"                         '! calls | grep -q "^manage-bde"'
run "$T/f_bl.facts" "7\no\n${K//-/}\nn\n"
check "Assistant : cle saisie SANS tirets acceptee et remise en forme"                    'calls | grep -q "^manage-bde -unlock D: -RecoveryPassword $K"'

# ---- G. pas de cle : pas de sauvegarde possible, dit clairement
run "$T/f_boot.facts" '1\nn\nn\nn\n' ""
check "Assistant : sans cle SONAR, la sauvegarde n'est pas proposee et le motif est dit" 'grep -q "Aucune cle SONAR-SE detectee : pas de destination" "$T/out.txt" && ! calls | grep -q "^robocopy"'

# ---- H. symptomes que WinPE ne traite pas : renvoi vers SystemRescue, aucune action
run "$T/f_boot.facts" '5\n'
check "Assistant : symptome virus -> renvoi vers SystemRescue (ClamAV), aucune action WinPE"  'grep -q "SystemRescue" "$T/out.txt" && grep -q "ClamAV" "$T/out.txt"'

# ---- I. mode d'emploi rappele et lecture seule annoncee
check "Assistant : annonce clairement lecture seule = automatique, modification = accord"  'grep -q "LECTURE SEULE se fait tout seul" "$T/out.txt" && grep -q "non par defaut" "$T/out.txt"'
exit "$fails"
