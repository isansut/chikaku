import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

@pragma('vm:entry-point')
void chikakuStartCallback() {
  FlutterForegroundTask.setTaskHandler(ChikakuTaskHandler());
}

class ChikakuTaskHandler extends TaskHandler {
  static const String _prefUserId = 'chikaku_user_id';
  static const String _prefName = 'chikaku_name';
  static const String _prefColor = 'chikaku_color';
  static const String _prefBio = 'chikaku_bio';
  static const String _prefRoomCode = 'chikaku_room_code';
  static const String _prefServerUrl = 'chikaku_server_url';

  String _userId = '';
  String _userName = 'Kamu';
  int _userColor = 0xFF5B4CF5;
  String _userBio = '';
  String _roomCode = '';
  String _serverUrl = '';

  String _statusEmoji = '📍';
  String _statusText = 'Live 24 Jam';
  bool _isPaused = false;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  StreamSubscription<Position>? _posSub;
  bool _isConnected = false;
  bool _isConnecting = false;

  final Battery _battery = Battery();
  int _cachedBattery = 100;
  Map<String, dynamic>? _lastMyLocation;
  final Map<String, Map<String, dynamic>> _members = {};
  int _sessionExpiresAt = 0;

  final fln.FlutterLocalNotificationsPlugin _notifications =
      fln.FlutterLocalNotificationsPlugin();
  bool _notifReady = false;
  int _notifId = 500;
  int _repeatCounter = 0;
  int _lastWsActivityMs = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _initNotifications();
    await _loadPrefs();
    await _refreshBattery();
    await _connectWs();
    await _startLocationStream();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString(_prefUserId) ?? '';
    _userName = prefs.getString(_prefName) ?? 'Kamu';
    _userColor = prefs.getInt(_prefColor) ?? 0xFF5B4CF5;
    _userBio = prefs.getString(_prefBio) ?? '';
    _roomCode = prefs.getString(_prefRoomCode) ?? '';
    _serverUrl = prefs.getString(_prefServerUrl) ?? '';
  }

  Future<void> _initNotifications() async {
    if (_notifReady) return;
    try {
      const androidInit =
          fln.AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notifications.initialize(
        settings: const fln.InitializationSettings(android: androidInit),
      );
      const chatChannel = fln.AndroidNotificationChannel(
        'chikaku_chat_v2',
        'Chikaku Chat & Pesan',
        description: 'Notifikasi chat, voice note, dan foto dari grup',
        importance: fln.Importance.max,
        playSound: true,
        sound: fln.RawResourceAndroidNotificationSound('chikaku_chat'),
        enableVibration: true,
      );
      const colekChannel = fln.AndroidNotificationChannel(
        'chikaku_colek_v2',
        'Chikaku Colek & Foto',
        description: 'Notifikasi colek dan permintaan foto',
        importance: fln.Importance.max,
        playSound: true,
        sound: fln.RawResourceAndroidNotificationSound('chikaku_colek'),
        enableVibration: true,
      );
      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              fln.AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(chatChannel);
      await androidPlugin?.createNotificationChannel(colekChannel);
      _notifReady = true;
    } catch (_) {}
  }

  Future<void> _showHeadsUp(
    String title,
    String body, {
    bool isColek = false,
  }) async {
    if (!_notifReady) return;
    try {
      final channelId = isColek ? 'chikaku_colek_v2' : 'chikaku_chat_v2';
      final channelName =
          isColek ? 'Chikaku Colek & Foto' : 'Chikaku Chat & Pesan';
      final soundName = isColek ? 'chikaku_colek' : 'chikaku_chat';
      final details = fln.AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifikasi Chikaku dengan suara kustom',
        importance: fln.Importance.max,
        priority: fln.Priority.high,
        ticker: 'Chikaku',
        playSound: true,
        sound: fln.RawResourceAndroidNotificationSound(soundName),
        enableVibration: true,
        visibility: fln.NotificationVisibility.public,
      );
      await _notifications.show(
        id: _notifId++,
        title: title,
        body: body,
        notificationDetails: fln.NotificationDetails(android: details),
      );
    } catch (_) {
      // Fallback to default sound if custom raw sound fails on OEM ROM
      try {
        const fallback = fln.AndroidNotificationDetails(
          'chikaku_fallback',
          'Chikaku Notifikasi',
          importance: fln.Importance.max,
          priority: fln.Priority.high,
          playSound: true,
          enableVibration: true,
        );
        await _notifications.show(
          id: _notifId++,
          title: title,
          body: body,
          notificationDetails: const fln.NotificationDetails(android: fallback),
        );
      } catch (_) {}
    }
  }

  Future<void> _refreshBattery() async {
    try {
      _cachedBattery = await _battery.batteryLevel;
    } catch (_) {
      _cachedBattery = 100;
    }
  }

  Future<void> _connectWs() async {
    if (_isConnecting || _roomCode.isEmpty || _serverUrl.isEmpty) return;
    _isConnecting = true;
    try {
      await _wsSub?.cancel();
      await _channel?.sink.close();

      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await _channel!.ready;
      _isConnected = true;
      _isConnecting = false;
      _lastWsActivityMs = DateTime.now().millisecondsSinceEpoch;

      _sendWs({
        'type': 'join',
        'roomCode': _roomCode,
        'userId': _userId,
        'name': _userName,
        'color': _userColor,
        'bio': _userBio,
      });

      FlutterForegroundTask.sendDataToMain({
        'event': 'ws_status',
        'connected': true,
        'error': null,
      });

      _wsSub = _channel!.stream.listen(
        _onWsMessage,
        onError: (_) {
          _isConnected = false;
          FlutterForegroundTask.sendDataToMain({
            'event': 'ws_status',
            'connected': false,
            'error': 'Gagal terhubung ke server',
          });
        },
        onDone: () {
          _isConnected = false;
          FlutterForegroundTask.sendDataToMain({
            'event': 'ws_status',
            'connected': false,
            'error': null,
          });
        },
      );
    } catch (_) {
      _isConnected = false;
      _isConnecting = false;
      FlutterForegroundTask.sendDataToMain({
        'event': 'ws_status',
        'connected': false,
        'error': 'Server tidak terjangkau ($_serverUrl)',
      });
    }
  }

  void _onWsMessage(dynamic raw) {
    _lastWsActivityMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'pong') return;

      if (type == 'joined') {
        if (data['expiresAt'] != null) {
          _sessionExpiresAt = (data['expiresAt'] as num).toInt();
        }
        _members.clear();
        if (data['members'] is List) {
          for (final item in data['members'] as List) {
            final m = Map<String, dynamic>.from(item as Map);
            final uid = m['userId'] as String?;
            if (uid != null) _members[uid] = m;
          }
        } else if (data['partner'] is Map) {
          final m = Map<String, dynamic>.from(data['partner'] as Map);
          final uid = m['userId'] as String?;
          if (uid != null) _members[uid] = m;
        }
        if (_lastMyLocation != null && !_isPaused) {
          _sendWs({'type': 'location', ..._lastMyLocation!});
        }
      } else if (type == 'member_status' || type == 'partner_status') {
        final rawMember = data['member'] ?? data['partner'];
        if (rawMember != null) {
          final m = Map<String, dynamic>.from(rawMember as Map);
          final uid = m['userId'] as String?;
          if (uid != null) {
            final wasOnline = (_members[uid]?['online'] as bool?) ?? false;
            final nowOnline = (m['online'] as bool?) ?? false;
            _members[uid] = m;
            if (nowOnline && !wasOnline) {
              _showHeadsUp(
                '${m['name'] ?? 'Anggota'} Online 📍',
                'Bergabung di grup $_roomCode',
              );
            }
          }
        }
      } else if (type == 'member_location' || type == 'partner_location') {
        final uid = data['userId'] as String? ?? 'member';
        _members[uid] = {
          'userId': uid,
          'name': data['name'] ?? _members[uid]?['name'] ?? 'Anggota',
          'color': data['color'] ?? 0xFFFF5A79,
          'bio': data['bio'] ?? '',
          'online': true,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'location': data['location'],
        };
        _updateServiceNotificationText();
      } else if (type == 'message') {
        final msg = Map<String, dynamic>.from(data['message'] as Map);
        final senderId = msg['senderId'] as String? ?? '';
        if (senderId != _userId) {
          final senderName = msg['senderName'] as String? ?? 'Pasangan';
          if (msg['type'] == 'voice_note') {
            final secs = (((msg['durationMs'] as num?) ?? 1000) / 1000).ceil();
            _showHeadsUp(
              '$senderName • Voice Note 🎤',
              'Mengirim pesan suara ($secs detik)',
            );
          } else if (msg['type'] == 'image') {
            _showHeadsUp(
              '$senderName • Foto 📷',
              'Mengirim foto baru di chat',
            );
          } else {
            _showHeadsUp(
              '$senderName 💬',
              msg['text'] as String? ?? 'Pesan baru',
            );
          }
        }
      } else if (type == 'nudge') {
        final sender = data['senderName'] as String? ?? 'Pasangan';
        final emoji = data['emoji'] as String? ?? '👋';
        final label = data['label'] as String? ?? 'Colek kamu!';
        _showHeadsUp('$emoji $sender', label, isColek: true);
      } else if (type == 'photo_request') {
        final sender = data['senderName'] as String? ?? 'Pasangan';
        final cam = data['camera'] == 'front' ? 'Depan' : 'Belakang';
        _showHeadsUp(
          '📸 $sender Minta Foto',
          'Buka Chikaku untuk ambil foto Kamera $cam',
          isColek: true,
        );
      } else if (type == 'session_extended') {
        _sessionExpiresAt = (data['expiresAt'] as num).toInt();
      }

      // Forward every event to UI isolate if open
      FlutterForegroundTask.sendDataToMain({
        'event': 'ws_message',
        'data': data,
      });
    } catch (_) {}
  }

  void _updateServiceNotificationText() {
    final activeCount = _members.values.where((m) => m['online'] == true).length;
    FlutterForegroundTask.updateService(
      notificationTitle: 'Chikaku Live 24 Jam • $_roomCode',
      notificationText: '$activeCount anggota online di grup',
    );
  }

  Future<void> _startLocationStream() async {
    await _posSub?.cancel();
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _onPosition(pos);

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(_onPosition, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _onPosition(Position pos) async {
    await _refreshBattery();
    _lastMyLocation = {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed': pos.speed,
      'accuracy': pos.accuracy,
      'battery': _cachedBattery,
      'statusEmoji': _statusEmoji,
      'statusText': _statusText,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    FlutterForegroundTask.sendDataToMain({
      'event': 'my_location',
      'location': _lastMyLocation,
    });

    if (!_isPaused && _isConnected) {
      _sendWs({'type': 'location', ..._lastMyLocation!});
    }
    _updateServiceNotificationText();
  }

  void _sendWs(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _repeatCounter++;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isConnected && (now - _lastWsActivityMs) > 65000) {
      _isConnected = false;
    }
    if (!_isConnected && !_isConnecting) {
      _connectWs();
      return;
    }
    if (_isConnected && _repeatCounter % 5 == 0) {
      _sendWs({'type': 'ping'});
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final cmd = data['cmd'] as String?;
    if (cmd == 'send_ws' && data['payload'] is Map) {
      _sendWs(Map<String, dynamic>.from(data['payload'] as Map));
    } else if (cmd == 'pause') {
      _isPaused = data['paused'] as bool? ?? false;
      if (!_isPaused && _lastMyLocation != null) {
        _sendWs({'type': 'location', ..._lastMyLocation!});
      }
    } else if (cmd == 'status') {
      _statusEmoji = data['emoji'] as String? ?? '📍';
      _statusText = data['text'] as String? ?? 'Live 24 Jam';
      if (_lastMyLocation != null) {
        _lastMyLocation!['statusEmoji'] = _statusEmoji;
        _lastMyLocation!['statusText'] = _statusText;
        if (!_isPaused) {
          _sendWs({'type': 'location', ..._lastMyLocation!});
        }
      }
    } else if (cmd == 'reload_prefs') {
      _loadPrefs().then((_) => _connectWs());
    } else if (cmd == 'test_notif') {
      _showHeadsUp(
        'Tes Notifikasi Chikaku 🔔',
        'Suara & pop-up notifikasi berfungsi normal!',
        isColek: data['colek'] == true,
      );
    } else if (cmd == 'sync_state') {
      FlutterForegroundTask.sendDataToMain({
        'event': 'sync_reply',
        'connected': _isConnected,
        'myLocation': _lastMyLocation,
        'members': _members.values.toList(),
        'expiresAt': _sessionExpiresAt,
      });
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _posSub?.cancel();
    await _wsSub?.cancel();
    await _channel?.sink.close();
  }
}
