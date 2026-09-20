# diag_engine.awk — moteur de regles du diagnostic intelligent SONAR-SE.
#
# Source UNIQUE du moteur : utilise par tools/sonar_diag.sh (Linux) et par le
# WinPE SONAR-SE (busybox awk). awk pur, aucune extension gawk : doit rester
# compatible gawk, mawk et busybox awk (tests/diag/run_tests.sh le verifie).
#
#   awk -f diag_engine.awk -v FACTS=faits -v RULES=regles -v SYMPTOM=boot -v MODE=report|tsv
#
# Format des regles : voir l'en-tete de diag_rules.txt.
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function isnum(x) { return (x ~ /^-?[0-9]+(\.[0-9]+)?$/) }

function parse_term(t) {
    t = trim(t); pk = ""; pop = ""; pv = ""
    if (match(t, / (exists|missing)$/)) {
        pk = trim(substr(t, 1, RSTART - 1)); pop = substr(t, RSTART + 1); return
    }
    if (match(t, / (==|!=|>=|<=|!~|~|>|<) /)) {
        pk = trim(substr(t, 1, RSTART - 1))
        pop = trim(substr(t, RSTART, RLENGTH))
        pv = trim(substr(t, RSTART + RLENGTH))
        if (pv ~ /^".*"$/) pv = substr(pv, 2, length(pv) - 2)
    }
}

function eval_term(k, op, v,   has, x) {
    has = (k in F)
    if (op == "exists") return has
    if (op == "missing") return !has
    if (!has) return 0
    x = F[k]
    if (op == "==") { if (isnum(x) && isnum(v)) return (x + 0 == v + 0); return (x == v) }
    if (op == "!=") { if (isnum(x) && isnum(v)) return (x + 0 != v + 0); return (x != v) }
    if (op == "~")  return (x ~ v)
    if (op == "!~") return !(x ~ v)
    if (!isnum(x) || !isnum(v)) return 0
    if (op == ">")  return (x + 0 >  v + 0)
    if (op == ">=") return (x + 0 >= v + 0)
    if (op == "<")  return (x + 0 <  v + 0)
    if (op == "<=") return (x + 0 <= v + 0)
    return 0
}

# Evalue "terme" pour une instance ; ajoute la preuve a EVID si vrai.
function check(term, inst,   k) {
    parse_term(term)
    k = pk; gsub(/\*/, inst, k)
    if (!eval_term(k, pop, pv)) return 0
    if ((k in F) && !(k in EVSEEN)) { EVSEEN[k] = 1; EVID = EVID (EVID == "" ? "" : ", ") k "=" F[k] }
    return 1
}

function interp(s, inst,   out, a, b, c, key, val) {
    out = ""
    while ((a = index(s, "{")) > 0) {
        b = index(substr(s, a + 1), "}")
        if (b == 0) break
        c = substr(s, a + 1, b - 1)
        if (c == "@") val = inst
        else { key = c; gsub(/\*/, inst, key); val = (key in F) ? F[key] : "?" }
        out = out substr(s, 1, a - 1) val
        s = substr(s, a + b + 1)
    }
    return out s
}

function run_rule(id, sev, syms, when, boost, base, title, cause, action, prof, dont,
                  nt, i, T, wk, p, pre, post, fk, inst, seen, ninst, INST, j, tmp, ok, nb, B, bi, d, cond, delta, conf, sym, cnt) {
    nt = split(when, T, / && /)
    wk = ""
    for (i = 1; i <= nt; i++) { parse_term(T[i]); if (index(pk, "*")) { wk = pk; break } }
    ninst = 0
    if (wk == "") { ninst = 1; INST[1] = "" }
    else {
        p = index(wk, "*"); pre = substr(wk, 1, p - 1); post = substr(wk, p + 1)
        for (fk in F) {
            if (index(fk, pre) == 1 && length(fk) > length(pre) + length(post) && \
                substr(fk, length(fk) - length(post) + 1) == post) {
                inst = substr(fk, length(pre) + 1, length(fk) - length(pre) - length(post))
                if (inst !~ /\./ && !(inst in seen)) { seen[inst] = 1; INST[++ninst] = inst }
            }
        }
        for (i = 2; i <= ninst; i++) {                       # tri stable
            tmp = INST[i]
            for (j = i - 1; j >= 1 && INST[j] > tmp; j--) INST[j + 1] = INST[j]
            INST[j + 1] = tmp
        }
    }
    for (i = 1; i <= ninst; i++) {
        inst = INST[i]; EVID = ""; delete EVSEEN; ok = 1
        for (j = 1; j <= nt; j++) if (!check(T[j], inst)) { ok = 0; break }
        if (!ok) continue
        conf = base
        if (boost != "-" && boost != "") {
            nb = split(boost, B, / ;; /)
            for (bi = 1; bi <= nb; bi++) {
                d = index(B[bi], "=>"); if (d == 0) continue
                cond = substr(B[bi], 1, d - 1); delta = substr(B[bi], d + 2) + 0
                if (check(cond, inst)) conf += delta
            }
        }
        sym = 0
        if (SYMPTOM != "" && syms != "*") {
            cnt = split(syms, T2, ",")
            for (j = 1; j <= cnt; j++) if (trim(T2[j]) == SYMPTOM) { sym = 1; conf += 10 }
        }
        if (conf > 99) conf = 99
        if (conf < 1) conf = 1
        n++
        f_sev[n] = sev; f_conf[n] = conf; f_id[n] = id; f_inst[n] = inst; f_sym[n] = sym
        f_title[n] = interp(title, inst); f_ev[n] = EVID
        f_cause[n] = interp(cause, inst); f_action[n] = interp(action, inst)
        f_prof[n] = prof; f_dont[n] = interp(dont, inst)
        f_key[n] = sevrank[sev] * 1000 + conf
    }
}

