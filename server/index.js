const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 3000;
const SESSION_DURATION_MS = 24 * 60 * 60 * 1000; // 24 jam
const LATEST_VERSION = process.env.APP_VERSION || '1.1.2';
const LATEST_BUILD = Number(process.env.APP_BUILD || 8);
const RELEASE_NOTES =
  process.env.APP_NOTES ||
  'Suara notifikasi kustom (Chat & Colek), heartbeat anti-putus di latar belakang (stopWithTask=false).';

// In-memory store for multi-user group rooms
// roomCode -> { expiresAt, users: Map<userId, { ws, name, color, bio, location, online, lastSeen }>, messages: [] }
const rooms = new Map();

function getOrCreateRoom(roomCode) {
  let room = rooms.get(roomCode);
  if (!room) {
    room = {
      code: roomCode,
      createdAt: Date.now(),
      expiresAt: Date.now() + SESSION_DURATION_MS,
      users: new Map(),
      messages: [],
    };
    rooms.set(roomCode, room);
  }
  return room;
}

function sendJson(ws, payload) {
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify(payload));
  }
}

function broadcastOthers(room, myUserId, payload) {
  for (const [uid, user] of room.users.entries()) {
    if (uid !== myUserId && user.ws) {
      sendJson(user.ws, payload);
    }
  }
}

function getOtherMembers(room, myUserId) {
  const list = [];
  for (const [uid, user] of room.users.entries()) {
    if (uid !== myUserId) {
      list.push({
        userId: uid,
        name: user.name,
        color: user.color,
        bio: user.bio || '',
        online: user.online,
        location: user.location,
        lastSeen: user.lastSeen,
      });
    }
  }
  return list;
}

const server = http.createServer((req, res) => {
  if (req.url === '/health' || req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        app: 'Chikaku Group Server',
        status: 'ok',
        activeRooms: rooms.size,
        uptimeSeconds: Math.floor(process.uptime()),
      })
    );
    return;
  }
  if (req.url === '/version.json') {
    const host = req.headers.host || `localhost:${PORT}`;
    const proto = req.headers['x-forwarded-proto'] || 'http';
    const apkUrl = process.env.APK_URL || `${proto}://${host}/download/chikaku.apk`;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        version: LATEST_VERSION,
        buildNumber: LATEST_BUILD,
        apkUrl,
        notes: RELEASE_NOTES,
      })
    );
    return;
  }
  if (req.url === '/download/chikaku.apk') {
    const apkPath = path.join(__dirname, 'public', 'chikaku.apk');
    if (!fs.existsSync(apkPath)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('File chikaku.apk belum di-upload ke server/public/chikaku.apk');
      return;
    }
    const stat = fs.statSync(apkPath);
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': 'attachment; filename="chikaku.apk"',
      'Content-Length': stat.size,
    });
    fs.createReadStream(apkPath).pipe(res);
    return;
  }
  res.writeHead(404);
  res.end('Not found');
});

const wss = new WebSocketServer({ server, maxPayload: 10 * 1024 * 1024 });

