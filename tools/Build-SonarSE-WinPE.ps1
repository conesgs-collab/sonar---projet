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
    le montage DISM (menu de réparation, add-on PowerShell) nécessitent
    aussi des droits administrateur. La génération finale de l'ISO
    (oscdimg, appelé directement) n'en a PAS besoin — confirmé le
    2026-09-17 après plusieurs heures de diagnostic : la lancer via
    élévation produisait des artefacts silencieusement corrompus (voir
    CHANGELOG.md).

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
    bcdedit, diskpart, DISM, SFC hors ligne, deverrouillage BitLocker,
    injection de pilotes, sauvegarde de fichiers utilisateur, export des
    journaux d'evenements, diagnostic reseau, invite libre) au lieu du
    cmd.exe brut par defaut. Toutes ces commandes (manage-bde, sfc,
    robocopy, ipconfig inclus) sont des binaires Windows de base deja
    presents dans WinPE — aucun composant ADK supplementaire requis,
    donc non concerne par la limite connue de -IncludePowerShell
    ci-dessous. ACTIVE par defaut — c'est un simple remplacement de
    fichier dans boot.wim (montage DISM + copie, PAS de /Add-Package).
    Utilisez -AddRepairMenu:$false pour revenir au cmd.exe brut.

.PARAMETER IncludeToolbox
    Embarque dans boot.wim (Windows\System32\sonar) une boite a outils qui
    depasse les seuls binaires Windows : BusyBox for Windows (busybox-w32
    FRP-6075 w64u, SHA-256 epingle, telecharge depuis frippery.org et refuse
    si different), le collecteur WinPE, le MEME moteur de regles que sous
    Linux (diag_engine.awk + diag_rules.txt). Active les options 12 a 16 du
    menu : diagnostic intelligent (rapport enregistre sur la cle dans
    Field-Logs\diag), reparation UEFI automatique (bcdboot), chargement de
    pilotes de stockage a chaud (drvload), lanceur d'outils portables de la
    cle, shell BusyBox. Comme le menu, c'est de la COPIE de fichiers dans
    l'image montee (pas de /Add-Package) : non concerne par la limite
    connue de -IncludePowerShell. Necessite -AddRepairMenu (meme montage).
    ACTIVE par defaut ; -IncludeToolbox:$false pour l'image sans BusyBox.

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

.PARAMETER BrandBootManager
    Renomme les entrees "Windows Boot Manager"/"Windows Setup" du
    magasin BCD (BIOS et UEFI) en "SONAR - SE", et desactive
    l'animation graphique de demarrage (bootuxdisabled) qui affiche
    autrement le logo Windows anime pendant quelques secondes avant que
    startnet.cmd ne prenne la main. Operations bcdedit standard sur un
    fichier de magasin (pas le magasin BCD systeme), pas de patch de
    ressource binaire — meme registre de risque que les autres options
    bcdedit du menu de reparation, pas le meme registre que le theme
    Ventoy plus haut. ACTIVE par defaut. Utilisez
    -BrandBootManager:$false pour garder le comportement Windows
    standard (logo anime "Windows Setup" inclus).

.PARAMETER IncludeBitLockerTools
    Tente d'ajouter le composant WinPE-SecureStartup (manage-bde.exe,
    necessaire a l'option "Deverrouiller un disque BitLocker" du menu de
    reparation) via `Dism /Add-Package`. DESACTIVE par defaut — MEME
    LIMITE CONNUE que -IncludePowerShell ci-dessus, confirmee le
    2026-09-18 sur ce meme hote (ADK 10.1.26100.2454) : `Dism /Add-Package`
    echoue avec "Erreur: 87 — Une erreur d'initialisation s'est produite"
    sur WinPE-SecureStartup exactement comme sur WinPE-WMI/NetFx/
    Scripting/PowerShell — pas un probleme specifique a BitLocker, la
    meme incompatibilite generale ADK/DISM sur cet hote. Sans cette
    option (defaut), l'entree "Deverrouiller un disque BitLocker" du menu
    detecte l'absence de manage-bde.exe et l'indique clairement au lieu
    d'echouer avec un message cmd.exe cryptique — le reste du menu
    (bootrec/bcdedit/diskpart/DISM/SFC/pilotes/sauvegarde/journaux/
    reseau/invite libre, tous des binaires deja presents dans WinPE de
    base) fonctionne normalement quel que soit ce parametre.

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
    [bool]$IncludeBitLockerTools = $false,
    [bool]$AddRepairMenu = $true,
    [bool]$IncludeToolbox = $true,
    [bool]$IncludeAdkComponents = $true,
    [int]$ServicingTimeoutMinutes = 60,
    [string]$ServicedBootWim = "",
    [bool]$BrandBootManager = $true
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


