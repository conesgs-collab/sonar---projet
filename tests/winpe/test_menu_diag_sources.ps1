<#
.SYNOPSIS
    Teste, sur un vrai cmd.exe Windows, la logique « d'ou vient le moteur / les regles du diagnostic »
    du menu WinPE (option 12) : cle SONAR-SE (D:..Z:) ou copie integree a l'ISO.

.DESCRIPTION
    Le menu batch est extrait de Build-SonarSE-WinPE.ps1 par l'analyseur PowerShell (le texte teste est EXACTEMENT
    celui que le build ecrit dans startnet.cmd, sans copie manuelle), puis execute avec un BusyBox reel, X: et Z:
    simules par `subst`. Ce n'est PAS un WinPE : wpeinit/wpeutil sont remplaces par des executables inertes.
    Il ne remplace pas le test avec une vraie cle branchee sur un vrai WinPE (voir CHANGELOG 3.50.0).

.PARAMETER BusyBox
    Chemin du busybox.exe (le meme que celui de l'ISO : busybox-w32 FRP-6075 w64u).

.EXAMPLE
    .\tests\winpe\test_menu_diag_sources.ps1 -BusyBox C:\swp_test\bb\busybox.exe
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BusyBox)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $BusyBox)) { throw "busybox.exe introuvable : $BusyBox" }
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ps1 = Join-Path $repo "tools\Build-SonarSE-WinPE.ps1"
$root = Join-Path $env:TEMP "sonar_menu_test_$PID"
$fails = 0
function Pass($m) { "PASS`t$m" }
function Fail($m) { "FAIL`t$m"; $script:fails++ }

foreach ($l in "X:", "Z:") { if (Test-Path "$l\") { throw "$l est deja utilise : ce test le monte avec subst, il ne peut pas continuer." } }

# 1) le menu tel que le build le genere
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ps1, [ref]$t, [ref]$e)
$assign = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$menuLines' }, $true) | Select-Object -First 1
$lines = & ([scriptblock]::Create($assign.Right.Extent.Text))
$emb = "$root\fakeroot\System32\sonar"
New-Item -ItemType Directory -Force $emb, "$root\xdrv", "$root\bin" | Out-Null
$batch = foreach ($l in $lines) {
    if ($l -like 'for %%d in (D E F*') { 'for %%d in (Y Z) do if exist %%d:\MANIFEST\PROFILES.tsv set KEY=%%d:' }   # lettres de test
    elseif ($l -eq 'set SB=%SystemRoot%\System32\sonar') { "set SB=$emb" }
    else { $l }
}
$batch | Set-Content "$root\startnet_t.cmd" -Encoding ASCII
Copy-Item $BusyBox "$emb\busybox.exe"
foreach ($f in "sonar_diag_winpe.sh", "sonar_check_awk.sh") { Copy-Item "$repo\tools\winpe\$f" $emb }
Copy-Item "$repo\tools\diag_engine.awk", "$repo\tools\diag_rules.txt" $emb
Copy-Item "$env:windir\System32\hostname.exe" "$root\bin\wpeinit.exe"
Copy-Item "$env:windir\System32\hostname.exe" "$root\bin\wpeutil.exe"
Set-Content "$root\in.txt" "12`r`nboot`r`n`r`n0`r`n" -Encoding ASCII
$env:PATH = "$root\bin;$env:PATH"

function New-Key($name, $rules, $engine) {
    $k = "$root\key_$name"; New-Item -ItemType Directory -Force "$k\MANIFEST", "$k\Scripts", "$k\Field-Logs" | Out-Null
    Set-Content "$k\MANIFEST\PROFILES.tsv" "PROFILE`tSCENARIO" -Encoding ASCII
    if ($rules) { Copy-Item $rules "$k\MANIFEST\DIAG_RULES.txt" }
    if ($engine) { Copy-Item $engine "$k\Scripts\diag_engine.awk" }
    $k
}
function Run-Menu($name, $keyDir) {
    cmd /c "subst X: `"$root\xdrv`"" | Out-Null
    if ($keyDir) { cmd /c "subst Z: `"$keyDir`"" | Out-Null }
    $out = "$root\out_$name.txt"
    $cl = '/c ""' + "$root\startnet_t.cmd" + '" < "' + "$root\in.txt" + '" > "' + $out + '" 2>&1"'
    $p = Start-Process cmd.exe -ArgumentList $cl -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(90000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $p.Id } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep 1
    $rep = Get-ChildItem "Z:\Field-Logs\diag\DIAG_*.txt", "X:\sonar_diag\DIAG_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    $reportTxt = if ($rep) { Get-Content $rep.FullName -Raw } else { "" }
    cmd /c "subst Z: /d" 2>$null | Out-Null; cmd /c "subst X: /d" 2>$null | Out-Null
    [pscustomobject]@{ Console = (Get-Content $out -Raw); Report = $reportTxt }
}

try {
    $few = "$root\few_rules.txt"
    Get-Content "$repo\tools\diag_rules.txt" | Where-Object { $_ -match '^(S001|S002) ::' } | Set-Content $few -Encoding UTF8
    $bad = "$root\bad_engine.awk"; Set-Content $bad 'BEGIN { system("calc.exe") }' -Encoding ASCII

    $r = Run-Menu "1" (New-Key "s1" "$repo\tools\diag_rules.txt" "$repo\tools\diag_engine.awk")
    if ($r.Console -match 'regles : CLE Z:.*- 37 regle' -and $r.Console -match 'moteur : CLE Z:') { Pass "cle complete : regles ET moteur pris sur la cle, message clair" } else { Fail "cle complete : sources non annoncees comme CLE" }
    if ($r.Report -match 'Sources : regles = CLE Z:.*moteur = CLE Z:') { Pass "cle complete : l'origine est consignee dans le rapport" } else { Fail "cle complete : origine absente du rapport" }

    $r = Run-Menu "2" (New-Key "s2" $few "$repo\tools\diag_engine.awk")
    if ($r.Console -match '- 2 regle' -and $r.Console -match 'Base : 2 regles') { Pass "regles modifiees sur la cle : le moteur travaille bien avec les 2 regles de la cle (pas la copie integree)" } else { Fail "les regles de la cle n'ont pas ete utilisees" }

    $r = Run-Menu "3" (New-Key "s3" "$repo\tools\diag_rules.txt" $bad)
    if ($r.Console -match 'REFUSE' -and $r.Console -match 'moteur : INTEGRE' -and $r.Console -match 'Base : 37 regles') { Pass "moteur de la cle qui execute une commande : REFUSE, moteur integre utilise, diagnostic mene a bien" } else { Fail "moteur malveillant de la cle non refuse" }

    $r = Run-Menu "4" (New-Key "s4" $null $null)
    if ($r.Console -match 'regles : INTEGREES' -and $r.Console -match 'moteur : INTEGRE' -and $r.Report -match 'Sources : regles = INTEGREES') { Pass "cle presente mais SANS les fichiers : repli sur les copies integrees" } else { Fail "cle sans fichiers : pas de repli propre" }

    $r = Run-Menu "5" $null
    if ($r.Console -match 'non detectee' -and $r.Console -match 'regles : INTEGREES' -and $r.Console -match 'Base : 37 regles') { Pass "aucune cle : copies integrees, message « non detectee », diagnostic mene a bien" } else { Fail "aucune cle : comportement d'origine perdu" }
} finally {
    cmd /c "subst Z: /d" 2>$null | Out-Null; cmd /c "subst X: /d" 2>$null | Out-Null
    cmd /c "rmdir /s /q `"$root`"" 2>$null | Out-Null
}
exit $fails
