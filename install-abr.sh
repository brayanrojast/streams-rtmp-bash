#!/bin/bash
set -e

# Base del repo (raw GitHub) — ajusta si cambias de repo/branch
BASE_URL="https://raw.githubusercontent.com/brayanrojast/streams-rtmp-bash/refs/heads/main"
WEBROOT="/var/www/brayanstreams"

echo "=== Instalando ABR (720p/480p/360p) para Radio Patio TV ==="

# 1. Backup de la config actual
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)
echo "✅ Backup de nginx.conf creado"

# 2. Instalar bs-abr.sh y bs-utils.sh
cp bs-abr.sh /usr/local/bin/bs-abr.sh
chmod +x /usr/local/bin/bs-abr.sh
echo "✅ /usr/local/bin/bs-abr.sh instalado"

if [ -f bs-utils.sh ]; then
  cp bs-utils.sh /usr/local/bin/bs-utils
  chmod +x /usr/local/bin/bs-utils
  echo "✅ /usr/local/bin/bs-utils instalado (cpu, logs, status, restart, update-web)"
fi

# 3. Reemplazar nginx.conf
cp nginx.conf /etc/nginx/nginx.conf
echo "✅ nginx.conf actualizado (token de stream DESACTIVADO por el momento)"

# 4. Crear carpetas de salida ABR
mkdir -p /tmp/hls_abr/cancha1/{720p,480p,360p}
mkdir -p /tmp/hls_abr/cancha2/{720p,480p,360p}
mkdir -p /tmp/hls_abr/cancha3/{720p,480p,360p}
mkdir -p /tmp/hls_abr/cancha4/{720p,480p,360p}
chmod -R 777 /tmp/hls_abr
echo "✅ Carpetas /tmp/hls_abr creadas"

# 5. Descargar/actualizar index.html y admin.html (Radio Patio TV)
mkdir -p "$WEBROOT"
if curl -sL "$BASE_URL/index.html" -o "$WEBROOT/index.html" && curl -sL "$BASE_URL/admin.html" -o "$WEBROOT/admin.html"; then
  echo "✅ index.html y admin.html actualizados desde el repo"
else
  echo "⚠️  No se pudo descargar index.html/admin.html (revisa conexión o URLs)"
fi

# 6. Probar y recargar nginx
nginx -t
systemctl restart nginx
echo "✅ nginx reiniciado"

echo ""
echo "=== Listo — Radio Patio TV ==="
echo "Las URLs HLS ahora usan master.m3u8 en vez de index.m3u8:"
echo "  /stream/cancha1/master.m3u8   (sin token, desactivado por el momento)"
echo ""
echo "Comandos disponibles (bs-utils):"
echo "  bs-utils cpu              Monitorea CPU (htop)"
echo "  bs-utils logs cancha1     Logs en vivo de ffmpeg de esa cancha"
echo "  bs-utils status           Estado de nginx + procesos ffmpeg activos"
echo "  bs-utils restart          Prueba config y reinicia nginx"
echo "  bs-utils update-web       Vuelve a descargar index.html/admin.html del repo"
echo ""
echo "⚠️  El token de los streams está desactivado por el momento — cualquiera con la URL puede ver el stream. Reactívalo cuando termines de probar."
