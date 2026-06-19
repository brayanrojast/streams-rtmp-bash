#!/bin/bash
# bs-utils — utilidades de monitoreo y mantenimiento para Radio Patio TV
#
# Instalado por install-abr.sh en /usr/local/bin/bs-utils
#
# Uso:
#   bs-utils cpu              -> abre htop para monitorear CPU mientras transmite OBS
#   bs-utils logs <cancha>    -> sigue en vivo el log de ffmpeg de esa cancha
#   bs-utils status           -> estado de nginx + procesos ffmpeg activos
#   bs-utils restart          -> prueba config y reinicia nginx
#   bs-utils update-web       -> vuelve a descargar index.html y admin.html del repo

BASE_URL="https://raw.githubusercontent.com/brayanrojast/streams-rtmp-bash/refs/heads/main"
WEBROOT="/var/www/brayanstreams"

case "$1" in
  cpu)
    htop
    ;;

  logs)
    if [ -z "$2" ]; then
      echo "Uso: bs-utils logs <cancha>   (ej: bs-utils logs cancha1)"
      exit 1
    fi
    tail -f "/var/log/bs-abr-$2.log"
    ;;

  status)
    echo "=== nginx ==="
    systemctl status nginx --no-pager
    echo ""
    echo "=== Procesos ffmpeg activos ==="
    pgrep -af ffmpeg || echo "Ninguno"
    ;;

  restart)
    nginx -t && systemctl restart nginx && echo "✅ nginx reiniciado"
    ;;

  update-web)
    curl -sL "$BASE_URL/index.html" -o "$WEBROOT/index.html" && \
    curl -sL "$BASE_URL/admin.html" -o "$WEBROOT/admin.html" && \
    echo "✅ index.html y admin.html actualizados"
    ;;

  *)
    echo "Radio Patio TV — bs-utils"
    echo "Comandos disponibles:"
    echo "  bs-utils cpu              Monitorea CPU (htop)"
    echo "  bs-utils logs <cancha>    Logs en vivo de ffmpeg (ej: cancha1)"
    echo "  bs-utils status           Estado de nginx + procesos ffmpeg"
    echo "  bs-utils restart          Prueba config y reinicia nginx"
    echo "  bs-utils update-web       Re-descarga index.html y admin.html del repo"
    ;;
esac
