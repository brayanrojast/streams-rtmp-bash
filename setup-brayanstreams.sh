#!/bin/bash
set -e

# ============================================================
#  BRAYAN STREAMS — Script de instalación completo
#  Uso: bash setup-brayanstreams.sh
# ============================================================

echo ""
echo "██████╗ ██████╗  █████╗ ██╗   ██╗ █████╗ ███╗   ██╗"
echo "██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗████╗  ██║"
echo "██████╔╝██████╔╝███████║ ╚████╔╝ ███████║██╔██╗ ██║"
echo "██╔══██╗██╔══██╗██╔══██║  ╚██╔╝  ██╔══██║██║╚██╗██║"
echo "██████╔╝██║  ██║██║  ██║   ██║   ██║  ██║██║ ╚████║"
echo "╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝"
echo "              STREAMS — Setup v1.0"
echo ""

# ── Pedir IP del servidor ─────────────────────────────────
read -p "  Ingresa la IP de este servidor: " SERVER_IP
if [ -z "$SERVER_IP" ]; then
    echo "❌ IP no puede estar vacía."
    exit 1
fi
echo ""
echo "  ✅ IP configurada: $SERVER_IP"
echo ""

# ============================================================
# 1. ACTUALIZAR SISTEMA
# ============================================================
echo "=== [1/9] Actualizando sistema ==="
apt update && apt upgrade -y

# ============================================================
# 2. INSTALAR DEPENDENCIAS
# ============================================================
echo "=== [2/9] Instalando paquetes ==="
apt install -y nginx libnginx-mod-rtmp ffmpeg ufw curl openssl

# ============================================================
# 3. CONFIGURAR SSH EN PUERTO 22022
# ============================================================
echo "=== [3/9] Configurando SSH ==="
mkdir -p /etc/ssh/sshd_config.d
cat << 'EOF' > /etc/ssh/sshd_config.d/00-custom.conf
Port 22022
ClientAliveInterval 60
ClientAliveCountMax 3
PermitRootLogin yes
PasswordAuthentication yes
EOF
systemctl restart ssh

# ============================================================
# 4. CONFIGURAR FIREWALL
# ============================================================
echo "=== [4/9] Configurando firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow 22022/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 1935/tcp
ufw allow 8080/tcp
ufw --force enable

# ============================================================
# 5. GENERAR TOKEN SECRETO
# ============================================================
echo "=== [5/9] Generando token de seguridad ==="
SECRET_TOKEN=$(openssl rand -hex 32)
echo "TOKEN_SECRET=$SECRET_TOKEN" > /etc/brayanstreams.env
echo "SERVER_IP=$SERVER_IP" >> /etc/brayanstreams.env
chmod 600 /etc/brayanstreams.env

# ============================================================
# 6. CONFIGURAR NGINX + RTMP
# ============================================================
echo "=== [6/9] Configurando Nginx + RTMP ==="

mkdir -p /var/www/brayanstreams
mkdir -p /tmp/hls/cancha1
mkdir -p /tmp/hls/cancha2
mkdir -p /tmp/hls/cancha3
mkdir -p /tmp/hls/cancha4
chmod -R 777 /tmp/hls

cat << 'NGINXCONF' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 2048;
}

rtmp {
    server {
        listen 1935;
        chunk_size 4096;
        timeout 30s;

        application live {
            live on;
            record off;

            hls on;
            hls_path /tmp/hls;
            hls_fragment 2s;
            hls_playlist_length 10s;
            hls_nested on;
        }
    }
}

http {
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log;

    gzip on;

    server {
        listen 80;
        server_name _;

        root /var/www/brayanstreams;
        index index.html;

        location / {
            try_files $uri $uri/ =404;
        }

        location /stream/ {
            if ($arg_token = "") {
                return 403;
            }
            alias /tmp/hls/;
            add_header Cache-Control no-cache;
            add_header Access-Control-Allow-Origin *;
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
        }

        location /proxy/ {
            if ($arg_token = "") {
                return 403;
            }
            resolver 8.8.8.8 valid=30s;
            set $upstream $arg_url;
            proxy_pass $upstream;
            proxy_hide_header X-Powered-By;
            proxy_hide_header Server;
            proxy_set_header Referer "";
            proxy_set_header Origin "";
            add_header Access-Control-Allow-Origin *;
            add_header Cache-Control no-cache;
        }

        location /stats {
            rtmp_stat all;
            rtmp_stat_stylesheet /stat.xsl;
        }
    }

    server {
        listen 8080;
        location /stats {
            rtmp_stat all;
        }
    }
}
NGINXCONF

