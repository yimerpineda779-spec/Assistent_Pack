# =============================================================
#  Lanzador de Cortana para Windows
#  - Revisa que Docker esté instalado y encendido
#  - La primera vez pide las claves (asistente con ventanas)
#  - Arranca los contenedores y ESPERA a que Cortana esté lista
#  - Solo entonces abre la ventana de chat
#  - Deja un vigilante junto al reloj que muestra los recordatorios
# =============================================================
param(
    [switch]$Configurar,
    [switch]$Detener,
    [switch]$Vigilar
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Raiz       = Split-Path -Parent $PSScriptRoot
$ArchivoEnv = Join-Path $Raiz '.env'
$Logs       = Join-Path $Raiz 'logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$LogLanzador = Join-Path $Logs 'lanzador.log'
Set-Location $Raiz

$ColorFondo  = [System.Drawing.Color]::FromArgb(22, 26, 46)
$ColorTexto  = [System.Drawing.Color]::FromArgb(233, 235, 250)
$ColorSuave  = [System.Drawing.Color]::FromArgb(154, 160, 198)
$ColorAcento = [System.Drawing.Color]::FromArgb(115, 128, 255)

# ---------------- Utilidades ----------------
function Escribir-Log([string]$texto) {
    $linea = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $texto
    try { Add-Content -Path $LogLanzador -Value $linea -Encoding UTF8 } catch { }
}

function Mostrar-Mensaje([string]$texto, [string]$icono = 'Information', [string]$botones = 'OK') {
    return [System.Windows.Forms.MessageBox]::Show($texto, 'Cortana', $botones, $icono)
}

function Refrescar { [System.Windows.Forms.Application]::DoEvents() }

function Esperar([double]$segundos) {
    $fin = (Get-Date).AddSeconds($segundos)
    while ((Get-Date) -lt $fin) { Start-Sleep -Milliseconds 100; Refrescar }
}

function Leer-Env {
    $datos = @{}
    if (Test-Path $ArchivoEnv) {
        foreach ($linea in Get-Content -Path $ArchivoEnv -Encoding UTF8) {
            if ($linea -match '^\s*([A-Z0-9_]+)\s*=(.*)$') { $datos[$Matches[1]] = $Matches[2].Trim() }
        }
    }
    return $datos
}

function Guardar-Env($datos) {
    $orden = 'GEMINI_API_KEY', 'TAVILY_API_KEY', 'GEMINI_MODEL', 'N8N_ENCRYPTION_KEY', 'ZONA_HORARIA', 'PUERTO_CORTANA', 'PUERTO_N8N', 'DB_PASSWORD'
    $lineas = @('# Configuración de Cortana (creada por el lanzador). No compartas este archivo.')
    foreach ($k in $orden) { $lineas += ($k + '=' + $datos[$k]) }
    # UTF-8 sin BOM, para que Docker lo lea bien
    [System.IO.File]::WriteAllText($ArchivoEnv, ($lineas -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Clave-Aleatoria {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLower()
}

# Ejecuta un programa sin mostrar consola y sin congelar la ventana
function Ejecutar([string]$programa, [string]$argumentos, [string]$nombreLog = 'docker') {
    $salida = Join-Path $Logs ($nombreLog + '.log')
    $errores = Join-Path $Logs ($nombreLog + '-error.log')
    $p = Start-Process -FilePath $programa -ArgumentList $argumentos -WorkingDirectory $Raiz `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $salida -RedirectStandardError $errores
    $null = $p.Handle
    while (-not $p.HasExited) { Start-Sleep -Milliseconds 150; Refrescar }
    $p.WaitForExit()
    return $p.ExitCode
}

# ---------------- Ventana de progreso ----------------
$script:Ventana = $null
$script:EtiquetaEstado = $null

function Abrir-Ventana-Progreso([string]$titulo) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Cortana'
    $f.Size = New-Object System.Drawing.Size(460, 190)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $true
    $f.BackColor = $ColorFondo
    $f.ForeColor = $ColorTexto
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $icono = Join-Path $PSScriptRoot 'cortana.ico'
    if (Test-Path $icono) { $f.Icon = New-Object System.Drawing.Icon($icono) }

    $t = New-Object System.Windows.Forms.Label
    $t.Text = $titulo
    $t.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $t.AutoSize = $true
    $t.Location = New-Object System.Drawing.Point(24, 18)
    $f.Controls.Add($t)

    $e = New-Object System.Windows.Forms.Label
    $e.Text = 'Un momento...'
    $e.ForeColor = $ColorSuave
    $e.Size = New-Object System.Drawing.Size(400, 44)
    $e.Location = New-Object System.Drawing.Point(26, 60)
    $f.Controls.Add($e)

    $b = New-Object System.Windows.Forms.ProgressBar
    $b.Style = 'Marquee'
    $b.MarqueeAnimationSpeed = 25
    $b.Size = New-Object System.Drawing.Size(395, 10)
    $b.Location = New-Object System.Drawing.Point(26, 112)
    $f.Controls.Add($b)

    $f.Show()
    $script:Ventana = $f
    $script:EtiquetaEstado = $e
    Refrescar
}

function Estado([string]$texto) {
    Escribir-Log $texto
    if ($script:EtiquetaEstado) { $script:EtiquetaEstado.Text = $texto; Refrescar }
}

function Cerrar-Ventana-Progreso {
    if ($script:Ventana) { $script:Ventana.Close(); $script:Ventana = $null }
}

function Fallar([string]$texto) {
    Escribir-Log ('ERROR: ' + $texto)
    Cerrar-Ventana-Progreso
    Mostrar-Mensaje ($texto + "`n`nSi el problema sigue, revisa la carpeta 'logs' de Cortana.") 'Error' | Out-Null
    exit 1
}

# ---------------- Asistente de claves ----------------
function Probar-Clave-Gemini([string]$clave) {
    # Devuelve: 'ok', 'invalida' o 'sin-internet'
    try {
        $url = 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1&key=' + [uri]::EscapeDataString($clave)
        $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
        return 'ok'
    } catch {
        $codigo = $null
        try { $codigo = [int]$_.Exception.Response.StatusCode } catch { }
        if ($codigo -ge 400 -and $codigo -lt 500) { return 'invalida' }
        return 'sin-internet'
    }
}

function Nuevo-Enlace($texto, $url, $x, $y) {
    $l = New-Object System.Windows.Forms.LinkLabel
    $l.Text = $texto
    $l.AutoSize = $true
    $l.LinkColor = $ColorAcento
    $l.ActiveLinkColor = $ColorTexto
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Tag = $url
    $l.Add_LinkClicked({ Start-Process $this.Tag })
    return $l
}

function Nueva-Etiqueta($texto, $x, $y, $ancho, $alto, $color, $fuente) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $texto
    $l.ForeColor = $color
    if ($fuente) { $l.Font = $fuente }
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($ancho, $alto)
    return $l
}

function Mostrar-Asistente-Claves($actual) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Configurar Cortana'
    $f.Size = New-Object System.Drawing.Size(560, 470)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.BackColor = $ColorFondo
    $f.ForeColor = $ColorTexto
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $icono = Join-Path $PSScriptRoot 'cortana.ico'
    if (Test-Path $icono) { $f.Icon = New-Object System.Drawing.Icon($icono) }

    $f.Controls.Add((Nueva-Etiqueta 'Bienvenido a Cortana' 24 16 500 34 $ColorTexto (New-Object System.Drawing.Font('Segoe UI Semibold', 16))))
    $f.Controls.Add((Nueva-Etiqueta 'Para pensar, Cortana usa la inteligencia artificial de Google (Gemini). Necesitas una clave gratuita; solo se pide una vez y se guarda en esta computadora.' 26 56 500 48 $ColorSuave $null))

    $f.Controls.Add((Nueva-Etiqueta '1. Clave de Google Gemini (obligatoria)' 26 116 500 22 $ColorTexto (New-Object System.Drawing.Font('Segoe UI Semibold', 10))))
    $f.Controls.Add((Nuevo-Enlace 'Conseguir mi clave gratis (abre Google AI Studio, botón "Create API key")' 'https://aistudio.google.com/apikey' 26 140))
    $txtGemini = New-Object System.Windows.Forms.TextBox
    $txtGemini.Location = New-Object System.Drawing.Point(28, 166)
    $txtGemini.Size = New-Object System.Drawing.Size(490, 26)
    $txtGemini.Text = $actual['GEMINI_API_KEY']
    $f.Controls.Add($txtGemini)

    $f.Controls.Add((Nueva-Etiqueta '2. Clave de Tavily (opcional, para buscar en internet)' 26 214 500 22 $ColorTexto (New-Object System.Drawing.Font('Segoe UI Semibold', 10))))
    $f.Controls.Add((Nuevo-Enlace 'Conseguir mi clave gratis en Tavily' 'https://app.tavily.com' 26 238))
    $txtTavily = New-Object System.Windows.Forms.TextBox
    $txtTavily.Location = New-Object System.Drawing.Point(28, 264)
    $txtTavily.Size = New-Object System.Drawing.Size(490, 26)
    $txtTavily.Text = $actual['TAVILY_API_KEY']
    $f.Controls.Add($txtTavily)
    $f.Controls.Add((Nueva-Etiqueta 'Si la dejas vacía, Cortana funciona igual pero sin buscar noticias ni datos actuales.' 26 294 500 22 $ColorSuave (New-Object System.Drawing.Font('Segoe UI', 9))))

    $estado = Nueva-Etiqueta '' 26 336 500 24 $ColorSuave $null
    $f.Controls.Add($estado)

    $btnGuardar = New-Object System.Windows.Forms.Button
    $btnGuardar.Text = 'Guardar y empezar'
    $btnGuardar.Size = New-Object System.Drawing.Size(170, 38)
    $btnGuardar.Location = New-Object System.Drawing.Point(348, 372)
    $btnGuardar.FlatStyle = 'Flat'
    $btnGuardar.BackColor = $ColorAcento
    $btnGuardar.ForeColor = [System.Drawing.Color]::White
    $btnGuardar.FlatAppearance.BorderSize = 0
    $f.Controls.Add($btnGuardar)

    $btnCancelar = New-Object System.Windows.Forms.Button
    $btnCancelar.Text = 'Cancelar'
    $btnCancelar.Size = New-Object System.Drawing.Size(110, 38)
    $btnCancelar.Location = New-Object System.Drawing.Point(228, 372)
    $btnCancelar.FlatStyle = 'Flat'
    $btnCancelar.ForeColor = $ColorTexto
    $btnCancelar.DialogResult = 'Cancel'
    $f.Controls.Add($btnCancelar)
    $f.CancelButton = $btnCancelar
    $f.AcceptButton = $btnGuardar

    $resultado = @{ ok = $false }
    $btnGuardar.Add_Click({
        $g = $txtGemini.Text.Trim()
        if (-not $g) {
            Mostrar-Mensaje 'Pega tu clave de Google Gemini para continuar. Si no la tienes, haz clic en el enlace azul para conseguirla gratis.' 'Warning' | Out-Null
            return
        }
        $btnGuardar.Enabled = $false
        $estado.Text = 'Verificando tu clave con Google...'
        Refrescar
        $prueba = Probar-Clave-Gemini $g
        $btnGuardar.Enabled = $true
        if ($prueba -eq 'invalida') {
            $estado.Text = ''
            Mostrar-Mensaje 'Google dice que esa clave no es válida. Revisa que la hayas copiado completa (sin espacios) e inténtalo otra vez.' 'Warning' | Out-Null
            return
        }
        if ($prueba -eq 'sin-internet') {
            $r = Mostrar-Mensaje 'No pude comprobar la clave (¿hay internet?). ¿Quieres guardarla de todas formas?' 'Question' 'YesNo'
            if ($r -ne 'Yes') { $estado.Text = ''; return }
        }
        $resultado.ok = $true
        $resultado.gemini = $g
        $resultado.tavily = $txtTavily.Text.Trim()
        $f.Close()
    })

    [void]$f.ShowDialog()
    return $resultado
}

function Crear-Acceso-Directo {
    try {
        $escritorio = [Environment]::GetFolderPath('Desktop')
        # Si ya existe no se toca; si lo borraron, se vuelve a crear
        if (Test-Path (Join-Path $escritorio 'Cortana.lnk')) { return }
        $wsh = New-Object -ComObject WScript.Shell
        $lnk = $wsh.CreateShortcut((Join-Path $escritorio 'Cortana.lnk'))
        $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '"'
        $lnk.WorkingDirectory = $Raiz
        $icono = Join-Path $PSScriptRoot 'cortana.ico'
        if (Test-Path $icono) { $lnk.IconLocation = $icono }
        $lnk.Description = 'Abrir Cortana, tu asistente virtual'
        $lnk.Save()
        Escribir-Log 'Acceso directo de Cortana creado en el escritorio'
    } catch { Escribir-Log ('No se pudo crear el acceso directo: ' + $_) }
}

function Configurar-Claves([bool]$primeraVez) {
    $datos = Leer-Env
    $r = Mostrar-Asistente-Claves $datos
    if (-not $r.ok) { return $false }
    $datos['GEMINI_API_KEY'] = $r.gemini
    $datos['TAVILY_API_KEY'] = $r.tavily
    if (-not $datos['GEMINI_MODEL'])       { $datos['GEMINI_MODEL'] = 'gemini-3-flash-preview' }
    if (-not $datos['N8N_ENCRYPTION_KEY']) { $datos['N8N_ENCRYPTION_KEY'] = Clave-Aleatoria }
    if (-not $datos['ZONA_HORARIA'])       { $datos['ZONA_HORARIA'] = 'America/Caracas' }
    if (-not $datos['PUERTO_CORTANA'])     { $datos['PUERTO_CORTANA'] = '8765' }
    if (-not $datos['PUERTO_N8N'])         { $datos['PUERTO_N8N'] = '5679' }
    if (-not $datos['DB_PASSWORD'])        { $datos['DB_PASSWORD'] = Clave-Aleatoria }
    Guardar-Env $datos
    Escribir-Log 'Claves guardadas en .env'
    return $true
}

# ---------------- Docker ----------------
function Revisar-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Cerrar-Ventana-Progreso
        $r = Mostrar-Mensaje ("Cortana necesita un programa gratuito llamado Docker Desktop para funcionar.`n`n" +
            "1. Descárgalo e instálalo (se abrirá la página).`n2. Reinicia la computadora si te lo pide.`n3. Vuelve a abrir Cortana.`n`n¿Abrir la página de descarga?") 'Information' 'YesNo'
        if ($r -eq 'Yes') { Start-Process 'https://www.docker.com/products/docker-desktop/' }
        exit 0
    }
    if ((Ejecutar 'docker' 'info' 'docker-info') -eq 0) { return }

    Estado 'Encendiendo Docker Desktop... (puede tardar hasta 2 minutos)'
    $rutas = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Docker\Docker\Docker Desktop.exe')
    )
    $exe = $rutas | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) { Start-Process -FilePath $exe } else { Fallar 'No encontré Docker Desktop. Ábrelo manualmente y vuelve a abrir Cortana.' }

    $limite = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $limite) {
        Esperar 3
        if ((Ejecutar 'docker' 'info' 'docker-info') -eq 0) { Estado 'Docker está listo.'; return }
    }
    Fallar 'Docker Desktop no terminó de encender. Ábrelo manualmente, espera a que diga "Engine running" y vuelve a abrir Cortana.'
}

function Contenedor-Caido {
    $null = Ejecutar 'docker' 'inspect -f "{{.State.Status}}" cortana-n8n' 'estado-contenedor'
    $estado = (Get-Content (Join-Path $Logs 'estado-contenedor.log') -ErrorAction SilentlyContinue | Select-Object -First 1)
    return ($estado -eq 'exited' -or $estado -eq 'dead')
}

function Guardar-Logs-n8n {
    $null = Ejecutar 'docker' 'compose logs --no-color --tail 200 db db-migrar n8n' 'n8n'
}

function Abrir-Ventana-Chat([string]$url) {
    $edge = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    $chrome = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    # Modo "app": se abre como una ventana propia, sin barra de direcciones
    $argumentos = '--app=' + $url + ' --window-size=1000,780'
    if ($edge) { Start-Process -FilePath $edge -ArgumentList $argumentos }
    elseif ($chrome) { Start-Process -FilePath $chrome -ArgumentList $argumentos }
    else { Start-Process $url }
}

# ---------------- Vigilante de recordatorios ----------------
# Es un segundo proceso, oculto, que deja el ícono de Cortana junto al reloj
# de Windows y cada 30 segundos pregunta si hay actividades por avisar.
$NombreMutex = 'Local\CortanaVigilante'

function Iniciar-Vigilante {
    # Si ya había un vigilante (quizás de una versión anterior), se reemplaza por uno nuevo
    Detener-Vigilante
    Start-Sleep -Milliseconds 500
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentos = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -Vigilar'
    Start-Process -FilePath $ps -ArgumentList $argumentos -WindowStyle Hidden
    Escribir-Log 'Vigilante de recordatorios iniciado'
}

function Detener-Vigilante {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.CommandLine -like '*Cortana.ps1*-Vigilar*' -and $_.ProcessId -ne $PID } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Texto-Cuando($a) {
    $hoy = (Get-Date).ToString('dd/MM/yyyy')
    $man = (Get-Date).AddDays(1).ToString('dd/MM/yyyy')
    if ($a.fecha -eq $hoy) { $dia = 'Hoy' } elseif ($a.fecha -eq $man) { $dia = 'Mañana' } else { $dia = 'El ' + $a.fecha }
    $m = [int]$a.minutos_faltan
    if ($m -le 0) { $falta = 'ahora' }
    elseif ($m -lt 60) { $falta = 'en ' + $m + ' min' }
    else {
        $h = [math]::Floor($m / 60); $r = $m % 60
        $falta = 'en ' + $h + ' h'
        if ($r -gt 0) { $falta += ' ' + $r + ' min' }
    }
    return ($dia + ' a las ' + $a.hora + ' (' + $falta + ')')
}

$script:Avisos = New-Object System.Collections.ArrayList

function Sonar-Aviso {
    $wav = @(
        (Join-Path $env:windir 'Media\Windows Notify Calendar.wav'),
        (Join-Path $env:windir 'Media\Alarm01.wav'),
        (Join-Path $env:windir 'Media\Windows Notify.wav')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    try {
        if ($wav) { (New-Object System.Media.SoundPlayer $wav).Play() }
        else { [System.Media.SystemSounds]::Exclamation.Play() }
    } catch { }
}

function Acomodar-Avisos {
    # Apila las ventanas de aviso en la esquina inferior derecha de la pantalla
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $y = $area.Bottom - 12
    foreach ($v in @($script:Avisos)) {
        $y -= $v.Height
        $v.Location = New-Object System.Drawing.Point(($area.Right - $v.Width - 12), $y)
        $y -= 10
    }
}

# Ventana de aviso propia: no depende de la configuración de notificaciones
# de Windows y se queda en pantalla hasta que el usuario la cierre.
function Mostrar-Aviso($a) {
    $esAhora = ($a.tipo -eq 'inicio')
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'Manual'
    $f.TopMost = $true
    $f.ShowInTaskbar = $true
    $f.Text = 'Cortana: ' + $a.titulo
    $f.Size = New-Object System.Drawing.Size(390, 168)
    $f.BackColor = $ColorFondo
    $f.ForeColor = $ColorTexto
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $ico = Join-Path $PSScriptRoot 'cortana.ico'
    if (Test-Path $ico) { $f.Icon = New-Object System.Drawing.Icon($ico) }

    $franja = New-Object System.Windows.Forms.Panel
    $franja.BackColor = $ColorAcento
    $franja.Dock = 'Left'
    $franja.Width = 6
    $f.Controls.Add($franja)

    if ($esAhora) { $encabezado = 'CORTANA  |  ¡ES LA HORA!' } else { $encabezado = 'CORTANA  |  RECORDATORIO' }
    $f.Controls.Add((Nueva-Etiqueta $encabezado 20 12 350 18 $ColorAcento (New-Object System.Drawing.Font('Segoe UI Semibold', 8.5))))
    $tit = $a.titulo
    if ($tit.Length -gt 42) { $tit = $tit.Substring(0, 40) + '...' }
    $f.Controls.Add((Nueva-Etiqueta $tit 20 32 355 28 $ColorTexto (New-Object System.Drawing.Font('Segoe UI Semibold', 13))))
    $f.Controls.Add((Nueva-Etiqueta (Texto-Cuando $a) 20 62 355 20 $ColorTexto $null))
    $desc = [string]$a.descripcion
    if ($desc.Length -gt 55) { $desc = $desc.Substring(0, 53) + '...' }
    $f.Controls.Add((Nueva-Etiqueta $desc 20 84 355 20 $ColorSuave (New-Object System.Drawing.Font('Segoe UI', 9))))

    $bAbrir = New-Object System.Windows.Forms.Button
    $bAbrir.Text = 'Abrir Cortana'
    $bAbrir.Size = New-Object System.Drawing.Size(120, 32)
    $bAbrir.Location = New-Object System.Drawing.Point(130, 120)
    $bAbrir.FlatStyle = 'Flat'
    $bAbrir.ForeColor = $ColorTexto
    $f.Controls.Add($bAbrir)

    $bOk = New-Object System.Windows.Forms.Button
    $bOk.Text = 'Entendido'
    $bOk.Size = New-Object System.Drawing.Size(110, 32)
    $bOk.Location = New-Object System.Drawing.Point(260, 120)
    $bOk.FlatStyle = 'Flat'
    $bOk.BackColor = $ColorAcento
    $bOk.ForeColor = [System.Drawing.Color]::White
    $bOk.FlatAppearance.BorderSize = 0
    $f.Controls.Add($bOk)

    $bOk.Add_Click({ $this.FindForm().Close() })
    $bAbrir.Add_Click({ Abrir-Ventana-Chat $script:UrlChat; $this.FindForm().Close() })
    $f.Add_FormClosed({ $script:Avisos.Remove($this); Acomodar-Avisos })

    [void]$script:Avisos.Insert(0, $f)
    Acomodar-Avisos
    $f.Show()
    $f.Activate()
}

function Revisar-Recordatorios {
    try {
        $r = Invoke-RestMethod -Uri ($script:UrlChat + '/api/cortana-recordatorios') -TimeoutSec 8
    } catch { return }   # Cortana apagada o arrancando: se intenta en la próxima vuelta
    $lista = @($r.recordatorios | Where-Object { $_ -and $_.titulo })
    if ($lista.Count -eq 0) { return }

    Escribir-Log ('Recordatorio mostrado: ' + (($lista | ForEach-Object { $_.titulo + ' (' + $_.tipo + ')' }) -join ', '))
    Sonar-Aviso
    foreach ($a in $lista) { Mostrar-Aviso $a }
}

function Iniciar-Modo-Vigilante([string]$url) {
    $creado = $false
    $mutex = New-Object System.Threading.Mutex($true, $NombreMutex, [ref]$creado)
    if (-not $creado) { exit 0 }   # ya hay otro vigilante

    $script:UrlChat = $url
    $script:Icono = New-Object System.Windows.Forms.NotifyIcon
    $ico = Join-Path $PSScriptRoot 'cortana.ico'
    if (Test-Path $ico) { $script:Icono.Icon = New-Object System.Drawing.Icon($ico) }
    else { $script:Icono.Icon = [System.Drawing.SystemIcons]::Information }
    $script:Icono.Text = 'Cortana: pendiente de tu agenda'
    $script:Icono.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $null = $menu.Items.Add('Abrir Cortana', $null, { Abrir-Ventana-Chat $script:UrlChat })
    $null = $menu.Items.Add('Revisar recordatorios ahora', $null, { Revisar-Recordatorios })
    $null = $menu.Items.Add('-')
    $null = $menu.Items.Add('Apagar Cortana', $null, {
        $script:Icono.ShowBalloonTip(3000, 'Cortana', 'Apagando... ¡hasta pronto!', [System.Windows.Forms.ToolTipIcon]::Info)
        $null = Ejecutar 'docker' 'compose stop' 'docker-detener'
        $script:Icono.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })
    $script:Icono.ContextMenuStrip = $menu
    $script:Icono.Add_DoubleClick({ Abrir-Ventana-Chat $script:UrlChat })
    $script:Icono.Add_BalloonTipClicked({ Abrir-Ventana-Chat $script:UrlChat })

    $script:Reloj = New-Object System.Windows.Forms.Timer
    $script:Reloj.Interval = 30000
    $script:Reloj.Add_Tick({ Revisar-Recordatorios })
    $script:Reloj.Start()

    $script:Icono.ShowBalloonTip(6000, 'Cortana', 'Estoy pendiente de tu agenda. Te avisaré antes de cada actividad y a la hora exacta.', [System.Windows.Forms.ToolTipIcon]::Info)
    Revisar-Recordatorios

    [System.Windows.Forms.Application]::Run()
    $script:Reloj.Stop()
    $script:Icono.Dispose()
    $mutex.ReleaseMutex()
}

# =============================================================
#  Programa principal
# =============================================================
try {
    if ($Vigilar) {
        $d = Leer-Env
        $p = $d['PUERTO_CORTANA']; if (-not $p) { $p = '8765' }
        Iniciar-Modo-Vigilante ('http://localhost:' + $p)
        exit 0
    }

    if ($Detener) {
        Detener-Vigilante
        Abrir-Ventana-Progreso 'Apagando Cortana'
        Estado 'Guardando todo y apagando...'
        $null = Ejecutar 'docker' 'compose stop' 'docker-detener'
        Cerrar-Ventana-Progreso
        Mostrar-Mensaje 'Cortana se apagó. ¡Hasta pronto!' | Out-Null
        exit 0
    }

    $datos = Leer-Env
    $primeraVez = -not $datos['GEMINI_API_KEY']
    if ($primeraVez -or $Configurar) {
        if (-not (Configurar-Claves $primeraVez)) { exit 0 }
        $datos = Leer-Env
    }
    # La base de datos de la agenda necesita su propia contraseña (se genera sola)
    if (-not $datos['DB_PASSWORD']) {
        $datos['DB_PASSWORD'] = Clave-Aleatoria
        if (-not $datos['PUERTO_N8N']) { $datos['PUERTO_N8N'] = '5679' }
        Guardar-Env $datos
        Escribir-Log 'Contraseña de la base de datos generada'
    }
    $puerto = $datos['PUERTO_CORTANA']
    if (-not $puerto) { $puerto = '8765' }
    $url = 'http://localhost:' + $puerto

    Abrir-Ventana-Progreso 'Iniciando Cortana'
    Estado 'Revisando Docker...'
    Revisar-Docker

    $imagenExiste = ((Ejecutar 'docker' 'image inspect cortana-n8n:1.0' 'docker-imagen') -eq 0)
    if ($imagenExiste) {
        Estado 'Encendiendo a Cortana... (si es la primera vez con la agenda, descarga la base de datos)'
        $codigo = Ejecutar 'docker' 'compose up -d' 'docker-arranque'
    } else {
        Estado 'Preparando Cortana por primera vez. Esto puede tardar varios minutos (descarga unos 700 MB)...'
        $codigo = Ejecutar 'docker' 'compose up -d --build' 'docker-arranque'
    }
    if ($codigo -ne 0) {
        $detalle = Get-Content (Join-Path $Logs 'docker-arranque-error.log') -Raw -ErrorAction SilentlyContinue
        if ($detalle -match 'port is already allocated|address already in use') {
            $puertoOcupado = ''
            if ($detalle -match ':(\d+) failed') { $puertoOcupado = ' (' + $Matches[1] + ')' }
            Fallar ("Otro programa ya está usando el puerto que necesita Cortana" + $puertoOcupado + ".`n`n" +
                "Suele pasar cuando hay otro asistente o n8n encendido en Docker (por ejemplo, Zoe). " +
                "Apágalo desde Docker Desktop y vuelve a abrir Cortana.")
        }
        if ($detalle -match 'db-migrar') {
            Guardar-Logs-n8n
            Fallar 'No pude preparar la base de datos de la agenda. Revisa el archivo logs\n8n.log.'
        }
        Fallar 'No pude encender los contenedores de Cortana. ¿Hay internet y Docker está funcionando?'
    }

    # Aquí estaba el error de Zoe: hay que ESPERAR a que el cerebro esté listo
    Estado 'Despertando a Cortana...'
    $listo = $false
    $limite = (Get-Date).AddSeconds(240)
    while ((Get-Date) -lt $limite) {
        try {
            $r = Invoke-WebRequest -Uri ($url + '/api/cortana-estado') -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $listo = $true; break }
        } catch { }
        if (Contenedor-Caido) {
            Guardar-Logs-n8n
            Fallar 'Cortana tuvo un problema al arrancar. Revisa el archivo logs\n8n.log o vuelve a configurar tus claves con Configurar_Cortana.'
        }
        Esperar 2
    }
    if (-not $listo) {
        Guardar-Logs-n8n
        Fallar 'Cortana está tardando demasiado en arrancar. Cierra esta ventana e inténtalo de nuevo en un momento.'
    }

    Estado '¡Lista!'
    Esperar 0.5
    Cerrar-Ventana-Progreso
    Crear-Acceso-Directo
    Abrir-Ventana-Chat $url
    Escribir-Log ('Ventana de chat abierta en ' + $url)
    Iniciar-Vigilante
}
catch {
    Fallar ('Ocurrió un error inesperado: ' + $_.Exception.Message)
}