function emit_all(   i, j, tmp, order, k, pen, score, top, ver, a, seenA, seenD, step, lbl, cat1) {
    for (i = 1; i <= n; i++) order[i] = i
    for (i = 2; i <= n; i++) {                                # tri par gravite puis confiance
        tmp = order[i]
        for (j = i - 1; j >= 1 && (f_key[order[j]] < f_key[tmp] || (f_key[order[j]] == f_key[tmp] && f_id[order[j]] > f_id[tmp])); j--) order[j + 1] = order[j]
        order[j + 1] = tmp
    }
    pen = 0
    for (i = 1; i <= n; i++) pen += sevw[f_sev[i]] * f_conf[i] / 100
    score = int(100 - pen + 0.5); if (score < 0) score = 0; if (score > 100) score = 100
    top = (n > 0) ? order[1] : 0
    ver = "Aucun probleme majeur detecte"
    if (top && sevrank[f_sev[top]] >= 2) ver = cat[substr(f_id[top], 1, 1)]

    if (MODE == "tsv") {
        for (i = 1; i <= n; i++) { k = order[i]
            printf "%d\t%s\t%d\t%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", i, f_sev[k], f_conf[k], f_id[k], f_inst[k], f_sym[k], f_title[k], f_ev[k], f_cause[k], f_action[k], f_prof[k], f_dont[k]
        }
        printf "#SCORE\t%d\n#VERDICT\t%s\n#RULES\t%d\n#BADRULES\t%d\n", score, ver, nrules, bad
        return
    }

    # ---- rapport lisible ----
    print "=============================================================="
    print "  SONAR-SE - DIAGNOSTIC INTELLIGENT"
    print "=============================================================="
    m = ("sys.vendor" in F ? F["sys.vendor"] : "") " " ("sys.product" in F ? F["sys.product"] : "")
    if (trim(m) == "") m = "(non identifiee)"
    print "Machine    : " trim(m)
    print "Firmware   : " toupper(("sys.firmware" in F) ? F["sys.firmware"] : "?") "  (Secure Boot : " (("sys.secureboot" in F) ? F["sys.secureboot"] : "?") ")"
    if ("sys.cpu_model" in F) print "Processeur : " F["sys.cpu_model"]
    if ("sys.ram_mb" in F) print "Memoire    : " F["sys.ram_mb"] " Mo"
    print "Symptome   : " (SYMPTOM != "" ? SYMPTOM : "(non precise)")
    if (F["sys.diag_root"] == "no") print "ATTENTION  : execute sans droits root - diagnostic PARTIEL (voir constat D999)"
    print ""
    lbl = (score >= 85) ? "bon etat apparent" : (score >= 60) ? "a surveiller" : (score >= 30) ? "degrade" : "critique"
    # Un score ne doit jamais rassurer a tort : un blocage grave ou un
    # diagnostic incomplet l'emporte sur le calcul.
    if (top && f_sev[top] == "CRITICAL") lbl = "critique"
    else if (top && f_sev[top] == "HIGH" && score >= 60) lbl = "a surveiller - action requise"
    if (F["sys.diag_root"] == "no") lbl = "NON CONCLUANT - diagnostic partiel"
    else if (F["sys.collector"] == "winpe" && lbl == "bon etat apparent") lbl = "aucun probleme de configuration - SMART/materiel non evalues"
    print "SCORE DE SANTE : " score "/100  (" lbl ")"
    print "  = 100 - somme(poids de gravite x confiance). Poids : CRITICAL 30, HIGH 15, MEDIUM 7, INFO 0."
    print "DOMAINE PRINCIPAL : " ver
    print ""
    if (n == 0) {
        print "Aucun constat : aucune regle ne s'est declenchee sur les faits collectes."
        print "(" nrules " regles evaluees ; cela ne prouve pas l'absence de panne, seulement l'absence de signes connus.)"
    } else {
        print "CONSTATS (du plus grave au moins grave)"
        print "--------------------------------------------------------------"
        for (i = 1; i <= n; i++) { k = order[i]
            printf "%d. [%s | confiance %d%%] %s\n", i, f_sev[k], f_conf[k], f_title[k]
            if (f_sym[k]) print "   (lie au symptome signale)"
            print "   Preuves      : " f_ev[k]
            print "   Cause probable : " f_cause[k]
            print "   Action       : " f_action[k] (f_prof[k] != "-" ? "   [profil " f_prof[k] "]" : "")
            if (f_dont[k] != "-" && f_dont[k] != "") print "   A EVITER     : " f_dont[k]
            print ""
        }
        print "PLAN D'ACTION ORDONNE"
        print "--------------------------------------------------------------"
        # Une etape par profil SONAR-SE (l'action du constat le plus grave en
        # tete, les autres en complement) : evite dix fois "sauvegarder".
        step = 0
        for (i = 1; i <= n; i++) { k = order[i]
            if (sevrank[f_sev[k]] < 2) continue
            a = f_action[k]
            key = (f_prof[k] != "-") ? "P:" f_prof[k] : "A:" a
            if (key in stepIdx) {
                s = stepIdx[key]
                if (a != stepMain[s] && !(s SUBSEP a in subSeen)) {
                    subSeen[s SUBSEP a] = 1
                    stepSub[s] = stepSub[s] "\n   + " a
                }
            } else {
                stepIdx[key] = ++step; stepMain[step] = a; stepProf[step] = f_prof[k]; stepSub[step] = ""
            }
        }
        for (s = 1; s <= step; s++)
            printf "%d. %s%s%s\n", s, stepMain[s], (stepProf[s] != "-" ? "   [profil " stepProf[s] "]" : ""), stepSub[s]
        if (step == 0) print "Rien d'urgent. Voir les constats informatifs ci-dessus."
        print ""
        cnt = 0
        for (i = 1; i <= n; i++) { k = order[i]
            d = f_dont[k]; if (d == "-" || d == "" || (d in seenD)) continue
            seenD[d] = 1
            if (!cnt++) { print "A NE PAS FAIRE"; print "--------------------------------------------------------------" }
            print "- " d
        }
        if (cnt) print ""
    }
    print "Base : " nrules " regles (" (bad ? bad " invalides ignorees" : "toutes valides") "). Moteur deterministe : memes faits => meme rapport."
}

