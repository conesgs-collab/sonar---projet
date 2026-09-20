# text2pdf.awk — SONAR-SE : met en page le "markup" de client_report.awk en PDF 1.4.
#
# awk pur, sans bibliothèque ni binaire externe : le PDF est écrit en ASCII pur
# (les caractères accentués sont émis en séquences octales \ooo, polices standard
# Helvetica/Courier, encodage WinAnsi), donc les décalages de la table xref sont
# exacts et identiques sous gawk, mawk et busybox awk. À lancer avec LC_ALL=C.
#
# Entrée  : lignes "TYPE<TAB>a[<TAB>b]" — T titre, S sous-titre, K clé/valeur, V niveau/texte
#           (niveau : ok watch bad crit partial), H intertitre, P paragraphe, B puce,
#           N numéro/texte, M ligne à chasse fixe (espaces conservés), R filet, G espace,
#           X hauteur (garde ce qui suit ensemble : saut de page si moins de X points).
# Variables : -v TITLE=  -v AUTHOR=  -v KEYWORDS=  -v FOOT=  -v PDFDATE=YYYYMMDDHHMMSS
#             -v DOCID=32 hexa (identifiant du document, écrit dans /ID)
# Sortie  : le PDF sur la sortie standard.

BEGIN {
    FS = "\t"
    for (i = 1; i <= 255; i++) ORD[sprintf("%c", i)] = i
    ws = "278 278 355 556 556 889 667 191 333 333 389 584 278 333 278 278 " \
         "556 556 556 556 556 556 556 556 556 556 278 278 584 584 584 556 1015 " \
         "667 667 722 722 667 611 778 722 278 500 667 556 833 722 778 667 778 722 667 611 722 667 944 667 667 611 " \
         "278 278 278 469 556 333 " \
         "556 556 500 556 556 278 556 556 222 222 500 222 833 556 556 556 556 333 500 278 556 500 722 500 500 500 " \
         "334 260 334 584"
    split(ws, WA, " ")
    for (i = 1; i <= 95; i++) W[i + 31] = WA[i]

    PW = 595; PH = 842; ML = 60; MR = 60; MB = 62
    TW = PW - ML - MR
    npg = 0
    newpage(0)

    # couleurs (r g b) : accent vert sombre, texte, gris
    split("0.04 0.16 0.10", CBAND, " ")
    LV["ok"]      = "0.86 0.95 0.87|0.16 0.55 0.28"
    LV["watch"]   = "0.99 0.95 0.80|0.85 0.60 0.05"
    LV["bad"]     = "0.99 0.90 0.80|0.85 0.40 0.05"
    LV["crit"]    = "0.98 0.85 0.85|0.75 0.12 0.12"
    LV["partial"] = "0.89 0.91 0.96|0.30 0.38 0.62"
}

