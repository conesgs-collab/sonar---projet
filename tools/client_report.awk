# client_report.awk — SONAR-SE : rapport CLIENT assemblé à partir du rapport technique.
#
# Aucune IA : ce programme ne fait que CHOISIR des phrases déjà écrites dans
# client_templates.txt, d'après les constats du moteur (findings.tsv). Même
# entrée => même rapport. awk pur (gawk, mawk, busybox awk).
#
# Usage :
#   awk -f client_report.awk -v FINDINGS=findings.tsv -v FACTS=facts.tsv \
#       -v TEMPLATES=client_templates.txt -v FORMAT=markup|txt \
#       [-v CLIENT="Nom"] [-v DATE="2026-09-20"] [-v REF="SE-1A2B3C4D5E"]
#
# FORMAT=markup : lignes "TYPE<TAB>texte" consommées par text2pdf.awk
#   T titre | S sous-titre | K clé<TAB>valeur | V niveau<TAB>texte | H intertitre
#   P paragraphe | B puce | N puce numérotée | G espace
# FORMAT=txt    : texte brut de 76 colonnes (pour un e-mail ou une impression).
#
# Garde-fous (écrits ici, testés dans tests/diag/run_tests.sh) :
#   - un diagnostic PARTIEL (sans root) ou limité (WinPE) n'est JAMAIS présenté comme sain ;
#   - un constat CRITICAL l'emporte toujours sur « partiel » ;
#   - les constats purement informatifs sans profil ne sont pas montrés au client.

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function clean(s) { gsub(/[[:cntrl:]]+$/, "", s); return s }

function wrap(prefix, cont, text,    n, w, i, line, fresh) {
    n = split(text, w, " "); line = prefix; fresh = 1
    for (i = 1; i <= n; i++) {
        if (!fresh && length(line) + length(w[i]) + 1 > 76) { print line; line = cont w[i]; continue }
        line = fresh ? line w[i] : line " " w[i]; fresh = 0
    }
    print line
}

function emit(kind, a, b) {
    if (FORMAT != "txt") { if (b != "") printf "%s\t%s\t%s\n", kind, a, b; else printf "%s\t%s\n", kind, a; return }
    if (kind == "T") { print a; print "=============================================="; return }
    if (kind == "S") { print a; print ""; return }
    if (kind == "K") { print a " : " b; return }
    if (kind == "V") { print ""; wrap("=> ", "   ", b); print ""; return }
    if (kind == "H") { print ""; print a; print "----------------------------------------------"; return }
    if (kind == "P") { wrap("", "", a); return }
    if (kind == "B") { wrap("  * ", "    ", a); return }
    if (kind == "N") { wrap("  " a ". ", "     ", b); return }
    if (kind == "G") { print ""; return }
}

function subst(s) { gsub(/\{machine\}/, MACHINE, s); return s }