BEGIN {
    FS = "\t"
    sevrank["CRITICAL"] = 4; sevrank["HIGH"] = 3; sevrank["MEDIUM"] = 2; sevrank["INFO"] = 1
    sevw["CRITICAL"] = 30; sevw["HIGH"] = 15; sevw["MEDIUM"] = 7; sevw["INFO"] = 0
    cat["D"] = "Disque"; cat["B"] = "Demarrage"; cat["F"] = "Systeme de fichiers / donnees"
    cat["M"] = "Materiel (memoire, thermique, batterie)"; cat["S"] = "Systeme"; cat["Y"] = "Symptome signale"
    while ((getline line < FACTS) > 0) {
        gsub(/[[:cntrl:]]+$/, "", line)
        if (line ~ /^#/ || line == "") continue
        p = index(line, "\t"); if (p == 0) p = index(line, "=")
        if (p == 0) continue
        F[trim(substr(line, 1, p - 1))] = substr(line, p + 1)
    }
    close(FACTS)
    if (SYMPTOM != "") F["sys.symptom"] = SYMPTOM
    n = 0; nrules = 0; bad = 0
    while ((getline line < RULES) > 0) {
        gsub(/[[:cntrl:]]+$/, "", line)
        if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
        if (split(line, R, / :: /) < 11 || !(R[2] in sevrank)) { bad++; continue }
        nrules++
        run_rule(R[1], R[2], R[3], R[4], R[5], R[6] + 0, R[7], R[8], R[9], R[10], R[11])
    }
    close(RULES)
    emit_all()
    exit
}
