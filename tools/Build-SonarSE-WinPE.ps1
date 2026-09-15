<#
.SYNOPSIS
    Construit une image WinPE amd64 pour SONAR - SE, via le Windows ADK
    officiel de Microsoft, et l'ISO résultante prête à déposer sur une
    clé SONAR-SE (SOURCE_DIR/ISO/WinPE/).

.DESCRIPTION
    Automatise ce que docs/WINPE.md décrit à la main : téléchargement et
    installation du Windows ADK (Deployment Tools) + de l'add-on WinPE
    depuis les liens officiels Microsoft, puis copype + MakeWinPEMedia
    pour produire une ISO WinPE amd64 de base (bootrec, bcdedit,
    diskpart, DISM inclus par défaut).

    SONAR - SE ne redistribue PAS cette image : ce script la CONSTRUIT
    sur VOTRE machine, à partir de VOS propres téléchargements Microsoft
    (Windows ADK), sous votre propre responsabilité — exactement comme
    si vous suiviez le guide manuel de docs/WINPE.md, juste automatisé.
    Voir docs/WINPE.md pour le pourquoi de cette distinction (elle est
    volontaire, pas cosmétique).

    Nécessite Windows, PowerShell, et une élévation administrateur pour
    les deux installateurs ADK (une fenêtre UAC apparaîtra) — copype et
    MakeWinPEMedia nécessitent aussi des droits administrateur (montage
    DISM).

.PARAMETER OutputIso
    Chemin de l'ISO WinPE final. Défaut : .\SONAR-SE-WinPE-amd64.iso

.PARAMETER WorkDir
    Dossier de travail temporaire (téléchargements + staging WinPE).
    Défaut : $env:TEMP\sonar-se-winpe-build

.PARAMETER SkipAdkInstall
    Suppose que le Windows ADK (Deployment Tools) et l'add-on WinPE sont
    déjà installés — saute le téléchargement/installation.

.EXAMPLE
    .\Build-SonarSE-WinPE.ps1
    Construit SONAR-SE-WinPE-amd64.iso dans le dossier courant.

.EXAMPLE
    .\Build-SonarSE-WinPE.ps1 -OutputIso C:\clé\SONAR_SOURCE\ISO\WinPE\winpe.iso
    Construit directement dans l'arborescence SONAR_SOURCE d'une clé en préparation.
#>
[CmdletBinding()]
param(
    [string]$OutputIso = ".\SONAR-SE-WinPE-amd64.iso",
    [string]$WorkDir = "$env:TEMP\sonar-se-winpe-build",
    [switch]$SkipAdkInstall
)

$ErrorActionPreference = "Stop"

# Liens officiels Microsoft (ADK 10.1.26100.2454, décembre 2024) — voir
# https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
$AdkSetupUrl = "https://go.microsoft.com/fwlink/?linkid=2289980"
$AdkWinPeSetupUrl = "https://go.microsoft.com/fwlink/?linkid=2289981"

$AdkRoot = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$DeploymentToolsDir = Join-Path $AdkRoot "Deployment Tools"
$WinPeDir = Join-Path $AdkRoot "Windows Preinstallation Environment"

