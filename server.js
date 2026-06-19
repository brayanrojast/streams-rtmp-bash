// bs-api — backend para Radio Patio TV
// Sin dependencias externas (solo módulos nativos de Node)
// Instalado en /opt/bs-api/server.js

const http = require('http');
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = 3001;
const CANCHAS = ['cancha1', 'cancha2', 'cancha3', 'cancha4'];
const PID_DIR = '/tmp';
const DATA_DIR = '/opt/bs-api/data';
const EVENTS_FILE = path.join(DATA_DIR, 'events.json');
const STATS_FILE = path.join(DATA_DIR, 'stream-stats.json');
const MAINT_FILE = path.join(DATA_DIR, 'maintenance.json');

// Asegurar directorio de datos
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

function pidFile(cancha) { return `${PID_DIR}/bs-${cancha}.pid`; }
function isValidCancha(c) { return /^cancha\d+$/.test(c); }
function isValidStreamUrl(url) {
  try { const u = new URL(url); return u.protocol === 'http:' || u.protocol === 'https:'; } catch { return false; }
}

function killExisting(cancha) {
  const file = pidFile(cancha);
  if (fs.existsSync(file)) {
    const pid = parseInt(fs.readFileSync(file, 'utf8').trim(), 10);
    if (pid) { try { process.kill(pid, 'SIGTERM'); } catch {} }
    try { fs.unlinkSync(file); } catch {}
  }
}

function sendJSON(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,PUT,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type'
  });
  res.end(body);
}

function readBody(req, cb) {
  let data = '';
  req.on('data', chunk => { data += chunk; if (data.length > 1e6) req.destroy(); });
  req.on('end', () => { try { cb(null, data ? JSON.parse(data) : {}); } catch (e) { cb(e); } });
}

function readJSON(file, def) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return def; }
}
function writeJSON(file, data) {
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

// ── STREAM START ──────────────────────────────────────────────
function handleStart(req, res) {
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { cancha, url } = body;
    if (!isValidCancha(cancha)) return sendJSON(res, 400, { error: 'Cancha inválida' });
    if (!url || !isValidStreamUrl(url)) return sendJSON(res, 400, { error: 'URL inválida' });
    killExisting(cancha);
    const args = ['-re', '-i', url, '-c:v', 'copy', '-c:a', 'copy', '-f', 'flv', `rtmp://localhost/live/${cancha}`, '-loglevel', 'warning'];
    const child = spawn('ffmpeg', args, { detached: true, stdio: 'ignore' });
    child.unref();
    fs.writeFileSync(pidFile(cancha), String(child.pid));
    child.on('error', (e) => console.error(`ffmpeg error (${cancha}):`, e.message));
    // Log inicio en stats
    logStreamEvent(cancha, 'start');
    sendJSON(res, 200, { pid: child.pid, cancha });
  });
}

// ── STREAM STOP ───────────────────────────────────────────────
function handleStop(req, res) {
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { cancha } = body;
    if (!isValidCancha(cancha)) return sendJSON(res, 400, { error: 'Cancha inválida' });
    if (!fs.existsSync(pidFile(cancha))) return sendJSON(res, 404, { error: 'No hay stream activo' });
    logStreamEvent(cancha, 'stop');
    killExisting(cancha);
    sendJSON(res, 200, { ok: true, cancha });
  });
}

// ── STREAM STATUS ─────────────────────────────────────────────
function handleStatus(req, res) {
  const status = {};
  // Obtener canchas dinámicas de events.json para soportar más de 4
  const allCanchas = new Set([...CANCHAS]);
  const events = readJSON(EVENTS_FILE, {});
  Object.keys(events).forEach(k => allCanchas.add(k));

  allCanchas.forEach(c => {
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

// ── REINICIAR FFMPEG (por cancha) ─────────────────────────────
function handleRestart(req, res) {
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { cancha } = body;
    if (!isValidCancha(cancha)) return sendJSON(res, 400, { error: 'Cancha inválida' });
    const file = pidFile(cancha);
    if (!fs.existsSync(file)) return sendJSON(res, 404, { error: 'No hay stream activo' });
    const pid = parseInt(fs.readFileSync(file, 'utf8').trim(), 10);
    try { process.kill(pid, 'SIGKILL'); } catch {}
    // nginx-rtmp + bs-abr.sh se reinicia automáticamente cuando OBS republica
    sendJSON(res, 200, { ok: true, cancha, msg: 'ffmpeg terminado — nginx-rtmp reiniciará al siguiente publish' });
  });
}

// ── EVENTS (persistencia en JSON) ─────────────────────────────
function handleGetEvents(req, res) {
  sendJSON(res, 200, readJSON(EVENTS_FILE, {}));
}

function handleSetEvent(req, res) {
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { cancha, nombre, fecha, mensaje, global } = body;
    const events = readJSON(EVENTS_FILE, {});
    const key = global ? '__global__' : cancha;
    if (!key) return sendJSON(res, 400, { error: 'Falta cancha o global:true' });
    events[key] = { nombre: nombre || 'Próximo evento', fecha, mensaje: mensaje || '', updatedAt: new Date().toISOString() };
    writeJSON(EVENTS_FILE, events);
    sendJSON(res, 200, { ok: true, event: events[key] });
  });
}

