import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SupabaseRoomClient {
  final SupabaseClient _client = SupabaseClient(
    SupabaseConfig.url,
    SupabaseConfig.anonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  RealtimeChannel? _channel;
  String? _roomCode;
  String? _userId;

  bool isConnected = false;

  Future<Map<String, dynamic>> joinRoom({
    required String roomCode,
    required String userId,
    required String name,
    required int color,
    required String bio,
    required void Function(Map<String, dynamic> memberRow) onMemberChange,
    required void Function(Map<String, dynamic> messageRow) onMessageInsert,
    required void Function(Map<String, dynamic> eventRow) onEventInsert,
    required void Function(bool connected, String? error) onStatusChange,
  }) async {
    await disconnect();
    _roomCode = roomCode;
    _userId = userId;

    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultExpires = now + 24 * 60 * 60 * 1000;

    // 1. Ensure room exists (ignore if already created)
    await _client.from('chikaku_rooms').upsert(
      {
        'code': roomCode,
        'expires_at': defaultExpires,
        'created_at': now,
      },
      onConflict: 'code',
      ignoreDuplicates: true,
    );

    final roomRow = await _client
        .from('chikaku_rooms')
        .select('expires_at')
        .eq('code', roomCode)
        .maybeSingle();

    final expiresAt =
        (roomRow?['expires_at'] as num?)?.toInt() ?? defaultExpires;

    // 2. Upsert self into chikaku_members
    await _client.from('chikaku_members').upsert(
      {
        'room_code': roomCode,
        'user_id': userId,
        'name': name,
        'color': color,
        'bio': bio,
        'online': true,
        'last_seen': now,
      },
      onConflict: 'room_code,user_id',
    );

    // 3. Fetch existing other members
    final memberRows = await _client
        .from('chikaku_members')
        .select()
        .eq('room_code', roomCode)
        .neq('user_id', userId);

    // 4. Fetch recent messages (last 80)
    final msgRows = await _client
        .from('chikaku_messages')
        .select()
        .eq('room_code', roomCode)
        .order('timestamp', ascending: false)
        .limit(80);

    // 5. Subscribe to Realtime changes
    _channel = _client.channel('chikaku_room_$roomCode');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chikaku_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_code',
            value: roomCode,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            if (row['user_id'] == _userId) return;
            onMemberChange(Map<String, dynamic>.from(row));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chikaku_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_code',
            value: roomCode,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            if (row['sender_id'] == _userId) return;
            onMessageInsert(Map<String, dynamic>.from(row));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chikaku_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_code',
            value: roomCode,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            if (row['sender_id'] == _userId) return;
            onEventInsert(Map<String, dynamic>.from(row));
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            isConnected = true;
            onStatusChange(true, null);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            isConnected = false;
            onStatusChange(
              false,
              error?.toString() ?? 'Koneksi Realtime terputus',
            );
          }
        });

    isConnected = true;
    onStatusChange(true, null);

    return {
      'expiresAt': expiresAt,
      'members': memberRows
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      'history': msgRows
          .reversed
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    };
  }

  Future<void> updateLocation({
    required String name,
    required int color,
    required String bio,
    required Map<String, dynamic> location,
  }) async {
    if (_roomCode == null || _userId == null) return;
    await _client.from('chikaku_members').upsert(
      {
        'room_code': _roomCode,
        'user_id': _userId,
        'name': name,
        'color': color,
        'bio': bio,
        'online': true,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
        'location': location,
      },
      onConflict: 'room_code,user_id',
    );
  }

  Future<void> sendMessage({
    required String id,
    required String type,
    required String senderName,
    required int senderColor,
    String? text,
    String? audioBase64,
    String? imageBase64,
    int durationMs = 0,
    required int timestamp,
  }) async {
    if (_roomCode == null || _userId == null) return;
    await _client.from('chikaku_messages').insert({
      'id': id,
      'room_code': _roomCode,
      'type': type,
      'sender_id': _userId,
      'sender_name': senderName,
      'sender_color': senderColor,
      'text': text,
      'audio_base64': audioBase64,
      'image_base64': imageBase64,
      'duration_ms': durationMs,
      'timestamp': timestamp,
    });
  }

  Future<void> sendEvent({
    required String type,
    required String senderName,
    String? emoji,
    String? label,
    String? camera,
  }) async {
    if (_roomCode == null || _userId == null) return;
    await _client.from('chikaku_events').insert({
      'room_code': _roomCode,
      'type': type,
      'sender_id': _userId,
      'sender_name': senderName,
      'emoji': emoji,
      'label': label,
      'camera': camera,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> extendSession() async {
    final newExpires =
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;
    if (_roomCode != null) {
      await _client
          .from('chikaku_rooms')
          .update({'expires_at': newExpires})
          .eq('code', _roomCode!);
    }
    return newExpires;
  }

  Future<void> setOffline() async {
    if (_roomCode == null || _userId == null) return;
    try {
      await _client
          .from('chikaku_members')
          .update({
            'online': false,
            'last_seen': DateTime.now().millisecondsSinceEpoch,
          })
          .eq('room_code', _roomCode!)
          .eq('user_id', _userId!);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    isConnected = false;
    if (_channel != null) {
      try {
        await _client.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _client.dispose();
  }
}
