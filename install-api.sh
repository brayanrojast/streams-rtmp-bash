#!/bin/bash
set -e

echo "=== Instalando bs-api (backend para botones Iniciar/Detener) ==="

# 1. Backup de nginx.conf actual
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)
echo "✅ Backup de nginx.conf creado"

# 2. Instalar el backend en /opt/bs-api
mkdir -p /opt/bs-api
cp server.js /opt/bs-api/server.js
echo "✅ /opt/bs-api/server.js instalado"

# 3. Verificar que Node esté disponible
if ! command -v node >/dev/null 2>&1; then
  echo "⚠️  Node.js no está instalado. Instalando..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
echo "✅ Node disponible: $(node --version)"

# 4. Instalar el servicio systemd
cp bs-api.service /etc/systemd/system/bs-api.service
systemctl daemon-reload
systemctl enable bs-api
systemctl restart bs-api
sleep 1
echo "✅ Servicio bs-api instalado e iniciado"

# 5. Reemplazar nginx.conf (agrega location /api/, no toca el token)
cp nginx.conf /etc/nginx/nginx.conf
nginx -t
systemctl restart nginx
echo "✅ nginx.conf actualizado y nginx reiniciado"

# 6. Verificación rápida
sleep 1
if curl -sf http://127.0.0.1:3001/api/stream/status >/dev/null; then
  echo "✅ bs-api responde correctamente en localhost:3001"
else
  echo "⚠️  bs-api no respondió — revisa: journalctl -u bs-api -n 50"
fi

echo ""
echo "=== Listo ==="
echo "Estado del servicio:  systemctl status bs-api"
echo "Logs en vivo:         journalctl -u bs-api -f"
echo "Probar manualmente:   curl http://localhost/api/stream/status"