function Find-ToolInAdk {
    param([string]$Name)
    Get-ChildItem $AdkRoot -Recurse -Filter $Name -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

if (-not $SkipAdkInstall) {
    if (-not (Test-Path $DeploymentToolsDir)) {
        Write-Host "== Téléchargement du Windows ADK (Deployment Tools) =="
        $adkSetup = Join-Path $WorkDir "adksetup.exe"
        Invoke-WebRequest -Uri $AdkSetupUrl -OutFile $adkSetup
        Write-Host "== Installation (élévation requise — approuvez la fenêtre UAC) =="
        $log = Join-Path $WorkDir "adk_install.log"
        Start-Process -FilePath $adkSetup -ArgumentList "/quiet /features OptionId.DeploymentTools /log `"$log`"" -Verb RunAs -Wait
        if (-not (Test-Path $DeploymentToolsDir)) {
            throw "Échec de l'installation du Windows ADK — voir $log"
        }
    } else {
        Write-Host "== Windows ADK (Deployment Tools) déjà installé, on saute le téléchargement =="
    }

    if (-not (Test-Path $WinPeDir)) {
        Write-Host "== Téléchargement de l'add-on WinPE =="
        $winpeSetup = Join-Path $WorkDir "adkwinpesetup.exe"
        Invoke-WebRequest -Uri $AdkWinPeSetupUrl -OutFile $winpeSetup
        Write-Host "== Installation (élévation requise — approuvez la fenêtre UAC) =="
        $log = Join-Path $WorkDir "winpe_install.log"
        Start-Process -FilePath $winpeSetup -ArgumentList "/quiet /log `"$log`"" -Verb RunAs -Wait
        if (-not (Test-Path $WinPeDir)) {
            throw "Échec de l'installation de l'add-on WinPE — voir $log"
        }
    } else {
        Write-Host "== Add-on WinPE déjà installé, on saute le téléchargement =="
    }
}

$setEnvBat = Find-ToolInAdk "DandISetEnv.bat"
$copypeCmd = Find-ToolInAdk "copype.cmd"
if (-not $setEnvBat -or -not $copypeCmd) {
    throw "Windows ADK/WinPE introuvable après installation — copype.cmd ou DandISetEnv.bat manquant sous '$AdkRoot'."
}

$stageDir = Join-Path $WorkDir "winpe_amd64"
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }

Write-Host "== Création de l'environnement de travail WinPE (élévation requise) =="
$stageLog = Join-Path $WorkDir "stage_log.txt"
$cmdline = "/c call `"$setEnvBat`" && `"$copypeCmd`" amd64 `"$stageDir`" > `"$stageLog`" 2>&1"
Start-Process -FilePath "cmd.exe" -ArgumentList $cmdline -Verb RunAs -Wait
if (-not (Test-Path (Join-Path $stageDir "media\sources\boot.wim"))) {
    Get-Content $stageLog -ErrorAction SilentlyContinue | Write-Host
    throw "Échec de la création de l'environnement WinPE — voir $stageLog ci-dessus."
}

$OutputIso = [System.IO.Path]::GetFullPath($OutputIso)
$outputDir = Split-Path $OutputIso -Parent
if ($outputDir -and -not (Test-Path $outputDir)) { New-Item -ItemType Directory -Force -Path $outputDir | Out-Null }

Write-Host "== Génération de l'ISO (élévation requise) =="
$isoLog = Join-Path $WorkDir "iso_log.txt"
$cmdline = "/c call `"$setEnvBat`" && MakeWinPEMedia /iso `"$stageDir`" `"$OutputIso`" > `"$isoLog`" 2>&1"
Start-Process -FilePath "cmd.exe" -ArgumentList $cmdline -Verb RunAs -Wait
if (-not (Test-Path $OutputIso)) {
    Get-Content $isoLog -ErrorAction SilentlyContinue | Write-Host
    throw "Échec de la génération de l'ISO — voir $isoLog ci-dessus."
}

$hash = (Get-FileHash $OutputIso -Algorithm SHA256).Hash
$size = (Get-Item $OutputIso).Length
Write-Host ""
Write-Host "== Terminé =="
Write-Host "ISO      : $OutputIso"
Write-Host "Taille   : $([math]::Round($size / 1MB, 1)) Mo"
Write-Host "SHA-256  : $hash"
Write-Host ""
Write-Host "Pour l'ajouter à une clé SONAR-SE :"
Write-Host "  mkdir SONAR_SOURCE\ISO\WinPE"
Write-Host "  copy `"$OutputIso`" SONAR_SOURCE\ISO\WinPE\"
Write-Host "  .\sonar_master.sh --disk /dev/sdX --source ./SONAR_SOURCE ..."
