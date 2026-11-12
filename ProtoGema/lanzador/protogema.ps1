<#
  ProtoGema | lanzador para Windows
  Uso:  protogema.ps1 -Accion encender | apagar | estado
  1. Revisa que Docker Desktop esté instalado y encendido (si no, lo abre)
  2. Crea el archivo .env la primera vez (claves aleatorias y puertos propios)
  3. Levanta los 4 servicios con Docker Compose
  4. Espera a que el cerebro responda y abre ProtoGema en el navegador
#>
param(
    [ValidateSet('encender', 'apagar', 'estado')]
    [string]$Accion = 'encender'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$Host.UI.RawUI.WindowTitle = 'ProtoGema'

$Raiz      = Split-Path -Parent $PSScriptRoot
$ArchivoEnv = Join-Path $Raiz '.env'
$Registros = Join-Path $Raiz 'registros'
New-Item -ItemType Directory -Force -Path $Registros | Out-Null
Set-Location $Raiz

function Portada {
    Clear-Host
    Write-Host ''
    Write-Host '       ________' -ForegroundColor Magenta
    Write-Host '      /\  /\  /\      P R O T O G E M A' -ForegroundColor Magenta
    Write-Host '     /__\/__\/__\     asistente personal con agenda inteligente' -ForegroundColor DarkGray
    Write-Host '     \    \/    /' -ForegroundColor Magenta
    Write-Host '       \  ||  /' -ForegroundColor Magenta
    Write-Host '         \||/' -ForegroundColor Magenta
    Write-Host ''
}

$script:Faceta = 0
function Faceta([string]$texto) {
    $script:Faceta++
    $llenas = '◆' * $script:Faceta
    $vacias = '◇' * (5 - $script:Faceta)
    Write-Host "   $llenas$vacias  " -ForegroundColor Magenta -NoNewline
    Write-Host $texto
}
function Bien([string]$t) { Write-Host "             ok  $t" -ForegroundColor Green }
function Nota([string]$t) { Write-Host "                 $t" -ForegroundColor DarkGray }
function Fallo([string]$t) {
    Write-Host ''
    Write-Host "   No pude seguir: $t" -ForegroundColor Red
    Write-Host "   Los detalles quedaron en la carpeta 'registros'." -ForegroundColor DarkGray
    Write-Host ''
    Read-Host '   Pulsa Enter para cerrar' | Out-Null
    exit 1
}

function Docker-Listo {
    cmd /c 'docker info >nul 2>&1'
    return ($LASTEXITCODE -eq 0)
}

function Secreto {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Zona-Horaria {
    $mapa = @{
        'Venezuela Standard Time'        = 'America/Caracas'
        'SA Pacific Standard Time'       = 'America/Bogota'
        'SA Western Standard Time'       = 'America/La_Paz'
        'Argentina Standard Time'        = 'America/Argentina/Buenos_Aires'
        'Pacific SA Standard Time'       = 'America/Santiago'
        'Central Standard Time (Mexico)' = 'America/Mexico_City'
        'E. South America Standard Time' = 'America/Sao_Paulo'
        'Eastern Standard Time'          = 'America/New_York'
        'Romance Standard Time'          = 'Europe/Madrid'
    }
    try {
        $id = (Get-TimeZone).Id
        if ($mapa.ContainsKey($id)) { return $mapa[$id] }
    } catch { }
    return 'America/Caracas'
}

function Leer-Env([string]$clave, [string]$defecto) {
    if (Test-Path $ArchivoEnv) {
        $linea = Get-Content $ArchivoEnv | Where-Object { $_ -match "^$clave=" } | Select-Object -First 1
        if ($linea) { return ($linea -split '=', 2)[1].Trim() }
    }
    return $defecto
}

function Compose([string]$argumentos, [string]$registro) {
    $ruta = Join-Path $Registros $registro
    cmd /c "docker compose $argumentos > `"$ruta`" 2>&1"
    return $LASTEXITCODE
}

# ---------------------------------------------------------------------
Portada

if ($Accion -eq 'apagar') {
    Faceta 'Apagando ProtoGema (tu agenda queda guardada)...'
    if (-not (Docker-Listo)) { Bien 'Docker ya estaba apagado'; Start-Sleep 2; exit 0 }
    Compose 'down' 'apagar.log' | Out-Null
    Bien 'ProtoGema se apagó'
    Start-Sleep 2
    exit 0
}

if ($Accion -eq 'estado') {
    cmd /c 'docker compose ps'
    Read-Host '   Pulsa Enter para cerrar' | Out-Null
    exit 0
}

# 1) Docker
Faceta 'Revisando Docker Desktop...'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fallo 'Docker Desktop no está instalado. Descárgalo gratis en https://www.docker.com/products/docker-desktop/'
}
if (-not (Docker-Listo)) {
    Nota 'Docker está apagado, lo estoy abriendo...'
    $exe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $exe) { Start-Process $exe | Out-Null }
    for ($i = 0; $i -lt 90 -and -not (Docker-Listo); $i++) { Start-Sleep 2 }
    if (-not (Docker-Listo)) { Fallo 'Docker Desktop no terminó de encender. Ábrelo, espera a que diga "Engine running" y vuelve a intentar.' }
}
Bien 'Docker responde'

# 2) Configuración
Faceta 'Preparando la configuración...'
if (-not (Test-Path $ArchivoEnv)) {
    $contenido = @(
        '# ProtoGema | configuración local (se creó sola, no la compartas)',
        "CLAVE_ALMACEN=$(Secreto)",
        "CLAVE_CEREBRO=$(Secreto)",
        "ZONA_HORARIA=$(Zona-Horaria)",
        'PUERTO_PROTOGEMA=4646',
        'PUERTO_N8N=5699'
    )
    [System.IO.File]::WriteAllLines($ArchivoEnv, $contenido, (New-Object System.Text.UTF8Encoding($false)))
    Bien 'Configuración creada por primera vez'
} else {
    Bien 'Configuración encontrada'
}
$Puerto = Leer-Env 'PUERTO_PROTOGEMA' '4646'
$Url = "http://localhost:$Puerto"

# 3) Servicios
Faceta 'Encendiendo los servicios (la primera vez descarga ~800 MB)...'
$ocupado = Get-NetTCPConnection -LocalPort ([int]$Puerto) -State Listen -ErrorAction SilentlyContinue
if ($ocupado) {
    $propio = cmd /c "docker ps --filter name=protogema-portal --format {{.Names}}"
    if (-not $propio) { Fallo "El puerto $Puerto lo está usando otro programa. Cambia PUERTO_PROTOGEMA en el archivo .env" }
}
if ((Compose 'up -d --build' 'encender.log') -ne 0) {
    Fallo 'Docker Compose no pudo levantar los servicios. Revisa registros\encender.log'
}
Bien 'Servicios levantados'

# 4) Esperar al cerebro
Faceta 'Esperando a que el cerebro (n8n) despierte...'
$listo = $false
for ($i = 0; $i -lt 180; $i++) {
    try {
        $r = Invoke-RestMethod -Uri "$Url/api/latido" -TimeoutSec 3
        if ($r.vivo) { $listo = $true; break }
    } catch { }
    Start-Sleep 2
}
if (-not $listo) {
    cmd /c "docker compose logs --tail 80 > `"$(Join-Path $Registros 'servicios.log')`" 2>&1"
    Fallo 'El cerebro no respondió a tiempo. Revisa registros\servicios.log'
}
Bien 'ProtoGema está despierta'

# 5) Acceso directo y navegador
Faceta 'Abriendo ProtoGema...'
try {
    $escritorio = [Environment]::GetFolderPath('Desktop')
    $acceso = Join-Path $escritorio 'ProtoGema.lnk'
    if (-not (Test-Path $acceso)) {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($acceso)
        $lnk.TargetPath = Join-Path $Raiz 'ProtoGema.bat'
        $lnk.WorkingDirectory = $Raiz
        $lnk.IconLocation = Join-Path $Raiz 'lanzador\protogema.ico'
        $lnk.Description = 'ProtoGema, tu asistente personal'
        $lnk.Save()
        Nota 'Creé el acceso directo "ProtoGema" en tu escritorio'
    }
} catch { }
Start-Process $Url
Bien "Listo: $Url"
Write-Host ''
Nota 'Puedes cerrar esta ventana. Para apagar usa "Apagar ProtoGema.bat".'
Start-Sleep 4