# ------------------------------------------------------------------ texte
function cpbyte(cp) {
    if (cp < 128 || (cp >= 160 && cp <= 255)) return sprintf("%c", cp)
    if (cp == 338) return sprintf("%c", 140)   # Œ
    if (cp == 339) return sprintf("%c", 156)   # œ
    if (cp == 8216) return sprintf("%c", 145)
    if (cp == 8217) return sprintf("%c", 146)
    if (cp == 8220) return sprintf("%c", 147)
    if (cp == 8221) return sprintf("%c", 148)
    if (cp == 8211) return sprintf("%c", 150)
    if (cp == 8212) return sprintf("%c", 151)
    if (cp == 8226) return sprintf("%c", 149)
    if (cp == 8230) return sprintf("%c", 133)
    if (cp == 8364) return sprintf("%c", 128)
    return "?"
}
# UTF-8 -> octets cp1252 (un octet = un caractère : length()/substr() exacts en LC_ALL=C)
function norm(s,    i, n, c, b, cp, out) {
    out = ""; n = length(s); i = 1
    while (i <= n) {
        c = substr(s, i, 1); b = ORD[c] + 0
        if (b < 128)                       { out = out c; i++ }
        else if (b >= 194 && b <= 223 && i < n)  { cp = (b - 192) * 64 + ORD[substr(s, i + 1, 1)] - 128; out = out cpbyte(cp); i += 2 }
        else if (b >= 224 && b <= 239 && i + 1 < n) { cp = (b - 224) * 4096 + (ORD[substr(s, i + 1, 1)] - 128) * 64 + ORD[substr(s, i + 2, 1)] - 128; out = out cpbyte(cp); i += 3 }
        else if (b >= 240 && i + 2 < n)    { out = out "?"; i += 4 }
        else                               { out = out "?"; i++ }
    }
    return out
}
function esc(s,    i, n, c, b, out) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1); b = ORD[c] + 0
        if (c == "\\") out = out "\\\\"
        else if (c == "(") out = out "\\("
        else if (c == ")") out = out "\\)"
        else if (b >= 128 || (b > 0 && b < 32)) out = out sprintf("\\%03o", b)
        else out = out c
    }
    return out
}
function cw(c,    b) {           # largeur d'un caractère, en 1/1000 d'em (Helvetica)
    b = ORD[c] + 0
    if (b >= 32 && b < 127) return W[b]
    if (b == 149) return 350
    if (b == 151 || b == 133) return 1000
    if (b == 156 || b == 140) return 944
    if (b == 146 || b == 145) return 222
    if (b >= 192 && b <= 223) return 667
    return 556
}
function tw(s, size, mono, bold,    i, n, w) {
    if (mono) return length(s) * 0.6 * size
    n = length(s); w = 0
    for (i = 1; i <= n; i++) w += cw(substr(s, i, 1))
    return w * size / 1000 * (bold ? 1.08 : 1)
}
# découpe s en lignes de largeur <= maxw ; résultat dans LN[1..nln]
function wraptext(s, size, maxw, mono, bold,    n, w, i, cur, t, cpl) {
    nln = 0
    if (mono) {                      # chasse fixe : on garde les espaces, coupe dure
        cpl = int(maxw / (0.6 * size)); if (cpl < 1) cpl = 1
        while (length(s) > cpl) { LN[++nln] = substr(s, 1, cpl); s = substr(s, cpl + 1) }
        LN[++nln] = s
        return
    }
    n = split(s, w, " "); cur = ""
    for (i = 1; i <= n; i++) {
        t = (cur == "") ? w[i] : cur " " w[i]
        if (cur != "" && tw(t, size, 0, bold) > maxw) { LN[++nln] = cur; cur = w[i] }
        else cur = t
    }
    if (cur != "" || nln == 0) LN[++nln] = cur
}

# ------------------------------------------------------------------ page
function newpage(first) {
    npg++; PG[npg] = ""; y = PH - 56
    if (npg == 1) y = PH - 56
}
function put(s) { PG[npg] = PG[npg] s "\n" }
function ensure(h) { if (y - h < MB) newpage(0) }
function text(font, size, x, yy, s, col) {
    put(sprintf("%s BT /%s %s Tf %.2f %.2f Td (%s) Tj ET", col, font, size, x, yy, esc(s)))
}
function rect(x, yy, w, h, col) { put(sprintf("%s %.2f %.2f %.2f %.2f re f", col, x, yy, w, h)) }
function line(x1, y1, x2, y2, col, wd) { put(sprintf("%s %s w %.2f %.2f m %.2f %.2f l S", col, wd, x1, y1, x2, y2)) }

# ------------------------------------------------------------------ directives
{
    kind = $1; a = norm($2); b = norm($3)
    if (kind == "T") {
        # bandeau de tête (première page)
        rect(0, PH - 104, PW, 104, "0.04 0.16 0.10 rg")
        put("0.49 1 0.49 rg BT /F2 9 Tf 1.6 Tc " ML " " (PH - 40) " Td (SONAR - SE) Tj ET")
        put("1 1 1 rg BT /F2 21 Tf 0 Tc " ML " " (PH - 72) " Td (" esc(a) ") Tj ET")
        y = PH - 104 - 26
        next
    }
    if (kind == "S") {
        text("F1", 10.5, ML, y, a, "0.30 0.34 0.32 rg"); y -= 24
        next
    }
    if (kind == "K") {
        wraptext(b, 10.5, TW - 92, 0, 0)
        ensure(nln * 15 + 2)
        text("F2", 10, ML, y, a, "0.30 0.34 0.32 rg")
        for (i = 1; i <= nln; i++) { text("F1", 10.5, ML + 92, y, LN[i], "0.08 0.10 0.09 rg"); y -= 15 }
        next
    }
    if (kind == "H") {
        ensure(52)
        y -= 14
        text("F2", 13, ML, y, a, "0.04 0.30 0.16 rg")
        y -= 6; line(ML, y, PW - MR, y, "0.70 0.80 0.73 RG", "0.6"); y -= 16
        next
    }
    if (kind == "P") {
        wraptext(a, 10.5, TW, 0, 0)
        for (i = 1; i <= nln; i++) { ensure(16); text("F1", 10.5, ML, y, LN[i], "0.10 0.12 0.11 rg"); y -= 15 }
        y -= 5
        next
    }
    if (kind == "B") {
        wraptext(a, 10.5, TW - 18, 0, 0)
        ensure(nln * 15 + 4)
        text("F1", 10.5, ML + 2, y, sprintf("%c", 149), "0.04 0.30 0.16 rg")
        for (i = 1; i <= nln; i++) { text("F1", 10.5, ML + 18, y, LN[i], "0.10 0.12 0.11 rg"); y -= 15 }
        y -= 4
        next
    }
    if (kind == "N") {
        wraptext(b, 10.5, TW - 22, 0, 0)
        ensure(nln * 15 + 4)
        text("F2", 10.5, ML + 2, y, a ".", "0.04 0.30 0.16 rg")
        for (i = 1; i <= nln; i++) { text("F1", 10.5, ML + 22, y, LN[i], "0.10 0.12 0.11 rg"); y -= 15 }
        y -= 4
        next
    }
    if (kind == "V") {
        split(LV[a], cc, "|")
        wraptext(b, 12, TW - 24, 0, 1)
        h = nln * 17 + 18
        ensure(h + 6)
        rect(ML, y - h + 12, TW, h, cc[1] " rg")
        rect(ML, y - h + 12, 5, h, cc[2] " rg")
        yy = y - 8
        for (i = 1; i <= nln; i++) { text("F2", 12, ML + 18, yy, LN[i], "0.08 0.10 0.09 rg"); yy -= 17 }
        y -= h + 8
        next
    }
    if (kind == "M") {
        wraptext(a, 7.5, TW, 1, 0)
        for (i = 1; i <= nln; i++) { ensure(11); text("F3", 7.5, ML, y, LN[i], "0.28 0.30 0.29 rg"); y -= 10.5 }
        next
    }
    if (kind == "X") { ensure(a + 0); next }
    if (kind == "R") { ensure(10); line(ML, y, PW - MR, y, "0.70 0.80 0.73 RG", "0.6"); y -= 10; next }
    if (kind == "G") { y -= 9; next }
}

