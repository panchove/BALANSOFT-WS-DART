# ============================================================
# BALANSOFT-WS · Reset total para pruebas desde la instalación (Windows)
#
# 1. Cierra la app y el WServer.
# 2. Elimina el estado de la app (AppData).
# 3. Elimina los tokens del almacén seguro (Credential Manager).
# 4. Elimina el runtime del WServer (~/.balansoft-ws/wserver).
# 5. Elimina la base de datos 'balansoft_ws_local' en PostgreSQL y SQL Server.
# 6. Reconstruye el bundle: flutter build windows + copia WServer.exe e icono.
#
# Uso:
#   .\reset_total.ps1            # con confirmaciones
#   .\reset_total.ps1 -y         # sin confirmaciones
#   .\reset_total.ps1 -NoBuild   # limpia sin reconstruir
#   .\reset_total.ps1 -NoDB      # no toca las bases de datos
# ============================================================

param (
    [switch]$y,
    [switch]$NoBuild,
    [switch]$NoDB
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ── Configuración ──────────────────────────────────────────────────────────
$ROOT = Resolve-Path (Join-Path $PSScriptRoot "..")
$APP_DATA = Join-Path $env:APPDATA "com.balansoft.balansoft_ws"
$WSRUNTIME = Join-Path $env:USERPROFILE ".balansoft-ws\wserver"
$BUNDLE = Join-Path $ROOT "frontend\build\windows\x64\runner\Release"
$WSERVER_BIN = Join-Path $ROOT "backend\dist\WServer.exe"
$WSERVER_ICON = Join-Path $ROOT "wserver_icon.jpeg"
$DB_NAME = "balansoft_ws_local"

# Credenciales de PostgreSQL
$PG_USER = "sqlman"
$PG_PASS = "7767"
$PG_HOST = "localhost"
$PG_PORT = "5432"
$psqlExe = "C:\Program Files\PostgreSQL\bin\psql.exe"

# Credenciales de SQL Server
$SQL_USER = "sa"
$SQL_PASS = "7767"
$SQL_HOST = "localhost"

# ── Utilidades ──────────────────────────────────────────────────────────────
function Info($msg) { Write-Host "[1] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[✓] $msg" -ForegroundColor Green }
function Aviso($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err($msg)  { Write-Host "[✗] $msg" -ForegroundColor Red }

# ── Banner + confirmación ───────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   BALANSOFT-WS · Reset total para instalación/pruebas    ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (-not $y) {
    Write-Host "Se va a eliminar:"
    Write-Host "  - Estado de la app        → $APP_DATA"
    Write-Host "  - Runtime del WServer     → $WSRUNTIME"
    Write-Host "  - Token seguro (Windows)  → Credential Manager"
    if (-not $NoDB) {
        Write-Host "  - Base de Datos           → $DB_NAME (PostgreSQL y SQL Server)"
    }
    if (-not $NoBuild) {
        Write-Host "  (y reconstruirá el bundle de release para Windows)"
    }
    Write-Host ""
    $respuesta = Read-Host 'Escribe "si" (en minúsculas) para continuar'
    if ($respuesta -ne "si") {
        Write-Host "Abortado."
        exit 1
    }
}

# ── 1. Cerrar app y WServer ─────────────────────────────────────────────────
Info "Deteniendo la app y el WServer... "
$appProc = Get-Process -Name "balansoft_ws" -ErrorAction SilentlyContinue
if ($appProc) { Stop-Process -Name "balansoft_ws" -Force; Aviso "App cerrada." } else { Ok "No había app corriendo." }

$srvProc = Get-Process -Name "WServer" -ErrorAction SilentlyContinue
if ($srvProc) { Stop-Process -Name "WServer" -Force; Aviso "WServer detenido." } else { Ok "No había WServer corriendo." }
Start-Sleep -Seconds 1

# ── 2. Estado de la app ─────────────────────────────────────────────────────
Info "Limpiando estado de la app... "
if (Test-Path $APP_DATA) {
    Remove-Item -Recurse -Force $APP_DATA
    Ok "Estado de la app eliminado."
} else {
    Ok "No existía estado de la app."
}

# ── 3. Tokens del almacén seguro ─────────────────────────────────────────────
Info "Eliminando tokens del almacén seguro (Credential Manager)... "
$targetName = "com.balansoft.balansoft_ws.secureStorage"
try {
    cmdkey /list | Select-String $targetName | ForEach-Object {
        if ($_ -match "Target:\s+(.+)") {
            $target = $matches[1].Trim()
            cmdkey /delete:$target | Out-Null
        }
    }
    Ok "Almacén seguro limpio."
} catch {
    Aviso "No se pudieron borrar los tokens automáticamente. Puedes hacerlo manualmente en el Administrador de Credenciales de Windows."
}

# ── 4. Runtime del WServer ──────────────────────────────────────────────────
Info "Limpiando runtime del WServer... "
if (Test-Path $WSRUNTIME) {
    Remove-Item -Recurse -Force $WSRUNTIME
    Ok "Runtime del WServer eliminado."
} else {
    Ok "No existía runtime del WServer."
}

# ── 5. Bases de Datos (PostgreSQL y SQL Server) ─────────────────────────────
if (-not $NoDB) {
    Info "Eliminando base de datos '$DB_NAME'..."

    # 5a. PostgreSQL
    Info "→ Buscando en PostgreSQL..."
    if (Test-Path $psqlExe) {
        $env:PGPASSWORD = $PG_PASS
        
        # Guardar configuración de errores y codificación
        $oldErrorAction = $ErrorActionPreference
        $oldOutputEncoding = [Console]::OutputEncoding
        
        # Ignorar avisos y forzar UTF-8 para evitar caracteres extraños
        $ErrorActionPreference = "Continue"
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

        $query = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();"
        & $psqlExe -h $PG_HOST -p $PG_PORT -U $PG_USER -d postgres -c $query 2>&1 | Out-Null
        
        $dropQuery = "DROP DATABASE IF EXISTS $DB_NAME;"
        & $psqlExe -h $PG_HOST -p $PG_PORT -U $PG_USER -d postgres -c $dropQuery 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Ok "Base de datos '$DB_NAME' eliminada en PostgreSQL."
        } else {
            Err "No se pudo eliminar en PostgreSQL (revisa que el servicio esté corriendo)."
        }
        
        # Restaurar configuración
        $ErrorActionPreference = $oldErrorAction
        [Console]::OutputEncoding = $oldOutputEncoding
    } else {
        Aviso "No se encontró psql.exe en la ruta esperada. Omitiendo PostgreSQL."
    }

    # 5b. SQL Server
    Info "→ Buscando en SQL Server..."
    if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
        $sqlQuery = "IF DB_ID('$DB_NAME') IS NOT NULL BEGIN ALTER DATABASE [$DB_NAME] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$DB_NAME]; END"
        sqlcmd -S $SQL_HOST -U $SQL_USER -P $SQL_PASS -Q $sqlQuery | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Ok "Base de datos '$DB_NAME' eliminada en SQL Server."
        } else {
            Err "No se pudo eliminar en SQL Server (revisa que el servicio esté corriendo)."
        }
    } else {
        Aviso "Comando 'sqlcmd' no encontrado en el PATH. Omitiendo SQL Server."
    }
} else {
    Info "Omitiendo bases de datos (-NoDB)."
}

