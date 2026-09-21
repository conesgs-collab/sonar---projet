#!/bin/sh
# sonar_check_awk.sh — garde-fou du WinPE SONAR-SE avant d'utiliser un moteur awk pris SUR UNE CLE.
#
# Un programme awk est du CODE : il peut lancer des commandes (system, "cmd" | getline, print | "cmd")
# et ecrire des fichiers (print > "fichier"). Le WinPE tourne en administrateur sur la machine du client,
# et les lettres de lecteur D: a Z: peuvent porter n'importe quel support (une cle USB du client, un disque
# externe). Le moteur du diagnostic, lui, ne fait que LIRE (getline < fichier) et ecrire sur la sortie
# standard : tout ce qui execute ou ecrit est donc refuse, et le WinPE retombe sur son moteur integre.
#
# C'est un filtre STATIQUE sur des jetons litteraux (awk n'a ni eval ni include) : il arrete un moteur
# malveillant ecrit naivement, pas un adversaire qui aurait deja la main sur la cle SONAR-SE. Les REGLES
# (diag_rules.txt) sont des donnees, pas du code : elles n'ont pas besoin de ce controle.
#
# Usage : sh sonar_check_awk.sh FICHIER.awk     ->  0 acceptable | 1 refuse | 2 illisible
f="$1"
[ -n "$f" ] && [ -r "$f" ] || exit 2
# Le contenu des chaines litterales est neutralise d'abord ("..." -> "") : un "|" ou un ">" DANS un texte
# affiche (printf "[%s | confiance %d%%]") n'est pas une redirection ; sans cela le moteur reel etait refuse.
if sed 's/"[^"]*"/""/g' "$f" 2>/dev/null | grep -Eq 'system[[:space:]]*\(|\|[[:space:]]*getline|(print|printf)[^;{}]*[^|]\|[^|]|(print|printf)[^;{}]*[^<=>!-]>[^=]'; then
    exit 1
fi
exit 0