BEGIN {
    FS = "\t"
    if (FORMAT == "") FORMAT = "markup"
    sevrank["CRITICAL"] = 4; sevrank["HIGH"] = 3; sevrank["MEDIUM"] = 2; sevrank["INFO"] = 1

    # ---- modèles
    while ((getline line < TEMPLATES) > 0) {
        line = clean(line)
        if (line ~ /^[ \t]*(#|$)/) continue
        n = split(line, p, / :: /)
        if (n < 4) continue
        k = trim(p[1]) SUBSEP trim(p[2])
        tpl_c[k] = trim(p[3]); tpl_r[k] = trim(p[4])
    }
    close(TEMPLATES)
    if (!((("_VERDICT") SUBSEP "sain") in tpl_c)) { print "ERREUR : client_templates.txt illisible ou incomplet : " TEMPLATES > "/dev/stderr"; exit 2 }

    # ---- faits (pour le nom de la machine)
    while ((getline line < FACTS) > 0) {
        line = clean(line)
        if (line ~ /^[ \t]*(#|$)/) continue
        if (index(line, "\t")) { k = substr(line, 1, index(line, "\t") - 1); v = substr(line, index(line, "\t") + 1) }
        else { k = substr(line, 1, index(line, "=") - 1); v = substr(line, index(line, "=") + 1) }
        F[k] = v
    }
    close(FACTS)
    MACHINE = trim(F["sys.vendor"] " " F["sys.product"])
    if (MACHINE == "") MACHINE = "votre appareil"

    # ---- constats du moteur
    nf = 0; score = -1; topsev = 0; partial = 0; winpe = 0
    while ((getline line < FINDINGS) > 0) {
        line = clean(line)
        if (line == "") continue
        m = split(line, c, "\t")
        if (substr(line, 1, 1) == "#") { if (c[1] == "#SCORE") score = c[2] + 0; continue }
        nf++; sev[nf] = c[2]; id[nf] = c[4]; prof[nf] = (c[11] == "" || c[11] == "-") ? "general" : c[11]
        if (sevrank[c[2]] > topsev) topsev = sevrank[c[2]]
        if (c[4] == "D999") partial = 1
        if (c[4] == "S010") winpe = 1
    }
    close(FINDINGS)
    if (score < 0) { print "ERREUR : findings.tsv illisible (pas de ligne #SCORE) : " FINDINGS > "/dev/stderr"; exit 2 }

    # ---- verdict global : le plus sévère d'abord ; jamais rassurant à tort
    if (topsev == 4 || score < 30) { vk = "critique"; lvl = "crit" }
    else if (partial)              { vk = "partiel";  lvl = "partial" }
    else if (score < 60)           { vk = "degrade";  lvl = "bad" }
    else if (topsev >= 2)          { vk = "surveiller"; lvl = "watch" }
    else if (winpe)                { vk = "winpe";    lvl = "partial" }
    else                           { vk = "sain";     lvl = "ok" }

    # ---- regroupement : une phrase par profil (ou par règle surchargée) et par gravité maximale
    ng = 0
    for (i = 1; i <= nf; i++) {
        if (id[i] == "D999" || id[i] == "S010") continue
        s = sev[i]; key = ""
        if ((("@" id[i]) SUBSEP s) in tpl_c) key = "@" id[i]
        else if ((("@" id[i]) SUBSEP "*") in tpl_c) key = "@" id[i]
        else key = prof[i]
        if (s == "INFO" && key == "general") continue
        gk = key SUBSEP s
        if (gk in seen) continue
        seen[gk] = 1
        ng++; gkey[ng] = key; gsev[ng] = s
    }
    # gravité max par clé : ne garder que la première (la plus grave) occurrence de chaque clé
    kept = 0
    for (g = 1; g <= ng; g++) {
        if (gkey[g] in keyseen) continue
        keyseen[gkey[g]] = 1
        kept++; kkey[kept] = gkey[g]; ksev[kept] = gsev[g]
    }

    if (DATE == "") DATE = "(date non renseignée)"

    # ================================================================ SORTIE
    emit("T", "Rapport d'état de l'appareil")
    emit("S", "SONAR-SE — synthèse pour le client")
    emit("K", "Appareil", (MACHINE == "votre appareil") ? "(non identifié)" : MACHINE)
    if (CLIENT != "") emit("K", "Client", CLIENT)
    emit("K", "Date", DATE)
    if (REF != "") emit("K", "Référence", REF)
    emit("G")
    emit("P", subst(tpl_c["_TEXTE" SUBSEP "introduction"]))

    emit("H", "En bref")
    emit("V", lvl, tpl_c["_VERDICT" SUBSEP vk])

    nshown = 0; nconst = 0
    for (g = 1; g <= kept; g++) if (ksev[g] != "INFO") nconst++
    ninfo = kept - nconst
    if (nconst > 0) {
        emit("H", "Ce que nous avons constaté")
        for (g = 1; g <= kept && nshown < 6; g++) {
            if (ksev[g] == "INFO") continue
            ck = kkey[g] SUBSEP ksev[g]
            if (!(ck in tpl_c)) ck = kkey[g] SUBSEP "*"
            if (!(ck in tpl_c)) ck = "general" SUBSEP ksev[g]
            emit("B", subst(tpl_c[ck])); nshown++
        }
    }
    if (ninfo > 0) {
        emit("H", "À noter")
        for (g = 1; g <= kept; g++) {
            if (ksev[g] != "INFO") continue
            ck = kkey[g] SUBSEP "INFO"
            if (ck in tpl_c) emit("B", subst(tpl_c[ck]))
        }
    }

    emit("H", "Ce que nous vous recommandons")
    nr = 0
    # la recommandation du verdict d'abord (elle cadre le reste), puis celles des constats
    r = tpl_r["_VERDICT" SUBSEP vk]
    if (r != "" && r != "-") { nr++; rlist[nr] = r; rseen[r] = 1 }
    for (g = 1; g <= kept; g++) {
        ck = kkey[g] SUBSEP ksev[g]
        if (!(ck in tpl_r)) ck = kkey[g] SUBSEP "*"
        if (!(ck in tpl_r)) ck = "general" SUBSEP ksev[g]
        r = subst(tpl_r[ck])
        if (r == "" || r == "-" || (r in rseen)) continue
        if (ksev[g] == "INFO" && kkey[g] == "general") continue
        nr++; rlist[nr] = r; rseen[r] = 1
    }
    # en cas de gravité, la recommandation du constat le plus grave passe devant celle du verdict
    if (vk == "critique" && nr >= 2) { t = rlist[1]; rlist[1] = rlist[2]; rlist[2] = t }
    for (i = 1; i <= nr; i++) emit("N", i, rlist[i])
    if (nr == 0) emit("P", "Aucune action particulière n'est nécessaire de votre part.")

    emit("G")
    emit("P", tpl_c["_TEXTE" SUBSEP "limites"])
    emit("P", tpl_c["_TEXTE" SUBSEP "confidentialite"])
    exit 0
}
