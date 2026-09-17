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

.PARAMETER AddRepairMenu
    Remplace startnet.cmd par un menu de reparation numerote (bootrec,
    bcdedit, diskpart, DISM, invite libre) au lieu du cmd.exe brut par
    defaut. ACTIVE par defaut — c'est un simple remplacement de fichier
    dans boot.wim (montage DISM + copie, PAS de /Add-Package), donc non
    concerne par la limite connue de -IncludePowerShell ci-dessous.
    Utilisez -AddRepairMenu:$false pour revenir au cmd.exe brut.

.PARAMETER IncludePowerShell
    Tente d'ajouter PowerShell à l'image WinPE (WinPE-WMI > WinPE-NetFx >
    WinPE-Scripting > WinPE-PowerShell, dans cet ordre de dépendance,
    chaque composant suivi de son paquet linguistique en-us). DÉSACTIVÉ
    par défaut — voir "LIMITE CONNUE" ci-dessous. bootrec/bcdedit/diskpart
    restent disponibles dans tous les cas (binaires Windows de base déjà
    présents dans WinPE), et le réseau Ethernet de base fonctionne sans
    composant supplémentaire (`wpeutil InitializeNetwork` après boot).

    LIMITE CONNUE (testé le 2026-09-16, ADK 10.1.26100.2454 sur hôte
    Windows 10 build 19045) : le montage de boot.wim réussit, mais
    `Dism /Add-Package` échoue systématiquement dès le premier paquet
    avec "Erreur: 87 — Une erreur d'initialisation s'est produite"
    (HRESULT 0x80070057 sur `CPEImg::Attach`, le fournisseur DISM chargé
    pour les images WinPE hors ligne). Écarté par test direct : chemin
    avec espaces (rejoué avec un chemin court 8.3, même échec), version
    de DISM utilisée (rejoué avec le DISM système ET celui de l'ADK,
    même échec), montage orphelin (rejoué sur montage propre vérifié via
    `Dism /Get-MountedWimInfo`, même échec). Hypothèse non confirmée :
    incompatibilité entre ce moteur DISM (ère Windows 11 24H2) et l'hôte
    Windows 10 22H2 pour le fournisseur PE spécifiquement — un ADK plus
    ancien (~10.1.19041 ou ~10.1.22621) pourrait résoudre le problème
    mais n'a pas été testé. `-IncludePowerShell` reste disponible pour
    qui veut retenter sur un hôte différent ou avec un autre ADK ; en cas
    d'échec, le script s'arrête proprement (démontage automatique,
    message d'erreur clair) sans corrompre boot.wim ni laisser de
    montage orphelin.

.EXAMPLE
    .\Build-SonarSE-WinPE.ps1
    Construit SONAR-SE-WinPE-amd64.iso (image minimale, cmd.exe) dans le dossier courant.

.EXAMPLE
    .\Build-SonarSE-WinPE.ps1 -OutputIso C:\clé\SONAR_SOURCE\ISO\WinPE\winpe.iso
    Construit directement dans l'arborescence SONAR_SOURCE d'une clé en préparation.

.EXAMPLE
    .\Build-SonarSE-WinPE.ps1 -IncludePowerShell
    Tente d'ajouter PowerShell — voir "LIMITE CONNUE" ci-dessus avant d'utiliser cette option.
#>
[CmdletBinding()]
param(
    [string]$OutputIso = ".\SONAR-SE-WinPE-amd64.iso",
    [string]$WorkDir = "$env:TEMP\sonar-se-winpe-build",
    [switch]$SkipAdkInstall,
    [bool]$IncludePowerShell = $false,
    [bool]$AddRepairMenu = $true
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
if (Test-Path $stageDir) {
    # cmd /c rmdir plutot que Remove-Item : sur certains profils Windows
    # (nom d'utilisateur avec espace -> alias 8.3 dans %TEMP%, ex.
    # C:\Users\CEPC~1\...), Remove-Item -Recurse echoue de facon
    # reproductible sur l'arborescence WinPE (des centaines de petits
    # fichiers) avec "Un objet n'existe pas a l'emplacement specifie
    # C:\Users\CEPC~1." — chemin tronque dans le message, cause exacte
    # non confirmee (quirk du provider FileSystem de PowerShell face a ce
    # chemin). Constate et reproduit le 2026-09-17 ; cmd.exe rmdir /s /q
    # reussit systematiquement sur le meme chemin.
    cmd /c "rmdir /s /q `"$stageDir`""
    if (Test-Path $stageDir) {
        throw "Impossible de supprimer l'ancien dossier de travail '$stageDir' (rmdir a echoue)."
    }
}

Write-Host "== Création de l'environnement de travail WinPE (élévation requise) =="
$stageLog = Join-Path $WorkDir "stage_log.txt"
$cmdline = "/c call `"$setEnvBat`" && `"$copypeCmd`" amd64 `"$stageDir`" > `"$stageLog`" 2>&1"
Start-Process -FilePath "cmd.exe" -ArgumentList $cmdline -Verb RunAs -Wait
if (-not (Test-Path (Join-Path $stageDir "media\sources\boot.wim"))) {
    Get-Content $stageLog -ErrorAction SilentlyContinue | Write-Host
    throw "Échec de la création de l'environnement WinPE — voir $stageLog ci-dessus."
}

if ($AddRepairMenu) {
    Write-Host "== Remplacement de startnet.cmd par le menu de reparation (montage DISM, elevation requise) =="
    $bootWim = Join-Path $stageDir "media\sources\boot.wim"
    $menuMountDir = Join-Path $WorkDir "mount_menu"
    New-Item -ItemType Directory -Force -Path $menuMountDir | Out-Null

    # Menu batch pur (pas de PowerShell) : reprend exactement les commandes
    # documentees dans docs/WINPE.md (bootrec, bcdedit, diskpart, DISM),
    # juste presentees sans que le technicien ait a en memoriser la syntaxe.
    $menuLines = @(
        "@echo off"
        "wpeutil InitializeNetwork"
        ":menu"
        "cls"
        "echo ============================================"
        "echo   SONAR-SE WinPE - Menu de reparation"
        "echo ============================================"
        "echo 1. Reparer le demarrage (bootrec : fixmbr, fixboot, rebuildbcd)"
        "echo 2. Configuration de boot (bcdedit, invite interactive)"
        "echo 3. Gestion des disques/partitions (diskpart)"
        "echo 4. Verifier/reparer une image Windows hors ligne (DISM)"
        "echo 5. Invite de commandes libre (cmd.exe)"
        "echo 0. Redemarrer"
        "echo ============================================"
        "set /p choix=Choix : "
        "if `"%choix%`"==`"1`" goto bootrec"
        "if `"%choix%`"==`"2`" goto bcdedit_menu"
        "if `"%choix%`"==`"3`" goto diskpart_menu"
        "if `"%choix%`"==`"4`" goto dism_menu"
        "if `"%choix%`"==`"5`" goto cmdfree"
        "if `"%choix%`"==`"0`" wpeutil reboot"
        "goto menu"
        ""
        ":bootrec"
        "cls"
        "echo --- Reparation du demarrage ---"
        "echo Va executer : bootrec /fixmbr, /fixboot, /rebuildbcd"
        "echo Verifiez que le disque Windows cible est bien branche."
        "pause"
        "bootrec /fixmbr"
        "bootrec /fixboot"
        "bootrec /rebuildbcd"
        "echo."
        "echo Termine. Appuyez sur une touche pour revenir au menu."
        "pause"
        "goto menu"
        ""
        ":bcdedit_menu"
        "cls"
        "echo --- Configuration de demarrage (bcdedit) ---"
        "echo Invite bcdedit interactive. Tapez ^`"exit^`" pour revenir au menu."
        "cmd /k bcdedit"
        "goto menu"
        ""
        ":diskpart_menu"
        "cls"
        "echo --- Gestion des disques (diskpart) ---"
        "diskpart"
        "goto menu"
        ""
        ":dism_menu"
        "cls"
        "echo --- DISM : verification/reparation d'une image hors ligne ---"
        "set /p lettre=Lettre du lecteur Windows cible (ex: C) : "
        "echo Verification de l'integrite de l'image (ScanHealth)..."
        "Dism /Image:%lettre%:\ /Cleanup-Image /ScanHealth"
        "echo."
        "set /p rep=Lancer la reparation RestoreHealth ? (o/n) : "
        "if /i `"%rep%`"==`"o`" Dism /Image:%lettre%:\ /Cleanup-Image /RestoreHealth"
        "echo."
        "pause"
        "goto menu"
        ""
        ":cmdfree"
        "cls"
        "cmd /k"
        "goto menu"
    )
    $startnetPath = Join-Path $WorkDir "startnet.cmd"
    $menuLines | Set-Content -Path $startnetPath -Encoding ASCII

    $menuScript = Join-Path $WorkDir "add_menu.cmd"
    $menuLog = Join-Path $WorkDir "menu_add_log.txt"
    # Meme schema robuste que le bloc -IncludePowerShell ci-dessous (call
    # :main > log 2>&1, setlocal enabledelayedexpansion + !errorlevel!,
    # Cleanup-Mountpoints en preambule, discard sur echec) : ici on
    # remplace juste un fichier dans l'image montee (pas de /Add-Package),
    # donc non concerne par le bug DISM Erreur 87 documente plus bas.
    $menuScriptLines = @(
        "@echo off"
        "setlocal enabledelayedexpansion"
        "call :main > `"$menuLog`" 2>&1"
        "exit /b !errorlevel!"
        ""
        ":main"
        "call `"$setEnvBat`""
        "echo [%date% %time%] Nettoyage des montages DISM orphelins"
        "Dism /Cleanup-Mountpoints"
        "echo [%date% %time%] Montage de l'image"
        "Dism /Mount-Image /ImageFile:`"$bootWim`" /Index:1 /MountDir:`"$menuMountDir`""
        "if !errorlevel! neq 0 exit /b 1"
        "echo [%date% %time%] Remplacement de startnet.cmd"
        "copy /y `"$startnetPath`" `"$menuMountDir\Windows\System32\startnet.cmd`""
        "if !errorlevel! neq 0 goto :fail_mounted"
        "echo [%date% %time%] Demontage et commit"
        "Dism /Unmount-Image /MountDir:`"$menuMountDir`" /Commit"
        "if !errorlevel! neq 0 goto :fail_mounted"
        "echo [%date% %time%] OK"
        "exit /b 0"
        ""
        ":fail_mounted"
        "echo [%date% %time%] Echec — demontage (discard) de l'image montee"
        "Dism /Unmount-Image /MountDir:`"$menuMountDir`" /Discard"
        "exit /b 1"
    )
    $menuScriptLines | Set-Content -Path $menuScript -Encoding ASCII

    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$menuScript`"" -Verb RunAs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "== Log remplacement startnet.cmd =="
        if (Test-Path $menuLog) {
            Get-Content $menuLog -ErrorAction SilentlyContinue | Write-Host
        } else {
            Write-Host "(aucun fichier log produit — voir $menuScript pour la commande exacte)"
        }
        throw "Echec du remplacement de startnet.cmd (code $($proc.ExitCode)) — voir le log ci-dessus. Relancez avec -AddRepairMenu:`$false pour l'image minimale (cmd.exe brut, deja fonctionnelle)."
    }
    Write-Host "Menu de reparation installe avec succes."
}

if ($IncludePowerShell) {
    Write-Host "== Ajout de PowerShell a l'image WinPE (montage DISM, elevation requise) =="
    $ocDir = Join-Path $WinPeDir "amd64\WinPE_OCs"
    $components = @("WinPE-WMI", "WinPE-NetFx", "WinPE-Scripting", "WinPE-PowerShell")
    $mountDir = Join-Path $WorkDir "mount"
    New-Item -ItemType Directory -Force -Path $mountDir | Out-Null
    $bootWim = Join-Path $stageDir "media\sources\boot.wim"

    $addPkgLines = foreach ($c in $components) {
        $neutral = Join-Path $ocDir "$c.cab"
        $lang = Join-Path $ocDir "en-us\${c}_en-us.cab"
        if (-not (Test-Path $neutral) -or -not (Test-Path $lang)) {
            throw "Composant WinPE '$c' introuvable sous '$ocDir' — ADK/add-on WinPE incomplet ou version differente."
        }
        "Dism /Image:`"$mountDir`" /Add-Package /PackagePath:`"$neutral`""
        "if !errorlevel! neq 0 goto :fail_mounted"
        "Dism /Image:`"$mountDir`" /Add-Package /PackagePath:`"$lang`""
        "if !errorlevel! neq 0 goto :fail_mounted"
    }
    $pkgScript = Join-Path $WorkDir "add_powershell.cmd"
    $pkgLog = Join-Path $WorkDir "powershell_add_log.txt"
    # La redirection ">...2>&1" vit DANS le .cmd plutôt que sur l'invocation
    # externe "cmd /c ... > log" : sous élévation UAC (-Verb RunAs), la
    # redirection passée dans -ArgumentList à un Start-Process élevé n'a
    # produit AUCUN fichier log, même vide — signe que ShellExecuteEx ne la
    # propage pas de façon fiable au process enfant. La faire porter par
    # cmd.exe lui-même est robuste indépendamment de la méthode de
    # lancement. `/Cleanup-Mountpoints` en préambule nettoie un montage DISM
    # orphelin laissé par une tentative précédente en échec, qui ferait
    # sinon échouer le nouveau /Mount-Image silencieusement.
    #
    # `if errorlevel 1` ne suffit PAS pour détecter un échec DISM : DISM
    # renvoie souvent son HRESULT brut comme code de sortie (ex.
    # 0xC1420127), qui a le bit de signe posé et est donc NÉGATIF une fois
    # interprété par cmd.exe — `if errorlevel 1` (qui teste errorlevel>=1
    # en entier signé) est alors silencieusement FAUX et laisse le script
    # continuer comme si tout allait bien. C'est réellement arrivé : un
    # /Mount-Image raté (mount orphelin d'une tentative interrompue) a
    # laissé passer tous les /Add-Package suivants sans jamais échouer, et
    # le script a rapporté un succès complet à tort. Le test correct est
    # `if !errorlevel! neq 0` (comparaison numérique directe) avec
    # `setlocal enabledelayedexpansion` + `!errorlevel!`.
    #
    # La logique vit dans une sous-routine appelée via `call :main > log
    # 2>&1` plutôt que dans un bloc `( ... ) > log 2>&1` inline : un `exit
    # /b` exécuté DANS un bloc parenthésé redirigé termine tout
    # l'interprète cmd.exe avant qu'il ait fini de traiter/fermer la
    # redirection — le fichier log n'est alors jamais créé, même vide (vu
    # en pratique : `ExitCode` non nul mais aucun fichier produit). `exit
    # /b` DANS une sous-routine appelée par `call` ne fait que revenir de
    # cet appel, donc la redirection portée par le `call` se ferme
    # normalement.
    #
    # `call "$setEnvBat"` en tête de :main est nécessaire : sans lui, "Dism"
    # résout vers le DISM système (C:\Windows\System32\Dism.exe, ex.
    # 10.0.19041.3636) au lieu de celui de l'ADK (ex. 10.0.26100.2454) —
    # observé en pratique : le DISM système montait l'image sans problème
    # mais échouait sur le tout premier /Add-Package avec "Erreur: 87 — Une
    # erreur d'initialisation s'est produite", incompatible avec des .cab
    # WinPE_OCs plus récents que son propre moteur de servicing.
    #
    # Tout échec APRÈS un /Mount-Image réussi saute vers :fail_mounted, qui
    # démonte l'image (/Discard) avant de sortir en erreur — observé en
    # pratique : un /Add-Package en échec qui se contentait d'un simple
    # `exit /b 1` laissait l'image montée en lecture/écriture, ce qui
    # faisait échouer la TENTATIVE SUIVANTE dès le /Mount-Image avec
    # "l'image ... est déjà montée" (0xC1420127) — un échec en cascade sur
    # un état orphelin, comme le /Mount-Image raté documenté plus haut.
    $lines = @(
        "@echo off"
        "setlocal enabledelayedexpansion"
        "call :main > `"$pkgLog`" 2>&1"
        "exit /b !errorlevel!"
        ""
        ":main"
        "call `"$setEnvBat`""
        "echo [%date% %time%] Nettoyage des montages DISM orphelins"
        "Dism /Cleanup-Mountpoints"
        "echo [%date% %time%] Montage de l'image"
        "Dism /Mount-Image /ImageFile:`"$bootWim`" /Index:1 /MountDir:`"$mountDir`""
        "if !errorlevel! neq 0 exit /b 1"
    )
    $lines += $addPkgLines
    $lines += @(
        "echo [%date% %time%] Demontage et commit"
        "Dism /Unmount-Image /MountDir:`"$mountDir`" /Commit"
        "if !errorlevel! neq 0 goto :fail_mounted"
        "echo [%date% %time%] OK"
        "exit /b 0"
        ""
        ":fail_mounted"
        "echo [%date% %time%] Echec — demontage (discard) de l'image montee"
        "Dism /Unmount-Image /MountDir:`"$mountDir`" /Discard"
        "exit /b 1"
    )
    $lines | Set-Content -Path $pkgScript -Encoding ASCII

    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$pkgScript`"" -Verb RunAs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "== Log ajout PowerShell =="
        if (Test-Path $pkgLog) {
            Get-Content $pkgLog -ErrorAction SilentlyContinue | Write-Host
        } else {
            Write-Host "(aucun fichier log produit — voir $pkgScript pour la commande exacte)"
        }
        throw "Echec de l'ajout de PowerShell a l'image (code $($proc.ExitCode)) — voir le log ci-dessus. Limite connue documentee dans '-? Build-SonarSE-WinPE.ps1' (parametre IncludePowerShell) ; relancez sans -IncludePowerShell pour l'image minimale (deja fonctionnelle)."
    }
    Write-Host "PowerShell ajoute avec succes."
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
