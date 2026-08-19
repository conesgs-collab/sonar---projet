# Catalogue complet des outils SONAR

Ce document est **généré directement depuis les données embarquées dans
`sonar_master.sh`** (extraction automatisée, pas de retranscription
manuelle) — voir la commande de régénération en bas de page.

## Ce que ce catalogue est — et n'est pas

Le catalogue est une **liste de référence** : les outils qu'il recense sont
ceux que SONAR *connaît, documente et peut aider à organiser/déployer* dans
son builder (`--builder`, profils MINIMAL/TECHNICIAN/RECOVERY/FORENSIC/
ADMIN/FULL/CUSTOM). Il ne signifie **pas** que chaque outil est embarqué
binaire sur la clé par défaut, ni que chacun a été validé sur matériel réel
— voir la colonne `VALIDATION` du catalogue "V2" (structurel) pour le
statut réel de chaque composant SONAR lui-même, et `ROADMAP.md` pour l'état
global de validation matérielle du projet.

**Domaines explicitement hors périmètre** (voir aussi la conversation) :
téléphonie mobile (pas d'ADB/Fastboot/JTAG), vidéosurveillance/CCTV (pas
d'ONVIF/RTSP dédié à ce jour).

## Statistiques

- **69 domaines**
- **936 outils/composants** recensés au total

## Résumé par domaine (nombre d'outils)

```
 1. Systèmes d'exploitation & virtualisation                13 outils
 2. 2. Administration système                               29 outils
 3. 3. Réseaux                                              24 outils
 4. 4. Cybersécurité                                       33 outils
 5. 5. Développement logiciel                               37 outils
 6. 6. Gestion du code source                                13 outils
 7. 7. DevOps / CI-CD                                        15 outils
 8. 8. Bases de données                                     22 outils
 9. 9. Web / serveurs                                        26 outils
10. 10. Cloud / infrastructure                               21 outils
11. 11. Stockage / sauvegarde / récupération               25 outils
12. 12. Boot / ISO / installation                            21 outils
13. 13. UEFI / BIOS / firmware                               17 outils
14. 14. Diagnostic matériel                                 27 outils
15. 15. Monitoring                                           12 outils
16. 16. Logs / SIEM                                          11 outils
17. 17. Automatisation                                       18 outils
18. 18. Gestion des paquets                                  16 outils
19. 19. Bureau / bureautique                                 14 outils
20. 20. Graphisme / design                                   14 outils
21. 21. Vidéo                                               11 outils
22. 22. Audio                                                11 outils
23. 23. 3D / CAO / ingénierie                               15 outils
24. 24. IA / Machine Learning / Data Science                 24 outils
25. 25. Data engineering / Big Data                          10 outils
26. 26. Blockchain / Web3                                     9 outils
27. 27. Messagerie / communication                           11 outils
28. 28. Navigateurs                                           9 outils
29. 29. Télémaintenance                                    10 outils
30. 30. Gestion de fichiers                                  21 outils
31. 31. Chiffrement / sécurité des données                10 outils
32. 32. Gestion des mots de passe                             7 outils
33. 33. Analyse réseau avancée                             10 outils
34. 34. Reverse engineering                                  12 outils
35. 35. Débogage                                            15 outils
36. 36. Analyse mémoire / performances                      13 outils
37. 37. Gestion de parc informatique                         10 outils
38. 38. ITSM / Helpdesk                                       8 outils
39. 39. Inventaire matériel / logiciel                       8 outils
40. 40. Serveurs de fichiers / NAS                            8 outils
41. 41. Active Directory / identité                          8 outils
42. 42. PKI / certificats                                     7 outils
43. 43. DNS / DHCP                                            8 outils
44. 44. Serveurs mail                                         7 outils
45. 45. Messagerie sécurisée / collaboration                7 outils
46. 46. Gestion de projet                                     8 outils
47. 47. Documentation / Wiki                                  7 outils
48. 48. Tests logiciels / QA                                 11 outils
49. 49. API / développement Web                              8 outils
50. 50. Gestion de dépendances / build                      15 outils
51. 51. Électronique / embarqué / IoT                      12 outils
52. 52. Robotique                                             8 outils
53. 53. Virtualisation réseau / sécurité                   8 outils
54. 54. Haute disponibilité / clustering                     9 outils
55. 55. Reverse proxy / load balancing                        6 outils
56. 56. Web hosting                                           7 outils
57. 57. Systèmes embarqués / boot                           8 outils
58. 58. Forensic disque                                       9 outils
59. 59. Récupération de données                            8 outils
60. 60. Gestion des partitions                                9 outils
61. 61. Déploiement d'entreprise                            10 outils
62. 62. Gestion des mises à jour                            15 outils
63. 63. MDM / gestion appareils                               8 outils
64. 64. Apple / macOS spécialisé                           19 outils
65. 65. Windows spécialisé                                 20 outils
66. 66. Linux spécialisé                                   19 outils
67. 67. Sécurité des postes                                13 outils
68. 68. Gestion des licences                                  7 outils
69. 69. Outils de productivité développeur                 15 outils
```

---

## Liste complète, par domaine

## Systèmes d'exploitation & virtualisation

- DomaineLogiciels
- Windows
- Windows 10/11, Windows Server, Windows PE, WinRE
- Linux
- Ubuntu, Debian, Fedora, Arch, Linux Mint, Rocky Linux, AlmaLinux, RHEL, Kali, openSUSE
- macOS
- macOS, RecoveryOS
- Virtualisation
- VMware Workstation/Fusion, VirtualBox, Hyper-V, QEMU/KVM, Parallels Desktop
- Conteneurs
- Docker, Podman, containerd
- Orchestration
- Kubernetes, K3s, Minikube, Helm

## 2. Administration système

- PowerShell
- Windows Terminal
- RSAT
- Active Directory
- Group Policy
- Server Manager
- Sysinternals Suite
- DISM
- SFC
- WMI/CIM
- Windows Admin Center
- Bash
- Zsh
- systemd
- SSH/OpenSSH
- sudo
- cron
- Ansible
- Cockpit
- Webmin
- Terminal
- zsh
- launchd
- SSH
- Apple Remote Desktop
- diskutil
- system_profiler
- profiles
- networksetup

## 3. Réseaux

- Wireshark
- Nmap
- Masscan
- tcpdump
- iperf3
- Netcat
- OpenVPN
- WireGuard
- Tailscale
- ZeroTier
- PuTTY
- MobaXterm
- SecureCRT
- Termius
- Cisco Packet Tracer
- GNS3
- EVE-NG
- Cisco IOS
- MikroTik RouterOS
- pfSense
- OPNsense
- OpenWrt
- VyOS
- FortiOS

## 4. Cybersécurité

- Microsoft Defender
- Microsoft Sentinel
- Wazuh
- Splunk
- Elastic Security
- Graylog
- CrowdStrike
- SentinelOne
- Sophos
- ESET
- Bitdefender
- Kali Linux
- Parrot Security
- Metasploit
- Burp Suite
- OWASP ZAP
- Nmap
- Nikto
- sqlmap
- Gobuster
- ffuf
- Hydra
- John the Ripper
- Hashcat
- Autopsy
- The Sleuth Kit
- Volatility
- FTK
- EnCase
- Magnet AXIOM
- Wireshark
- Plaso
- KAPE

## 5. Développement logiciel

- Visual Studio
- Visual Studio Code
- JetBrains IntelliJ IDEA
- PyCharm
- WebStorm
- PhpStorm
- Rider
- CLion
- Android Studio
- Xcode
- Eclipse
- NetBeans
- Vim
- Neovim
- Emacs
- Sublime Text
- C
- C++
- C#
- Java
- Kotlin
- Swift
- Objective-C
- Python
- JavaScript
- TypeScript
- Go
- Rust
- PHP
- Ruby
- Dart
- R
- MATLAB
- Lua
- Perl
- Bash
- PowerShell

## 6. Gestion du code source

- Git
- GitHub
- GitLab
- Bitbucket
- Azure DevOps
- SVN
- Mercurial
- GitHub Desktop
- GitKraken
- Sourcetree
- Fork
- Tower
- SmartGit

## 7. DevOps / CI-CD

- Jenkins
- GitHub Actions
- GitLab CI/CD
- Azure Pipelines
- TeamCity
- CircleCI
- Travis CI
- Argo CD
- Flux
- Spinnaker
- Terraform
- OpenTofu
- Ansible
- Pulumi
- CloudFormation

## 8. Bases de données

- PostgreSQL
- MySQL
- MariaDB
- SQLite
- Microsoft SQL Server
- Oracle Database
- IBM Db2
- MongoDB
- Redis
- Cassandra
- CouchDB
- Elasticsearch
- OpenSearch
- Neo4j
- DBeaver
- DataGrip
- pgAdmin
- MySQL Workbench
- SQL Server Management Studio
- Azure Data Studio
- Oracle SQL Developer
- MongoDB Compass

## 9. Web / serveurs

- Apache HTTP Server
- Nginx
- Caddy
- IIS
- Tomcat
- Jetty
- Node.js
- Deno
- Bun
- PHP
- Composer
- Laravel
- Symfony
- WordPress
- Drupal
- Joomla
- Node.js
- npm
- Yarn
- pnpm
- React
- Angular
- Vue
- Svelte
- Next.js
- Nuxt

## 10. Cloud / infrastructure

- AWS CLI
- EC2
- S3
- RDS
- Lambda
- CloudFormation
- CloudWatch
- Azure CLI
- Azure PowerShell
- Azure DevOps
- Azure Storage
- Azure VM
- gcloud CLI
- GKE
- Compute Engine
- Cloud Storage
- Terraform
- Pulumi
- Kubernetes
- Docker
- Ansible

## 11. Stockage / sauvegarde / récupération

- Clonezilla
- Rescuezilla
- Veeam
- Acronis
- Macrium Reflect
- EaseUS
- MiniTool
- Clone Hero
- Timeshift
- BorgBackup
- Restic
- Duplicati
- UrBackup
- rsync
- Robocopy
- dd
- GParted
- DiskPart
- Disk Management
- GNOME Disks
- KDE Partition Manager
- parted
- fdisk
- gdisk
- diskutil

## 12. Boot / ISO / installation

- Ventoy
- Rufus
- balenaEtcher
- Fedora Media Writer
- UNetbootin
- YUMI
- Easy2Boot
- GRUB
- systemd-boot
- Windows PE
- WinRE
- Clonezilla
- iPXE
- PXE
- netboot.xyz
- OpenCore
- OpenCore Legacy Patcher
- Clover
- bless
- macOS Recovery
- createinstallmedia

## 13. UEFI / BIOS / firmware

- UEFI Shell
- BIOS/UEFI Setup
- fwupd
- LVFS
- flashrom
- Dell BIOS tools
- Lenovo firmware tools
- HP firmware tools
- Intel firmware tools
- dmidecode
- CPU-Z
- HWiNFO
- Speccy
- AIDA64
- HardInfo
- lshw
- inxi

## 14. Diagnostic matériel

- HWiNFO
- CPU-Z
- GPU-Z
- CrystalDiskInfo
- CrystalDiskMark
- MemTest86
- OCCT
- Prime95
- FurMark
- SMART tools
- smartctl
- nvme-cli
- lm-sensors
- stress-ng
- memtest86+
- lshw
- lspci
- lsusb
- inxi
- Apple Diagnostics
- Disk Utility
- diskutil
- system_profiler
- ioreg
- pmset
- log
- fsck

## 15. Monitoring

- Zabbix
- Nagios
- Prometheus
- Grafana
- PRTG
- Datadog
- New Relic
- Checkmk
- Icinga
- Netdata
- Telegraf
- InfluxDB

## 16. Logs / SIEM

- Splunk
- Elastic Stack
- Elasticsearch
- Logstash
- Kibana
- OpenSearch
- Graylog
- Loki
- Fluent Bit
- Fluentd
- Wazuh

## 17. Automatisation

- PowerShell
- PowerShell DSC
- Task Scheduler
- AutoHotkey
- Chocolatey
- winget
- Scoop
- Bash
- Ansible
- cron
- systemd timers
- Make
- Python
- zsh
- Automator
- Shortcuts
- launchd
- Homebrew

## 18. Gestion des paquets

- WindowsLinuxmacOS
- winget
- apt
- Homebrew
- Chocolatey
- dnf
- MacPorts
- Scoop
- yum
- Nix
- MSIX
- pacman
- pkg
- NuGet
- zypper
- mas

## 19. Bureau / bureautique

- Microsoft 365
- Microsoft Office
- LibreOffice
- OnlyOffice
- OpenOffice
- WPS Office
- Apple iWork
- Google Workspace
- Adobe Acrobat
- Foxit PDF
- PDF-XChange
- Okular
- Preview
- Evince

## 20. Graphisme / design

- Adobe Photoshop
- Adobe Illustrator
- Adobe InDesign
- Adobe Lightroom
- Affinity Photo
- Affinity Designer
- Affinity Publisher
- GIMP
- Krita
- Inkscape
- Blender
- Sketch
- Figma
- Canva

## 21. Vidéo

- Adobe Premiere Pro
- DaVinci Resolve
- Final Cut Pro
- Avid Media Composer
- Vegas Pro
- Shotcut
- Kdenlive
- OpenShot
- OBS Studio
- HandBrake
- FFmpeg

## 22. Audio

- Audacity
- Adobe Audition
- FL Studio
- Ableton Live
- Logic Pro
- Pro Tools
- Reaper
- Ardour
- LMMS
- VLC
- ffmpeg

## 23. 3D / CAO / ingénierie

- AutoCAD
- SolidWorks
- CATIA
- Fusion 360
- FreeCAD
- Blender
- Rhino
- SketchUp
- Revit
- Inventor
- Siemens NX
- Abaqus
- ANSYS
- MATLAB
- Simulink

## 24. IA / Machine Learning / Data Science

- Python
- Jupyter
- JupyterLab
- Anaconda
- Miniconda
- PyTorch
- TensorFlow
- Keras
- scikit-learn
- Pandas
- NumPy
- SciPy
- Matplotlib
- R
- RStudio
- CUDA
- ROCm
- Ollama
- LM Studio
- Ollama
- llama.cpp
- LM Studio
- vLLM
- Hugging Face Transformers

## 25. Data engineering / Big Data

- Apache Spark
- Apache Hadoop
- Kafka
- Airflow
- Flink
- Databricks
- dbt
- Trino
- Presto
- Apache Beam

## 26. Blockchain / Web3

- Bitcoin Core
- Ethereum
- Geth
- Solidity
- Hardhat
- Foundry
- MetaMask
- Ganache
- Remix

## 27. Messagerie / communication

- Microsoft Teams
- Slack
- Discord
- Zoom
- Google Meet
- Thunderbird
- Outlook
- Apple Mail
- Evolution
- Mattermost
- Element

## 28. Navigateurs

- Chrome
- Firefox
- Edge
- Safari 🍎
- Opera
- Brave
- Vivaldi
- Chromium
- Tor Browser

## 29. Télémaintenance

- AnyDesk
- TeamViewer
- RustDesk
- Chrome Remote Desktop
- Windows Remote Desktop
- SSH
- VNC
- NoMachine
- Remmina
- Apple Remote Desktop

## 30. Gestion de fichiers

- Explorer
- Total Commander
- 7-Zip
- WinRAR
- Nautilus
- Dolphin
- Thunar
- PCManFM
- Midnight Commander
- Finder
- Commander One
- ForkLift
- Keka
- 7-Zip
- WinRAR
- PeaZip
- tar
- gzip
- bzip2
- xz
- zstd

## 31. Chiffrement / sécurité des données

- BitLocker
- VeraCrypt
- FileVault
- LUKS
- GnuPG
- OpenSSL
- age
- KeePass
- Bitwarden
- 1Password

## 32. Gestion des mots de passe

- Bitwarden
- KeePass
- KeePassXC
- 1Password
- LastPass
- Dashlane
- Proton Pass

## 33. Analyse réseau avancée

- Wireshark
- tshark
- tcpdump
- Nmap
- Zeek
- Suricata
- Snort
- ntopng
- Ettercap
- Bettercap

## 34. Reverse engineering

- Ghidra
- IDA Pro
- Binary Ninja
- radare2
- Cutter
- x64dbg
- WinDbg
- LLDB
- GDB
- Hopper
- Frida
- dnSpy

## 35. Débogage

- WinDbg
- Visual Studio Debugger
- x64dbg
- Process Monitor
- Process Explorer
- GDB
- LLDB
- strace
- ltrace
- perf
- Valgrind
- LLDB
- Xcode Instruments
- DTrace
- Activity Monitor

## 36. Analyse mémoire / performances

- RAMMap
- Process Explorer
- Process Monitor
- Windows Performance Analyzer
- perf
- top
- htop
- btop
- vmstat
- iostat
- sar
- Activity Monitor
- Instruments

## 37. Gestion de parc informatique

- Microsoft Intune
- Microsoft Configuration Manager
- ManageEngine
- GLPI
- OCS Inventory
- FleetDM
- Lansweeper
- PDQ Deploy
- NinjaOne
- Datto RMM

## 38. ITSM / Helpdesk

- GLPI
- ServiceNow
- Jira Service Management
- Freshservice
- Zendesk
- ManageEngine ServiceDesk
- OTRS
- Zammad

## 39. Inventaire matériel / logiciel

- GLPI
- OCS Inventory
- Lansweeper
- HWiNFO
- CPU-Z
- Speccy
- AIDA64
- FleetDM

## 40. Serveurs de fichiers / NAS

- TrueNAS
- OpenMediaVault
- Synology DSM
- QNAP QTS
- Samba
- NFS
- Ceph
- MinIO

## 41. Active Directory / identité

- Active Directory
- Entra ID
- FreeIPA
- Samba AD
- OpenLDAP
- Keycloak
- Authentik
- Okta

## 42. PKI / certificats

- OpenSSL
- Let's Encrypt
- Certbot
- HashiCorp Vault
- Microsoft AD CS
- Smallstep
- cfssl

## 43. DNS / DHCP

- Windows DNS
- Windows DHCP
- BIND
- dnsmasq
- Unbound
- PowerDNS
- Kea DHCP
- ISC DHCP

## 44. Serveurs mail

- Microsoft Exchange
- Postfix
- Sendmail
- Exim
- Dovecot
- Zimbra
- Mailcow

## 45. Messagerie sécurisée / collaboration

- Nextcloud
- ownCloud
- Mattermost
- Rocket.Chat
- Matrix
- Element
- Syncthing

## 46. Gestion de projet

- Jira
- Trello
- Asana
- Monday.com
- ClickUp
- Redmine
- OpenProject
- Microsoft Project

## 47. Documentation / Wiki

- Confluence
- MediaWiki
- DokuWiki
- BookStack
- MkDocs
- Docusaurus
- GitBook

## 48. Tests logiciels / QA

- Selenium
- Playwright
- Cypress
- Appium
- Postman
- Insomnia
- JMeter
- k6
- pytest
- Jest
- PHPUnit

## 49. API / développement Web

- Postman
- Insomnia
- Swagger / OpenAPI
- curl
- HTTPie
- REST Client
- GraphQL
- Apollo

## 50. Gestion de dépendances / build

- Maven
- Gradle
- MSBuild
- CMake
- Ninja
- Make
- Cargo
- Go modules
- npm
- pnpm
- Yarn
- Composer
- pip
- Poetry
- uv

## 51. Électronique / embarqué / IoT

- Arduino IDE
- PlatformIO
- ESP-IDF
- STM32CubeIDE
- Keil
- MPLAB X
- KiCad
- Eagle
- LTspice
- Proteus
- Quartus
- Vivado

## 52. Robotique

- ROS
- ROS 2
- Gazebo
- Webots
- MATLAB
- Simulink
- Arduino
- PlatformIO

## 53. Virtualisation réseau / sécurité

- pfSense
- OPNsense
- Proxmox VE
- VMware ESXi
- Hyper-V
- KVM
- Xen
- QEMU

## 54. Haute disponibilité / clustering

- Kubernetes
- Docker Swarm
- Proxmox Cluster
- Pacemaker
- Corosync
- Ceph
- GlusterFS
- Keepalived
- HAProxy

## 55. Reverse proxy / load balancing

- Nginx
- HAProxy
- Traefik
- Caddy
- Envoy
- Apache

## 56. Web hosting

- cPanel
- Plesk
- DirectAdmin
- CyberPanel
- ISPConfig
- Webmin
- Virtualmin

## 57. Systèmes embarqués / boot

- GRUB
- U-Boot
- OpenCore
- Clover
- systemd-boot
- rEFInd
- Ventoy
- iPXE

## 58. Forensic disque

- Autopsy
- FTK Imager
- EnCase
- Magnet AXIOM
- dd
- ddrescue
- TestDisk
- PhotoRec
- Sleuth Kit

## 59. Récupération de données

- TestDisk
- PhotoRec
- R-Studio
- UFS Explorer
- DMDE
- Recuva
- Disk Drill
- Stellar Data Recovery

## 60. Gestion des partitions

- DiskPart
- Disk Management
- GParted
- KDE Partition Manager
- fdisk
- cfdisk
- gdisk
- parted
- diskutil

## 61. Déploiement d'entreprise

- MDT
- Microsoft Configuration Manager
- Windows Autopilot
- Clonezilla
- FOG
- Cobbler
- MAAS
- PXE
- iPXE
- Ansible

## 62. Gestion des mises à jour

- Windows Update
- WSUS
- Intune
- winget
- Chocolatey
- apt
- dnf
- yum
- pacman
- zypper
- unattended-upgrades
- Software Update
- MDM
- Munki
- Homebrew

## 63. MDM / gestion appareils

- Microsoft Intune
- Jamf Pro
- Jamf Now
- Mosyle
- Kandji
- VMware Workspace ONE
- Apple Business Manager
- Google Endpoint Management

## 64. Apple / macOS spécialisé

- Xcode
- OpenCore
- OpenCore Legacy Patcher
- Clover
- ProperTree
- GenSMBIOS
- MountEFI
- Hackintool
- IORegistryExplorer
- OCAT
- gibMacOS
- Mist
- createinstallmedia
- diskutil
- bless
- system_profiler
- Apple Configurator
- Apple Devices
- Apple Diagnostics

## 65. Windows spécialisé

- PowerShell
- Windows Terminal
- DISM
- SFC
- BCDEdit
- DiskPart
- WinRE
- WinPE
- Windows ADK
- RSAT
- Sysinternals
- Process Explorer
- Autoruns
- Procmon
- PsExec
- Robocopy
- winget
- Chocolatey
- Rufus
- Ventoy

## 66. Linux spécialisé

- Bash
- Zsh
- systemd
- GRUB
- apt
- dnf
- pacman
- snap
- Flatpak
- AppImage
- Docker
- Podman
- KVM
- QEMU
- LXC
- LXD
- OpenSSH
- Ansible
- Cockpit

## 67. Sécurité des postes

- Microsoft Defender
- Bitdefender
- ESET
- Sophos
- Malwarebytes
- CrowdStrike
- SentinelOne
- ClamAV
- Little Snitch
- LuLu
- OpenSnitch
- Windows Firewall
- pfSense/OPNsense

## 68. Gestion des licences

- Microsoft Volume Licensing
- Microsoft 365 Admin
- Adobe Admin Console
- JetBrains Licensing
- Autodesk Licensing
- FlexNet
- Sentinel HASP

## 69. Outils de productivité développeur

- VS Code
- Git
- Docker
- Postman
- GitHub
- GitLab
- Jira
- npm
- Python
- Node.js
- WSL
- Homebrew
- Chocolatey
- Make
- CMake


---

## Régénérer ce document

```bash
# Extraire le bloc catalogue brut du script (entre les deux marqueurs heredoc)
sed -n '/cat > "\$SONAR_CATALOGUE_EMBEDDED" <<.SONAR_CATALOGUE_EOF/,/^SONAR_CATALOGUE_EOF$/p' sonar_master.sh | sed '1d;$d'
```

Cette commande donne le TSV brut (`DOMAIN\tSUBDOMAIN\tNAME`) tel qu'il vit
dans le script — la source de vérité reste toujours `sonar_master.sh`, pas
ce document.
