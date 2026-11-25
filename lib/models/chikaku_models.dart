import 'package:latlong2/latlong.dart';

class UserLocation {
  final double lat;
  final double lng;
  final double speed;
  final double accuracy;
  final int battery;
  final String statusEmoji;
  final String statusText;
  final int timestamp;

  const UserLocation({
    required this.lat,
    required this.lng,
    this.speed = 0,
    this.accuracy = 0,
    this.battery = 100,
    this.statusEmoji = '📍',
    this.statusText = 'Live 24 Jam',
    required this.timestamp,
  });

  LatLng get latLng => LatLng(lat, lng);

  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      battery: (json['battery'] as num?)?.toInt() ?? 100,
      statusEmoji: json['statusEmoji'] as String? ?? '📍',
      statusText: json['statusText'] as String? ?? 'Live 24 Jam',
      timestamp: (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'accuracy': accuracy,
        'battery': battery,
        'statusEmoji': statusEmoji,
        'statusText': statusText,
        'timestamp': timestamp,
      };
}

class RoomMember {
  final String userId;
  final String name;
  final int color;
  final String bio;
  final bool online;
  final int lastSeen;
  final UserLocation? location;

  const RoomMember({
    required this.userId,
    required this.name,
    required this.color,
    this.bio = '',
    required this.online,
    required this.lastSeen,
    this.location,
  });

  RoomMember copyWith({
    String? name,
    int? color,
    String? bio,
    bool? online,
    int? lastSeen,
    UserLocation? location,
  }) {
    return RoomMember(
      userId: userId,
      name: name ?? this.name,
      color: color ?? this.color,
      bio: bio ?? this.bio,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
      location: location ?? this.location,
    );
  }

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      userId: json['userId'] as String? ?? 'member',
      name: json['name'] as String? ?? 'Anggota',
      color: (json['color'] as num?)?.toInt() ?? 0xFFFF5A79,
      bio: json['bio'] as String? ?? '',
      online: json['online'] as bool? ?? false,
      lastSeen: (json['lastSeen'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      location: json['location'] != null
          ? UserLocation.fromJson(
              Map<String, dynamic>.from(json['location'] as Map))
          : null,
    );
  }
}

enum ChatMessageType { chat, voiceNote, image }

class ChatMessage {
  final String id;
  final ChatMessageType type;
  final String senderId;
  final String senderName;
  final int senderColor;
  final String? text;
  final String? audioBase64;
  final String? localAudioPath;
  final String? imageBase64;
  final int durationMs;
  final int timestamp;
  final bool isMe;

  const ChatMessage({
    required this.id,
    required this.type,
    required this.senderId,
    required this.senderName,
    this.senderColor = 0xFFFF5A79,
    this.text,
    this.audioBase64,
    this.localAudioPath,
    this.imageBase64,
    this.durationMs = 0,
    required this.timestamp,
    required this.isMe,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String myUserId) {
    final senderId = json['senderId'] as String? ?? '';
    final typeStr = json['type'] as String? ?? 'chat';
    final msgType = typeStr == 'voice_note'
        ? ChatMessageType.voiceNote
        : (typeStr == 'image' ? ChatMessageType.image : ChatMessageType.chat);
    return ChatMessage(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: msgType,
      senderId: senderId,
      senderName: json['senderName'] as String? ?? 'Teman',
      senderColor: (json['senderColor'] as num?)?.toInt() ?? 0xFFFF5A79,
      text: json['text'] as String?,
      audioBase64: json['audioBase64'] as String?,
      imageBase64: json['imageBase64'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      isMe: senderId == myUserId,
    );
  }
}

class NudgeEvent {
  final String senderName;
  final String emoji;
  final String label;
  final int timestamp;

  const NudgeEvent({
    required this.senderName,
    required this.emoji,
    required this.label,
    required this.timestamp,
  });
}

class PhotoRequestEvent {
  final String senderName;
  final bool useFrontCamera;
  final int timestamp;

  const PhotoRequestEvent({
    required this.senderName,
    required this.useFrontCamera,
    required this.timestamp,
  });
}
