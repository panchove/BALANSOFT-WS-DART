#!/bin/bash
# deploy/security-setup.sh
# Configuración de seguridad de BALANSOFT-WS (espejo de BALANSOFT-SG).
# Ejecutar con sudo: sudo bash security-setup.sh   (estando en backend/deploy)
# Requiere acceso sudo.
#
# NOTA: el sitio nginx para ws.balansoft.com.ve SOLO se habilita cuando el DNS y
# el certificado (SAN) cubren ese subdominio; si aún no existen, la config se
# deja instalada en sites-available (sin habilitar) y se avisa al operador.

set -euo pipefail

REPO=/var/www/BALANSOFT-WS-DART
APP_USER=serverman
DOMAIN=ws.balansoft.com.ve
CERT=/etc/letsencrypt/live/balansoft.com.ve/fullchain.pem

echo "=== BALANSOFT WS - Configuración de Seguridad ==="
echo ""

# 1. Crear directorio de logs de seguridad (ver docs/DEPLOY.md §4.4)
echo "[1/5] Creando directorio de logs de seguridad..."
mkdir -p /var/log/balansoft-ws
chown -R "$APP_USER:$APP_USER" /var/log/balansoft-ws
chmod 750 /var/log/balansoft-ws
echo "   ✓ /var/log/balansoft-ws creado"

# 2. Aplicar configuración Nginx con headers de seguridad
echo "[2/5] Aplicando configuración Nginx..."
cp "$REPO/backend/deploy/balansoft-ws.nginx" /etc/nginx/sites-available/balansoft-ws

# Solo habilitar si DNS + certificado cubren el subdominio (evita romper TLS).
if getent hosts "$DOMAIN" >/dev/null 2>&1 \
   && sudo openssl x509 -in "$CERT" -noout -checkhost "$DOMAIN" 2>/dev/null | grep -qi matches; then
    ln -sf /etc/nginx/sites-available/balansoft-ws /etc/nginx/sites-enabled/balansoft-ws
    echo "   ✓ $DOMAIN habilitado en nginx (DNS + certificado OK)"
else
    echo "   ⚠ DNS o certificado de $DOMAIN aún no listos; NO se habilitó el sitio."
    echo "     Ampliar el SAN con: certbot --nginx -d ... -d ws.balansoft.com.ve"
fi

# 3. Validar y recargar Nginx (validación siempre; recarga solo si hubo cambios)
echo "[3/5] Validando y recargando Nginx..."
if nginx -t 2>&1; then
    systemctl reload nginx
    echo "   ✓ Nginx recargado exitosamente"
else
    echo "   ✗ Error en configuración Nginx. Revirtiendo..."
    exit 1
fi

# 4. Reiniciar la API
echo "[4/5] Reiniciando la API..."
systemctl restart balansoft-ws
sleep 2
if systemctl is-active --quiet balansoft-ws; then
    echo "   ✓ API reiniciada exitosamente"
else
    echo "   ✗ Error al reiniciar la API"
    systemctl status balansoft-ws --no-pager
    exit 1
fi

# 5. Configurar UFW
echo "[5/5] Configurando firewall UFW..."
if command -v ufw &> /dev/null; then
    # Permitir servicios esenciales
    ufw allow 22/tcp comment "SSH"
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"

    # Estaciones desktop por LAN usan :8002 directo (bind 0.0.0.0 intencional,
    # ver DEPLOY.md §4.10). Restringir al subnet de estaciones según convenga,
    # por ejemplo:  ufw allow from 192.168.1.0/24 to any port 8002 proto tcp
    ufw allow 8002/tcp comment "API WS (estaciones LAN)"

    # Habilitar si no está activo
    ufw --force enable
    echo "   ✓ Firewall configurado"
else
    echo "   ⚠ UFW no encontrado. Instalar con: apt install ufw"
fi

echo ""
echo "=== VERIFICACIÓN ==="
echo ""
echo "1. Estado del firewall:"
ufw status | grep -E "(Status|22|80|443|8002)" || echo "   (UFW no disponible)"
echo ""
echo "2. Documentación API (debe dar 404):"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8002/docs 2>/dev/null || echo "error")
echo "   /docs → HTTP $HTTP_CODE"
echo ""
echo "3. Health check (debe dar 200):"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8002/api/v1/health 2>/dev/null || echo "error")
echo "   /api/v1/health → HTTP $HTTP_CODE"
echo ""
echo "4. Sitio nginx ($DOMAIN):"
if [ -L /etc/nginx/sites-enabled/balansoft-ws ]; then
    echo "   habilitado"
else
    echo "   instalado en sites-available (pendiente DNS + certificado)"
fi
echo ""
echo "5. Puerto 8002 (debe mostrar el bind de uvicorn):"
netstat -tlnp 2>/dev/null | grep 8002 || ss -tlnp | grep 8002
echo ""
echo "=== Configuración de seguridad completada ==="