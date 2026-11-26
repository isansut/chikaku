import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_room_client.dart';

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

  String _userId = '';
  String _userName = 'Kamu';
  int _userColor = 0xFF5B4CF5;
  String _userBio = '';
  String _roomCode = '';

  String _statusEmoji = '📍';
  String _statusText = 'Live 24 Jam';
  bool _isPaused = false;

  final SupabaseRoomClient _supabase = SupabaseRoomClient();
  StreamSubscription<Position>? _posSub;
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

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _initNotifications();
    await _loadPrefs();
    await _refreshBattery();
    await _connectSupabase();
    await _startLocationStream();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString(_prefUserId) ?? '';
    _userName = prefs.getString(_prefName) ?? 'Kamu';
    _userColor = prefs.getInt(_prefColor) ?? 0xFF5B4CF5;
    _userBio = prefs.getString(_prefBio) ?? '';
    _roomCode = prefs.getString(_prefRoomCode) ?? '';
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

  Future<void> _connectSupabase() async {
    if (_isConnecting || _roomCode.isEmpty || _userId.isEmpty) return;
    _isConnecting = true;
    try {
      final joined = await _supabase.joinRoom(
        roomCode: _roomCode,
        userId: _userId,
        name: _userName,
        color: _userColor,
        bio: _userBio,
        onMemberChange: (row) {
          final uid = row['user_id'] as String?;
          if (uid == null) return;
          final wasOnline = (_members[uid]?['online'] as bool?) ?? false;
          final nowOnline = (row['online'] as bool?) ?? false;
          _members[uid] = row;
          if (nowOnline && !wasOnline) {
            _showHeadsUp(
              '${row['name'] ?? 'Anggota'} Online 📍',
              'Bergabung di grup $_roomCode',
            );
          }
          _updateServiceNotificationText();
          FlutterForegroundTask.sendDataToMain({
            'event': 'member_update',
            'member': row,
          });
        },
        onMessageInsert: (msg) {
          final senderName = msg['sender_name'] as String? ?? 'Anggota';
          final msgType = msg['type'] as String? ?? 'chat';
          if (msgType == 'voice_note') {
            final secs =
                (((msg['duration_ms'] as num?) ?? 1000) / 1000).ceil();
            _showHeadsUp(
              '$senderName • Voice Note 🎤',
              'Mengirim pesan suara ($secs detik)',
            );
          } else if (msgType == 'image') {
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
          FlutterForegroundTask.sendDataToMain({
            'event': 'message_insert',
            'message': msg,
          });
        },
        onEventInsert: (ev) {
          final evType = ev['type'] as String?;
          final sender = ev['sender_name'] as String? ?? 'Anggota';
          if (evType == 'nudge') {
            final emoji = ev['emoji'] as String? ?? '👋';
            final label = ev['label'] as String? ?? 'Colek kamu!';
            _showHeadsUp('$emoji $sender', label, isColek: true);
          } else if (evType == 'photo_request') {
            final cam = ev['camera'] == 'front' ? 'Depan' : 'Belakang';
            _showHeadsUp(
              '📸 $sender Minta Foto',
              'Buka Chikaku untuk ambil foto Kamera $cam',
              isColek: true,
            );
          }
          FlutterForegroundTask.sendDataToMain({
            'event': 'event_insert',
            'data': ev,
          });
        },
        onStatusChange: (connected, error) {
          FlutterForegroundTask.sendDataToMain({
            'event': 'ws_status',
            'connected': connected,
            'error': error,
          });
        },
      );

      _sessionExpiresAt = (joined['expiresAt'] as num?)?.toInt() ?? 0;
      _members.clear();
      for (final m in (joined['members'] as List)) {
        final map = Map<String, dynamic>.from(m as Map);
        final uid = map['user_id'] as String?;
        if (uid != null) _members[uid] = map;
      }

      if (_lastMyLocation != null && !_isPaused) {
        await _supabase.updateLocation(
          name: _userName,
          color: _userColor,
          bio: _userBio,
          location: _lastMyLocation!,
        );
      }

      FlutterForegroundTask.sendDataToMain({
        'event': 'joined_data',
        'expiresAt': _sessionExpiresAt,
        'members': joined['members'],
        'history': joined['history'],
      });
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'event': 'ws_status',
        'connected': false,
        'error': 'Gagal terhubung ke Supabase: $e',
      });
    } finally {
      _isConnecting = false;
    }
  }

  void _updateServiceNotificationText() {
    final activeCount =
        _members.values.where((m) => m['online'] == true).length;
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

    if (!_isPaused && _supabase.isConnected) {
      try {
        await _supabase.updateLocation(
          name: _userName,
          color: _userColor,
          bio: _userBio,
          location: _lastMyLocation!,
        );
      } catch (_) {}
    }
    _updateServiceNotificationText();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_supabase.isConnected && !_isConnecting) {
      _connectSupabase();
    }
  }

  @override
  void onReceiveData(Object data) async {
    if (data is! Map) return;
    final cmd = data['cmd'] as String?;

    if (cmd == 'send_message' && data['payload'] is Map) {
      final p = Map<String, dynamic>.from(data['payload'] as Map);
      try {
        await _supabase.sendMessage(
          id: p['id'] as String,
          type: p['type'] as String,
          senderName: _userName,
          senderColor: _userColor,
          text: p['text'] as String?,
          audioBase64: p['audioBase64'] as String?,
          imageBase64: p['imageBase64'] as String?,
          durationMs: (p['durationMs'] as num?)?.toInt() ?? 0,
          timestamp: (p['timestamp'] as num).toInt(),
        );
      } catch (_) {}
    } else if (cmd == 'send_event' && data['payload'] is Map) {
      final p = Map<String, dynamic>.from(data['payload'] as Map);
      try {
        await _supabase.sendEvent(
          type: p['type'] as String,
          senderName: _userName,
          emoji: p['emoji'] as String?,
          label: p['label'] as String?,
          camera: p['camera'] as String?,
        );
      } catch (_) {}
    } else if (cmd == 'extend_session') {
      try {
        _sessionExpiresAt = await _supabase.extendSession();
      } catch (_) {}
    } else if (cmd == 'pause') {
      _isPaused = data['paused'] as bool? ?? false;
      if (!_isPaused && _lastMyLocation != null) {
        try {
          await _supabase.updateLocation(
            name: _userName,
            color: _userColor,
            bio: _userBio,
            location: _lastMyLocation!,
          );
        } catch (_) {}
      }
    } else if (cmd == 'status') {
      _statusEmoji = data['emoji'] as String? ?? '📍';
      _statusText = data['text'] as String? ?? 'Live 24 Jam';
      if (_lastMyLocation != null) {
        _lastMyLocation!['statusEmoji'] = _statusEmoji;
        _lastMyLocation!['statusText'] = _statusText;
        if (!_isPaused) {
          try {
            await _supabase.updateLocation(
              name: _userName,
              color: _userColor,
              bio: _userBio,
              location: _lastMyLocation!,
            );
          } catch (_) {}
        }
      }
    } else if (cmd == 'reload_prefs') {
      await _loadPrefs();
      await _connectSupabase();
    } else if (cmd == 'test_notif') {
      await _showHeadsUp(
        'Tes Notifikasi Chikaku 🔔',
        'Suara & pop-up notifikasi berfungsi normal!',
        isColek: data['colek'] == true,
      );
    } else if (cmd == 'sync_state') {
      FlutterForegroundTask.sendDataToMain({
        'event': 'sync_reply',
        'connected': _supabase.isConnected,
        'myLocation': _lastMyLocation,
        'members': _members.values.toList(),
        'expiresAt': _sessionExpiresAt,
      });
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _posSub?.cancel();
    await _supabase.setOffline();
    await _supabase.disconnect();
  }
}
