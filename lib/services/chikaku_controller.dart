import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chikaku_models.dart';
import 'background_service.dart';
import 'supabase_room_client.dart';

class ChikakuController extends ChangeNotifier {
  static const String _prefUserId = 'chikaku_user_id';
  static const String _prefName = 'chikaku_name';
  static const String _prefColor = 'chikaku_color';
  static const String _prefBio = 'chikaku_bio';
  static const String _prefRoomCode = 'chikaku_room_code';
  static const String _prefInterval = 'chikaku_interval_sec';

  // Identity & Settings
  String userId = '';
  String userName = 'Kamu';
  int userColor = 0xFF5B4CF5;
  String userBio = '';
  String roomCode = '';
  int updateIntervalSeconds = 5;
  String myStatusEmoji = '📍';
  String myStatusText = 'Live 24 Jam';
  bool isSharingPaused = false;
  bool showTrail = true;

  // Live state
  bool isInitialized = false;
  bool isPaired = false;
  bool isConnected = false;
  String? connectionError;
  int sessionExpiresAt = 0;

  String appVersion = '2.0.0';
  int appBuildNumber = 12;

  UserLocation? myLocation;
  final Map<String, RoomMember> members = {};
  String? selectedMemberId;
  final List<ChatMessage> messages = [];
  final List<LatLng> myTrail = [];
  final Map<String, List<LatLng>> memberTrails = {};

  RoomMember? get selectedMember {
    if (selectedMemberId != null && members.containsKey(selectedMemberId)) {
      return members[selectedMemberId];
    }
    if (members.isEmpty) return null;
    for (final m in members.values) {
      if (m.online) return m;
    }
    return members.values.first;
  }

  void selectMember(String memberId) {
    selectedMemberId = memberId;
    notifyListeners();
  }

  // Nudge & Photo Request streams for in-app banner/dialog
  final StreamController<NudgeEvent> _nudgeController =
      StreamController<NudgeEvent>.broadcast();
  Stream<NudgeEvent> get nudgeStream => _nudgeController.stream;

  final StreamController<PhotoRequestEvent> _photoReqController =
      StreamController<PhotoRequestEvent>.broadcast();
  Stream<PhotoRequestEvent> get photoRequestStream =>
      _photoReqController.stream;

  final ImagePicker _imagePicker = ImagePicker();

  // Audio recording & playback
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool isRecording = false;
  int recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _currentRecordingPath;

  String? playingMessageId;
  Duration playbackPosition = Duration.zero;
  Duration playbackDuration = Duration.zero;

  Timer? _countdownTimer;

  // Direct iOS / non-Android Supabase & GPS
  final SupabaseRoomClient _directSupabase = SupabaseRoomClient();
  StreamSubscription<Position>? _directPosSub;
  Timer? _directReconnectTimer;
  final Battery _battery = Battery();
  int _cachedBattery = 100;
  final fln.FlutterLocalNotificationsPlugin _iosNotif =
      fln.FlutterLocalNotificationsPlugin();
  bool _iosNotifReady = false;
  int _iosNotifId = 900;

  ChikakuController() {
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    _player.onPlayerComplete.listen((_) {
      playingMessageId = null;
      playbackPosition = Duration.zero;
      notifyListeners();
    });
    _player.onPositionChanged.listen((pos) {
      playbackPosition = pos;
      notifyListeners();
    });
    _player.onDurationChanged.listen((dur) {
      playbackDuration = dur;
      notifyListeners();
    });
  }