function handleDeleteEvent(req, res) {
  const url = new URL(req.url, 'http://x');
  const key = url.searchParams.get('cancha') || (url.searchParams.get('global') === 'true' ? '__global__' : null);
  if (!key) return sendJSON(res, 400, { error: 'Falta cancha o global=true' });
  const events = readJSON(EVENTS_FILE, {});
  delete events[key];
  writeJSON(EVENTS_FILE, events);
  sendJSON(res, 200, { ok: true });
}

// ── STREAM STATS (historial de horas) ────────────────────────
function logStreamEvent(cancha, type) {
  const stats = readJSON(STATS_FILE, { streams: [] });
  const now = new Date().toISOString();
  if (type === 'start') {
    // Marcar inicio
    stats.streams.push({ cancha, start: now, end: null });
  } else if (type === 'stop') {
    // Cerrar última sesión abierta
    for (let i = stats.streams.length - 1; i >= 0; i--) {
      if (stats.streams[i].cancha === cancha && !stats.streams[i].end) {
        stats.streams[i].end = now;
        const ms = new Date(now) - new Date(stats.streams[i].start);
        stats.streams[i].durationMin = Math.round(ms / 60000);
        break;
      }
    }
  }
  // Mantener solo últimos 500 registros
  if (stats.streams.length > 500) stats.streams = stats.streams.slice(-500);
  writeJSON(STATS_FILE, stats);
}

function handleGetStats(req, res) {
  const stats = readJSON(STATS_FILE, { streams: [] });
  // Calcular totales por cancha
  const totals = {};
  stats.streams.forEach(s => {
    if (!totals[s.cancha]) totals[s.cancha] = { sessions: 0, totalMin: 0 };
    totals[s.cancha].sessions++;
    totals[s.cancha].totalMin += (s.durationMin || 0);
  });
  sendJSON(res, 200, { streams: stats.streams.slice(-100), totals });
}

// ── MANTENIMIENTO ─────────────────────────────────────────────
function handleMaintenance(req, res) {
  if (req.method === 'GET') {
    return sendJSON(res, 200, readJSON(MAINT_FILE, { enabled: false, mensaje: '' }));
  }
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { enabled, mensaje } = body;
    writeJSON(MAINT_FILE, { enabled: !!enabled, mensaje: mensaje || 'Sistema en mantenimiento. Volvemos pronto.', updatedAt: new Date().toISOString() });
    sendJSON(res, 200, { ok: true });
  });
}

// ── ABR CONFIG (resoluciones por cancha) ──────────────────────
const ABR_FILE = path.join(DATA_DIR, 'abr-config.json');
function handleAbrConfig(req, res) {
  if (req.method === 'GET') {
    return sendJSON(res, 200, readJSON(ABR_FILE, {}));
  }
  readBody(req, (err, body) => {
    if (err) return sendJSON(res, 400, { error: 'JSON inválido' });
    const { cancha, resolutions } = body; // resolutions: [{ height, bitrate }]
    if (!isValidCancha(cancha)) return sendJSON(res, 400, { error: 'Cancha inválida' });
    const cfg = readJSON(ABR_FILE, {});
    cfg[cancha] = { resolutions: resolutions || [], updatedAt: new Date().toISOString() };
    writeJSON(ABR_FILE, cfg);
    sendJSON(res, 200, { ok: true });
  });
}

// ── ROUTER ────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') return sendJSON(res, 200, {});

  const url = req.url.split('?')[0];

  if (req.method === 'POST' && url === '/api/stream/start')       return handleStart(req, res);
  if (req.method === 'POST' && url === '/api/stream/stop')        return handleStop(req, res);
  if (req.method === 'GET'  && url === '/api/stream/status')      return handleStatus(req, res);
  if (req.method === 'POST' && url === '/api/stream/restart')     return handleRestart(req, res);
  if (req.method === 'GET'  && url === '/api/events')             return handleGetEvents(req, res);
  if (req.method === 'POST' && url === '/api/events')             return handleSetEvent(req, res);
  if (req.method === 'DELETE' && url === '/api/events')           return handleDeleteEvent(req, res);
  if (req.method === 'GET'  && url === '/api/stream-stats')       return handleGetStats(req, res);
  if ((req.method === 'GET' || req.method === 'POST') && url === '/api/maintenance') return handleMaintenance(req, res);
  if ((req.method === 'GET' || req.method === 'POST') && url === '/api/abr-config')  return handleAbrConfig(req, res);

  sendJSON(res, 404, { error: 'No encontrado' });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`bs-api escuchando en http://127.0.0.1:${PORT}`);
});
