#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║        Radio Patio TV — Setup completo v2.0                ║
# ║  Un solo comando instala TODO: nginx-rtmp, ABR, API, web   ║
# ║  curl -fsSL https://raw.githubusercontent.com/brayanrojast/ ║
# ║    streams-rtmp-bash/refs/heads/main/setup.sh | bash        ║
# ╚══════════════════════════════════════════════════════════════╝
set -e

BASE_URL="https://raw.githubusercontent.com/brayanrojast/streams-rtmp-bash/refs/heads/main"
WEBROOT="/var/www/brayanstreams"
ENV_FILE="/etc/brayanstreams.env"

echo ""
echo "██████╗  █████╗ ██████╗ ██╗ ██████╗     ██████╗  █████╗ ████████╗██╗ ██████╗"
echo "██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗    ██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗"
echo "██████╔╝███████║██║  ██║██║██║   ██║    ██████╔╝███████║   ██║   ██║██║   ██║"
echo "██╔══██╗██╔══██║██║  ██║██║██║   ██║    ██╔═══╝ ██╔══██║   ██║   ██║██║   ██║"
echo "██║  ██║██║  ██║██████╔╝██║╚██████╔╝    ██║     ██║  ██║   ██║   ██║╚██████╔╝"
echo "╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝     ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝"
echo "                         TV — Setup v2.0"
echo ""

# ── Verificar root ────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Este script debe ejecutarse como root (sudo bash setup.sh)"
  exit 1
fi

# ── Detectar IP pública ───────────────────────────────────────────────────────
echo "  Detectando IP pública del servidor..."
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
         || curl -s --max-time 5 https://ifconfig.me \
         || curl -s --max-time 5 https://icanhazip.com \
         || hostname -I | awk '{print $1}')

if [ -z "$SERVER_IP" ]; then
  echo "❌ No se pudo detectar la IP. Verifica la conexión a internet."
  exit 1
fi
echo "  ✅ IP detectada: $SERVER_IP"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 1. ACTUALIZAR SISTEMA
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [1/10] Actualizando sistema ==="
apt update && apt upgrade -y

# ═══════════════════════════════════════════════════════════════════════════════
# 2. INSTALAR DEPENDENCIAS BASE
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [2/10] Instalando paquetes ==="
apt install -y nginx libnginx-mod-rtmp ffmpeg ufw curl openssl htop

# ── Node.js 20.x ──────────────────────────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  echo "  Instalando Node.js 20.x..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
echo "  ✅ Node.js: $(node --version)"

# ═══════════════════════════════════════════════════════════════════════════════
# 3. CONFIGURAR SSH EN PUERTO 22022
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [3/10] Configurando SSH en puerto 22022 ==="
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-custom.conf << 'SSHEOF'
Port 22022
ClientAliveInterval 60
ClientAliveCountMax 3
PermitRootLogin yes
PasswordAuthentication yes
SSHEOF
systemctl restart ssh || service ssh restart
echo "  ✅ SSH ahora escucha en puerto 22022"

# ═══════════════════════════════════════════════════════════════════════════════
# 4. CONFIGURAR FIREWALL
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [4/10] Configurando firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow 22022/tcp   # SSH
ufw allow 80/tcp      # HTTP
ufw allow 443/tcp     # HTTPS (futuro)
ufw allow 1935/tcp    # RTMP (OBS)
ufw allow 8080/tcp    # Stats alternativo
ufw --force enable
echo "  ✅ Firewall activo"

# ═══════════════════════════════════════════════════════════════════════════════
# 5. GENERAR TOKEN Y GUARDAR ENTORNO
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [5/10] Generando token de seguridad ==="

# Reusar token existente si ya hay una instalación previa
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
  echo "  ♻️  Token existente reutilizado"
else
  SECRET_TOKEN=$(openssl rand -hex 32)
fi

cat > "$ENV_FILE" << ENVEOF
TOKEN_SECRET=$SECRET_TOKEN
SERVER_IP=$SERVER_IP
ENVEOF
chmod 600 "$ENV_FILE"
echo "  ✅ Token guardado en $ENV_FILE"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. DESCARGAR SCRIPTS DESDE GITHUB
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [6/10] Descargando scripts desde GitHub ==="

dl() {
  local src="$1" dst="$2" mode="${3:-644}"
  if curl -fsSL "$BASE_URL/$src" -o "$dst"; then
    chmod "$mode" "$dst"
    echo "  ✅ $dst"
  else
    echo "  ❌ Error descargando $src — abortando"
    exit 1
  fi
}

# Scripts de sistema
dl "bs-abr.sh"    "/usr/local/bin/bs-abr.sh"  755
dl "bs-utils.sh"  "/usr/local/bin/bs-utils"   755

# Backend API
mkdir -p /opt/bs-api
dl "server.js"    "/opt/bs-api/server.js"      644

# Servicio systemd
dl "bs-api.service" "/etc/systemd/system/bs-api.service" 644

# ═══════════════════════════════════════════════════════════════════════════════
# 7. CONFIGURAR NGINX (con ABR + API en una sola config)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [7/10] Configurando Nginx + RTMP + ABR + API ==="