# ============================================================
# 7. COPIAR STAT.XSL
# ============================================================
echo "=== [7/9] Copiando recursos de stats ==="
cp /usr/share/doc/libnginx-mod-rtmp/examples/stat.xsl /var/www/brayanstreams/ 2>/dev/null || true

# ============================================================
# 8. CREAR COMANDOS DE GESTIÓN
# ============================================================
echo "=== [8/9] Creando comandos de gestión ==="

cat << 'PROXYSH' > /usr/local/bin/bs-proxy
#!/bin/bash
# Uso: bs-proxy <cancha> <url_m3u8>
CANCHA=$1
URL=$2
if [ -z "$CANCHA" ] || [ -z "$URL" ]; then
    echo "Uso: bs-proxy <cancha1|cancha2|cancha3|cancha4> <url_m3u8>"
    exit 1
fi
echo "Iniciando proxy: $URL → rtmp://localhost/live/$CANCHA"
ffmpeg -re -i "$URL" -c:v copy -c:a copy -f flv "rtmp://localhost/live/$CANCHA" -loglevel warning &
echo $! > /tmp/bs-$CANCHA.pid
echo "✅ Stream corriendo en $CANCHA (PID: $!)"
PROXYSH

cat << 'STOPSH' > /usr/local/bin/bs-stop
#!/bin/bash
# Uso: bs-stop <cancha>
CANCHA=$1
if [ -f /tmp/bs-$CANCHA.pid ]; then
    kill $(cat /tmp/bs-$CANCHA.pid) 2>/dev/null
    rm /tmp/bs-$CANCHA.pid
    echo "⏹ Stream $CANCHA detenido."
else
    echo "No hay stream activo en $CANCHA"
fi
STOPSH

chmod +x /usr/local/bin/bs-proxy
chmod +x /usr/local/bin/bs-stop

# ============================================================
# 9. INICIAR SERVICIOS
# ============================================================
echo "=== [9/9] Iniciando servicios ==="
nginx -t && systemctl restart nginx
systemctl enable nginx

# ============================================================
# RESUMEN FINAL
# ============================================================
source /etc/brayanstreams.env

echo ""
echo "=============================================="
echo "  ✅ BRAYAN STREAMS — INSTALACIÓN COMPLETA"
echo "=============================================="
echo ""
echo "  🌐 Página web:   http://$SERVER_IP"
echo "  📡 RTMP (OBS):   rtmp://$SERVER_IP/live/cancha1"
echo "  🎥 HLS cancha1:  http://$SERVER_IP/stream/cancha1/index.m3u8?token=$TOKEN_SECRET"
echo "  🎥 HLS cancha2:  http://$SERVER_IP/stream/cancha2/index.m3u8?token=$TOKEN_SECRET"
echo "  🎥 HLS cancha3:  http://$SERVER_IP/stream/cancha3/index.m3u8?token=$TOKEN_SECRET"
echo "  🎥 HLS cancha4:  http://$SERVER_IP/stream/cancha4/index.m3u8?token=$TOKEN_SECRET"
echo "  📊 Stats:        http://$SERVER_IP/stats"
echo ""
echo "  🔑 TOKEN SECRETO (guárdalo, no lo compartas):"
echo "  $TOKEN_SECRET"
echo ""
echo "  COMANDOS:"
echo "  bs-proxy cancha1 https://url-externa.m3u8   ← M3U8 externo"
echo "  bs-stop  cancha1                             ← detener stream"
echo ""
echo "  OBS → Settings → Stream:"
echo "  Server: rtmp://$SERVER_IP/live"
echo "  Key:    cancha1  (o cancha2, cancha3, cancha4)"
echo "=============================================="