wss.on('connection', (ws) => {
  let currentRoomCode = null;
  let currentUserId = null;

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch {
      return;
    }

    const { type } = data;

    if (type === 'ping') {
      sendJson(ws, { type: 'pong', ts: Date.now() });
      return;
    }

    if (type === 'join') {
      const roomCode = String(data.roomCode || '').trim().toUpperCase();
      const userId = String(data.userId || '').trim();
      const name = String(data.name || 'Pengguna').trim();
      const color = Number(data.color || 0xFF5B4CF5);
      const bio = String(data.bio || '').trim();

      if (!roomCode || !userId) {
        sendJson(ws, { type: 'error', message: 'Kode room dan userId wajib diisi.' });
        return;
      }

      const room = getOrCreateRoom(roomCode);
      currentRoomCode = roomCode;
      currentUserId = userId;

      const existing = room.users.get(userId);
      room.users.set(userId, {
        ws,
        name,
        color,
        bio,
        online: true,
        location: existing?.location || null,
        lastSeen: Date.now(),
      });

      const members = getOtherMembers(room, userId);

      // Send room state + all members + history to joining user
      sendJson(ws, {
        type: 'joined',
        roomCode,
        expiresAt: room.expiresAt,
        members,
        history: room.messages.slice(-80),
      });

      // Notify all other members in the room
      broadcastOthers(room, userId, {
        type: 'member_status',
        member: {
          userId,
          name,
          color,
          bio,
          online: true,
          location: room.users.get(userId).location,
          lastSeen: Date.now(),
        },
      });
      return;
    }

    if (!currentRoomCode || !currentUserId) return;
    const room = rooms.get(currentRoomCode);
    if (!room) return;

    const me = room.users.get(currentUserId);
    if (!me) return;

    if (type === 'location') {
      const loc = {
        lat: data.lat,
        lng: data.lng,
        speed: data.speed || 0,
        accuracy: data.accuracy || 0,
        battery: data.battery ?? 100,
        statusEmoji: data.statusEmoji || '📍',
        statusText: data.statusText || 'Live 24 Jam',
        timestamp: data.timestamp || Date.now(),
      };
      me.location = loc;
      me.lastSeen = Date.now();

      broadcastOthers(room, currentUserId, {
        type: 'member_location',
        userId: currentUserId,
        name: me.name,
        color: me.color,
        bio: me.bio || '',
        location: loc,
      });
    } else if (type === 'chat' || type === 'voice_note' || type === 'image') {
      const msg = {
        id: data.id || `${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
        type,
        senderId: currentUserId,
        senderName: me.name,
        senderColor: me.color,
        text: data.text || null,
        audioBase64: data.audioBase64 || null,
        imageBase64: data.imageBase64 || null,
        durationMs: data.durationMs || 0,
        timestamp: data.timestamp || Date.now(),
      };

      room.messages.push(msg);
      if (room.messages.length > 120) {
        room.messages.shift();
      }

      broadcastOthers(room, currentUserId, {
        type: 'message',
        message: msg,
      });
    } else if (type === 'nudge') {
      broadcastOthers(room, currentUserId, {
        type: 'nudge',
        senderName: me.name,
        emoji: data.emoji || '👋',
        label: data.label || 'Colek grup!',
        timestamp: Date.now(),
      });
    } else if (type === 'photo_request') {
      broadcastOthers(room, currentUserId, {
        type: 'photo_request',
        senderName: me.name,
        camera: data.camera === 'front' ? 'front' : 'rear',
        timestamp: Date.now(),
      });
    } else if (type === 'extend_session') {
      room.expiresAt = Date.now() + SESSION_DURATION_MS;
      for (const user of room.users.values()) {
        sendJson(user.ws, {
          type: 'session_extended',
          expiresAt: room.expiresAt,
        });
      }
    }
  });

  ws.on('close', () => {
    if (!currentRoomCode || !currentUserId) return;
    const room = rooms.get(currentRoomCode);
    if (!room) return;

    const me = room.users.get(currentUserId);
    if (me) {
      me.online = false;
      me.lastSeen = Date.now();
      me.ws = null;
    }

    broadcastOthers(room, currentUserId, {
      type: 'member_status',
      member: {
        userId: currentUserId,
        name: me?.name || 'Anggota',
        color: me?.color || 0xFFFF5A79,
        bio: me?.bio || '',
        online: false,
        location: me?.location || null,
        lastSeen: Date.now(),
      },
    });
  });
});

// Cleanup expired rooms every 15 minutes
setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms.entries()) {
    if (now > room.expiresAt) {
      rooms.delete(code);
    }
  }
}, 15 * 60 * 1000);

server.listen(PORT, () => {
  console.log(`Chikaku Group WebSocket Server running on port ${PORT}`);
});
