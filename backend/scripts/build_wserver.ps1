# ============================================================
# BALANSOFT-WS - Build del WServer (backend local compilado)
#
# Empaca la API FastAPI (rol local) en un binario único con
# PyInstaller (one-file) llamado "WServer", con los datos
# embebidos (esquemas SQL, migraciones y plantilla .env).
#
# Uso:
#   .\scripts\build_wserver.ps1
#
# Salida: backend\dist\WServer.exe
# ============================================================

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Ir a la raíz del backend (carpeta padre de scripts\)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptDir "..")

Write-Host "== WServer build ==" -ForegroundColor Cyan
Write-Host ("Backend: " + (Get-Location))
Write-Host ""

# Rutas a los ejecutables del venv local (soporta .venv y venv)
$pyExe = $null
if (Test-Path (Join-Path $PWD ".venv\Scripts\python.exe")) {
    $pyExe = Join-Path $PWD ".venv\Scripts\python.exe"
} elseif (Test-Path (Join-Path $PWD "venv\Scripts\python.exe")) {
    $pyExe = Join-Path $PWD "venv\Scripts\python.exe"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $pyExe = (Get-Command python).Source
}

# 1) Asegurar PyInstaller en el entorno
if (-not $pyExe -or -not (Test-Path $pyExe)) {
    Write-Host "❌ No se encontró el entorno virtual en .venv o venv" -ForegroundColor Red
    Write-Host "   Asegúrate de tener el venv creado y activado en la carpeta backend." -ForegroundColor Yellow
    exit 1
}

$venvScripts = Split-Path -Parent $pyExe
$pyiExe = Join-Path $venvScripts "pyinstaller.exe" 

$hasPyInstaller = $false
try {
    & $pyExe -c "import PyInstaller" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $hasPyInstaller = $true }
} catch { $hasPyInstaller = $false }

if (-not $hasPyInstaller) {
    Write-Host "[1] Instalando pyinstaller y pillow (dev dep)..."
    & $pyExe -m pip install pyinstaller pillow
    if ($LASTEXITCODE -ne 0) { throw "Fallo al instalar pyinstaller/pillow" }
}

$pyiVer = (& $pyExe -c "import PyInstaller; print(PyInstaller.__version__)").Trim()
Write-Host "[1] PyInstaller: $pyiVer"

# 1.5) Preparar icono
$iconSrc = Join-Path $PWD "..\wserver_icon.jpeg"
if (Test-Path $iconSrc) {
    Write-Host "[1.5] Generando icono wserver_icon.ico desde JPEG..."
    & $pyExe -c @"
from PIL import Image
try:
    img = Image.open('../wserver_icon.jpeg')
    img.save('wserver_icon.ico', format='ICO', sizes=[(256, 256)])
except Exception as e:
    print('Error generando icono:', e)
"@
}

# 2) Compilar one-file
Write-Host "[2] Compilando WServer..."
if (Test-Path build) { Remove-Item -Recurse -Force build }
if (Test-Path dist)  { Remove-Item -Recurse -Force dist }
& $pyiExe WServer.spec --noconfirm --clean
if ($LASTEXITCODE -ne 0) { throw "PyInstaller falló" }

# 3) Verificar (en Windows el binario es .exe)
$bin = "dist\WServer.exe"
if (-not (Test-Path $bin)) {
    # fallback por si el spec genera dist\WServer\WServer.exe
    if (Test-Path "dist\WServer\WServer.exe") {
        $bin = "dist\WServer\WServer.exe"
    } else {
        Write-Host "❌ No se encontró el binario: $bin" -ForegroundColor Red
        exit 1
    }
}
$size = "{0:N2} MB" -f ((Get-Item $bin).Length / 1MB)
Write-Host "[3] ✅ Binario generado: $bin ($size)" -ForegroundColor Green

# 3.5) Verificar que los drivers de SQL Server estén dentro (Sanity check)
Write-Host "[3.5] Verificando que pyodbc está empaquetado..."
$pyiViewer = Join-Path $PWD ".\venv\Scripts\pyi-archive_viewer.exe"
if (Test-Path $pyiViewer) {
    $check = & $pyiViewer $bin | Select-String "pyodbc" | Select-Object -First 1
    if ($check) {
        Write-Host "    ✅ pyodbc encontrado en el ejecutable." -ForegroundColor Green
    } else {
        Write-Host "    ⚠️ ADVERTENCIA: pyodbc no parece estar dentro del .exe." -ForegroundColor Yellow
    }
}

# 4) Integrar al bundle de Flutter (Windows release)
$bundleDir = "..\frontend\build\windows\x64\runner\Release"
if (-not (Test-Path $bundleDir) -and (Test-Path "..\frontend\build\windows\runner\Release")) {
    $bundleDir = "..\frontend\build\windows\runner\Release"
}
if (Test-Path $bundleDir) {
    Write-Host "[4] Integrando WServer en el bundle de Flutter Desktop (Windows)..."
    Copy-Item $bin (Join-Path $bundleDir "WServer.exe") -Force
    if (Test-Path $iconSrc) {
        Copy-Item $iconSrc (Join-Path $bundleDir "wserver_icon.jpeg") -Force
    }
    Write-Host "    ✅ WServer.exe + wserver_icon.jpeg copiados a la raíz del bundle."
}

# 4.5) Bundle de debug (dev)
$debugDirs = @(
    "..\frontend\build\windows\x64\runner\Debug",
    "..\frontend\build\windows\x64\runner\Profile"
)
foreach ($debugDir in $debugDirs) {
    if (Test-Path $debugDir) {
        Write-Host "[4.5] Actualizando WServer en el bundle ($debugDir)..."
        Copy-Item $bin (Join-Path $debugDir "WServer.exe") -Force
        Write-Host "    ✅ WServer.exe actualizado."
    }
}

Write-Host ""
Write-Host "== Listo ==" -ForegroundColor Cyan
Write-Host "  Prueba rápida: $bin --version"
Write-Host "  Arranque (primera instalación):"
Write-Host "    `$env:WSERVER_HOME='C:\Temp\wserver-demo'; $bin"
Write-Host "  Después verifica: curl http://127.0.0.1:8000/api/v1/health"