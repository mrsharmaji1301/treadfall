// TREADFALL lobby server.
// Keeps the list of open lobbies and passes game data between the players
// of one lobby. The game itself runs on the lobby host's PC, not here.
// Run: node lobby_server.js   (port 8765, or the PORT environment variable)
'use strict';
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = parseInt(process.env.PORT || '8765', 10);
const MAX_ROOMS = 300;
const MAX_MEMBERS = 10;
const MAX_PACKET = 256 * 1024;
const ALL = 255;      // relay target: everyone else in the room
const HOST_ID = 1;    // the room's creator is always peer 1

const rooms = new Map();   // id -> room
let nextRoom = 1;

function clean(text, max) {
  return String(text == null ? '' : text).replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, max);
}

function makeCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (;;) {
    let code = '';
    for (let i = 0; i < 5; i++) code += letters[Math.floor(Math.random() * letters.length)];
    let taken = false;
    for (const r of rooms.values()) if (r.code === code) taken = true;
    if (!taken) return code;
  }
}

function send(ws, obj) {
  if (ws.readyState === 1) ws.send(JSON.stringify(obj));
}

function publicList(ver) {
  const list = [];
  for (const r of rooms.values()) {
    if (r.private || r.started || r.ver !== ver) continue;
    list.push({ id: r.id, name: r.name, players: r.members.size, info: r.info });
  }
  return list;
}

function leave(ws, reason) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  room.members.delete(ws.peer);
  if (ws.peer === HOST_ID || room.members.size === 0) {
    // The host has gone: the lobby closes for everyone.
    for (const m of room.members.values()) {
      m.room = null;
      send(m, { t: 'left', reason: 'The host closed the lobby' });
    }
    rooms.delete(room.id);
  } else {
    for (const m of room.members.values()) send(m, { t: 'peer_left', peer: ws.peer });
  }
  if (reason) send(ws, { t: 'left', reason });
}

function control(ws, msg) {
  switch (msg.t) {
    case 'hello':
      ws.name = clean(msg.name, 20) || 'Player';
      ws.ver = clean(msg.ver, 12);
      send(ws, { t: 'welcome' });
      break;
    case 'list':
      send(ws, { t: 'lobbies', list: publicList(ws.ver) });
      break;
    case 'create': {
      if (ws.room) leave(ws, '');
      if (rooms.size >= MAX_ROOMS) return send(ws, { t: 'error', msg: 'The server is full' });
      const room = {
        id: nextRoom++, name: clean(msg.name, 30) || ws.name + "'s lobby", code: makeCode(),
        private: !!msg.private, started: false, ver: ws.ver, open: 0,
        info: typeof msg.info === 'object' && msg.info ? msg.info : {}, members: new Map(),
      };
      rooms.set(room.id, room);
      ws.room = room;
      ws.peer = HOST_ID;
      room.members.set(HOST_ID, ws);
      send(ws, { t: 'joined', room: { id: room.id, name: room.name, code: room.code }, you: HOST_ID, peers: [] });
      break;
    }
    case 'join': {
      if (ws.room) leave(ws, '');
      let room = null;
      if (msg.code) {
        const code = clean(msg.code, 8).toUpperCase();
        for (const r of rooms.values()) if (r.code === code) room = r;
      } else {
        room = rooms.get(msg.id);
      }
      if (!room) return send(ws, { t: 'error', msg: 'Lobby not found' });
      if (room.ver !== ws.ver) return send(ws, { t: 'error', msg: 'That lobby runs a different game version' });
      if (room.started) return send(ws, { t: 'error', msg: 'That battle has already started' });
      if (room.open <= 0 || room.members.size >= MAX_MEMBERS) return send(ws, { t: 'error', msg: 'Lobby is full' });
      let peer = 2;
      while (room.members.has(peer)) peer++;
      room.open--;
      for (const m of room.members.values()) send(m, { t: 'peer_join', peer, name: ws.name });
      ws.room = room;
      ws.peer = peer;
      room.members.set(peer, ws);
      send(ws, { t: 'joined', room: { id: room.id, name: room.name, code: room.code }, you: peer,
        peers: [...room.members.keys()].filter((p) => p !== peer) });
      break;
    }
    case 'leave':
      leave(ws, 'You left the lobby');
      break;
    case 'info': {
      // The host describes its lobby for the list.
      const room = ws.room;
      if (!room || ws.peer !== HOST_ID) return;
      if (typeof msg.info === 'object' && msg.info) room.info = msg.info;
      if (msg.name != null) room.name = clean(msg.name, 30) || room.name;
      if (msg.private != null) room.private = !!msg.private;
      if (msg.started != null) room.started = !!msg.started;
      if (msg.open != null) room.open = Math.max(0, Math.min(MAX_MEMBERS, msg.open | 0));
      break;
    }
    case 'kick': {
      const room = ws.room;
      if (!room || ws.peer !== HOST_ID || msg.peer === HOST_ID) return;
      const target = room.members.get(msg.peer);
      if (target) leave(target, clean(msg.reason, 60) || 'Removed by the host');
      break;
    }
  }
}

// Game data: first byte is who it is for. The server swaps it for who sent
// it. Only the host may address other players; everyone else talks to the host.
function relay(ws, data) {
  const room = ws.room;
  if (!room || data.length < 2) return;
  let target = data[0];
  if (ws.peer !== HOST_ID) target = HOST_ID;
  data[0] = ws.peer;
  if (target === ALL) {
    for (const [peer, m] of room.members) if (peer !== ws.peer && m.readyState === 1) m.send(data);
  } else {
    const m = room.members.get(target);
    if (m && m.readyState === 1) m.send(data);
  }
}

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('TREADFALL lobby server: ' + rooms.size + ' lobbies\n');
});
const wss = new WebSocketServer({ server, maxPayload: MAX_PACKET });

wss.on('connection', (ws) => {
  ws.room = null;
  ws.peer = 0;
  ws.name = 'Player';
  ws.ver = '';
  ws.alive = true;
  ws.on('pong', () => { ws.alive = true; });
  ws.on('message', (data, isBinary) => {
    try {
      if (isBinary) return relay(ws, data);
      const msg = JSON.parse(data.toString());
      if (msg && typeof msg === 'object') control(ws, msg);
    } catch (e) {
      // A bad message from one player must never stop the server.
    }
  });
  ws.on('close', (code) => { if (process.env.DEBUG) console.log('close', ws.peer, ws.name, code); leave(ws, ''); });
  ws.on('error', () => {});
});

// Drop connections that have gone silent.
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 20000);

server.listen(PORT, () => console.log('TREADFALL lobby server on port ' + PORT));