# ----------------------------------------------------------------------------
# Composants Microsoft (PowerShell, WMI, BitLocker) — servicing DANS un WinPE
# ----------------------------------------------------------------------------
# Sur cet hote (Windows 10 19045) `Dism /Add-Package` sur une image WinPE 26100
# echoue (CPEImg::Attach 0x80070057, voir l'aide de -IncludePowerShell). Le meme
# DISM, lance DANS un WinPE 26100 en marche, fonctionne (teste le 2026-09-21 en
# VM : WMI, NetFx, Scripting, PowerShell, StorageWMI, SecureStartup, chacun avec
# son paquet de langue). On fait donc le servicing la-bas :
#   1. une ISO "de servicing" (la meme boot.wim + un startnet.cmd qui sert la
#      boot.wim puis eteint la machine) et une ISO portant les .cab de l'ADK ;
#   2. une VM VirtualBox les demarre SANS intervention, sur un disque de travail ;
#   3. on recupere la boot.wim servie sur le disque de travail, et le reste du
#      script (menu, boite a outils, marque) continue dessus comme avant.
# Rien de Microsoft n'est redistribue : les .cab viennent de VOTRE ADK.
$serviced = $false
if ($IncludeAdkComponents -and $ServicedBootWim) {
    # Reprise : une boot.wim deja servie (par un build precedent, dossier svc\boot_serviced.wim) est reutilisee.
    if (-not (Test-Path $ServicedBootWim)) { throw "-ServicedBootWim introuvable : $ServicedBootWim" }
    Write-Host "== Reutilisation de la boot.wim deja servie : $ServicedBootWim =="
    Copy-Item $ServicedBootWim (Join-Path $stageDir "media\sources\boot.wim") -Force
    $serviced = $true
    $IncludeAdkComponents = $false
}
if ($IncludeAdkComponents -and -not $serviced) {
    $vbm = $null
    foreach ($c in @((Get-Command VBoxManage.exe -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }), "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe")) {
        if ($c -and (Test-Path $c)) { $vbm = $c; break }
    }
    $ocDir = Join-Path $WinPeDir "amd64\WinPE_OCs"
    $ocList = @("WinPE-WMI", "WinPE-NetFx", "WinPE-Scripting", "WinPE-PowerShell", "WinPE-StorageWMI", "WinPE-DismCmdlets", "WinPE-SecureStartup")
    if (-not $vbm) {
        Write-Warning "VirtualBox (VBoxManage.exe) introuvable : PowerShell, WMI et BitLocker NE SONT PAS ajoutes (le WinPE reste minimal). Installez VirtualBox, ou -IncludeAdkComponents:`$false pour ne plus voir ce message."
    } elseif (-not (Test-Path $ocDir)) {
        Write-Warning "Dossier des composants ADK introuvable ($ocDir) : composants non ajoutes."
    } else {
        Write-Host "== Ajout de PowerShell / WMI / BitLocker (servicing dans une VM WinPE, ~20 a 40 min, elevations requises) =="
        $svcDir = Join-Path $WorkDir "svc"
        if (Test-Path $svcDir) { cmd /c "rmdir /s /q `"$svcDir`"" | Out-Null }
        New-Item -ItemType Directory -Force -Path (Join-Path $svcDir "ocs\WinPE_OCs\en-us") | Out-Null
        foreach ($p in $ocList) {
            Copy-Item (Join-Path $ocDir "$p.cab") (Join-Path $svcDir "ocs\WinPE_OCs\") -ErrorAction Stop
            Copy-Item (Join-Path $ocDir "en-us\${p}_en-us.cab") (Join-Path $svcDir "ocs\WinPE_OCs\en-us\") -ErrorAction Stop
        }

        # startnet.cmd de servicing : sert la boot.wim, restaure le startnet par defaut, eteint.
        $pkgLoop = ($ocList -join " ")
        $svcStartnet = @(
            "@echo off"
            "wpeinit"
            "call :main > X:\svc.log 2>&1"
            "wpeutil shutdown"
            "exit /b"
            ""
            ":main"
            "set SRC="
            "set OCS="
            "for %%d in (C D E F G H I J K) do if exist %%d:\sources\boot.wim set SRC=%%d:"
            "for %%d in (C D E F G H I J K) do if exist %%d:\WinPE_OCs\WinPE-WMI.cab set OCS=%%d:\WinPE_OCs"
            "echo SRC=%SRC% OCS=%OCS%"
            "if not defined SRC exit /b 21"
            "if not defined OCS exit /b 22"
            "> X:\dp.txt echo select disk 0"
            ">> X:\dp.txt echo clean"
            ">> X:\dp.txt echo create partition primary"
            ">> X:\dp.txt echo format fs=ntfs quick label=SVC"
            ">> X:\dp.txt echo assign letter=S"
            "diskpart /s X:\dp.txt"
            "if not exist S:\ exit /b 23"
            "mkdir S:\m S:\scratch"
            "copy %SRC%\sources\boot.wim S:\boot.wim"
            "dism /Mount-Image /ImageFile:S:\boot.wim /Index:1 /MountDir:S:\m /ScratchDir:S:\scratch"
            "if errorlevel 1 goto :fail"
            "for %%p in ($pkgLoop) do ("
            "  echo ===== %%p"
            "  dism /Image:S:\m /Add-Package /PackagePath:`"%OCS%\%%p.cab`" /ScratchDir:S:\scratch"
            "  if errorlevel 1 goto :fail_mounted"
            "  dism /Image:S:\m /Add-Package /PackagePath:`"%OCS%\en-us\%%p_en-us.cab`" /ScratchDir:S:\scratch"
            "  if errorlevel 1 goto :fail_mounted"
            ")"
            "dism /Image:S:\m /Get-Packages /Format:Table > S:\packages.txt"
            "echo wpeinit> S:\m\Windows\System32\startnet.cmd"
            "dism /Unmount-Image /MountDir:S:\m /Commit"
            "if errorlevel 1 goto :fail"
            "echo OK> S:\SERVICING_OK.flag"
            "copy X:\svc.log S:\svc.log"
            "exit /b 0"
            ":fail_mounted"
            "dism /Unmount-Image /MountDir:S:\m /Discard"
            ":fail"
            "echo FAILED> S:\SERVICING_FAILED.flag"
            "copy X:\svc.log S:\svc.log"
            "exit /b 12"
        )

        # ISO de servicing = copie du media + boot.wim montee pour remplacer startnet.cmd
        $svcMedia = Join-Path $svcDir "media"
        robocopy (Join-Path $stageDir "media") $svcMedia /E /NFL /NDL /NJH /NJS /NP | Out-Null
        $svcStartnetPath = Join-Path $svcDir "startnet.cmd"
        $svcStartnet | Set-Content -Path $svcStartnetPath -Encoding ASCII
        $svcMount = Join-Path $svcDir "mount"
        New-Item -ItemType Directory -Force -Path $svcMount | Out-Null
        $svcWim = Join-Path $svcMedia "sources\boot.wim"
        $prepScript = Join-Path $svcDir "prep.cmd"
        $prepLog = Join-Path $svcDir "prep_log.txt"
        @(
            "@echo off"
            "setlocal enabledelayedexpansion"
            "call :main > `"$prepLog`" 2>&1"
            "exit /b !errorlevel!"
            ":main"
            "call `"$setEnvBat`""
            "Dism /Cleanup-Mountpoints"
            "Dism /Mount-Image /ImageFile:`"$svcWim`" /Index:1 /MountDir:`"$svcMount`""
            "if !errorlevel! neq 0 exit /b 1"
            "copy /y `"$svcStartnetPath`" `"$svcMount\Windows\System32\startnet.cmd`""
            "if !errorlevel! neq 0 goto :fail_mounted"
            "Dism /Unmount-Image /MountDir:`"$svcMount`" /Commit"
            "if !errorlevel! neq 0 goto :fail_mounted"
            "exit /b 0"
            ":fail_mounted"
            "Dism /Unmount-Image /MountDir:`"$svcMount`" /Discard"
            "exit /b 1"
        ) | Set-Content -Path $prepScript -Encoding ASCII
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$prepScript`"" -Verb RunAs -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Get-Content $prepLog -ErrorAction SilentlyContinue | Write-Host; throw "Preparation de l'image de servicing echouee (voir $prepLog)." }

        $oscd = Find-ToolInAdk "oscdimg.exe"
        $oscdDir = Split-Path $oscd -Parent
        $noprompt = Join-Path $oscdDir "efisys_noprompt.bin"
        $etfs = Join-Path $oscdDir "etfsboot.com"
        if (-not (Test-Path $noprompt) -or -not (Test-Path $etfs)) { throw "efisys_noprompt.bin / etfsboot.com introuvables sous $oscdDir." }
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $svcIso = Join-Path $svcDir "svc.iso"; $ocsIso = Join-Path $svcDir "ocs.iso"
        & $oscd "-bootdata:2#p0,e,b`"$etfs`"#pEF,e,b`"$noprompt`"" -u1 -udfver102 $svcMedia $svcIso 2>&1 | Out-Null
        & $oscd -m -u2 -lOCS (Join-Path $svcDir "ocs") $ocsIso 2>&1 | Out-Null
        $ErrorActionPreference = $prevEap
        if (-not (Test-Path $svcIso) -or -not (Test-Path $ocsIso)) { throw "Creation des ISO de servicing echouee." }

        # VM : 4 Go, UEFI (efisys_noprompt : aucune touche a presser), disque de travail VHD dynamique 10 Go
        $vm = "sonar-winpe-svc-$PID"
        $vhd = Join-Path $svcDir "scratch.vhd"
        & $vbm createvm --name $vm --ostype Windows11_64 --register --basefolder $svcDir | Out-Null
        & $vbm modifyvm $vm --memory 4096 --cpus 2 --firmware efi --graphicscontroller vmsvga --vram 16 | Out-Null
        & $vbm createmedium disk --filename $vhd --format VHD --variant Standard --size 10240 | Out-Null
        & $vbm storagectl $vm --name SATA --add sata --controller IntelAHCI --portcount 4 | Out-Null
        & $vbm storageattach $vm --storagectl SATA --port 0 --device 0 --type dvddrive --medium $svcIso | Out-Null
        & $vbm storageattach $vm --storagectl SATA --port 1 --device 0 --type dvddrive --medium $ocsIso | Out-Null
        & $vbm storageattach $vm --storagectl SATA --port 2 --device 0 --type hdd --medium $vhd | Out-Null
        Write-Host "VM de servicing '$vm' demarree (sans fenetre) — patience, l'image est reecrite en emulation."
        & $vbm startvm $vm --type headless | Out-Null
        $deadline = (Get-Date).AddMinutes($ServicingTimeoutMinutes)
        do {
            Start-Sleep -Seconds 15
            $state = (& $vbm showvminfo $vm --machinereadable | Select-String '^VMState="(.*)"').Matches.Groups[1].Value
        } while ($state -eq "running" -and (Get-Date) -lt $deadline)
        if ($state -eq "running") {
            & $vbm controlvm $vm poweroff | Out-Null
            Start-Sleep -Seconds 5
            & $vbm unregistervm $vm --delete | Out-Null
            throw "Servicing WinPE : delai de $ServicingTimeoutMinutes min depasse — VM arretee. Relancez avec un delai plus long (-ServicingTimeoutMinutes) ou -IncludeAdkComponents:`$false."
        }

        # recuperation de la boot.wim servie sur le disque de travail (montage VHD : elevation)
        $outWim = Join-Path $svcDir "boot_serviced.wim"
        $getScript = Join-Path $svcDir "get.ps1"
        $getLog = Join-Path $svcDir "get_log.txt"
        @(
            "`$ErrorActionPreference = 'Stop'"
            "Start-Transcript -Path '$getLog' | Out-Null"
            "Mount-DiskImage -ImagePath '$vhd' | Out-Null"
            "try {"
            "  Start-Sleep -Seconds 3"
            "  `$v = Get-Volume | Where-Object { `$_.FileSystemLabel -eq 'SVC' } | Select-Object -First 1"
            "  if (-not `$v) { throw 'volume SVC introuvable' }"
            "  `$r = `$v.DriveLetter + ':\'"
            "  Copy-Item (`$r + 'svc.log') '$svcDir\svc.log' -ErrorAction SilentlyContinue"
            "  Copy-Item (`$r + 'packages.txt') '$svcDir\packages.txt' -ErrorAction SilentlyContinue"
            "  if (Test-Path (`$r + 'SERVICING_OK.flag')) { Copy-Item (`$r + 'boot.wim') '$outWim' -Force }"
            "} finally { Dismount-DiskImage -ImagePath '$vhd' | Out-Null; Stop-Transcript | Out-Null }"
        ) | Set-Content -Path $getScript -Encoding UTF8
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$getScript`"" -Verb RunAs -Wait
        & $vbm unregistervm $vm --delete | Out-Null
        if (-not (Test-Path $outWim)) {
            if (Test-Path (Join-Path $svcDir "svc.log")) { Get-Content (Join-Path $svcDir "svc.log") -Tail 40 | Write-Host }
            throw "Le servicing dans la VM n'a pas abouti (pas de SERVICING_OK) — journaux : $svcDir\svc.log, get_log.txt. Relancez avec -IncludeAdkComponents:`$false pour l'image sans composants."
        }
        Copy-Item $outWim (Join-Path $stageDir "media\sources\boot.wim") -Force
        $serviced = $true
        Write-Host "Composants ajoutes : PowerShell, WMI, StorageWMI, DismCmdlets, BitLocker (manage-bde). Paquets : $svcDir\packages.txt"
        if (Test-Path $svcMedia) { cmd /c "rmdir /s /q `"$svcMedia`"" | Out-Null }
    }
}
if ($BrandBootManager) {
    # Renomme les entrees BCD ("Windows Boot Manager"/"Windows Setup" ->
    # "SONAR - SE") et desactive l'animation graphique de demarrage
    # (bootuxdisabled) qui affiche autrement le logo Windows anime avant
    # meme que startnet.cmd ne prenne la main. Operations bcdedit
    # standard sur un fichier de magasin arbitraire (PAS le magasin BCD
    # du systeme en cours d'execution) — aucun patch binaire de
    # ressource (bootres.dll etc.), donc pas la meme classe de risque
    # que le theme Ventoy (voir plus haut) : ceci reste dans le domaine
    # officiellement supporte de bcdedit. Applique aux DEUX magasins
    # (BIOS et UEFI) generes par copype, Ventoy pouvant chainloader
    # l'un ou l'autre selon le micrologiciel de la machine cible.
    Write-Host "== Renommage du gestionnaire de demarrage en SONAR - SE (elevation requise) =="
    $bcdPaths = @(
        (Join-Path $stageDir "media\Boot\BCD")
        (Join-Path $stageDir "media\EFI\Microsoft\Boot\BCD")
    )
    $bcdLog = Join-Path $WorkDir "bcd_brand_log.txt"
    $bcdScript = Join-Path $WorkDir "bcd_brand.cmd"
    $bcdLines = @("@echo off", "setlocal enabledelayedexpansion", "call :main > `"$bcdLog`" 2>&1", "exit /b !errorlevel!", "", ":main")
    foreach ($bcd in $bcdPaths) {
        if (-not (Test-Path $bcd)) {
            throw "Magasin BCD introuvable : $bcd — copype a peut-etre change de disposition."
        }
        $bcdLines += "bcdedit /store `"$bcd`" /set {bootmgr} description `"SONAR - SE`""
        $bcdLines += "if !errorlevel! neq 0 exit /b 1"
        $bcdLines += "bcdedit /store `"$bcd`" /set {default} description `"SONAR - SE`""
        $bcdLines += "if !errorlevel! neq 0 exit /b 1"
        $bcdLines += "bcdedit /store `"$bcd`" /set {default} bootuxdisabled yes"
        $bcdLines += "if !errorlevel! neq 0 exit /b 1"
    }
    $bcdLines += "exit /b 0"
    $bcdLines | Set-Content -Path $bcdScript -Encoding ASCII
    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$bcdScript`"" -Verb RunAs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "== Log renommage BCD =="
        Get-Content $bcdLog -ErrorAction SilentlyContinue | Write-Host
        throw "Echec du renommage du gestionnaire de demarrage (code $($proc.ExitCode)) — voir le log ci-dessus. Relancez avec -BrandBootManager:`$false pour garder le magasin BCD par defaut (comportement Windows standard, logo anime inclus)."
    }
    Write-Host "Gestionnaire de demarrage renomme en SONAR - SE, animation de demarrage desactivee."
}

