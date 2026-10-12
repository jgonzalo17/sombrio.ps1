#Requires -Version 5.1
# ============================================================
# EL SOMBRIO IF - SS TOOLKIT (V1)
#   Herramientas, comandos, scripts y guías de screenshare, separados por categorías.
#   - Menú lateral por categorías + buscador global (Ctrl+F)
#   - Descargas directas a Escritorio\SS_Tools (con validación MZ/PK y plan B en el navegador)
#   - Win+R, CMD, servicios, USN Journal, regedit, visor de eventos con un clic
#   - Scripts remotos (GitHub) con confirmación previa
#   - Guías paso a paso (Journal Trace, Process Hacker / System Informer...)
# ============================================================

$script:AutoElevate = $true     # $true = pedir permisos de Administrador (UAC) al abrir
$script:IsChild     = ($args -contains '--sombrio-child')

function Test-Administrator {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    catch { return $false }
}

# Relanzar como administrador y sin ventana de consola
if ($script:AutoElevate -and -not $script:IsChild -and $PSCommandPath -and -not (Test-Administrator)) {
    try {
        $psExe = (Get-Process -Id $PID).Path
        Start-Process -FilePath $psExe -Verb RunAs -ErrorAction Stop `
            -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`" --sombrio-child"
        exit
    } catch { }   # UAC cancelado: se abre igual, sin privilegios
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'SsKit.Native').Type) {
    try { Add-Type -Namespace SsKit -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' } catch { }
}
try { [void][SsKit.Native]::SetProcessDPIAware() } catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:UiScale = 1.0
try { $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $script:UiScale = $g.DpiX / 96.0; $g.Dispose() } catch { }
function Px([double]$n) { return [int][math]::Round($n * $script:UiScale) }

# ============================================================
# TEMA (rojo / negro)
# ============================================================
function New-Color([int]$R, [int]$G, [int]$B) { return [System.Drawing.Color]::FromArgb($R, $G, $B) }
$script:C = @{
    Bg = (New-Color 8 4 6);       Panel = (New-Color 16 8 10);   Panel2 = (New-Color 24 11 13)
    Border = (New-Color 140 40 46); Hover = (New-Color 70 20 24);  Select = (New-Color 95 26 30)
    Accent = (New-Color 255 84 92); Text = (New-Color 245 235 235); Muted = (New-Color 190 140 145)
    Red = (New-Color 255 70 84);  Green = (New-Color 80 255 140); Yellow = (New-Color 255 200 90)
}
$script:FontBase  = New-Object System.Drawing.Font('Segoe UI', [single]9.5, [System.Drawing.FontStyle]::Regular)
$script:FontBold  = New-Object System.Drawing.Font('Segoe UI', [single]9.5, [System.Drawing.FontStyle]::Bold)
$script:FontSmall = New-Object System.Drawing.Font('Segoe UI', [single]8, [System.Drawing.FontStyle]::Bold)
$script:FontTitle = New-Object System.Drawing.Font('Segoe UI', [single]15, [System.Drawing.FontStyle]::Bold)
$script:FontHead  = New-Object System.Drawing.Font('Segoe UI', [single]10.5, [System.Drawing.FontStyle]::Bold)
$script:Tip = New-Object System.Windows.Forms.ToolTip
$script:Tip.InitialDelay = 400; $script:Tip.AutoPopDelay = 20000

# ============================================================
# UTILIDADES
# ============================================================
function Set-Status([string]$Text) {
    if ($script:StatusLbl) { $script:StatusLbl.Text = "  " + $Text; [System.Windows.Forms.Application]::DoEvents() }
}
function Show-Info([string]$Text, [string]$Title = "SS TOOLKIT") {
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', 'Information')
}
function Confirm-Action([string]$Text, [string]$Title = "CONFIRMAR") {
    return ([System.Windows.Forms.MessageBox]::Show($Text, $Title, 'YesNo', 'Question') -eq 'Yes')
}
function Copy-ToClipboard([string]$Text) {
    try { [System.Windows.Forms.Clipboard]::SetText($Text); Set-Status "Copiado al portapapeles." }
    catch { Show-Info "No se pudo copiar al portapapeles:`n$($_.Exception.Message)" }
}
function Get-FileMagic([string]$Path) {
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try { $b = [byte[]]::new(2); [void]$fs.Read($b, 0, 2); return [System.Text.Encoding]::ASCII.GetString($b) } finally { $fs.Dispose() }
    } catch { return "" }
}
function Get-PsExe {
    $p = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $p) { return $p }
    return 'powershell.exe'
}

# Abre una ventana de PowerShell que ejecuta el código dado (se queda abierta)
function Start-PsWindow([string]$Command) {
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
    Start-Process -FilePath (Get-PsExe) -WorkingDirectory $env:USERPROFILE `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand $enc"
}
# Abre una ventana de CMD con el comando (se queda abierta)
function Start-CmdWindow([string]$Command) {
    Start-Process -FilePath 'cmd.exe' -WorkingDirectory $env:USERPROFILE -ArgumentList ('/k ' + $Command)
}

# ------------------------------------------------------------
# Scripts remotos: se descargan en UTF-8 (evita acentos rotos en PS 5.1) y se ejecutan en otra ventana
# ------------------------------------------------------------
function Get-RemoteOneLiner([string]$Url) {
    return "powershell -Command `"Set-ExecutionPolicy Bypass -Scope Process; Invoke-Expression (Invoke-RestMethod '$Url')`""
}
function Start-RemoteScript($r) {
    $msg = "Se descargará y ejecutará este script desde internet:`n`n$($r.V)`n`nAutor / fuente: $($r.Info)`n`nEjecuta código de terceros: revisa que confías en la fuente.`n`n¿Continuar?"
    if (-not (Confirm-Action $msg $r.Title)) { return }
    $cmd = "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; " +
           "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " +
           "`$wc = New-Object Net.WebClient; `$wc.Encoding = [System.Text.Encoding]::UTF8; " +
           "Invoke-Expression (`$wc.DownloadString('$($r.V)'))"
    Start-PsWindow $cmd
    Set-Status "$($r.Title) abierto en otra ventana."
}

