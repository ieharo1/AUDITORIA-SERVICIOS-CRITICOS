# Auditoria de Servicios Criticos - Documentacion Operativa

Script principal: `critical-services-audit.ps1`

## Objetivo
Verificar estado de servicios criticos de Windows, intentar auto-recuperacion, registrar evento y notificar si no se logra levantar.

## Funcionamiento
1. Valida disponibilidad de `Get-Service`.
2. Recorre servicios configurados en `CriticalServices`.
3. Si un servicio esta detenido:
   - intenta `Start-Service`
   - revalida estado
   - registra evento en `Application` log
4. Si falla la recuperacion, envía alerta SMTP y Telegram.
5. Guarda log diario estructurado.

## Prerequisitos
- Windows Server 2019/2022
- PowerShell 5.1+
- Permisos para iniciar servicios
- Permisos para escribir en Event Log

## Configuracion
- `CriticalServices` (ejemplo: `Spooler`, `W32Time`, `LanmanServer`)
- `EventLog.Name` y `EventLog.Source`
- `Notification.Mail.*`
- `Notification.Telegram.*`

## Variables de entorno
- `AUTOMATION_SMTP_PASSWORD`
- `AUTOMATION_TELEGRAM_BOT_TOKEN`
- `AUTOMATION_TELEGRAM_CHAT_ID`

## Como ejecutar

```powershell
cd C:\Users\Nabetse\Downloads\server\Applet1
.\critical-services-audit.ps1
```

## Programacion recomendada
- Trigger: cada 5 o 10 minutos
- Ejecutar con privilegios altos
- Cuenta con permisos sobre servicios criticos

## Resultado esperado
- Sin fallos: mensaje de estado OK
- Con servicio caido y recuperado: evento de recuperacion
- Con servicio no recuperado: alerta inmediata

## Seguridad
- Evitar cuenta Domain Admin
- Usar cuenta de servicio local dedicada
- Proteger variables de entorno sensibles
---
## ‍ Desarrollado por Isaac Esteban Haro Torres
**Ingeniero en Sistemas · Full Stack · Automatización · Data**
-  Email: zackharo1@gmail.com
-  WhatsApp: 098805517
-  GitHub: https://github.com/ieharo1
-  Portafolio: https://ieharo1.github.io/portafolio-isaac.haro/
---
##  Licencia
© 2026 Isaac Esteban Haro Torres - Todos los derechos reservados.