if ($AddRepairMenu) {
    Write-Host "== Remplacement de startnet.cmd par le menu de reparation (montage DISM, elevation requise) =="
    $bootWim = Join-Path $stageDir "media\sources\boot.wim"
    $menuMountDir = Join-Path $WorkDir "mount_menu"
    New-Item -ItemType Directory -Force -Path $menuMountDir | Out-Null

    # --- Boite a outils (diagnostic intelligent + BusyBox) ---------------------
    # Pas de /Add-Package (impossible sur cet hote, voir plus haut) : on copie
    # simplement des fichiers dans l'image montee. BusyBox fournit sh/awk/grep/
    # dd/vi ; le moteur de diagnostic est le MEME diag_engine.awk que sous Linux.
    $toolboxDir = $null
    if ($IncludeToolbox) {
        # BusyBox for Windows (busybox-w32, Ron Yorston), build FRP-6075 "w64u"
        # (64 bits, Unicode). SHA-256 epingle : un fichier different est refuse.
        # Verifie aussi hors ligne par signature GPG (cle publiee sur le compte
        # GitHub de l'auteur) lors de la mise en place initiale.
        $bbName = "busybox-w64u-FRP-6075-g169694ebd.exe"
        $bbUrl = "https://frippery.org/files/busybox/$bbName"
        $bbSha256 = "6e263d154d8548d1eb936f65d1d8312c80df31c45974e48d6335e4dcc0f4f34c"
        $toolboxDir = Join-Path $WorkDir "toolbox"
        New-Item -ItemType Directory -Force -Path $toolboxDir | Out-Null

        $bbCache = Join-Path $WorkDir $bbName
        if (-not (Test-Path $bbCache) -or (Get-FileHash $bbCache -Algorithm SHA256).Hash.ToLower() -ne $bbSha256) {
            Write-Host "== Telechargement de BusyBox ($bbName) =="
            Invoke-WebRequest -Uri $bbUrl -OutFile $bbCache -UseBasicParsing
        }
        $bbGot = (Get-FileHash $bbCache -Algorithm SHA256).Hash.ToLower()
        if ($bbGot -ne $bbSha256) {
            Remove-Item $bbCache -Force -ErrorAction SilentlyContinue
            throw "BusyBox : SHA-256 inattendu ($bbGot, attendu $bbSha256) - fichier refuse. Relancez avec -IncludeToolbox:`$false pour construire sans la boite a outils."
        }
        Copy-Item $bbCache (Join-Path $toolboxDir "busybox.exe") -Force

        # Fichiers du diagnostic, ecrits en LF sans BOM (busybox sh n'aime pas le CRLF).
        $tbSources = @{
            "sonar_diag_winpe.sh" = Join-Path $PSScriptRoot "winpe\sonar_diag_winpe.sh"
            "sonar_check_awk.sh"  = Join-Path $PSScriptRoot "winpe\sonar_check_awk.sh"
            "diag_engine.awk"     = Join-Path $PSScriptRoot "diag_engine.awk"
            "diag_rules.txt"      = Join-Path $PSScriptRoot "diag_rules.txt"
            "sonar_assistant.sh"  = Join-Path $PSScriptRoot "winpe\sonar_assistant.sh"
            "sonar_banner.txt"    = Join-Path $PSScriptRoot "winpe\sonar_banner.txt"
        }
        foreach ($name in $tbSources.Keys) {
            $src = $tbSources[$name]
            if (-not (Test-Path $src)) { throw "Boite a outils : fichier source introuvable : $src" }
            $text = [System.IO.File]::ReadAllText($src) -replace "`r`n", "`n"
            [System.IO.File]::WriteAllText((Join-Path $toolboxDir $name), $text, (New-Object System.Text.UTF8Encoding($false)))
        }
        Write-Host "Boite a outils preparee : $toolboxDir"
    }

    # Fond d'ecran SONAR (remplace le fond bleu uni de WinPE) : Branding\default_background.png -> winpe.jpg.
    # Non bloquant : sans image ou sans System.Drawing, le WinPE garde son fond d'origine.
    $wallpaperJpg = $null
    $wallSrc = Join-Path $PSScriptRoot "..\Branding\default_background.png"
    if (Test-Path $wallSrc) {
        try {
            Add-Type -AssemblyName System.Drawing
            $wallpaperJpg = Join-Path $WorkDir "winpe.jpg"
            $img = [System.Drawing.Image]::FromFile((Resolve-Path $wallSrc).Path)
            try { $img.Save($wallpaperJpg, [System.Drawing.Imaging.ImageFormat]::Jpeg) } finally { $img.Dispose() }
            Write-Host "Fond d'ecran SONAR prepare : $wallpaperJpg"
        } catch {
            Write-Warning "Fond d'ecran SONAR non genere ($($_.Exception.Message)) : le fond WinPE d'origine est conserve."
            $wallpaperJpg = $null
        }
    }

    # Menu batch pur (pas de PowerShell) : reprend exactement les commandes
    # documentees dans docs/WINPE.md (bootrec, bcdedit, diskpart, DISM),
    # juste presentees sans que le technicien ait a en memoriser la syntaxe.
    $menuLines = @(
        "@echo off"
        "wpeinit"
        "rem Clavier AZERTY francais par defaut (langue 040c, disposition 0000040c)"
        "wpeutil SetKeyboardLayout 040c:0000040c"
        "title SONAR - SE"
        "set SB=%SystemRoot%\System32\sonar"
        ":start"
        "cls"
        "call :banner"
        "echo   Bienvenue. SONAR enchaine les etapes ; vous n'avez qu'a repondre oui ou non."
        "echo."
        "echo     [Entree]  Assistant guide (recommande)"
        "echo     [M]       Menu manuel (outils a la carte)"
        "echo."
        "set ANS="
        "set /p ANS=Votre choix : "
        "if /i `"%ANS%`"==`"M`" goto menu"
        "if not exist `"%SB%\sonar_assistant.sh`" (echo Assistant absent de cette image ^(reconstruire avec -IncludeToolbox^) - menu manuel. & pause & goto menu)"
        "goto assistant"
        ""
        ":banner"
        "if exist `"%SB%\sonar_banner.txt`" (`"%SB%\busybox.exe`" cat `"%SB%\sonar_banner.txt`") else (echo   SONAR - SE  ^|  Assistant de depannage)"
        "exit /b 0"
        ""
        ":assistant"
        "cls"
        "call :banner"
        "call :findkey"
        "set OUT=X:\sonar_assist"
        "if defined KEY set OUT=%KEY%\Field-Logs\assistant"
        "if not exist `"%OUT%`" mkdir `"%OUT%`""
        "rem chemins en barres obliques pour busybox/awk (awk -v interprete les antislashs)"
        "set SBF=%SB:\=/%"
        "set OUTF=%OUT:\=/%"
        "call :diagsources"
        "echo."
        "set SONAR_KEY=%KEY%"
        "set SONAR_SB=%SBF%"
        "set SONAR_ENGINE=%ENGF%"
        "set SONAR_RULES=%RULF%"
        "set SONAR_OUT=%OUTF%"
        "set SONAR_RULSRC=%RULSRC%"
        "set SONAR_ENGSRC=%ENGSRC%"
        "`"%SB%\busybox.exe`" sh `"%SBF%/sonar_assistant.sh`""
        "echo."
        "pause"
        "goto menu"
        ""
        ":menu"
        "cls"
        "echo ============================================"
        "echo   SONAR-SE WinPE - Menu de reparation"
        "echo ============================================"
        "echo 1. Reparer le demarrage (bootrec : fixmbr, fixboot, rebuildbcd)"
        "echo 2. Configuration de boot (bcdedit, invite interactive)"
        "echo 3. Gestion des disques/partitions (diskpart)"
        "echo 4. Verifier/reparer une image Windows hors ligne (DISM)"
        "echo 5. Verifier les fichiers systeme hors ligne (SFC)"
        "echo 6. Deverrouiller un disque BitLocker"
        "echo 7. Injecter des pilotes dans le disque cible"
        "echo 8. Sauvegarder des fichiers utilisateur"
        "echo 9. Exporter les journaux d'evenements (.evtx)"
        "echo 10. Diagnostic reseau (ipconfig, ping)"
        "echo 11. Invite de commandes libre (cmd.exe)"
        "echo 12. DIAGNOSTIC INTELLIGENT (analyse, score, plan d'action)"
        "echo 13. Reparation UEFI automatique (bcdboot vers l'ESP)"
        "echo 14. Charger un pilote de stockage (drvload) et re-scanner"
        "echo 15. Lancer un outil portable de la cle (CrystalDiskInfo...)"
        "echo 16. Shell BusyBox (ls, grep, awk, vi, tar...)"
        "echo 17. PowerShell (si present dans cette image)"
        "echo 18. Relancer l'assistant guide (etapes automatiques, oui/non)"
        "echo 0. Redemarrer"
        "echo ============================================"
        "set /p choix=Choix : "
        "if `"%choix%`"==`"1`" goto bootrec"
        "if `"%choix%`"==`"2`" goto bcdedit_menu"
        "if `"%choix%`"==`"3`" goto diskpart_menu"
        "if `"%choix%`"==`"4`" goto dism_menu"
        "if `"%choix%`"==`"5`" goto sfc_menu"
        "if `"%choix%`"==`"6`" goto bitlocker_menu"
        "if `"%choix%`"==`"7`" goto driver_menu"
        "if `"%choix%`"==`"8`" goto backup_menu"
        "if `"%choix%`"==`"9`" goto eventlog_menu"
        "if `"%choix%`"==`"10`" goto network_menu"
        "if `"%choix%`"==`"11`" goto cmdfree"
        "if `"%choix%`"==`"12`" goto diag_menu"
        "if `"%choix%`"==`"13`" goto uefi_repair"
        "if `"%choix%`"==`"14`" goto drvload_menu"
        "if `"%choix%`"==`"15`" goto tools_menu"
        "if `"%choix%`"==`"16`" goto bb_shell"
        "if `"%choix%`"==`"17`" goto ps_shell"
        "if `"%choix%`"==`"18`" goto assistant"
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
        ":sfc_menu"
        "cls"
        "echo --- Verification des fichiers systeme hors ligne (SFC) ---"
        "echo Complementaire a DISM : DISM repare le magasin de composants,"
        "echo SFC remplace les fichiers systeme proteges corrompus."
        "set /p lettre=Lettre du lecteur Windows cible (ex: C) : "
        "if not exist `"%lettre%:\Windows`" (echo Windows introuvable sur %lettre%:\ - verifiez la lettre. & pause & goto menu)"
        "echo Lancement de sfc /scannow en mode hors ligne (peut prendre du temps)..."
        "sfc /scannow /offbootdir=%lettre%:\ /offwindir=%lettre%:\Windows"
        "echo."
        "echo Termine. Appuyez sur une touche pour revenir au menu."
        "pause"
        "goto menu"
        ""
        ":bitlocker_menu"
        "cls"
        "echo --- Deverrouillage BitLocker ---"
        "if not exist `"%WINDIR%\System32\manage-bde.exe`" (echo. & echo manage-bde.exe absent de cette image WinPE ^(composants ADK non ajoutes au build : VirtualBox absent ou -IncludeAdkComponents:$false^). & echo Alternative : demarrer SystemRescue puis SONAR Field, option b ^(deverrouillage BitLocker en lecture seule^). & echo. & pause & goto menu)"
        "manage-bde -status"
        "echo."
        "echo Necessaire avant bootrec/DISM/SFC si le disque cible est chiffre"
        "echo (chiffrement de l'appareil active par defaut sur la plupart des"
        "echo PC recents) - sinon ces outils ne peuvent pas lire le disque."
        "set /p lettre=Lettre du lecteur chiffre (ex: C) : "
        "echo."
        "echo 1. Deverrouiller avec la cle de recuperation (48 chiffres)"
        "echo 2. Deverrouiller avec un fichier de cle (.bek) sur un support externe"
        "set /p blchoix=Choix : "
        "if `"%blchoix%`"==`"1`" goto bitlocker_recovery"
        "if `"%blchoix%`"==`"2`" goto bitlocker_bek"
        "goto menu"
        ":bitlocker_recovery"
        "set /p reckey=Cle de recuperation (xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx) : "
        "manage-bde -unlock %lettre%: -RecoveryPassword %reckey%"
        "echo."
        "pause"
        "goto menu"
        ":bitlocker_bek"
        "set /p bekpath=Chemin complet du fichier .bek (ex: E:\recovery.bek) : "
        "manage-bde -unlock %lettre%: -RecoveryKey `"%bekpath%`""
        "echo."
        "pause"
        "goto menu"
        ""
        ":driver_menu"
        "cls"
        "echo --- Injection de pilotes dans le disque cible ---"
        "echo Utile si diskpart/bootrec ne voient aucun disque (controleur"
        "echo NVMe/RAID recent absent du WinPE de base) - injecte les pilotes"
        "echo du dossier Drivers/ de la cle SONAR-SE dans le disque cible."
        "set /p lettre=Lettre du lecteur Windows cible (ex: C) : "
        "set /p drvpath=Dossier de pilotes (ex: E:\Drivers) : "
        "if not exist `"%drvpath%`" (echo Dossier introuvable : %drvpath% & pause & goto menu)"
        "echo Injection des pilotes de %drvpath% dans %lettre%:\ ..."
        "Dism /Image:%lettre%:\ /Add-Driver /Driver:`"%drvpath%`" /Recurse"
        "echo."
        "echo Termine. Appuyez sur une touche pour revenir au menu."
        "pause"
        "goto menu"
        ""
        ":backup_menu"
        "cls"
        "echo --- Sauvegarde de fichiers utilisateur ---"
        "echo A faire AVANT toute reparation risquee si des donnees"
        "echo importantes n'ont pas d'autre copie."
        "set /p srcpath=Dossier source (ex: C:\Users\NomUtilisateur) : "
        "set /p dstpath=Destination (ex: E:\Sauvegarde) : "
        "if not exist `"%srcpath%`" (echo Dossier source introuvable : %srcpath% & pause & goto menu)"
        "echo Copie de %srcpath% vers %dstpath% (peut prendre du temps)..."
        "robocopy `"%srcpath%`" `"%dstpath%`" /E /R:1 /W:1 /XJ /TEE /LOG+:X:\sonar_backup.log"
        "echo."
        "echo Termine. Journal : X:\sonar_backup.log"
        "pause"
        "goto menu"
        ""
        ":eventlog_menu"
        "cls"
        "echo --- Export des journaux d'evenements ---"
        "echo Pour diagnostiquer POURQUOI le demarrage a echoue avant de"
        "echo lancer une reparation a l'aveugle."
        "set /p lettre=Lettre du lecteur Windows cible (ex: C) : "
        "set /p dstpath=Destination (ex: E:\Logs) : "
        "if not exist `"%lettre%:\Windows\System32\winevt\Logs`" (echo Journaux introuvables sur %lettre%:\ - verifiez la lettre. & pause & goto menu)"
        "if not exist `"%dstpath%`" mkdir `"%dstpath%`""
        "echo Copie des journaux .evtx vers %dstpath% ..."
        "robocopy `"%lettre%:\Windows\System32\winevt\Logs`" `"%dstpath%`" *.evtx /R:1 /W:1"
        "echo."
        "echo Termine. Journaux copies dans %dstpath%"
        "pause"
        "goto menu"
        ""
        ":network_menu"
        "cls"
        "echo --- Diagnostic reseau ---"
        "ipconfig /all"
        "echo."
        "set /p cible=Adresse a tester (ex: 8.8.8.8, ou Entree pour passer) : "
        "if not `"%cible%`"==`"`" ping %cible%"
        "echo."
        "pause"
        "goto menu"
        ""
        ":cmdfree"
        "cls"
        "cmd /k"
        "goto menu"
        ""
        ":findkey"
        "rem Repere la cle SONAR-SE : le lecteur D: a Z: qui porte MANIFEST\PROFILES.tsv (C: est le disque du client,"
        "rem X: le WinPE lui-meme : ni l'un ni l'autre ne sont cherches)"
        "set KEY="
        "for %%d in (D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%d:\MANIFEST\PROFILES.tsv set KEY=%%d:"
        "exit /b 0"
        ""
        ":diagsources"
        "rem Sources du diagnostic : la CLE SONAR-SE si elle porte les fichiers, sinon la copie INTEGREE a l'ISO."
        "rem Regles (donnees) et moteur (code awk) sont choisis separement ; le moteur de la cle passe d'abord par"
        "rem sonar_check_awk.sh (refus s'il execute des commandes ou ecrit des fichiers). L'origine est TOUJOURS affichee."
        "set ENGF=%SBF%/diag_engine.awk"
        "set RULF=%SBF%/diag_rules.txt"
        "set ENGSRC=INTEGRE dans l'ISO"
        "set RULSRC=INTEGREES dans l'ISO"
        "if not defined KEY goto diagsrc_show"
        "set KFR=%KEY%/MANIFEST/DIAG_RULES.txt"
        "set KFE=%KEY%/Scripts/diag_engine.awk"
        "if exist `"%KFR%`" ("
        "    set `"RULF=%KFR%`""
        "    set `"RULSRC=CLE %KEY% (MANIFEST\DIAG_RULES.txt)`""
        ")"
        "if not exist `"%KFE%`" goto diagsrc_show"
        "`"%SB%\busybox.exe`" sh `"%SBF%/sonar_check_awk.sh`" `"%KFE%`""
        "if errorlevel 1 goto diagsrc_refused"
        "set `"ENGF=%KFE%`""
        "set `"ENGSRC=CLE %KEY% (Scripts\diag_engine.awk)`""
        "goto diagsrc_show"
        ":diagsrc_refused"
        "set `"ENGSRC=INTEGRE dans l'ISO (moteur de la cle REFUSE : il execute des commandes ou ecrit des fichiers)`""
        ":diagsrc_show"
        "set NRUL=?"
        "rem (pas de for /f ici : une commande entre '...' avec plus de deux guillemets est deformee par cmd /c)"
        "`"%SB%\busybox.exe`" grep -Evc `"^[[:space:]]*(#|$)`" `"%RULF%`" > X:\sonar_nrul.txt 2>nul"
        "if exist X:\sonar_nrul.txt set /p NRUL=<X:\sonar_nrul.txt"
        "echo Sources du diagnostic :"
        "echo    regles : %RULSRC% - %NRUL% regle(s)"
        "echo    moteur : %ENGSRC%"
        "if not defined KEY echo    (cle SONAR-SE non detectee : copies integrees a l'ISO utilisees)"
        "exit /b 0"
        ""
        ":diag_menu"
        "cls"
        "echo --- DIAGNOSTIC INTELLIGENT (lecture seule) ---"
        "echo Collecte disques, volumes, ESP/BCD, BitLocker, hibernation, firmware,"
        "echo puis le moteur de regles conclut : score, causes, plan d'action."
        "set SB=%SystemRoot%\System32\sonar"
        "if not exist `"%SB%\busybox.exe`" (echo Boite a outils absente de cette image ^(reconstruire avec -IncludeToolbox^). & pause & goto menu)"
        "call :findkey"
        "set OUT=X:\sonar_diag"
        "if defined KEY set OUT=%KEY%\Field-Logs\diag"
        "if not exist `"%OUT%`" mkdir `"%OUT%`""
        "set STAMP=manuel"
        "for /f %%t in ('`"%SB%\busybox.exe`" date +%%Y%%m%%d_%%H%%M%%S') do set STAMP=%%t"
        "set SYMPT="
        "set /p SYMPT=Symptome [boot / bsod / slow / data / virus / password / other, Entree = aucun] : "
        "echo Collecte en cours (quelques secondes)..."
        "rem awk -v interprete les antislashs (\s, \d...) : chemins passes en barres obliques"
        "set SBF=%SB:\=/%"
        "set OUTF=%OUT:\=/%"
        "call :diagsources"
        "`"%SB%\busybox.exe`" sh `"%SBF%/sonar_diag_winpe.sh`" `"%OUTF%/DIAG_%STAMP%.facts`""
        "`"%SB%\busybox.exe`" awk -f `"%ENGF%`" -v `"FACTS=%OUTF%/DIAG_%STAMP%.facts`" -v `"RULES=%RULF%`" -v `"SYMPTOM=%SYMPT%`" -v MODE=report > `"%OUT%\DIAG_%STAMP%.txt`""
        "rem la trace de l'origine des regles/du moteur est dans le rapport lui-meme (redirection en tete : un chiffre avant > serait un numero de handle)"
        ">> `"%OUT%\DIAG_%STAMP%.txt`" echo Sources : regles = %RULSRC% ; moteur = %ENGSRC%"
        "`"%SB%\busybox.exe`" cat `"%OUT%\DIAG_%STAMP%.txt`" | more"
        "echo."
        "if defined KEY (echo Rapport enregistre sur la cle : %OUT%\DIAG_%STAMP%.txt) else (echo Cle SONAR-SE non detectee - rapport dans X:\sonar_diag ^(perdu au redemarrage^))"
        "pause"
        "goto menu"
        ""
        ":uefi_repair"
        "cls"
        "echo --- Reparation UEFI automatique (bcdboot) ---"
        "echo Reconstruit les fichiers de demarrage (bootmgfw.efi + BCD) de l'ESP"
        "echo a partir du Windows installe. Ne touche PAS aux donnees."
        "echo Si le disque est chiffre (BitLocker), deverrouillez-le d'abord (option 6)."
        "echo."
        "set /p lettre=Lettre du Windows cible (ex: C) : "
        "if not exist `"%lettre%:\Windows\System32\config\SYSTEM`" (echo Windows introuvable sur %lettre%:\ - verifiez la lettre. & pause & goto menu)"
        "echo list volume> X:\sonar_dp1.txt"
        "diskpart /s X:\sonar_dp1.txt"
        "echo."
        "echo Reperez le volume ESP : FAT32, info Systeme, ~100 a 500 Mo."
        "set /p espvol=Numero du volume ESP (Entree = annuler) : "
        "if `"%espvol%`"==`"`" goto menu"
        ">X:\sonar_dp2.txt echo select volume %espvol%"
        ">>X:\sonar_dp2.txt echo assign letter=S"
        "diskpart /s X:\sonar_dp2.txt"
        "if not exist S:\ (echo Attribution de la lettre S: impossible - abandon. & pause & goto menu)"
        "set /p go=Reconstruire l'ESP S: depuis %lettre%:\Windows ? (o/n) : "
        "if /i `"%go%`"==`"o`" bcdboot %lettre%:\Windows /s S: /f UEFI"
        ">X:\sonar_dp3.txt echo select volume %espvol%"
        ">>X:\sonar_dp3.txt echo remove letter=S"
        "diskpart /s X:\sonar_dp3.txt >nul"
        "echo."
        "echo Termine. Redemarrez (option 0) et testez le demarrage."
        "pause"
        "goto menu"
        ""
        ":drvload_menu"
        "cls"
        "echo --- Charger un pilote de stockage dans le WinPE en cours ---"
        "echo Utile si diskpart ne voit aucun disque (NVMe / Intel VMD-RST / RAID)."
        "echo Le pilote n'est charge que pour cette session ; rien n'est modifie sur le disque."
        "call :findkey"
        "if defined KEY echo Dossier conseille : %KEY%\Drivers"
        "set /p inf=Chemin d'un .inf ou d'un dossier de pilotes : "
        "if `"%inf%`"==`"`" goto menu"
        "if /i `"%inf:~-4%`"==`".inf`" (drvload `"%inf%`") else (for /r `"%inf%`" %%f in (*.inf) do drvload `"%%f`")"
        "echo rescan> X:\sonar_dp4.txt"
        "echo list disk>> X:\sonar_dp4.txt"
        "diskpart /s X:\sonar_dp4.txt"
        "echo."
        "pause"
        "goto menu"
        ""
        ":tools_menu"
        "cls"
        "echo --- Outils portables de la cle ---"
        "call :findkey"
        "if not defined KEY (echo Cle SONAR-SE non detectee. & pause & goto menu)"
        "if not exist `"%KEY%\Portable`" (echo Dossier %KEY%\Portable absent. & pause & goto menu)"
        "dir /s /b `"%KEY%\Portable\*.exe`""
        "echo."
        "set /p tool=Chemin complet de l'outil a lancer (Entree = retour) : "
        "if `"%tool%`"==`"`" goto menu"
        "start `"`" `"%tool%`""
        "goto menu"
        ""
        ":ps_shell"
        "cls"
        "if not exist `"%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe`" (echo PowerShell absent de cette image ^(composants ADK non ajoutes au build^). & pause & goto menu)"
        "echo --- PowerShell --- tapez exit pour revenir au menu."
        "powershell -NoLogo -NoProfile"
        "goto menu"
        ""
        ":bb_shell"
        "cls"
        "echo --- Shell BusyBox --- tapez exit pour revenir au menu."
        "if not exist `"%SystemRoot%\System32\sonar\busybox.exe`" (echo Boite a outils absente de cette image. & pause & goto menu)"
        "`"%SystemRoot%\System32\sonar\busybox.exe`" sh"
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
        "::TOOLBOX::"
        "::WALLPAPER::"
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
    $toolboxScriptLines = @("echo [%date% %time%] Boite a outils non demandee - ignoree")
    if ($toolboxDir) {
        $toolboxScriptLines = @(
            "echo [%date% %time%] Installation de la boite a outils (BusyBox + diagnostic)"
            "mkdir `"$menuMountDir\Windows\System32\sonar`""
            "xcopy /y /q `"$toolboxDir\*`" `"$menuMountDir\Windows\System32\sonar\`""
            "if !errorlevel! neq 0 goto :fail_mounted"
            "if not exist `"$menuMountDir\Windows\System32\sonar\busybox.exe`" goto :fail_mounted"
        )
    }
    # Fond d'ecran SONAR : propriete de TrustedInstaller si un winpe.jpg existe deja -> takeown/icacls avant de le remplacer.
    # Un echec ici n'annule pas le build (le fond d'origine reste).
    $wallScriptLines = @("echo [%date% %time%] Fond d'ecran SONAR non demande - ignore")
    if ($wallpaperJpg) {
        $wpTarget = "$menuMountDir\Windows\System32\winpe.jpg"
        $wallScriptLines = @(
            "echo [%date% %time%] Fond d'ecran SONAR"
            "if exist `"$wpTarget`" takeown /f `"$wpTarget`" >nul & icacls `"$wpTarget`" /grant Administrators:F >nul"
            "copy /y `"$wallpaperJpg`" `"$wpTarget`" >nul"
            "if !errorlevel! neq 0 echo [%date% %time%] AVERTISSEMENT : fond d'ecran SONAR non copie - fond d'origine conserve"
        )
    }
    $menuScriptLines = @($menuScriptLines | ForEach-Object { if ($_ -eq "::TOOLBOX::") { $toolboxScriptLines } elseif ($_ -eq "::WALLPAPER::") { $wallScriptLines } else { $_ } })
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

if ($IncludeBitLockerTools) {
    Write-Host "== Ajout du support BitLocker (WinPE-SecureStartup) a l'image WinPE (montage DISM, elevation requise) =="
    $ocDir = Join-Path $WinPeDir "amd64\WinPE_OCs"
    $mountDir = Join-Path $WorkDir "mount_bitlocker"
    New-Item -ItemType Directory -Force -Path $mountDir | Out-Null
    $bootWim = Join-Path $stageDir "media\sources\boot.wim"
    $neutral = Join-Path $ocDir "WinPE-SecureStartup.cab"
    $lang = Join-Path $ocDir "en-us\WinPE-SecureStartup_en-us.cab"
    if (-not (Test-Path $neutral) -or -not (Test-Path $lang)) {
        throw "Composant WinPE-SecureStartup introuvable sous '$ocDir' — ADK/add-on WinPE incomplet ou version differente."
    }
    $pkgScript = Join-Path $WorkDir "add_bitlocker.cmd"
    $pkgLog = Join-Path $WorkDir "bitlocker_add_log.txt"
    # Meme schema que le bloc -IncludePowerShell ci-dessus (voir ses
    # commentaires pour le detail de chaque choix) : redirection portee
    # par le .cmd lui-meme, Cleanup-Mountpoints en preambule,
    # !errorlevel! en comparaison numerique directe, discard sur echec.
    $lines = @(
        "@echo off"
        "setlocal enabledelayedexpansion"
        "call :main > `"$pkgLog`" 2>&1"
        "exit /b !errorlevel!"
        ""
        ":main"
        "call `"$setEnvBat`""
        "Dism /Cleanup-Mountpoints"
        "Dism /Mount-Image /ImageFile:`"$bootWim`" /Index:1 /MountDir:`"$mountDir`""
        "if !errorlevel! neq 0 exit /b 1"
        "Dism /Image:`"$mountDir`" /Add-Package /PackagePath:`"$neutral`""
        "if !errorlevel! neq 0 goto :fail_mounted"
        "Dism /Image:`"$mountDir`" /Add-Package /PackagePath:`"$lang`""
        "if !errorlevel! neq 0 goto :fail_mounted"
        "Dism /Unmount-Image /MountDir:`"$mountDir`" /Commit"
        "if !errorlevel! neq 0 goto :fail_mounted"
        "exit /b 0"
        ""
        ":fail_mounted"
        "Dism /Unmount-Image /MountDir:`"$mountDir`" /Discard"
        "exit /b 1"
    )
    $lines | Set-Content -Path $pkgScript -Encoding ASCII

    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$pkgScript`"" -Verb RunAs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "== Log ajout BitLocker =="
        if (Test-Path $pkgLog) {
            Get-Content $pkgLog -ErrorAction SilentlyContinue | Write-Host
        } else {
            Write-Host "(aucun fichier log produit — voir $pkgScript pour la commande exacte)"
        }
        throw "Echec de l'ajout du support BitLocker a l'image (code $($proc.ExitCode)) — voir le log ci-dessus. Meme limite connue documentee pour -IncludePowerShell ; relancez sans -IncludeBitLockerTools pour l'image sans BitLocker (le reste du menu de reparation fonctionne normalement)."
    }
    Write-Host "Support BitLocker ajoute avec succes."
}

$OutputIso = [System.IO.Path]::GetFullPath($OutputIso)
$outputDir = Split-Path $OutputIso -Parent
if ($outputDir -and -not (Test-Path $outputDir)) { New-Item -ItemType Directory -Force -Path $outputDir | Out-Null }

Write-Host "== Génération de l'ISO =="
$isoLog = Join-Path $WorkDir "iso_log.txt"
# oscdimg.exe appele DIRECTEMENT, sans passer par MakeWinPEMedia.cmd, et
# SANS elevation (-Verb RunAs) — root cause confirmee le 2026-09-17 apres
# plusieurs heures d'isolation : le probleme n'etait ni oscdimg, ni le
# fichier de destination deja existant, ni un verrou externe (VirtualBox,
# montage DISM orphelin) — TOUS ecartes par test direct. C'est
# specifiquement le fait de lancer oscdimg (via MakeWinPEMedia.cmd ou
# directement) a travers "Start-Process -Verb RunAs" qui produisait soit
# l'invite interactive fantome "Destination file ... exists, overwrite it
# [O,N]?" (jamais emise par oscdimg lui-meme en execution directe), soit un
# ISO au boot.wim inchange malgre un "100% complete" affiche. oscdimg
# n'ecrit qu'un fichier dans un dossier utilisateur ordinaire — il n'a
# JAMAIS eu besoin de droits admin ; seul le montage DISM (menu de
# reparation, plus haut) en a reellement besoin. Execution non-elevee
# testee et confirmee correcte (boot.wim contient bien le menu) a plusieurs
# reprises. -bootdata reconstruit nous-memes a partir du dossier bootbins
# de l'ADK (copype le copie dans <stageDir>\bootbins). Reference :
# ISOWorker_OscdImgCommand dans MakeWinPEMedia.cmd pour la formule.
$oscdimgExe = Find-ToolInAdk "oscdimg.exe"
if (-not $oscdimgExe) { throw "oscdimg.exe introuvable dans l'ADK sous '$AdkRoot'." }
# copype copie les binaires de boot dans <stageDir>\bootbins (pas dans
# l'arborescence de l'ADK lui-meme) — meme dossier que MakeWinPEMedia.cmd
# utilise via %WORKINGDIR%\%BOOTBINS% (BOOTBINS="bootbins" en dur dans ce
# .cmd). Verifie par test manuel reussi le 2026-09-17.
$bootbinsDir = Join-Path $stageDir "bootbins"
$etfsboot = Join-Path $bootbinsDir "etfsboot.com"
$efisys = Join-Path $bootbinsDir "efisys.bin"
if (-not (Test-Path $etfsboot) -or -not (Test-Path $efisys)) {
    throw "Fichiers de boot introuvables sous '$bootbinsDir' (etfsboot.com / efisys.bin) — ADK/add-on WinPE incomplet ou disposition differente."
}
if (Test-Path $OutputIso) { Remove-Item -LiteralPath $OutputIso -Force }
$bootData = "2#p0,e,b`"$etfsboot`"#pEF,e,b`"$efisys`""
$mediaDir = Join-Path $stageDir "media"
# oscdimg ecrit sa progression sur stderr — avec $ErrorActionPreference
# = "Stop" (global, en tete de script), capturer stderr via "2>&1" fait
# lever une NativeCommandError terminale a la PREMIERE ligne de stderr,
# meme quand oscdimg reussit au final (code de sortie 0). ErrorAction
# Continue localement pour ce seul appel evite ça sans affaiblir le
# Stop global pour le reste du script.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$oscdimgOutput = & $oscdimgExe "-bootdata:$bootData" -u1 -udfver102 $mediaDir $OutputIso 2>&1
$ErrorActionPreference = $prevEap
try {
    $oscdimgOutput | Out-String | Set-Content -Path $isoLog -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Host "(log d'oscdimg non ecrit — fichier verrouille par un reste d'execution precedente, sans rapport avec le resultat ci-dessous)"
}
if (-not (Test-Path $OutputIso)) {
    Get-Content $isoLog -ErrorAction SilentlyContinue | Write-Host
    throw "Échec de la génération de l'ISO — voir $isoLog ci-dessus."
}

if ($AddRepairMenu) {
    # Verification post-generation indispensable : le bug MakeWinPEMedia.cmd
    # corrige ci-dessus (destination deja existante -> invite interactive
    # jamais repondue -> boot.wim non modifie dans l'ISO final) etait
    # SILENCIEUX — le script rapportait un succes complet (ISO de taille et
    # hash plausibles) tout en produisant un artefact casse. Seul un boot
    # reel en VM l'a revele. Remonter l'ISO final et verifier le contenu de
    # startnet.cmd directement evite de redecouvrir ce genre de bug a la
    # main a chaque fois.
    Write-Host "== Verification du menu dans l'ISO final =="
    $verifyMountDir = Join-Path $WorkDir "verify_final_iso"
    New-Item -ItemType Directory -Force -Path $verifyMountDir | Out-Null
    $isoMount = Mount-DiskImage -ImagePath $OutputIso -PassThru
    $isoVol = $isoMount | Get-Volume
    $isoDrive = $isoVol.DriveLetter
    $verifyLog = Join-Path $WorkDir "verify_final_iso.log"
    $verifyScript = Join-Path $WorkDir "verify_final_iso.cmd"
    $verifyLines = @(
        "@echo off"
        "setlocal enabledelayedexpansion"
        "call :main > `"$verifyLog`" 2>&1"
        "exit /b !errorlevel!"
        ""
        ":main"
        "call `"$setEnvBat`""
        "Dism /Cleanup-Mountpoints"
        "Dism /Mount-Image /ImageFile:`"${isoDrive}:\sources\boot.wim`" /Index:1 /MountDir:`"$verifyMountDir`" /ReadOnly"
        "if !errorlevel! neq 0 exit /b 1"
        "findstr /C:`"SONAR-SE WinPE - Menu de reparation`" `"$verifyMountDir\Windows\System32\startnet.cmd`" >nul"
        "set FOUND=!errorlevel!"
        "if !FOUND! equ 0 findstr /C:`"diag_menu`" `"$verifyMountDir\Windows\System32\startnet.cmd`" >nul"
        "if !FOUND! equ 0 set FOUND=!errorlevel!"
        "Dism /Unmount-Image /MountDir:`"$verifyMountDir`" /Discard"
        "exit /b !FOUND!"
    )
    if ($toolboxDir) {
        $verifyLines = @($verifyLines | ForEach-Object { $_; if ($_ -like '*if !FOUND! equ 0 set FOUND=!errorlevel!*') { "if !FOUND! equ 0 if not exist `"$verifyMountDir\Windows\System32\sonar\busybox.exe`" set FOUND=2"; "if !FOUND! equ 0 if not exist `"$verifyMountDir\Windows\System32\sonar\diag_engine.awk`" set FOUND=2"; "if !FOUND! equ 0 if not exist `"$verifyMountDir\Windows\System32\sonar\sonar_assistant.sh`" set FOUND=2"; "if !FOUND! equ 0 (findstr /C:`"SetKeyboardLayout 040c:0000040c`" `"$verifyMountDir\Windows\System32\startnet.cmd`" >nul || set FOUND=4)" } })
    }
    if ($serviced) {
        $verifyLines = @($verifyLines | ForEach-Object { $_; if ($_ -like '*if !FOUND! equ 0 set FOUND=!errorlevel!*') { "if !FOUND! equ 0 if not exist `"$verifyMountDir\Windows\System32\manage-bde.exe`" set FOUND=3"; "if !FOUND! equ 0 if not exist `"$verifyMountDir\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`" set FOUND=3" } })
    }
    $verifyLines | Set-Content -Path $verifyScript -Encoding ASCII
    $verifyProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$verifyScript`"" -Verb RunAs -Wait -PassThru
    Dismount-DiskImage -ImagePath $OutputIso | Out-Null
    if ($verifyProc.ExitCode -ne 0) {
        Get-Content $verifyLog -ErrorAction SilentlyContinue | Write-Host
        throw "L'ISO generee ($OutputIso) ne contient PAS le menu de reparation attendu dans startnet.cmd — voir le log ci-dessus. Ne pas deployer cet ISO tel quel."
    }
    Write-Host "Menu de reparation confirme present dans l'ISO finale."
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