# ------------------------------------------------------------
# Descargas directas
# ------------------------------------------------------------
function Invoke-Download($r) {
    $dir = Join-Path $env:USERPROFILE 'Desktop\SS_Tools'
    $old = [System.Windows.Forms.Cursor]::Current
    $oldPref = $ProgressPreference
    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $out = Join-Path $dir $r.F
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
        Set-Status "Descargando $($r.Title)..."
        $hdr = @{ Referer = ([uri]$r.V).GetLeftPart([System.UriPartial]::Authority) + '/' }
        Invoke-WebRequest -Uri $r.V -OutFile $out -UseBasicParsing -MaximumRedirection 10 -Headers $hdr `
            -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36'
        $magic = Get-FileMagic $out
        if ($magic -eq 'PK') {
            $zip = $out
            if ($zip -notmatch '\.zip$') { $zip = [System.IO.Path]::ChangeExtension($out, '.zip'); Move-Item -LiteralPath $out -Destination $zip -Force }
            $dest = Join-Path $dir ([System.IO.Path]::GetFileNameWithoutExtension($zip))
            Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
            Start-Process explorer.exe -ArgumentList ('"' + $dest + '"')
            Set-Status "Descargado y extraído en $dest"
        } elseif ($magic -eq 'MZ') {
            $exe = $out
            if ($exe -notmatch '\.exe$') { $exe = [System.IO.Path]::ChangeExtension($out, '.exe'); Move-Item -LiteralPath $out -Destination $exe -Force }
            Set-Status "Descargado en $exe"
            if (Confirm-Action "Descargado en:`n$exe`n`n¿Ejecutarlo ahora?" $r.Title) { Start-Process -FilePath $exe }
            else { Start-Process explorer.exe -ArgumentList ('/select,"' + $exe + '"') }
        } else {
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
            throw "La descarga no es un archivo válido (el servidor devolvió una página web)."
        }
    } catch {
        Set-Status "Descarga fallida: se abre en el navegador."
        Show-Info ("No se pudo descargar automáticamente:`n`n" + $_.Exception.Message + "`n`nSe abrirá el enlace en tu navegador.") $r.Title
        $u = if ($r.V2) { $r.V2 } else { $r.V }
        try { Start-Process $u } catch { }
    } finally {
        $ProgressPreference = $oldPref
        [System.Windows.Forms.Cursor]::Current = $old
    }
}

# ------------------------------------------------------------
# Carpetas / ejecutables / shell
# ------------------------------------------------------------
function Open-Location($r) {
    $target = [Environment]::ExpandEnvironmentVariables($r.V)
    try {
        switch ($r.T) {
            'exe'    { Start-Process -FilePath $target }
            'shell'  { Start-Process -FilePath 'explorer.exe' -ArgumentList $target }
            'folder' {
                if (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue) {
                    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $target + '"')
                } elseif ($target -like '*$Recycle.Bin*') {
                    Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:RecycleBinFolder'
                } else {
                    Show-Info "No existe o no se puede acceder a:`n$target"
                }
            }
        }
        Set-Status "Abierto: $target"
    } catch { Show-Info ("No se pudo abrir:`n$target`n`n" + $_.Exception.Message) }
}