# ------------------------------------------------------------------ assemblage du PDF
END {
    if (npg == 0) exit 1
    # pied de page + numérotation, maintenant que le nombre de pages est connu
    for (p = 1; p <= npg; p++) {
        PG[p] = PG[p] sprintf("0.70 0.80 0.73 RG 0.5 w %d 46 m %d 46 l S\n", ML, PW - MR)
        PG[p] = PG[p] sprintf("0.40 0.44 0.42 rg BT /F1 7.5 Tf %d 34 Td (%s) Tj ET\n", ML, esc(norm(FOOT)))
        lab = "Page " p " / " npg
        PG[p] = PG[p] sprintf("0.40 0.44 0.42 rg BT /F1 7.5 Tf %.2f 34 Td (%s) Tj ET\n", PW - MR - tw(lab, 7.5, 0, 0), lab)
    }
    out = "%PDF-1.4\n"; pos = length(out); printf "%s", out
    nobj = 5 + 2 * npg + 1
    # 1 Catalog, 2 Pages, 3-5 polices, puis (page, contenu) par page, puis Info
    kids = ""
    for (p = 1; p <= npg; p++) kids = kids (6 + 2 * (p - 1)) " 0 R "
    OB[1] = "<< /Type /Catalog /Pages 2 0 R >>"
    OB[2] = "<< /Type /Pages /Kids [ " kids "] /Count " npg " >>"
    OB[3] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    OB[4] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"
    OB[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>"
    for (p = 1; p <= npg; p++) {
        pid = 6 + 2 * (p - 1)
        OB[pid] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " PW " " PH "] /Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> /Contents " (pid + 1) " 0 R >>"
        OB[pid + 1] = "<< /Length " length(PG[p]) " >>\nstream\n" PG[p] "endstream"
    }
    iid = 6 + 2 * npg
    OB[iid] = "<< /Title (" esc(norm(TITLE)) ") /Author (" esc(norm(AUTHOR)) ") /Keywords (" esc(norm(KEYWORDS)) ") /Creator (sonar_diag.sh --client-report) /Producer (SONAR-SE text2pdf.awk) /CreationDate (D:" PDFDATE "Z) >>"
    for (i = 1; i <= iid; i++) {
        OFF[i] = pos
        s = i " 0 obj\n" OB[i] "\nendobj\n"
        printf "%s", s; pos += length(s)
    }
    xr = pos
    printf "xref\n0 %d\n0000000000 65535 f \n", iid + 1
    for (i = 1; i <= iid; i++) printf "%010d 00000 n \n", OFF[i]
    id = (DOCID == "") ? "00000000000000000000000000000000" : DOCID
    printf "trailer\n<< /Size %d /Root 1 0 R /Info %d 0 R /ID [<%s> <%s>] >>\nstartxref\n%d\n%%%%EOF\n", iid + 1, iid, id, id, xr
}
