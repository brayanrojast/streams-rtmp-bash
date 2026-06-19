// bs-api — backend mínimo para los botones "Iniciar"/"Detener" del panel admin
// Reemplaza la necesidad de ejecutar bs-proxy/bs-stop a mano en la terminal.
// Sin dependencias externas (solo módulos nativos de Node) — no requiere npm install.
//
// Instalado por install-api.sh en /opt/bs-api/server.js
// Corre como servicio systemd "bs-api" en 127.0.0.1:3001
// nginx hace proxy_pass de /api/ hacia este puerto (ver nginx.conf actualizado).

const http = require('http');
const { spawn } = require('child_process');
const fs = require('fs');

const PORT = 3001;
const CANCHAS = ['cancha1', 'cancha2', 'cancha3', 'cancha4'];
const PID_DIR = '/tmp';

function pidFile(cancha) {
  return `${PID_DIR}/bs-${cancha}.pid`;
}

function isValidCancha(cancha) {
  return CANCHAS.includes(cancha);
}

// Solo permite URLs http/https bien formadas. Esto evita que alguien
// inyecte flags de ffmpeg o comandos a través del campo de URL del
// panel (nunca se usa shell para correr ffmpeg, pero igual se valida).
function isValidStreamUrl(url) {
  try {
    const u = new URL(url);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch {
    return false;
  }
}

function killExisting(cancha) {
  const file = pidFile(cancha);
  if (fs.existsSync(file)) {
    const pid = parseInt(fs.readFileSync(file, 'utf8').trim(), 10);
    if (pid) {
      try { process.kill(pid, 'SIGTERM'); } catch { /* ya no existe, ok */ }
    }
    try { fs.unlinkSync(file); } catch {}
  }
}

function sendJSON(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
    'Access-Control-Allow-Origin': '*'
  });
  res.end(body);
}

function readBody(req, cb) {
  let data = '';
  req.on('data', chunk => {
    data += chunk;
    if (data.length > 1e6) req.destroy(); // límite de seguridad, 1MB
  });
  req.on('end', () => {
    try {
      cb(null, data ? JSON.parse(data) : {});
    } catch (e) {
      cb(e);
    }
  });
}

function handleStart(req, res) {
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { cancha, url } = body;

    if (!isValidCancha(cancha)) {
      return sendJSON(res, 400, { error: 'Cancha inválida' });
    }
    if (!url || !isValidStreamUrl(url)) {
      return sendJSON(res, 400, { error: 'URL inválida — debe ser http:// o https://' });
    }

    killExisting(cancha);

    // Mismo comando que bs-proxy: re-empuja la URL externa hacia
    // rtmp://localhost/live/<cancha>, donde nginx-rtmp + bs-abr.sh
    // generan el ABR (720p/480p/360p) automáticamente.
    const args = [
      '-re', '-i', url,
      '-c:v', 'copy', '-c:a', 'copy',
      '-f', 'flv', `rtmp://localhost/live/${cancha}`,
      '-loglevel', 'warning'
    ];

    const child = spawn('ffmpeg', args, { detached: true, stdio: 'ignore' });
    child.unref();
    fs.writeFileSync(pidFile(cancha), String(child.pid));

    child.on('error', (e) => console.error(`ffmpeg error (${cancha}):`, e.message));

    sendJSON(res, 200, { pid: child.pid, cancha });
  });
}

function handleStop(req, res) {
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { cancha } = body;

    if (!isValidCancha(cancha)) {
      return sendJSON(res, 400, { error: 'Cancha inválida' });
    }
    if (!fs.existsSync(pidFile(cancha))) {
      return sendJSON(res, 404, { error: 'No hay stream activo en esa cancha' });
    }
    killExisting(cancha);
    sendJSON(res, 200, { ok: true, cancha });
  });
}

function handleStatus(req, res) {
  const status = {};
  CANCHAS.forEach(c => {
    const file = pidFile(c);
    let pid = null;
    if (fs.existsSync(file)) {
      pid = parseInt(fs.readFileSync(file, 'utf8').trim(), 10);
      try { process.kill(pid, 0); } catch { pid = null; }
    }
    status[c] = { running: !!pid, pid };
  });
  sendJSON(res, 200, status);
}

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/api/stream/start') return handleStart(req, res);
  if (req.method === 'POST' && req.url === '/api/stream/stop') return handleStop(req, res);
  if (req.method === 'GET' && req.url === '/api/stream/status') return handleStatus(req, res);
  sendJSON(res, 404, { error: 'No encontrado' });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`bs-api escuchando en http://127.0.0.1:${PORT}`);
});