  Future<void> init() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback(_onBackgroundData);
      _initForegroundTaskOptions();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _initIosNotifications();
    }

    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = pkg.version;
      appBuildNumber = int.tryParse(pkg.buildNumber) ?? 12;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString(_prefUserId) ?? _generateUserId();
    await prefs.setString(_prefUserId, userId);

    userName = prefs.getString(_prefName) ?? '';
    userColor = prefs.getInt(_prefColor) ?? 0xFF5B4CF5;
    userBio = prefs.getString(_prefBio) ?? '';
    roomCode = prefs.getString(_prefRoomCode) ?? '';
    updateIntervalSeconds = prefs.getInt(_prefInterval) ?? 5;

    isPaired = userName.isNotEmpty && roomCode.isNotEmpty;
    isInitialized = true;
    notifyListeners();

    if (isPaired) {
      await startSession();
    }
  }

  void _initForegroundTaskOptions() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'chikaku_bg_service',
        channelName: 'Chikaku Live 24 Jam Service',
        channelDescription:
            'Menjaga koneksi chat, notifikasi, dan lokasi 24 jam di latar belakang',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  String _generateUserId() {
    final r = math.Random();
    return 'u_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(9999)}';
  }

  String generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = math.Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> saveAndJoin({
    required String name,
    required int color,
    required String code,
  }) async {
    userName = name.trim();
    userColor = color;
    roomCode = code.trim().toUpperCase();
    isPaired = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefName, userName);
    await prefs.setInt(_prefColor, userColor);
    await prefs.setString(_prefRoomCode, roomCode);

    messages.clear();
    myTrail.clear();
    memberTrails.clear();
    members.clear();
    selectedMemberId = null;
    notifyListeners();

    await startSession();
  }

  Future<void> updateProfile({
    required String name,
    required int color,
    required String bio,
    required String statusEmoji,
    required String statusText,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name.trim().isNotEmpty) {
      userName = name.trim();
      await prefs.setString(_prefName, userName);
    }
    userColor = color;
    await prefs.setInt(_prefColor, userColor);
    userBio = bio.trim();
    await prefs.setString(_prefBio, userBio);
    myStatusEmoji = statusEmoji;
    myStatusText = statusText.trim().isEmpty ? 'Live 24 Jam' : statusText.trim();
    notifyListeners();

    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'status',
        'emoji': myStatusEmoji,
        'text': myStatusText,
      });
      FlutterForegroundTask.sendDataToTask({'cmd': 'reload_prefs'});
    } else {
      await _connectDirectSupabase();
    }
  }

  Future<void> updateSettings({
    String? name,
    int? intervalSeconds,
    String? statusEmoji,
    String? statusText,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    bool needReload = false;

    if (name != null && name.trim().isNotEmpty) {
      userName = name.trim();
      await prefs.setString(_prefName, userName);
      needReload = true;
    }
    if (intervalSeconds != null && intervalSeconds != updateIntervalSeconds) {
      updateIntervalSeconds = intervalSeconds;
      await prefs.setInt(_prefInterval, updateIntervalSeconds);
    }
    if (statusEmoji != null) myStatusEmoji = statusEmoji;
    if (statusText != null) myStatusText = statusText;

    notifyListeners();

    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'status',
        'emoji': myStatusEmoji,
        'text': myStatusText,
      });
      if (needReload) {
        FlutterForegroundTask.sendDataToTask({'cmd': 'reload_prefs'});
      }
    } else {
      if (needReload) {
        await _connectDirectSupabase();
      } else {
        await _sendDirectCurrentLocation();
      }
    }
  }

  void toggleTrail() {
    showTrail = !showTrail;
    notifyListeners();
  }

  Future<void> startSession() async {
    sessionExpiresAt =
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;
    _startCountdownTimer();
    await _requestPermissions();

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        FlutterForegroundTask.sendDataToTask({'cmd': 'reload_prefs'});
        FlutterForegroundTask.sendDataToTask({'cmd': 'sync_state'});
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'Chikaku Live 24 Jam • $roomCode',
          notificationText: 'Menjaga koneksi chat & lokasi di latar belakang',
          callback: chikakuStartCallback,
        );
      }
    } else {
      await _startDirectLocationTracking();
      await _connectDirectSupabase();
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();
  }

  void _onBackgroundData(Object data) {
    if (data is! Map) return;
    final event = data['event'] as String?;

    if (event == 'ws_status') {
      isConnected = data['connected'] as bool? ?? false;
      connectionError = data['error'] as String?;
      notifyListeners();
    } else if (event == 'my_location' && data['location'] is Map) {
      myLocation = UserLocation.fromJson(
          Map<String, dynamic>.from(data['location'] as Map));
      _appendTrailPoint(myTrail, myLocation!.latLng);
      notifyListeners();
    } else if (event == 'joined_data') {
      isConnected = true;
      connectionError = null;
      if (data['expiresAt'] != null) {
        sessionExpiresAt = (data['expiresAt'] as num).toInt();
      }
      if (data['members'] is List) {
        members.clear();
        for (final item in data['members'] as List) {
          final m = RoomMember.fromJson(Map<String, dynamic>.from(item as Map));
          members[m.userId] = m;
          if (m.location != null) {
            final trail = memberTrails.putIfAbsent(m.userId, () => []);
            _appendTrailPoint(trail, m.location!.latLng);
          }
        }
      }
      if (data['history'] is List) {
        messages.clear();
        for (final item in data['history'] as List) {
          messages.add(ChatMessage.fromJson(
              Map<String, dynamic>.from(item as Map), userId));
        }
      }
      notifyListeners();
    } else if (event == 'member_update' && data['member'] is Map) {
      final m = RoomMember.fromJson(
          Map<String, dynamic>.from(data['member'] as Map));
      members[m.userId] = m;
      if (m.location != null) {
        final trail = memberTrails.putIfAbsent(m.userId, () => []);
        _appendTrailPoint(trail, m.location!.latLng);
      }
      notifyListeners();
    } else if (event == 'message_insert' && data['message'] is Map) {
      final msg = ChatMessage.fromJson(
          Map<String, dynamic>.from(data['message'] as Map), userId);
      if (!messages.any((m) => m.id == msg.id)) {
        messages.add(msg);
        notifyListeners();
      }
    } else if (event == 'event_insert' && data['data'] is Map) {
      _handleEventRow(Map<String, dynamic>.from(data['data'] as Map));
    } else if (event == 'sync_reply') {
      isConnected = data['connected'] as bool? ?? false;
      if (data['expiresAt'] != null && (data['expiresAt'] as num) > 0) {
        sessionExpiresAt = (data['expiresAt'] as num).toInt();
      }
      if (data['myLocation'] is Map) {
        myLocation = UserLocation.fromJson(
            Map<String, dynamic>.from(data['myLocation'] as Map));
      }
      if (data['members'] is List) {
        members.clear();
        for (final item in data['members'] as List) {
          final m = RoomMember.fromJson(Map<String, dynamic>.from(item as Map));
          members[m.userId] = m;
        }
      }
      notifyListeners();
    }
  }

  void _handleEventRow(Map<String, dynamic> ev) {
    final type = ev['type'] as String?;
    final sender =
        (ev['sender_name'] ?? ev['senderName']) as String? ?? 'Pasangan';
    if (type == 'nudge') {
      _nudgeController.add(NudgeEvent(
        senderName: sender,
        emoji: ev['emoji'] as String? ?? '👋',
        label: ev['label'] as String? ?? 'Colek kamu!',
        timestamp: (ev['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ));
    } else if (type == 'photo_request') {
      _photoReqController.add(PhotoRequestEvent(
        senderName: sender,
        useFrontCamera: ev['camera'] == 'front',
        timestamp: (ev['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  void _appendTrailPoint(List<LatLng> trail, LatLng point) {
    if (trail.isEmpty) {
      trail.add(point);
      return;
    }
    final last = trail.last;
    final dist = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      point.latitude,
      point.longitude,
    );
    if (dist >= 15) {
      trail.add(point);
      if (trail.length > 500) {
        trail.removeAt(0);
      }
    }
  }

  void togglePauseSharing() {
    isSharingPaused = !isSharingPaused;
    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'pause',
        'paused': isSharingPaused,
      });
    } else if (!isSharingPaused) {
      _sendDirectCurrentLocation();
    }
    notifyListeners();
  }

  // --- Chat, Voice Notes & Camera ---
  Future<void> sendTextMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final msg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999)}',
      type: ChatMessageType.chat,
      senderId: userId,
      senderName: userName,
      senderColor: userColor,
      text: trimmed,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isMe: true,
    );
    messages.add(msg);
    notifyListeners();

    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'send_message',
        'payload': {
          'id': msg.id,
          'type': 'chat',
          'text': msg.text,
          'timestamp': msg.timestamp,
        },
      });
    } else {
      try {
        await _directSupabase.sendMessage(
          id: msg.id,
          type: 'chat',
          senderName: userName,
          senderColor: userColor,
          text: msg.text,
          timestamp: msg.timestamp,
        );
      } catch (_) {}
    }
  }

  Future<void> sendNudge(String emoji, String label) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'send_event',
        'payload': {
          'type': 'nudge',
          'emoji': emoji,
          'label': label,
        },
      });
    } else {
      try {
        await _directSupabase.sendEvent(
          type: 'nudge',
          senderName: userName,
          emoji: emoji,
          label: label,
        );
      } catch (_) {}
    }
  }

  void sendTestNotification({bool colek = false}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'test_notif',
        'colek': colek,
      });
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      _showIosNotification(
        'Tes Notifikasi Chikaku 🔔',
        'Suara & pop-up notifikasi berfungsi normal!',
      );
    }
  }

  Future<void> requestPartnerPhoto({required bool useFrontCamera}) async {
    final cam = useFrontCamera ? 'front' : 'rear';
    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'send_event',
        'payload': {
          'type': 'photo_request',
          'camera': cam,
        },
      });
    } else {
      try {
        await _directSupabase.sendEvent(
          type: 'photo_request',
          senderName: userName,
          camera: cam,
        );
      } catch (_) {}
    }
  }

  Future<bool> captureAndSendPhoto({required bool useFrontCamera}) async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice:
            useFrontCamera ? CameraDevice.front : CameraDevice.rear,
        maxWidth: 1080,
        imageQuality: 75,
      );
      if (file == null) return false;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final msg = ChatMessage(
        id: 'img_${DateTime.now().millisecondsSinceEpoch}',
        type: ChatMessageType.image,
        senderId: userId,
        senderName: userName,
        senderColor: userColor,
        imageBase64: b64,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isMe: true,
      );
      messages.add(msg);
      notifyListeners();

      if (defaultTargetPlatform == TargetPlatform.android) {
        FlutterForegroundTask.sendDataToTask({
          'cmd': 'send_message',
          'payload': {
            'id': msg.id,
            'type': 'image',
            'imageBase64': b64,
            'timestamp': msg.timestamp,
          },
        });
      } else {
        await _directSupabase.sendMessage(
          id: msg.id,
          type: 'image',
          senderName: userName,
          senderColor: userColor,
          imageBase64: b64,
          timestamp: msg.timestamp,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> extend24Hours() async {
    sessionExpiresAt =
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;
    notifyListeners();
    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({'cmd': 'extend_session'});
    } else {
      try {
        sessionExpiresAt = await _directSupabase.extendSession();
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<bool> openPartnerInGoogleMaps() async {
    final loc = selectedMember?.location;
    if (loc == null) return false;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${loc.lat},${loc.lng}&travelmode=driving',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Note: OTA APK self-update disabled when serverless; returns null cleanly.
  Future<Map<String, dynamic>?> checkForUpdate() async => null;

  Future<bool> openUpdateDownload(String apkUrl) async {
    final uri = Uri.parse(apkUrl);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> startRecording() async {
    if (isRecording) return false;
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) return false;

    final dir = await getTemporaryDirectory();
    _currentRecordingPath =
        '${dir.path}/chikaku_vn_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 22050,
      ),
      path: _currentRecordingPath!,
    );

    isRecording = true;
    recordingSeconds = 0;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      recordingSeconds++;
      notifyListeners();
      if (recordingSeconds >= 60) {
        stopAndSendRecording();
      }
    });
    notifyListeners();
    return true;
  }

  Future<void> cancelRecording() async {
    if (!isRecording) return;
    _recordingTimer?.cancel();
    await _recorder.stop();
    isRecording = false;
    recordingSeconds = 0;
    _currentRecordingPath = null;
    notifyListeners();
  }

  Future<void> stopAndSendRecording() async {
    if (!isRecording) return;
    _recordingTimer?.cancel();
    final durationMs = math.max(1000, recordingSeconds * 1000);
    final path = await _recorder.stop();
    isRecording = false;
    recordingSeconds = 0;
    notifyListeners();

    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);

    final msg = ChatMessage(
      id: 'vn_${DateTime.now().millisecondsSinceEpoch}',
      type: ChatMessageType.voiceNote,
      senderId: userId,
      senderName: userName,
      senderColor: userColor,
      audioBase64: b64,
      localAudioPath: path,
      durationMs: durationMs,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isMe: true,
    );
    messages.add(msg);
    notifyListeners();

    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'send_message',
        'payload': {
          'id': msg.id,
          'type': 'voice_note',
          'audioBase64': b64,
          'durationMs': durationMs,
          'timestamp': msg.timestamp,
        },
      });
    } else {
      try {
        await _directSupabase.sendMessage(
          id: msg.id,
          type: 'voice_note',
          senderName: userName,
          senderColor: userColor,
          audioBase64: b64,
          durationMs: durationMs,
          timestamp: msg.timestamp,
        );
      } catch (_) {}
    }
  }

  Future<void> togglePlayVoiceNote(ChatMessage msg) async {
    if (playingMessageId == msg.id) {
      await _player.stop();
      playingMessageId = null;
      playbackPosition = Duration.zero;
      notifyListeners();
      return;
    }

    String? filePath = msg.localAudioPath;
    if (filePath == null || !await File(filePath).exists()) {
      if (msg.audioBase64 == null) return;
      final dir = await getTemporaryDirectory();
      filePath = '${dir.path}/${msg.id}.m4a';
      final file = File(filePath);
      if (!await file.exists()) {
        await file.writeAsBytes(base64Decode(msg.audioBase64!));
      }
    }

    playingMessageId = msg.id;
    playbackPosition = Duration.zero;
    playbackDuration = Duration(milliseconds: msg.durationMs);
    notifyListeners();

    await _player.play(DeviceFileSource(filePath));
  }

  // --- Distance & Time Helpers ---
  double? distanceToMember(RoomMember? m) {
    if (myLocation == null || m?.location == null) return null;
    return Geolocator.distanceBetween(
      myLocation!.lat,
      myLocation!.lng,
      m!.location!.lat,
      m.location!.lng,
    );
  }

  double? get distanceMeters => distanceToMember(selectedMember);

  String formattedDistanceTo(RoomMember? m) {
    final d = distanceToMember(m);
    if (d == null) return 'Menunggu...';
    if (d < 50) return 'Berdekatan (${d.round()} m)';
    if (d < 1000) return '${d.round()} m';
    return '${(d / 1000).toStringAsFixed(2)} km';
  }

  String get formattedDistance => formattedDistanceTo(selectedMember);

  String get formattedEta {
    final d = distanceMeters;
    if (d == null) return '';
    if (d < 50) return 'Di sekitar kamu';
    if (d < 1200) {
      final walkMin = math.max(1, (d / 80).round());
      return '~$walkMin mnt jalan';
    }
    final rideMin = math.max(1, (d / 550).round());
    return '~$rideMin mnt motor';
  }

  List<LatLng> get connectionLinePoints {
    final m = selectedMember;
    if (myLocation == null || m?.location == null) return [];
    return [myLocation!.latLng, m!.location!.latLng];
  }

  String get remainingSessionText {
    final diff = sessionExpiresAt - DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return '00:00:00';
    final hours = diff ~/ 3600000;
    final mins = (diff % 3600000) ~/ 60000;
    final secs = (diff % 60000) ~/ 1000;
    return '${hours.toString().padLeft(2, '0')}:'
        '${mins.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  Future<void> leaveRoom() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await FlutterForegroundTask.stopService();
    } else {
      _directReconnectTimer?.cancel();
      await _directSupabase.setOffline();
      await _directSupabase.disconnect();
      await _directPosSub?.cancel();
    }
    _countdownTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefRoomCode);
    roomCode = '';
    isPaired = false;
    isConnected = false;
    members.clear();
    selectedMemberId = null;
    messages.clear();
    myTrail.clear();
    memberTrails.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);
    }
    _directReconnectTimer?.cancel();
    _directSupabase.dispose();
    _directPosSub?.cancel();
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _nudgeController.close();
    _photoReqController.close();
    super.dispose();
  }

  // --- Direct iOS / non-Android GPS, Supabase & Local Notifications ---
  Future<void> _initIosNotifications() async {
    if (_iosNotifReady) return;
    try {
      const darwinInit = fln.DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _iosNotif.initialize(
        settings: const fln.InitializationSettings(iOS: darwinInit),
      );
      _iosNotifReady = true;
    } catch (_) {}
  }

  Future<void> _showIosNotification(String title, String body) async {
    if (!_iosNotifReady) return;
    try {
      const details = fln.DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
      );
      await _iosNotif.show(
        id: _iosNotifId++,
        title: title,
        body: body,
        notificationDetails: const fln.NotificationDetails(iOS: details),
      );
    } catch (_) {}
  }

  Future<void> _startDirectLocationTracking() async {
    await _directPosSub?.cancel();
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _onDirectPosition(pos);

      final LocationSettings settings = defaultTargetPlatform == TargetPlatform.iOS
          ? AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
              allowBackgroundLocationUpdates: true,
              pauseLocationUpdatesAutomatically: false,
              showBackgroundLocationIndicator: true,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            );

      _directPosSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(_onDirectPosition, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _onDirectPosition(Position pos) async {
    try {
      _cachedBattery = await _battery.batteryLevel;
    } catch (_) {
      _cachedBattery = 100;
    }
    myLocation = UserLocation(
      lat: pos.latitude,
      lng: pos.longitude,
      speed: pos.speed,
      accuracy: pos.accuracy,
      battery: _cachedBattery,
      statusEmoji: myStatusEmoji,
      statusText: myStatusText,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _appendTrailPoint(myTrail, myLocation!.latLng);
    notifyListeners();
    await _sendDirectCurrentLocation();
  }

  Future<void> _sendDirectCurrentLocation() async {
    if (isSharingPaused || myLocation == null || !_directSupabase.isConnected) {
      return;
    }
    try {
      await _directSupabase.updateLocation(
        name: userName,
        color: userColor,
        bio: userBio,
        location: myLocation!.toJson(),
      );
    } catch (_) {}
  }

  Future<void> _connectDirectSupabase() async {
    if (roomCode.isEmpty || userId.isEmpty) return;
    try {
      final joined = await _directSupabase.joinRoom(
        roomCode: roomCode,
        userId: userId,
        name: userName,
        color: userColor,
        bio: userBio,
        onMemberChange: (row) {
          final m = RoomMember.fromJson(row);
          members[m.userId] = m;
          if (m.location != null) {
            final trail = memberTrails.putIfAbsent(m.userId, () => []);
            _appendTrailPoint(trail, m.location!.latLng);
          }
          notifyListeners();
        },
        onMessageInsert: (row) {
          final msg = ChatMessage.fromJson(row, userId);
          if (!messages.any((m) => m.id == msg.id)) {
            messages.add(msg);
            if (defaultTargetPlatform == TargetPlatform.iOS && !msg.isMe) {
              if (msg.type == ChatMessageType.voiceNote) {
                _showIosNotification(
                    '${msg.senderName} • Voice Note 🎤', 'Mengirim pesan suara');
              } else if (msg.type == ChatMessageType.image) {
                _showIosNotification(
                    '${msg.senderName} • Foto 📷', 'Mengirim foto baru');
              } else {
                _showIosNotification(
                    '${msg.senderName} 💬', msg.text ?? 'Pesan baru');
              }
            }
            notifyListeners();
          }
        },
        onEventInsert: (row) {
          _handleEventRow(row);
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            final sender = row['sender_name'] as String? ?? 'Pasangan';
            if (row['type'] == 'nudge') {
              _showIosNotification(
                '${row['emoji'] ?? '👋'} $sender',
                row['label'] as String? ?? 'Colek kamu!',
              );
            } else if (row['type'] == 'photo_request') {
              _showIosNotification(
                '📸 $sender Minta Foto',
                'Tap untuk ambil foto kamera ${row['camera'] == 'front' ? 'Depan' : 'Belakang'}',
              );
            }
          }
        },
        onStatusChange: (connected, error) {
          isConnected = connected;
          connectionError = error;
          notifyListeners();
          if (!connected) _scheduleDirectReconnect();
        },
      );

      isConnected = true;
      connectionError = null;
      sessionExpiresAt = (joined['expiresAt'] as num?)?.toInt() ??
          DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;

      members.clear();
      for (final item in (joined['members'] as List)) {
        final m = RoomMember.fromJson(Map<String, dynamic>.from(item as Map));
        members[m.userId] = m;
        if (m.location != null) {
          final trail = memberTrails.putIfAbsent(m.userId, () => []);
          _appendTrailPoint(trail, m.location!.latLng);
        }
      }

      messages.clear();
      for (final item in (joined['history'] as List)) {
        messages.add(ChatMessage.fromJson(
            Map<String, dynamic>.from(item as Map), userId));
      }

      await _sendDirectCurrentLocation();
      notifyListeners();
    } catch (e) {
      isConnected = false;
      connectionError = 'Gagal terhubung ke Supabase';
      notifyListeners();
      _scheduleDirectReconnect();
    }
  }

  void _scheduleDirectReconnect() {
    if (!isPaired) return;
    _directReconnectTimer?.cancel();
    _directReconnectTimer =
        Timer(const Duration(seconds: 5), _connectDirectSupabase);
  }
}
