# ===============================================================
# critical-services-audit.ps1
# Auditoría y recuperación de servicios críticos de Windows
# ===============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ================= CONFIG =================
$Config = @{
    ScriptName = 'Critical-Services-Audit'
    LogRoot = 'C:\Scripts\Logs\Critical-Services-Audit'
    CriticalServices = @('Spooler', 'W32Time', 'LanmanServer')
    EventLog = @{ Name = 'Application'; Source = 'CriticalServicesAuditScript' }
    Notification = @{
        Mail = @{ Enabled = $true; SmtpServer = 'smtp.company.local'; Port = 587; UseSsl = $true; User = 'smtp_user_placeholder'; PasswordEnvVar = 'AUTOMATION_SMTP_PASSWORD'; From = 'automation@company.local'; To = @('ops@company.local') }
        Telegram = @{ Enabled = $true; BotTokenEnvVar = 'AUTOMATION_TELEGRAM_BOT_TOKEN'; ChatIdEnvVar = 'AUTOMATION_TELEGRAM_CHAT_ID' }
    }
}

# ================= LOG =================
if (-not (Test-Path -Path $Config.LogRoot)) { New-Item -Path $Config.LogRoot -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $Config.LogRoot ('{0}-{1:yyyyMMdd}.log' -f $Config.ScriptName, (Get-Date))

function Log {
    param([Parameter(Mandatory)] [string]$Message, [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO', [hashtable]$Data)
    $entry = [ordered]@{ timestamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); level=$Level; script=$Config.ScriptName; host=$env:COMPUTERNAME; message=$Message; data=$Data }
    Add-Content -Path $LogFile -Value ($entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
    Write-Host ('[{0}] {1}' -f $Level, $Message)
}

function Send-Mail {
    param([Parameter(Mandatory)] [string]$Subject, [Parameter(Mandatory)] [string]$Body)
    if (-not $Config.Notification.Mail.Enabled) { return }
    try {
        $pwd = [Environment]::GetEnvironmentVariable($Config.Notification.Mail.PasswordEnvVar, 'Machine')
        if ([string]::IsNullOrWhiteSpace($pwd)) { $pwd = [Environment]::GetEnvironmentVariable($Config.Notification.Mail.PasswordEnvVar, 'Process') }
        if ([string]::IsNullOrWhiteSpace($pwd)) { throw "No existe variable '$($Config.Notification.Mail.PasswordEnvVar)'" }
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $Config.Notification.Mail.From
        foreach ($recipient in $Config.Notification.Mail.To) { [void]$mail.To.Add($recipient) }
        $mail.Subject = $Subject
        $mail.Body = $Body
        $smtp = New-Object System.Net.Mail.SmtpClient($Config.Notification.Mail.SmtpServer, $Config.Notification.Mail.Port)
        $smtp.EnableSsl = $Config.Notification.Mail.UseSsl
        $smtp.Credentials = New-Object System.Net.NetworkCredential($Config.Notification.Mail.User, $pwd)
        $smtp.Send($mail)
        $mail.Dispose(); $smtp.Dispose()
        Log -Message 'Notificación SMTP enviada.'
    }
    catch { Log -Message "Error SMTP: $($_.Exception.Message)" -Level 'ERROR' }
}

function Send-Telegram {
    param([Parameter(Mandatory)] [string]$Message)
    if (-not $Config.Notification.Telegram.Enabled) { return }
    try {
        $bot = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.BotTokenEnvVar, 'Machine')
        $chat = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.ChatIdEnvVar, 'Machine')
        if ([string]::IsNullOrWhiteSpace($bot)) { $bot = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.BotTokenEnvVar, 'Process') }
        if ([string]::IsNullOrWhiteSpace($chat)) { $chat = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.ChatIdEnvVar, 'Process') }
        if ([string]::IsNullOrWhiteSpace($bot) -or [string]::IsNullOrWhiteSpace($chat)) { throw 'Faltan credenciales Telegram.' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri ("https://api.telegram.org/bot{0}/sendMessage" -f $bot) -Method Post -Body @{ chat_id=$chat; text=$Message } | Out-Null
        Log -Message 'Notificación Telegram enviada.'
    }
    catch { Log -Message "Error Telegram: $($_.Exception.Message)" -Level 'ERROR' }
}

function Test-Prerequisites {
    if (-not (Get-Command -Name Get-Service -ErrorAction SilentlyContinue)) { throw 'Get-Service no está disponible.' }
}

function Write-ServiceEvent {
    param([string]$Message, [int]$EventId = 5501)
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($Config.EventLog.Source)) {
            New-EventLog -LogName $Config.EventLog.Name -Source $Config.EventLog.Source
        }
        Write-EventLog -LogName $Config.EventLog.Name -Source $Config.EventLog.Source -EntryType Warning -EventId $EventId -Message $Message
    }
    catch {
        Log -Message "No se pudo registrar evento: $($_.Exception.Message)" -Level 'WARN'
    }
}

$errorsList = New-Object System.Collections.Generic.List[string]
$notRecovered = New-Object System.Collections.Generic.List[string]

Log -Message '=== INICIO CRITICAL SERVICES AUDIT ==='

try {
    Test-Prerequisites
    foreach ($serviceName in $Config.CriticalServices) {
        $svc = Get-Service -Name $serviceName -ErrorAction Stop
        if ($svc.Status -eq 'Running') {
            Log -Message "Servicio $serviceName operativo."
            continue
        }

        Log -Message "Servicio $serviceName detenido, intentando iniciar." -Level 'WARN'
        try {
            Start-Service -Name $serviceName -ErrorAction Stop
            Start-Sleep -Seconds 3
            $svcAfter = Get-Service -Name $serviceName -ErrorAction Stop
            if ($svcAfter.Status -ne 'Running') { throw "Estado actual: $($svcAfter.Status)" }
            Write-ServiceEvent -Message "Servicio crítico $serviceName reiniciado automáticamente." -EventId 5502
            Log -Message "Servicio $serviceName recuperado."
        }
        catch {
            $msg = "No se pudo iniciar $serviceName: $($_.Exception.Message)"
            $notRecovered.Add($serviceName)
            $errorsList.Add($msg)
            Write-ServiceEvent -Message $msg -EventId 5503
            Log -Message $msg -Level 'ERROR'
        }
    }
}
catch {
    $errorsList.Add($_.Exception.Message)
    Log -Message "Error general: $($_.Exception.Message)" -Level 'ERROR'
}

# ================= NOTIFICACION FINAL =================
if ($errorsList.Count -gt 0 -or $notRecovered.Count -gt 0) {
    $msg = "Critical Services Audit ($env:COMPUTERNAME)`n" + (($errorsList | Select-Object -Unique) -join "`n")
    Send-Mail -Subject "ALERTA Servicios Críticos - $env:COMPUTERNAME" -Body $msg
    Send-Telegram -Message $msg
}
else {
    Send-Telegram -Message "Critical Services Audit sin novedades en $env:COMPUTERNAME"
}

Log -Message '=== FIN CRITICAL SERVICES AUDIT ==='

# ---
# ## ‍ Desarrollado por Isaac Esteban Haro Torres
# **Ingeniero en Sistemas · Full Stack · Automatización · Data**
# -  Email: zackharo1@gmail.com
# -  WhatsApp: 098805517
# -  GitHub: https://github.com/ieharo1
# -  Portafolio: https://ieharo1.github.io/portafolio-isaac.haro/
# ---
# ##  Licencia
# © 2026 Isaac Esteban Haro Torres - Todos los derechos reservados.