# ── 6. Reconstruir bundle ────────────────────────────────────────────────────
$BUILD_OK = $true
if (-not $NoBuild) {
    Info "Reconstruyendo bundle de release para Windows... "
    if (-not (Test-Path $WSERVER_BIN)) {
        Err "No existe el binario del WServer en $WSERVER_BIN. Compílalo primero."
        $BUILD_OK = $false
    } else {
        Push-Location (Join-Path $ROOT "frontend")
        try {
            flutter build windows --release
            if ($LASTEXITCODE -ne 0) { throw "Fallo en flutter build" }
            
            if (-not (Test-Path $BUNDLE) -and (Test-Path (Join-Path $ROOT "frontend\build\windows\runner\Release"))) {
                $BUNDLE = Join-Path $ROOT "frontend\build\windows\runner\Release"
            }
            if (Test-Path $BUNDLE) {
                Copy-Item $WSERVER_BIN -Destination $BUNDLE -Force
                Ok "WServer.exe copiado al bundle."
                
                if (Test-Path $WSERVER_ICON) {
                    Copy-Item $WSERVER_ICON -Destination $BUNDLE -Force
                    Ok "Icono del WServer copiado al bundle."
                }
            } else {
                throw "No se encontró la carpeta de salida de Flutter ($BUNDLE)."
            }
        } catch {
            Err $_.Exception.Message
            $BUILD_OK = $false
        } finally {
            Pop-Location
        }
    }
} else {
    Info "Omitiendo rebuild (-NoBuild)."
}

# ── Resumen ──────────────────────────────────────────────────────────────────
Write-Host ""
if ($BUILD_OK -eq $false) {
    Err "El reset de estado está hecho, pero el bundle NO quedó reconstruido."
    Write-Host ""
}
Write-Host "  == Listo ==" -ForegroundColor Cyan

if ($NoBuild) {
    Write-Host "  (Reconstrucción del bundle omitida por -NoBuild)"
    Write-Host "  El WServer regenerará su runtime en la primera ejecución."
} else {
    if ($BUILD_OK) {
        Write-Host "  Bundle listo: $BUNDLE"
        Write-Host "  Prueba la instalación con:"
        Write-Host "    $BUNDLE\balansoft_ws.exe"
        Write-Host "  El WServer regenerará su runtime en la primera ejecución."
    } else {
        Write-Host "  Para dejar el bundle listo, compila manualmente:"
        Write-Host "    cd $ROOT\frontend"
        Write-Host "    flutter build windows --release"
    }
}
Write-Host ""