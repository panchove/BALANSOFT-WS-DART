#!/bin/bash

# install_flutter.sh - Instalar Flutter en MX Linux (basado en Debian)
set -e  # Salir inmediatamente si ocurre un error

FLUTTER_DIR="$HOME/development"
FLUTTER_TARBALL="flutter_linux_3.47.5-stable.tar.xz" # Puedes reemplazarlo con el enlace de la versión más reciente en https://docs.flutter.dev/release/archive
DOWNLOAD_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$FLUTTER_TARBALL"

echo "===> 1. Actualizando repositorios e instalando dependencias necesarias..."
sudo apt update
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa \
    clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev

echo "===> 2. Creando directorio de instalación..."
mkdir -p "$FLUTTER_DIR"
cd "$FLUTTER_DIR"

echo "===> 3. Descargando Flutter SDK..."
if [ ! -f "$FLUTTER_TARBALL" ]; then
    curl -LO "$DOWNLOAD_URL"
fi

echo "===> 4. Extrayendo Flutter..."
tar -xf "$FLUTTER_TARBALL"
# Después de extraer se genera el directorio flutter
FLUTTER_BIN="$FLUTTER_DIR/flutter/bin"

echo "===> 5. Configurando variables de entorno (agregando a ~/.bashrc)..."
if ! grep -q "export PATH=\"\$PATH:$FLUTTER_BIN\"" ~/.bashrc; then
    echo "export PATH=\"\$PATH:$FLUTTER_BIN\"" >> ~/.bashrc
    echo "Ruta agregada a ~/.bashrc"
else
    echo "La variable de entorno ya existe, omitiendo."
fi

# Aplicar en la sesión actual
export PATH="$PATH:$FLUTTER_BIN"

echo "===> 6. Verificando la instalación..."
flutter --version

echo "===> 7. Ejecutando flutter doctor (detectar problemas de configuración)..."
# Si se usa por primera vez, puede ser necesario aceptar el acuerdo de licencia de Android; aquí solo se muestra el estado
flutter doctor

echo ""
echo "=========================================="
echo "¡Instalación completada!"
echo "Por favor ejecuta: source ~/.bashrc"
echo "O cierra y vuelve a abrir la terminal para que la configuración surta efecto."
echo "=========================================="