# Backup si ya existe
[ -f /etc/nginx/nginx.conf ] && \
  cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)"

dl "nginx.conf" "/etc/nginx/nginx.conf" 644

# Crear directorios HLS ABR
for c in cancha1 cancha2 cancha3 cancha4; do
  mkdir -p "/tmp/hls_abr/$c/720p" "/tmp/hls_abr/$c/480p" "/tmp/hls_abr/$c/360p"
done
chmod -R 777 /tmp/hls_abr

# Directorio de logs ffmpeg (www-data necesita escribir aquí)
mkdir -p /var/log/bs-abr
chmod 777 /var/log/bs-abr

# stat.xsl para /stats
mkdir -p "$WEBROOT"
cp /usr/share/doc/libnginx-mod-rtmp/examples/stat.xsl "$WEBROOT/" 2>/dev/null || true

echo "  ✅ nginx.conf instalado (ABR + API)"

# ═══════════════════════════════════════════════════════════════════════════════
# 8. DESCARGAR Y CONFIGURAR PÁGINAS WEB
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [8/10] Descargando páginas web ==="

dl "index.html" "$WEBROOT/index.html" 644
dl "admin.html" "$WEBROOT/admin.html" 644

# Inyectar IP del servidor (el token está desactivado, no se inyecta)
sed -i "s|http://TU_IP|http://$SERVER_IP|g"  "$WEBROOT/index.html"
sed -i "s|http://TU_IP|http://$SERVER_IP|g"  "$WEBROOT/admin.html"

echo "  ✅ index.html y admin.html listos"

# ═══════════════════════════════════════════════════════════════════════════════
# 9. CREAR COMANDOS DE GESTIÓN (bs-proxy / bs-stop)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [9/10] Creando comandos bs-proxy y bs-stop ==="

cat > /usr/local/bin/bs-proxy << 'PROXYEOF'
#!/bin/bash
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
PROXYEOF

cat > /usr/local/bin/bs-stop << 'STOPEOF'
#!/bin/bash
CANCHA=$1
if [ -f /tmp/bs-$CANCHA.pid ]; then
  kill $(cat /tmp/bs-$CANCHA.pid) 2>/dev/null
  rm /tmp/bs-$CANCHA.pid
  echo "⏹ Stream $CANCHA detenido."
else
  echo "No hay stream activo en $CANCHA"
fi
STOPEOF

chmod +x /usr/local/bin/bs-proxy /usr/local/bin/bs-stop
echo "  ✅ bs-proxy y bs-stop instalados"

# ═══════════════════════════════════════════════════════════════════════════════
# 10. INICIAR / REINICIAR SERVICIOS
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== [10/10] Iniciando servicios ==="

# nginx
nginx -t
systemctl enable nginx
systemctl restart nginx
echo "  ✅ nginx iniciado"

# bs-api (Node backend)
systemctl daemon-reload
systemctl enable bs-api
systemctl restart bs-api
sleep 2

if curl -sf http://127.0.0.1:3001/api/stream/status >/dev/null; then
  echo "  ✅ bs-api OK en localhost:3001"
else
  echo "  ⚠️  bs-api no respondió — revisa: journalctl -u bs-api -n 30"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ═══════════════════════════════════════════════════════════════════════════════
source "$ENV_FILE"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        ✅  RADIO PATIO TV — INSTALACIÓN COMPLETA        ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║"
echo "║  🌐 Página pública:   http://$SERVER_IP"
echo "║  🔐 Panel admin:      http://$SERVER_IP/admin.html"
echo "║  📊 Stats RTMP:       http://$SERVER_IP/stats"
echo "║"
echo "║  📡 OBS → Settings → Stream:"
echo "║     Server:  rtmp://$SERVER_IP/live"
echo "║     Key:     cancha1  (cancha2, cancha3, cancha4)"
echo "║"
echo "║  📺 URLs HLS (ABR — 720p/480p/360p auto):"
echo "║     http://$SERVER_IP/stream/cancha1/master.m3u8"
echo "║     http://$SERVER_IP/stream/cancha2/master.m3u8"
echo "║     http://$SERVER_IP/stream/cancha3/master.m3u8"
echo "║     http://$SERVER_IP/stream/cancha4/master.m3u8"
echo "║"
echo "║  🛠️  Comandos útiles:"
echo "║     bs-utils status          Estado nginx + ffmpeg"
echo "║     bs-utils logs cancha1    Logs ffmpeg en vivo"
echo "║     bs-utils restart         Reiniciar nginx"
echo "║     bs-utils cpu             Monitor de CPU (htop)"
echo "║     bs-proxy cancha1 <url>   Conectar M3U8 externo"
echo "║     bs-stop  cancha1         Detener stream"
echo "║"
echo "║  🔑 Token (guardado en $ENV_FILE):"
echo "║     $TOKEN_SECRET"
echo "║"
echo "║  ⚠️  SSH ahora en puerto 22022 — reconecta con:"
echo "║     ssh -p 22022 root@$SERVER_IP"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