# ------------------------------------------------------------
# Regedit: se posiciona en la clave (usa LastKey) y copia la ruta
# ------------------------------------------------------------
function Open-Regedit([string]$Key) {
    try {
        $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit'
        if (-not (Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
        $prefix = if ((Get-Culture).TwoLetterISOLanguageName -eq 'es') { 'Equipo' } else { 'Computer' }
        try {
            $last = (Get-ItemProperty -Path $reg -Name LastKey -ErrorAction Stop).LastKey
            if ($last -and $last.Contains('\')) { $prefix = $last.Substring(0, $last.IndexOf('\')) }
        } catch { }
        Set-ItemProperty -Path $reg -Name LastKey -Value ($prefix + '\' + $Key) -Force
        Get-Process -Name regedit -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
        Start-Process -FilePath 'regedit.exe'
        try { [System.Windows.Forms.Clipboard]::SetText($Key) } catch { }
        Set-Status "Regedit abierto en la clave (también copiada al portapapeles)."
    } catch { Show-Info ("No se pudo abrir regedit:`n" + $_.Exception.Message) }
}

# ------------------------------------------------------------
# Plantillas PowerShell (se ejecutan en otra ventana)
# ------------------------------------------------------------
$script:UsnTemplate = @'
$ErrorActionPreference = 'SilentlyContinue'
$ext  = '__EXT__'
$name = '__NAME__'
$isAdm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if (-not $isAdm) { Write-Host 'ATENCIÓN: fsutil necesita permisos de administrador.' -ForegroundColor Red }
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) ($name + 'Activity.txt')
Write-Host "Leyendo el USN Journal de C: buscando $ext (puede tardar un poco)..." -ForegroundColor Yellow
$all = @(fsutil usn readjournal C: csv | Select-String -SimpleMatch $ext)
$sections = @(
    @('Recently created', '0x00000100'),
    @('Recently deleted', '0x80000200'),
    @('Recently renamed', '0x00001000'),
    @('Previously renamed', '0x00002000')
)
$lines = New-Object System.Collections.Generic.List[string]
foreach ($s in $sections) {
    $lines.Add('===== ' + $s[0] + ' ' + $name + ' files =====')
    foreach ($l in $all) { if ($l.Line -match $s[1]) { $lines.Add($l.Line) } }
    $lines.Add('')
}
$lines | Set-Content -Path $out -Encoding UTF8
Write-Host "Guardado en: $out" -ForegroundColor Green
notepad $out
'@

$script:EvtTemplate = @'
$e = @(Get-WinEvent -FilterHashtable @{ LogName = '__LOG__'; Id = __ID__ } -MaxEvents 100 -ErrorAction SilentlyContinue)
if ($e.Count -eq 0) {
    Write-Host 'Sin eventos con ese ID (o falta ejecutar como administrador).' -ForegroundColor Yellow
} else {
    Write-Host ("Eventos encontrados: " + $e.Count + " (máx. 100)") -ForegroundColor Green
    $e | Select-Object TimeCreated, Id, @{ n = 'Detalle'; e = { ($_.Message -split "`r?`n")[0] } } | Format-Table -AutoSize -Wrap
}
'@

$script:SvcCmd = @'
$l = 'pcasvc','dps','sysmain','eventlog','diagtrack','sgrmbroker','bam','dusmsvc','appinfo'
foreach ($n in $l) {
    $q  = sc.exe query $n
    $st = ($q | Select-String 'STATE|ESTADO' | Select-Object -First 1).Line
    if (-not $st) { $st = 'NO ENCONTRADO' }
    '{0,-12} {1}' -f $n, $st.Trim()
}
'@

$script:PrefetchCmd = @'
$k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
$v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).EnablePrefetcher
$map = @{ 0 = '0 = Deshabilitado'; 1 = '1 = Aplicaciones de inicio'; 2 = '2 = Aplicaciones externas'; 3 = '3 = Aplicaciones de inicio y externas' }
Write-Host ('EnablePrefetcher: ' + $(if ($null -ne $v) { $map[[int]$v] } else { 'no encontrado' }))
$s = Get-Service SysMain -ErrorAction SilentlyContinue
Write-Host ('SysMain: ' + $(if ($s) { [string]$s.Status } else { 'no encontrado' }))
'@

$script:ProxyCmd = @'
$ErrorActionPreference = 'Stop'
try {
    $ip = (Invoke-WebRequest ifconfig.me/ip -UseBasicParsing).Content.Trim()
    $r  = Invoke-RestMethod ('https://proxycheck.io/v2/{0}?vpn=1&asn=1' -f $ip)
    $json = $r | ConvertTo-Json -Depth 6
    $json
    if ($json -match '"proxy":\s*"yes"') { Write-Host '>>> PROXY / VPN DETECTADO' -ForegroundColor Red }
    else { Write-Host 'Sin proxy / VPN detectado' -ForegroundColor Green }
} catch { Write-Host ('Error: ' + $_.Exception.Message) -ForegroundColor Red }
'@

function Start-UsnReport([string]$Ext, [string]$Name) {
    Start-PsWindow ($script:UsnTemplate.Replace('__EXT__', $Ext).Replace('__NAME__', $Name))
    Set-Status "Informe USN ($Ext) en curso en otra ventana..."
}
function Start-EventReport([string]$Log, [string]$Id) {
    Start-PsWindow ($script:EvtTemplate.Replace('__LOG__', $Log).Replace('__ID__', $Id))
    Set-Status "Consultando evento $Id del registro $Log..."
}

# ============================================================
# CATÁLOGO DE CONTENIDO
# T: head | note | link | dl | folder | exe | shell | reg | remote | cmd | ps | usn | evt | copy
# V: valor principal (URL, ruta, comando)   V2: URL alternativa   F: nombre de archivo / extra
# ============================================================
function Row([string]$T, [string]$Title, [string]$Info = '', [string]$V = '', [string]$V2 = '', [string]$F = '') {
    return [pscustomobject]@{ T = $T; Title = $Title; Info = $Info; V = $V; V2 = $V2; F = $F }
}

$script:Catalog = [ordered]@{}

# ---------------- DESCARGAS ----------------
$script:Catalog['Journal y procesos'] = @(
    (Row 'head' 'Journal Trace'),
    (Row 'dl'   'JournalTrace (ponei)' 'Release 1.0 · .exe directo' 'https://github.com/ponei/JournalTrace/releases/download/1.0/JournalTrace.exe' 'https://github.com/ponei/JournalTrace/releases' 'JournalTrace.exe'),
    (Row 'link' 'JournalTrace (spokwn)' 'Repositorio / releases' 'https://github.com/spokwn/journaltrace'),
    (Row 'link' 'Echo Journal Trace' 'Descarga desde echo.ac' 'https://dl.echo.ac/tool/journal'),
    (Row 'head' 'Process Hacker / System Informer'),
    (Row 'dl'   'Process Hacker 2.39' 'Instalador (SourceForge)' 'https://sourceforge.net/projects/processhacker/files/processhacker2/processhacker-2.39-setup.exe/download' 'https://sourceforge.net/projects/processhacker/' 'processhacker-2.39-setup.exe'),
    (Row 'dl'   'System Informer' 'Última versión (SourceForge)' 'https://sourceforge.net/projects/systeminformer/files/latest/download' 'https://sourceforge.net/projects/systeminformer/' 'SystemInformer_download.bin')
)

$script:Catalog['Prefetch, búsqueda y recuperación'] = @(
    (Row 'head' 'Prefetch'),
    (Row 'dl'   'WinPrefetchView' 'NirSoft · zip x64' 'https://www.nirsoft.net/utils/winprefetchview-x64.zip' '' 'winprefetchview-x64.zip'),
    (Row 'dl'   'WinPrefetchView ++  (PrefetchView++)' 'Orbdiff · v1.6.1' 'https://github.com/Orbdiff/PrefetchView/releases/download/v1.6.1/PrefetchView++.exe' 'https://github.com/Orbdiff/PrefetchView/releases' 'PrefetchView++.exe'),
    (Row 'head' 'Búsqueda de archivos'),
    (Row 'dl'   'Everything' 'voidtools · instalador 1.4.1.1026' 'https://www.voidtools.com/Everything-1.4.1.1026.x86-Setup.exe' 'https://www.voidtools.com/downloads/' 'Everything-1.4.1.1026.x86-Setup.exe'),
    (Row 'head' 'Recuperación de archivos'),
    (Row 'link' 'Asistente de Recuva' 'Página de descarga (CCleaner)' 'https://www.ccleaner.com/es-es/recuva/download/standard'),
    (Row 'dl'   'PreviousFilesRecovery' 'NirSoft · zip x64' 'https://www.nirsoft.net/utils/previousfilesrecovery-x64.zip' '' 'previousfilesrecovery-x64.zip')
)

$script:Catalog['Visores NirSoft y Windows'] = @(
    (Row 'head' 'Visores de actividad'),
    (Row 'link' 'BrowserDownloadsView' 'Descargas del navegador (MajorGeeks)' 'https://www.majorgeeks.com/mg/get/browserdownloadsview,2.html'),
    (Row 'dl'   'ExecutedProgramsList' 'NirSoft · programas ejecutados' 'https://www.nirsoft.net/utils/executedprogramslist.zip' '' 'executedprogramslist.zip'),
    (Row 'link' 'USB Deview' 'Dispositivos USB (echo.ac)' 'https://dl.echo.ac/tool/usb'),
    (Row 'dl'   'LastActivityView' 'NirSoft · última actividad del equipo' 'https://www.nirsoft.net/utils/lastactivityview.zip' '' 'lastactivityview.zip'),
    (Row 'dl'   'UninstallView' 'NirSoft · programas instalados / desinstalados' 'https://www.nirsoft.net/utils/uninstallview-x64.zip' '' 'uninstallview-x64.zip'),
    (Row 'link' 'Win10LiveInfo' 'kacos2000 · releases' 'https://github.com/kacos2000/Win10LiveInfo/releases')
)

$script:Catalog['Detectores y analizadores'] = @(
    (Row 'head' 'MeowTonynoh'),
    (Row 'link' 'DoomsdayFucker' 'Releases' 'https://github.com/MeowTonynoh/MeowDoomsdayFucker/releases'),
    (Row 'link' 'NovoWareFucker' 'Releases' 'https://github.com/MeowTonynoh/MeowNovowareFucker/releases'),
    (Row 'link' 'ClientFucker' 'Releases' 'https://github.com/MeowTonynoh/MeowClientFucker/releases'),
    (Row 'link' 'MeowResolver' 'Releases' 'https://github.com/MeowTonynoh/MeowResolver/releases'),
    (Row 'head' 'Orbdiff / spokwn / otros'),
    (Row 'link' 'InjGen' 'Orbdiff' 'https://github.com/Orbdiff/InjGen/'),
    (Row 'link' 'DetectItEasy' 'horsicq · releases' 'https://github.com/horsicq/Detect-It-Easy/releases'),
    (Row 'link' 'PathParser' 'spokwn · releases' 'https://github.com/spokwn/PathsParser/releases/'),
    (Row 'link' 'SStool' 'Orbdiff · release update' 'https://github.com/Orbdiff/SSTool/releases/tag/update'),
    (Row 'link' 'Red Lotus Downloader' 'ItzIceHere' 'https://github.com/ItzIceHere/RedLotus-Tool-Downloader'),
    (Row 'link' 'checkdeletedUSN' 'Orbdiff' 'https://github.com/orbdiff/checkdeletedusn'),
    (Row 'link' 'BAM parser' 'spokwn · releases' 'https://github.com/spokwn/BAM-parser/releases'),
    (Row 'head' 'Decompilador'),
    (Row 'dl'   'Luyten 0.5.4' 'Decompilador de .jar (exe)' 'https://github.com/deathmarine/Luyten/releases/download/v0.5.4_Rebuilt_with_Latest_depenencies/luyten-0.5.4.exe' 'https://github.com/deathmarine/Luyten/releases' 'luyten-0.5.4.exe')
)

# ---------------- REVISIÓN DE WINDOWS ----------------
$script:Catalog['Win+R'] = @(
    (Row 'head' 'Ubicaciones que se revisan con Win+R'),
    (Row 'folder' 'Win+R  ›  C:\$Recycle.Bin' 'Archivos eliminados' 'C:\$Recycle.Bin'),
    (Row 'exe'    'Win+R  ›  regedit' 'Registro de Windows' 'regedit.exe'),
    (Row 'folder' 'Win+R  ›  prefetch' 'Programas ejecutados (depende de SysMain activo y EnablePrefetcher) -> Javaw.pf' '%SystemRoot%\Prefetch'),
    (Row 'folder' 'Win+R  ›  %temp%' 'JNativeHook -> dependencia de autoclickers viejos' '%TEMP%'),
    (Row 'folder' 'Win+R  ›  %appdata%\.minecraft' 'mods / versions / logs / resourcepacks: buscar hacked client, xray, mods ilegales' '%APPDATA%\.minecraft'),
    (Row 'shell'  'Win+R  ›  shell:recent' 'Archivos ejecutados recientemente' 'shell:recent'),
    (Row 'folder' 'Win+R  ›  ...\PowerShell\PSReadLine' 'Historial de comandos de PowerShell' '%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine'),
    (Row 'exe'    'Win+R  ›  msinfo32' 'Información del sistema: Virtual Machine = BAN' 'msinfo32.exe'),
    (Row 'folder' 'Win+R  ›  C:\Windows\System32\drivers\etc' 'Archivo hosts: dominios bloqueados' '%SystemRoot%\System32\drivers\etc'),
    (Row 'folder' 'Win+R  ›  %LOCALAPPDATA%\Microsoft\Windows\History' 'Páginas y archivos ejecutados' '%LOCALAPPDATA%\Microsoft\Windows\History')
)

$script:Catalog['CMD y servicios'] = @(
    (Row 'head' 'CMD'),
    (Row 'cmd' 'tasklist' 'Task list: archivos / procesos en segundo plano' 'tasklist'),
    (Row 'cmd' 'ipconfig /displaydns' 'Caché DNS (historial de búsquedas)' 'ipconfig /displaydns'),
    (Row 'head' 'Servicios clave'),
    (Row 'note' 'Lista: pcasvc · dps · sysmain · eventlog · diagtrack · sgrmbroker · bam · dusmsvc · appinfo'),
    (Row 'ps'  'Resumen del estado de los servicios' 'Muestra el estado de cada servicio de la lista' $script:SvcCmd),
    (Row 'cmd' 'sc query (todos)' 'Salida completa de cada servicio' 'sc query dps && sc query appinfo && sc query pcasvc && sc query eventlog && sc query sysmain && sc query dusmsvc && sc query bam'),
    (Row 'note' 'Individual:  sc query [servicio]   ·   sc qc [servicio]  (tipo de inicio)'),
    (Row 'head' 'Máquina virtual'),
    (Row 'cmd' 'systeminfo (fabricante y modelo)' 'Si el modelo/fabricante delata una VM = BAN' 'systeminfo | findstr /B /C:"Fabricante del sistema" /C:"Modelo del sistema" /C:"System Manufacturer" /C:"System Model"')
)

$script:Catalog['USN Journal y archivos'] = @(
    (Row 'head' 'Actividad reciente (creados / eliminados / renombrados)'),
    (Row 'note' 'Guarda un .txt en el Escritorio y lo abre en el Bloc de notas. Requiere administrador.'),
    (Row 'usn' 'JARActivity' 'Archivos .jar creados, eliminados y renombrados' '.jar' '' 'JAR'),
    (Row 'usn' 'EXEActivity' 'Archivos .exe creados, eliminados y renombrados' '.exe' '' 'EXE'),
    (Row 'usn' 'DLLActivity' 'Archivos .dll creados, eliminados y renombrados' '.dll' '' 'DLL'),
    (Row 'head' 'USN Journal'),
    (Row 'ps' 'Archivos eliminados (0x80000200)' 'Eliminados JAR-EXE-DLL en una tabla (requiere administrador)' 'fsutil usn readjournal c: csv | findstr /i /c:0x80000200 | out-gridview'),
    (Row 'head' 'Búsqueda de archivos con PowerShell (desde tu carpeta de usuario)'),
    (Row 'ps' 'gci -recurse -filter *.jar' 'Busca .jar' 'gci -recurse -filter *.jar'),
    (Row 'ps' 'gci -recurse -filter *.rar' 'Busca .rar' 'gci -recurse -filter *.rar'),
    (Row 'ps' 'gci -recurse -filter *.dll' 'Busca .dll' 'gci -recurse -filter *.dll'),
    (Row 'ps' 'gci -recurse -filter *.exe' 'Busca .exe' 'gci -recurse -filter *.exe')
)

$script:Catalog['Registro (regedit)'] = @(
    (Row 'head' 'Claves de actividad (se abre regedit posicionado en la clave)'),
    (Row 'reg' 'AppSwitched' 'Apps ejecutadas' 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched'),
    (Row 'reg' 'OpenSavePidlMRU' 'rar - dll - exe' 'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU'),
    (Row 'reg' 'Compatibility Assistant\Store' 'Apps descargadas' 'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'),
    (Row 'reg' 'RecentDocs' 'Documentos recientes' 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs'),
    (Row 'reg' 'DisallowRun' 'Apps bloqueadas' 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun'),
    (Row 'head' 'Enable Prefetch'),
    (Row 'reg' 'PrefetchParameters' 'Valor EnablePrefetcher' 'HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Session Manager\Memory Management\PrefetchParameters'),
    (Row 'note' 'Valores:  0 = Deshabilitado  ·  1 = Aplicaciones de inicio  ·  2 = Aplicaciones externas  ·  3 = Inicio y externas'),
    (Row 'ps'  'Ver valor actual de Prefetch y SysMain' 'Lee EnablePrefetcher y el estado del servicio SysMain' $script:PrefetchCmd)
)

$script:Catalog['Visor de eventos'] = @(
    (Row 'head' 'Visor de eventos'),
    (Row 'exe' 'eventvwr.msc' 'Abre el Visor de eventos de Windows' 'eventvwr.msc'),
    (Row 'note' 'Manual:  Registros de Windows › Seguridad / Aplicación › Filtrar registro actual › ID.   Los botones de abajo hacen la misma consulta (máx. 100 eventos).'),
    (Row 'head' 'Fecha y hora'),
    (Row 'evt' 'Cambio de fecha/hora  (Seguridad · 4616)' 'Datetime' 'Security' '4616'),
    (Row 'head' 'USN Journal borrado'),
    (Row 'evt' 'USN Journal delete  (Aplicación · 3076)' 'Registros de Windows › Aplicación' 'Application' '3076'),
    (Row 'head' 'Registro de eventos borrado'),
    (Row 'evt' 'Eventlog delete  (Seguridad · 1102)' 'Registros de Windows › Seguridad' 'Security' '1102'),
    (Row 'head' 'Cambio de usuarios'),
    (Row 'evt' 'Cambio de usuarios  (Seguridad · 4634)' 'Registros de Windows › Seguridad' 'Security' '4634')
)

# ---------------- SCRIPTS REMOTOS ----------------
$script:Catalog['Scripts remotos'] = @(
    (Row 'note' 'Estos botones descargan y ejecutan código de terceros desde GitHub (con confirmación previa). Revisa que confías en el autor.'),
    (Row 'head' 'Servicios'),
    (Row 'remote' 'Lilith · Services' 'praiselily' 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Services.ps1'),
    (Row 'remote' 'Lilith · Service Enabler' 'praiselily (reactiva servicios: modifica el sistema)' 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Service-Enabler.ps1'),
    (Row 'head' 'Kill ScreenRecording'),
    (Row 'remote' 'Orbdiff · kill-screen-processes' 'Orbdiff (cierra procesos de grabación de pantalla)' 'https://raw.githubusercontent.com/Orbdiff/powershell/refs/heads/main/kill-screen-processes.ps1'),
    (Row 'head' 'Doomsday Detector'),
    (Row 'remote' 'zedoon · DoomsDayDetector' 'zedoonvm1' 'https://raw.githubusercontent.com/zedoonvm1/powershell-scripts/refs/heads/main/DoomsDayDetector.ps1'),
    (Row 'remote' 'Lilith · DoomsdayFinder' 'praiselily' 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/DoomsdayFinder.ps1'),
    (Row 'remote' '14rpSucks · dd-finder' 'l4rpsucks' 'https://raw.githubusercontent.com/l4rpsucks/Scripts/refs/heads/main/dd-finder.ps1'),
    (Row 'head' 'JarParser'),
    (Row 'remote' 'Orbdiff · JARParser' 'Orbdiff' 'https://raw.githubusercontent.com/Orbdiff/JARParser/refs/heads/main/JARParser.ps1'),
    (Row 'remote' 'NoDiff-del · JARParser' 'NoDiff-del' 'https://raw.githubusercontent.com/NoDiff-del/JARParser/refs/heads/main/JARParser.ps1'),
    (Row 'head' 'BamParser'),
    (Row 'remote' 'RedLotus · BAM' 'PureIntent' 'https://raw.githubusercontent.com/PureIntent/ScreenShare/main/RedLotusBam.ps1'),
    (Row 'remote' 'Spokwn · bamparser' 'spokwn' 'https://raw.githubusercontent.com/spokwn/powershells/refs/heads/main/bamparser.ps1'),
    (Row 'head' 'Mod analyzer'),
    (Row 'remote' 'MeowTonynoh · MeowModAnalyzer' 'MeowTonynoh' 'https://raw.githubusercontent.com/MeowTonynoh/MeowModAnalyzer/main/MeowModAnalyzer.ps1'),
    (Row 'head' 'Prefetch Integrity'),
    (Row 'remote' 'RedLotus · Prefetch Integrity Analyzer' 'bacanoicua' 'https://raw.githubusercontent.com/bacanoicua/Screenshare/main/RedLotusPrefetchIntegrityAnalyzer.ps1'),
    (Row 'head' 'Bam Deleted Keys'),
    (Row 'remote' 'Florinyoq · bam' 'Florinyoq' 'https://raw.githubusercontent.com/Florinyoq/Screenshare/refs/heads/main/bam.ps1'),
    (Row 'head' 'MiniSS'),
    (Row 'remote' '14rpSucks · miniss' 'l4rpsucks' 'https://raw.githubusercontent.com/l4rpsucks/Scripts/refs/heads/main/miniss.ps1')
)

# ---------------- GUÍAS ----------------
$script:Catalog['Journal Trace / Echo'] = @(
    (Row 'head' 'Journal Trace'),
    (Row 'note' '●  Drive › seleccionar (C:)'),
    (Row 'note' '●  Scan (esperar a que complete la barra)'),
    (Row 'note' '●  Layout › Data grid'),
    (Row 'note' '●  Buscar lo que nos interesa'),
    (Row 'head' 'Echo Journal'),
    (Row 'note' '●  Ejecutar › seleccionar [Delete]'),
    (Row 'note' '●  Buscar el archivo que nos interesa')
)

$script:Catalog['Process Hacker / System Informer'] = @(
    (Row 'note' 'En todas las búsquedas:  Memory › Strings › marcar image | mapped | private  (en Javaw.exe solo mapped | private).  Filter › Contains (case-insensitive) salvo que se indique Regex.'),
    (Row 'head' 'explorer  ·  búsqueda general  (mínimo 4)'),
    (Row 'note' 'Proceso: explorer  ·  Filter contains: autoclick, cliente, macro, etc.'),
    (Row 'copy' 'autoclick' 'Filtro contains' 'autoclick'),
    (Row 'copy' 'cliente' 'Filtro contains' 'cliente'),
    (Row 'copy' 'macro' 'Filtro contains' 'macro'),
    (Row 'head' 'explorer  ·  jar ejecutados  (mínimo 5)'),
    (Row 'copy' '(?i)\bjar\b' 'Filter › Regex (case-insensitive)' '(?i)\bjar\b'),
    (Row 'head' 'explorer  ·  PcaClient: últimos 5 ejecutados  (mínimo 5)'),
    (Row 'copy' 'pcaclient' 'Filter contains › Save › revisar los resultados' 'pcaclient'),
    (Row 'head' 'DcomLaunch  ·  jar ejecutados  (mínimo 5)'),
    (Row 'note' '.jar = ejecución estándar   ·   -jar = ejecución en CMD'),
    (Row 'copy' '.jar' 'Filter contains' '.jar'),
    (Row 'copy' '-jar' 'Filter contains' '-jar'),
    (Row 'head' 'Conhost  ·  JournalDelete (registro volátil de conhost)  (mínimo 5)'),
    (Row 'copy' 'fsutil' 'Filter contains' 'fsutil'),
    (Row 'head' 'Conhost  ·  servicios detenidos / iniciados (registro volátil)  (mínimo 5)'),
    (Row 'copy' 'sc stop' 'Filter contains' 'sc stop'),
    (Row 'copy' 'sc start' 'Filter contains' 'sc start'),
    (Row 'head' 'MsMpEng  ·  JournalDelete  (mínimo 5)'),
    (Row 'copy' 'fsutil usn deletejournal' 'Filter contains' 'fsutil usn deletejournal'),
    (Row 'head' 'Csrss  ·  .dll  (mínimo 5)'),
    (Row 'copy' 'Regex de rutas' 'Filter › Regex (case-insensitive)' '^(?:\\\\\?\\)?[A-Za-z]:\\.+$'),
    (Row 'head' 'BFE  ·  .exe ejecutados  (mínimo 5)'),
    (Row 'copy' 'Regex TCP|UDP Query user' 'Filter › Regex (case-insensitive)' '^TCP|UDP Query user'),
    (Row 'head' 'Javaw.exe  ·  Doomsday strings 0.9.8  (mínimo 5 · solo mapped | private)'),
    (Row 'copy' '`lYgKfQhaCkHofBf' 'Filter contains' '`lYgKfQhaCkHofBf'),
    (Row 'copy' '?WHt4Y' 'Filter contains' '?WHt4Y'),
    (Row 'copy' '!hi!kGD@<nS' 'Filter contains' '!hi!kGD@<nS'),
    (Row 'copy' '%#ksghCP$NIS7$EQuX' 'Filter contains' '%#ksghCP$NIS7$EQuX'),
    (Row 'copy' '%@])c@[u6g6mCf1(' 'Filter contains' '%@])c@[u6g6mCf1('),
    (Row 'copy' ']Cu2TF' 'Filter contains' ']Cu2TF'),
    (Row 'copy' 'WO^iB' 'Filter contains' 'WO^iB'),
    (Row 'copy' '#-=yL&yn`R' 'Filter contains' '#-=yL&yn`R')
)

$script:Catalog['Otros'] = @(
    (Row 'head' 'CMD desactivado (gpedit)'),
    (Row 'note' 'Algunas personas deshabilitan CMD mediante gpedit; con eso CMD no es utilizable [baneable].'),
    (Row 'exe'  'gpedit.msc' 'Win+R › gpedit (no existe en Windows Home)' 'gpedit.msc'),
    (Row 'note' '●  Configuración de usuario › Plantillas administrativas › Sistema'),
    (Row 'note' '●  Clic en "Impedir el acceso al símbolo del sistema" (prevenir acceso a la consola de comandos)'),
    (Row 'note' '●  Si está habilitado, cambiarlo a Deshabilitado y Aplicar'),
    (Row 'head' 'Proxy & VPN'),
    (Row 'note' 'Consulta tu IP pública en ifconfig.me y la analiza en proxycheck.io (la IP se envía a esos servicios).'),
    (Row 'ps'   'Comprobar proxy / VPN' 'ifconfig.me + proxycheck.io' $script:ProxyCmd),
    (Row 'head' 'Ocean Anticheat'),
    (Row 'note' '_  Loguear y generar un PIN'),
    (Row 'note' '_  Descargar el link › utilizar el PIN'),
    (Row 'note' '_  Esperar a que termine'),
    (Row 'note' '_  Revisar en el panel de Ocean')
)

# Estructura del menú lateral
$script:NavLayout = @(
    @{ Section = 'DESCARGAS';           Items = @('Journal y procesos', 'Prefetch, búsqueda y recuperación', 'Visores NirSoft y Windows', 'Detectores y analizadores') },
    @{ Section = 'REVISIÓN DE WINDOWS'; Items = @('Win+R', 'CMD y servicios', 'USN Journal y archivos', 'Registro (regedit)', 'Visor de eventos') },
    @{ Section = 'SCRIPTS';             Items = @('Scripts remotos') },
    @{ Section = 'GUÍAS';               Items = @('Journal Trace / Echo', 'Process Hacker / System Informer', 'Otros') }
)

# ============================================================
# ACCIONES DE FILA
# ============================================================
function Get-RowButtons($r) {
    switch ($r.T) {
        'link'   { return @(@{ Text = 'Abrir enlace'; Act = 'link' }) }
        'dl'     { return @(@{ Text = 'Descargar'; Act = 'dl' }, @{ Text = 'Abrir enlace'; Act = 'link' }) }
        'folder' { return @(@{ Text = 'Abrir'; Act = 'open' }) }
        'exe'    { return @(@{ Text = 'Abrir'; Act = 'open' }) }
        'shell'  { return @(@{ Text = 'Abrir'; Act = 'open' }) }
        'reg'    { return @(@{ Text = 'Abrir regedit'; Act = 'reg' }, @{ Text = 'Copiar clave'; Act = 'copy' }) }
        'remote' { return @(@{ Text = 'Ejecutar'; Act = 'run' }, @{ Text = 'Copiar cmd'; Act = 'copy' }) }
        'cmd'    { return @(@{ Text = 'Ejecutar'; Act = 'run' }, @{ Text = 'Copiar'; Act = 'copy' }) }
        'ps'     { return @(@{ Text = 'Ejecutar'; Act = 'run' }, @{ Text = 'Copiar'; Act = 'copy' }) }
        'usn'    { return @(@{ Text = 'Ejecutar'; Act = 'run' }) }
        'evt'    { return @(@{ Text = 'Consultar'; Act = 'run' }) }
        'copy'   { return @(@{ Text = 'Copiar'; Act = 'copy' }) }
    }
    return @()
}

function Invoke-RowAction($r, [string]$Act) {
    try {
        switch ($Act) {
            'link' {
                $u = if ($r.T -eq 'dl' -and $r.V2) { $r.V2 } else { $r.V }
                Start-Process $u
                Set-Status "Abierto en el navegador: $u"
            }
            'dl'   { Invoke-Download $r }
            'open' { Open-Location $r }
            'reg'  { Open-Regedit $r.V }
            'copy' {
                if ($r.T -eq 'remote') { Copy-ToClipboard (Get-RemoteOneLiner $r.V) } else { Copy-ToClipboard $r.V }
            }
            'run' {
                switch ($r.T) {
                    'remote' { Start-RemoteScript $r }
                    'cmd'    { Start-CmdWindow $r.V; Set-Status "Ejecutado en CMD: $($r.Title)" }
                    'ps'     { Start-PsWindow $r.V;  Set-Status "Ejecutado en PowerShell: $($r.Title)" }
                    'usn'    { Start-UsnReport $r.V $r.F }
                    'evt'    { Start-EventReport $r.V $r.V2 }
                }
            }
        }
    } catch {
        Show-Info ("Ocurrió un error:`n`n" + $_.Exception.Message)
    }
}

# ============================================================
# INTERFAZ
# ============================================================
function New-FlatButton([string]$Text, [int]$Width, [int]$Height = 30) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Width = (Px $Width); $b.Height = (Px $Height)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $script:C.Border
    $b.FlatAppearance.MouseOverBackColor = $script:C.Hover
    $b.FlatAppearance.MouseDownBackColor = $script:C.Select
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $script:C.Panel2
    $b.ForeColor = $script:C.Text
    $b.Font = $script:FontBase
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

function New-Label([string]$Text, $Font, $Color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Font = $Font; $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $false
    return $l
}

function Clear-ContentPanel {
    $p = $script:Content
    while ($p.Controls.Count -gt 0) { $p.Controls[0].Dispose() }
}

function Show-Rows($Rows) {
    $p = $script:Content
    $p.SuspendLayout()
    $p.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    Clear-ContentPanel
    $w = $p.ClientSize.Width - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth - (Px 24)
    if ($w -lt (Px 400)) { $w = Px 400 }
    $y = Px 10
    $alt = $false
    foreach ($r in @($Rows)) {
        switch ($r.T) {
            'head' {
                $y += (Px 8)
                $l = New-Label $r.Title $script:FontHead $script:C.Accent
                $l.SetBounds((Px 12), $y, $w, (Px 24)); $l.Anchor = 'Top,Left,Right'
                $p.Controls.Add($l)
                $line = New-Object System.Windows.Forms.Panel
                $line.SetBounds((Px 12), ($y + (Px 25)), $w, 1); $line.BackColor = $script:C.Border; $line.Anchor = 'Top,Left,Right'
                $p.Controls.Add($line)
                $y += (Px 34); $alt = $false
            }
            'note' {
                $sz = [System.Windows.Forms.TextRenderer]::MeasureText($r.Title, $script:FontBase, (New-Object System.Drawing.Size(($w - (Px 20)), 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
                $h = $sz.Height + (Px 8)
                $l = New-Label $r.Title $script:FontBase $script:C.Muted
                $l.SetBounds((Px 20), $y, ($w - (Px 20)), $h); $l.Anchor = 'Top,Left,Right'
                $p.Controls.Add($l)
                $y += $h + (Px 2)
            }
            default {
                $pnl = New-Object System.Windows.Forms.Panel
                $pnl.SetBounds((Px 12), $y, $w, (Px 52)); $pnl.Anchor = 'Top,Left,Right'
                $pnl.BackColor = if ($alt) { $script:C.Panel2 } else { $script:C.Panel }
                $x = Px 8
                foreach ($b in @(Get-RowButtons $r)) {
                    $btn = New-FlatButton $b.Text 104 32
                    $btn.Location = New-Object System.Drawing.Point($x, (Px 10))
                    $btn.Name = $b.Act; $btn.Tag = $r
                    $btn.Add_Click({ param($s, $e) Invoke-RowAction $s.Tag $s.Name })
                    $pnl.Controls.Add($btn)
                    $x += (Px 110)
                }
                $tx = Px 236
                $lt = New-Label $r.Title $script:FontBold $script:C.Text
                $lt.AutoEllipsis = $true
                $lt.SetBounds($tx, (Px 6), ($w - $tx - (Px 8)), (Px 20)); $lt.Anchor = 'Top,Left,Right'
                $pnl.Controls.Add($lt)
                $li = New-Label $r.Info $script:FontBase $script:C.Muted
                $li.AutoEllipsis = $true
                $li.SetBounds($tx, (Px 27), ($w - $tx - (Px 8)), (Px 20)); $li.Anchor = 'Top,Left,Right'
                $pnl.Controls.Add($li)
                $tipText = if ($r.V) { "$($r.Info)`n$($r.V)" } else { $r.Info }
                $script:Tip.SetToolTip($lt, $tipText); $script:Tip.SetToolTip($li, $tipText)
                $p.Controls.Add($pnl)
                $y += (Px 54); $alt = -not $alt
            }
        }
    }
    $sp = New-Object System.Windows.Forms.Panel
    $sp.SetBounds(0, $y, 1, (Px 20)); $p.Controls.Add($sp)   # margen inferior
    $p.ResumeLayout($true)
}

function Set-NavActive([string]$Name) {
    foreach ($b in $script:NavButtons) {
        if ([string]$b.Tag -eq $Name) { $b.BackColor = $script:C.Select; $b.ForeColor = $script:C.Accent }
        else { $b.BackColor = $script:C.Panel; $b.ForeColor = $script:C.Text }
    }
}

function Show-Category([string]$Name) {
    $script:CurrentCat = $Name
    $script:Suppress = $true
    $script:SearchBox.Text = ''
    $script:Suppress = $false
    $script:TitleLbl.Text = $Name
    Set-NavActive $Name
    Show-Rows $script:Catalog[$Name]
    Set-Status "Categoría: $Name"
}

function Show-Search([string]$Query) {
    $q = $Query.Trim()
    if (-not $q) { Show-Category $script:CurrentCat; return }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($cat in $script:Catalog.Keys) {
        $hits = @($script:Catalog[$cat] | Where-Object { $_.T -ne 'head' -and $_.T -ne 'note' -and (($_.Title + ' ' + $_.Info + ' ' + $_.V) -like "*$q*") })
        if ($hits.Count -gt 0) {
            $rows.Add((Row 'head' $cat))
            foreach ($h in $hits) { $rows.Add($h) }
        }
    }
    $script:TitleLbl.Text = "Resultados: $q"
    Set-NavActive ''
    if ($rows.Count -eq 0) { $rows.Add((Row 'note' 'Sin resultados.')) }
    Show-Rows $rows
    Set-Status "Búsqueda: $q"
}

# --- Ventana principal ---
$isAdmin = Test-Administrator
$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = "EL SOMBRIO IF  ·  SS Toolkit V1"
$script:Form.StartPosition = 'CenterScreen'
$script:Form.ClientSize = New-Object System.Drawing.Size((Px 1180), (Px 740))
$script:Form.MinimumSize = New-Object System.Drawing.Size((Px 900), (Px 560))
$script:Form.BackColor = $script:C.Bg
$script:Form.ForeColor = $script:C.Text
$script:Form.Font = $script:FontBase
$script:Form.KeyPreview = $true

$navW = Px 270
$navPanel = New-Object System.Windows.Forms.Panel
$navPanel.Dock = 'Left'; $navPanel.Width = $navW; $navPanel.BackColor = $script:C.Panel

$navTitle = New-Object System.Windows.Forms.Label
$navTitle.Dock = 'Top'; $navTitle.Height = (Px 74)
$navTitle.Text = "EL SOMBRIO IF`nSS TOOLKIT"
$navTitle.Font = $script:FontTitle; $navTitle.ForeColor = $script:C.Red
$navTitle.TextAlign = 'MiddleCenter'; $navTitle.BackColor = $script:C.Bg

$navFooter = New-Object System.Windows.Forms.Panel
$navFooter.Dock = 'Bottom'; $navFooter.Height = (Px 64); $navFooter.BackColor = $script:C.Panel
$btnExit = New-FlatButton "Salir" 244 34
$btnExit.Location = New-Object System.Drawing.Point((Px 12), (Px 24))
$btnExit.ForeColor = $script:C.Muted
$btnExit.Add_Click({ $script:Form.Close() })
$navFooter.Controls.Add($btnExit)
$adm = New-Object System.Windows.Forms.Label
$adm.SetBounds((Px 12), (Px 2), (Px 244), (Px 20))
$adm.Font = $script:FontSmall
$adm.Text = if ($isAdmin) { "ADMINISTRADOR: SÍ" } else { "ADMINISTRADOR: NO (algunas funciones fallarán)" }
$adm.ForeColor = if ($isAdmin) { $script:C.Green } else { $script:C.Yellow }
$navFooter.Controls.Add($adm)

$navFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$navFlow.Dock = 'Fill'; $navFlow.FlowDirection = 'TopDown'; $navFlow.WrapContents = $false
$navFlow.AutoScroll = $true; $navFlow.BackColor = $script:C.Panel
$navFlow.Padding = [System.Windows.Forms.Padding]::new((Px 12), (Px 4), (Px 8), 0)

$script:NavButtons = New-Object System.Collections.Generic.List[object]
$idx = 0
foreach ($grp in $script:NavLayout) {
    $sec = New-Object System.Windows.Forms.Label
    $sec.Text = $grp.Section; $sec.Font = $script:FontSmall; $sec.ForeColor = $script:C.Muted
    $sec.Width = (Px 244); $sec.Height = (Px 30); $sec.TextAlign = 'BottomLeft'
    $sec.Padding = [System.Windows.Forms.Padding]::new((Px 6), 0, 0, (Px 4))
    $sec.Margin = [System.Windows.Forms.Padding]::new(0, (Px 6), 0, 0)
    $navFlow.Controls.Add($sec)
    foreach ($name in $grp.Items) {
        $idx++
        $b = New-Object System.Windows.Forms.Button
        $b.Text = ('{0:00}   {1}' -f $idx, $name)
        $b.Tag = $name
        $b.Width = (Px 244); $b.Height = (Px 38)
        $b.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, (Px 3))
        $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = $script:C.Hover
        $b.FlatAppearance.MouseDownBackColor = $script:C.Select
        $b.UseVisualStyleBackColor = $false
        $b.BackColor = $script:C.Panel; $b.ForeColor = $script:C.Text
        $b.Font = $script:FontBase; $b.TextAlign = 'MiddleLeft'
        $b.Padding = [System.Windows.Forms.Padding]::new((Px 14), 0, 0, 0)
        $b.Cursor = [System.Windows.Forms.Cursors]::Hand
        $b.Add_Click({ param($s, $e) Show-Category ([string]$s.Tag) })
        $script:NavButtons.Add($b)
        $navFlow.Controls.Add($b)
    }
}
$navPanel.Controls.Add($navFlow)
$navPanel.Controls.Add($navFooter)
$navPanel.Controls.Add($navTitle)

# --- Panel derecho ---
$main = New-Object System.Windows.Forms.Panel
$main.Dock = 'Fill'; $main.BackColor = $script:C.Bg

$script:Content = New-Object System.Windows.Forms.Panel
$script:Content.Dock = 'Fill'; $script:Content.AutoScroll = $true; $script:Content.BackColor = $script:C.Bg

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = (Px 58); $header.BackColor = $script:C.Bg

$script:TitleLbl = New-Object System.Windows.Forms.Label
$script:TitleLbl.Font = $script:FontTitle; $script:TitleLbl.ForeColor = $script:C.Text
$script:TitleLbl.AutoEllipsis = $true
$script:TitleLbl.SetBounds((Px 16), (Px 12), (Px 520), (Px 36))
$script:TitleLbl.Anchor = 'Top,Left'
$header.Controls.Add($script:TitleLbl)

$hdrW = $script:Form.ClientSize.Width - $navW
$lblBuscar = New-Object System.Windows.Forms.Label
$lblBuscar.Text = "Buscar:"; $lblBuscar.ForeColor = $script:C.Muted; $lblBuscar.Font = $script:FontBase
$lblBuscar.SetBounds(($hdrW - (Px 316)), (Px 19), (Px 56), (Px 22)); $lblBuscar.Anchor = 'Top,Right'
$header.Controls.Add($lblBuscar)

$script:SearchBox = New-Object System.Windows.Forms.TextBox
$script:SearchBox.SetBounds(($hdrW - (Px 256)), (Px 16), (Px 240), (Px 26)); $script:SearchBox.Anchor = 'Top,Right'
$script:SearchBox.BackColor = $script:C.Panel2; $script:SearchBox.ForeColor = $script:C.Text
$script:SearchBox.BorderStyle = 'FixedSingle'; $script:SearchBox.Font = $script:FontBase
$script:SearchBox.Add_TextChanged({ if (-not $script:Suppress) { Show-Search $script:SearchBox.Text } })
$header.Controls.Add($script:SearchBox)

$script:StatusLbl = New-Object System.Windows.Forms.Label
$script:StatusLbl.Dock = 'Bottom'; $script:StatusLbl.Height = (Px 26)
$script:StatusLbl.BackColor = $script:C.Panel; $script:StatusLbl.ForeColor = $script:C.Muted
$script:StatusLbl.Font = $script:FontBase; $script:StatusLbl.TextAlign = 'MiddleLeft'
$script:StatusLbl.Text = "  Listo."

$main.Controls.Add($script:Content)
$main.Controls.Add($header)
$main.Controls.Add($script:StatusLbl)

$script:Form.Controls.Add($main)
$script:Form.Controls.Add($navPanel)

# --- Atajos: Ctrl+F busca, Esc limpia ---
$script:Form.Add_KeyDown({
    param($s, $e)
    try {
        if ($e.Control -and $e.KeyCode -eq 'F') { [void]$script:SearchBox.Focus(); $script:SearchBox.SelectAll(); $e.Handled = $true }
        elseif ($e.KeyCode -eq 'Escape' -and $script:SearchBox.Text) { $script:SearchBox.Text = ''; $e.Handled = $true }
    } catch { }
})

# ============================================================
# ARRANQUE
# ============================================================
$script:Suppress = $false
$script:CurrentCat = $script:NavLayout[0].Items[0]
$script:Form.Add_Shown({ Show-Category $script:CurrentCat })
[System.Windows.Forms.Application]::Run($script:Form)
