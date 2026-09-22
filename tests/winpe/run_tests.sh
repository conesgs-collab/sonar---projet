#!/bin/bash
# Tests de tools/winpe/sonar_check_awk.sh (garde-fou avant d'utiliser un moteur awk pris sur une cle) et des
# garanties statiques du menu WinPE (build). La logique du menu elle-meme, sur un vrai cmd.exe, est dans
# tests/winpe/test_menu_diag_sources.ps1 (Windows uniquement).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="${DIR}/../../tools/winpe/sonar_check_awk.sh"
ENGINE="${DIR}/../../tools/diag_engine.awk"
PS1="${DIR}/../../tools/Build-SonarSE-WinPE.ps1"
fails=0
ok()   { printf 'PASS\t%s\n' "$1"; }
ko()   { printf 'FAIL\t%s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }
[[ -f "$G" ]] || { ko "WinPE : sonar_check_awk.sh present"; exit "$fails"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

check "WinPE garde awk : le VRAI moteur du diagnostic est accepte (code 0)"        'sh "$G" "$ENGINE"'
check "WinPE garde awk : un fichier illisible -> code 2"                           'sh "$G" "$T/absent.awk"; [[ $? -eq 2 ]]'
check "WinPE garde awk : sans argument -> code 2"                                  'sh "$G"; [[ $? -eq 2 ]]'
printf 'BEGIN { if (a > b || c) print "ok"; while ((getline l < F) > 0) n++ }\n' > "$T/ok.awk"
check "WinPE garde awk : comparaisons, || et getline < fichier acceptes"           'sh "$G" "$T/ok.awk"'
printf 'BEGIN { printf "[%%s | confiance %%d] a > b\\n", x, y }\n' > "$T/okstr.awk"
check "WinPE garde awk : un | ou > DANS un texte affiche n'est pas une redirection" 'sh "$G" "$T/okstr.awk"'
n=0
for body in 'BEGIN { system("calc.exe") }' 'BEGIN { "whoami" | getline u }' 'BEGIN { print "x" | "cmd /c del c:\\*" }' \
            'BEGIN { print "x" > "C:/Windows/evil.txt" }' 'BEGIN { printf "x" >> "f" }' 'BEGIN { system ( "x" ) }'; do
    n=$((n + 1)); printf '%s\n' "$body" > "$T/bad$n.awk"
    check "WinPE garde awk : moteur malveillant n.$n refuse (code 1)"               'sh "$G" "$T/bad$n.awk"; [[ $? -eq 1 ]]'
done

# --- garanties statiques du build (le menu genere est teste sur cmd.exe par le script .ps1)
check "WinPE build : le menu cherche la cle sur D: a Z: (C: et X: exclus)"          '_fk="$(grep -A6 "\":findkey\"" "$PS1")"; grep -q "for %%d in (D E F G H I J K L M N O P Q R S T U V W Y Z)" <<<"$_fk" && ! grep -q "for %%d in (C D E" <<<"$_fk"'
check "WinPE build : la copie integree reste le repli (les 3 fichiers sont toujours embarques)" 'grep -q "\"sonar_diag_winpe.sh\"" "$PS1" && grep -q "\"diag_engine.awk\"" "$PS1" && grep -q "\"diag_rules.txt\"" "$PS1" && grep -q "\"sonar_check_awk.sh\"" "$PS1"'
check "WinPE build : le moteur pris sur la cle passe par le garde-fou"              'grep -q "sonar_check_awk.sh" "$PS1" && grep -q "goto diagsrc_refused" "$PS1"'
check "WinPE build : l'origine est affichee ET consignee dans le rapport"           'grep -q "echo    regles : %RULSRC%" "$PS1" && grep -q "Sources : regles = %RULSRC%" "$PS1"'
check "WinPE build : la commande awk utilise ENGF/RULF (plus de chemin integre en dur)" 'grep -q "awk -f .\"%ENGF%" "$PS1" && grep -q "RULES=%RULF%" "$PS1"'
check "WinPE build : clavier AZERTY francais par defaut (wpeutil SetKeyboardLayout 040c:0000040c)" 'grep -q "wpeutil SetKeyboardLayout 040c:0000040c" "$PS1"'
check "WinPE build : le clavier est applique a une NOUVELLE console (attente puis relance gardee par SONAR_RELAUNCH, wpeinit une seule fois)" '_l="$(grep -n "if defined SONAR_RELAUNCH goto sonar_start" "$PS1" | head -1 | cut -d: -f1)"; [[ -n "$_l" ]] && [[ "$(sed -n "$((_l + 1))p" "$PS1")" == *\"wpeinit\"* ]] && grep -q "ping -n 6 127.0.0.1" "$PS1" && grep -q "start .*SONAR - SE.* /wait cmd /c" "$PS1"'
check "WinPE build : titre de fenetre SONAR et banniere SONAR (plus de marque generique a l'accueil)" 'grep -q "\"title SONAR - SE\"" "$PS1" && grep -q "sonar_banner.txt" "$PS1" && grep -q "Assistant guide" "$PS1"'
check "WinPE build : l'assistant et sa banniere sont embarques, et l'ISO finale est verifiee pour eux" 'grep -q "\"sonar_assistant.sh\"  = " "$PS1" && grep -q "sonar.sonar_assistant.sh" "$PS1"'
check "WinPE build : le menu manuel reste (option 18 relance l'assistant, texte verifie par le build conserve)" 'grep -q "goto assistant" "$PS1" && grep -q "SONAR-SE WinPE - Menu de reparation" "$PS1"'
check "WinPE build : resolution native forcee (highestmode), dans la meme boucle BCD que bootuxdisabled (donc sur les DEUX magasins BIOS et UEFI)" '_l1="$(grep -n "bootuxdisabled yes" "$PS1" | head -1 | cut -d: -f1)"; _l2="$(grep -n "highestmode yes" "$PS1" | head -1 | cut -d: -f1)"; [[ -n "$_l1" && -n "$_l2" && $((_l2 - _l1)) -ge 1 && $((_l2 - _l1)) -le 12 ]] && grep -q "foreach (\$bcd in \$bcdPaths)" "$PS1"'
check "WinPE build : analyse antivirus (option 19) prise sur la cle, refuse sans base de signatures, lecture seule" 'grep -q "if \`\"%choix%\`\"==\`\"19\`\" goto av_scan" "$PS1" && grep -q "\":av_scan\"" "$PS1" && grep -q "sonar-clamscan.cmd" "$PS1" && grep -q "AVHAVE" "$PS1" && grep -q "Ne modifie ni ne supprime rien" "$PS1"'
check "WinPE build : outils portables (option 15) en liste NUMEROTEE, plus de chemin complet a taper" 'grep -q "Numero de l.outil a lancer" "$PS1" && grep -q ":tools_show" "$PS1" && grep -q ":tools_pick" "$PS1" && ! grep -q "Chemin complet de l.outil a lancer" "$PS1"'
# CrystalDiskInfo/Mark et autres outils avec ressources externes (CdiResource\...) plantent a l'ouverture si
# lances sans etre positionnes dans LEUR propre dossier (start herite sinon de X:\Windows\System32) - trouve
# sur materiel reel (fenetre visible puis fermeture immediate), 2026-09-22.
check "WinPE build : outils portables (option 15) lances depuis LEUR propre dossier (start /D), pas X:\\Windows\\System32" 'grep -q "start \`\"\`\" /D \`\"%TDIR%\`\" \`\"%TPATH%\`\"" "$PS1" && grep -q "set \`\"TDIR=%%~dpd\`\"" "$PS1"'
check "WinPE build : image systeme DISM (option 20) capture ET restaure, confirmation avant ecrasement" 'grep -q "if \`\"%choix%\`\"==\`\"20\`\" goto clone_menu" "$PS1" && grep -q "Dism /Capture-Image" "$PS1" && grep -q "Dism /Apply-Image" "$PS1" && grep -q "sera REMPLACE" "$PS1" && grep -q "Clonezilla" "$PS1"'
# cmd.exe "set /p var=" ne vide PAS var sur un Entree vide (garde sa valeur precedente si var a deja servi dans
# CE boot) : tout "set /p" dont la valeur est ensuite comparee (retour menu sur vide, ou confirmation o/n / OUI)
# doit etre precede d'un "set var=" pour qu'un Entree vide soit bien vu comme vide, sinon une confirmation ou un
# choix precedents peuvent se rejouer silencieusement (decouvert sur tchoix/cchoix/clettre/cimg cette session,
# puis retrouve preexistant sur cible/espvol/inf/rep/go/confirm en auditant tout le fichier pour le meme piege).
for _v in tchoix cchoix clettre cimg cible espvol inf rep go confirm; do
    check "WinPE build : set /p ${_v} est precede d'un 'set ${_v}=' (Entree vide ne doit pas rejouer l'ancienne valeur)" \
        "grep -B1 \"set /p ${_v}=\" \"\$PS1\" | grep -q \"\\\"set ${_v}=\\\"\""
done
# l'assistant lui-meme (etapes proposees, refus par defaut, cle BitLocker jamais journalisee) : suite dediee
_ao="$(bash "${DIR}/run_assistant_tests.sh" 2>&1)"; _arc=$?
printf '%s\n' "$_ao"
fails=$((fails + _arc))
exit "$fails"
