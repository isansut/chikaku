import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/chikaku_models.dart';
import '../services/chikaku_controller.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final ChikakuController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();

  bool _darkMap = false;
  bool _hasCenteredInitially = false;
  StreamSubscription<NudgeEvent>? _nudgeSub;
  StreamSubscription<PhotoRequestEvent>? _photoReqSub;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _nudgeSub = widget.controller.nudgeStream.listen((event) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.primary,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              Text(event.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${event.senderName}: ${event.label}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    });

    _photoReqSub = widget.controller.photoRequestStream.listen((req) {
      if (!mounted) return;
      final camLabel = req.useFrontCamera ? 'Kamera Depan' : 'Kamera Belakang';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('📸 ${req.senderName} Minta Foto'),
          content: Text(
            '${req.senderName} meminta kamu mengambil foto menggunakan $camLabel untuk dikirim ke chat.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Nanti'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await widget.controller
                    .captureAndSendPhoto(useFrontCamera: req.useFrontCamera);
              },
              icon: const Icon(Icons.camera_alt_rounded),
              label: Text('Buka $camLabel'),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    _nudgeSub?.cancel();
    _photoReqSub?.cancel();
    _pulseCtrl.dispose();
    _chatCtrl.dispose();
    _chatScrollCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _fitBoth() {
    final c = widget.controller;
    final pts = <LatLng>[];
    if (c.myLocation != null) pts.add(c.myLocation!.latLng);
    for (final m in c.members.values) {
      if (m.location != null) pts.add(m.location!.latLng);
    }
    if (pts.length >= 2) {
      final bounds = LatLngBounds.fromPoints(pts);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(60, 190, 60, 140),
          maxZoom: 16.5,
        ),
      );
    } else if (pts.length == 1) {
      _mapController.move(pts.first, 15.5);
    }
  }

  void _focusPoint(LatLng? point) {
    if (point == null) return;
    _mapController.move(point, 16.0);
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    widget.controller.sendTextMessage(text);
    _chatCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openChatModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (_, _) => _ChatModalSheet(
                controller: widget.controller,
                chatScrollController: _chatScrollCtrl,
                chatCtrl: _chatCtrl,
                onSendChat: _sendChat,
                onOpenCamera: () => _showCameraOptions(ctx, widget.controller),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCameraOptions(BuildContext context, ChikakuController c) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kamera & Minta Foto',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0E7FF),
                  child: Icon(Icons.camera_front_rounded,
                      color: AppTheme.primary),
                ),
                title: const Text('Kirim Foto (Kamera Depan)'),
                subtitle: const Text('Ambil selfie dan kirim langsung ke chat'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.captureAndSendPhoto(useFrontCamera: true);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0E7FF),
                  child: Icon(Icons.camera_rear_rounded,
                      color: AppTheme.primary),
                ),
                title: const Text('Kirim Foto (Kamera Belakang)'),
                subtitle: const Text('Ambil foto sekitar dan kirim ke chat'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.captureAndSendPhoto(useFrontCamera: false);
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFE4E6),
                  child: Icon(Icons.face_retouching_natural_rounded,
                      color: AppTheme.partnerCoral),
                ),
                title: const Text('Minta Anggota Foto (Kamera Depan)'),
                subtitle: const Text('Kirim notifikasi ke grup untuk selfie'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.requestPartnerPhoto(useFrontCamera: true);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Permintaan foto kamera depan dikirim ke grup!')),
                  );
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFE4E6),
                  child: Icon(Icons.photo_camera_back_rounded,
                      color: AppTheme.partnerCoral),
                ),
                title: const Text('Minta Anggota Foto (Kamera Belakang)'),
                subtitle:
                    const Text('Kirim notifikasi ke grup untuk foto sekitar'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.requestPartnerPhoto(useFrontCamera: false);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Permintaan foto kamera belakang dikirim ke grup!')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNudgeMenu(BuildContext context, ChikakuController c) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kirim Colek / Ping Cepat',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickPingTile(
                    emoji: '👋',
                    label: 'Colek!',
                    onTap: () {
                      Navigator.pop(ctx);
                      c.sendNudge('👋', 'Colek kamu!');
                    },
                  ),
                  _QuickPingTile(
                    emoji: '❤️',
                    label: 'Kangen',
                    onTap: () {
                      Navigator.pop(ctx);
                      c.sendNudge('❤️', 'Kangen nih!');
                    },
                  ),
                  _QuickPingTile(
                    emoji: '🚗',
                    label: 'Lagi OTW',
                    onTap: () {
                      Navigator.pop(ctx);
                      c.sendNudge('🚗', 'Lagi otw nih!');
                    },
                  ),
                  _QuickPingTile(
                    emoji: '📍',
                    label: 'Dimana?',
                    onTap: () {
                      Navigator.pop(ctx);
                      c.sendNudge('📍', 'Posisi dimana sekarang?');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final myLatLng =
            c.myLocation?.latLng ?? const LatLng(-6.175392, 106.827153);
        final selectedLatLng = c.selectedMember?.location?.latLng;

        if (!_hasCenteredInitially && c.myLocation != null) {
          _hasCenteredInitially = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitBoth());
        }

        const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // 1. Full-Screen Live OpenStreetMap
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: myLatLng,
                  initialZoom: 15.0,
                  minZoom: 3,
                  maxZoom: 19,
                ),
                children: [
                  TileLayer(
                    urlTemplate: tileUrl,
                    userAgentPackageName: 'com.chikaku.app.chikaku',
                    tileBuilder: _darkMap
                        ? (context, tileWidget, tile) => ColorFiltered(
                              colorFilter: const ColorFilter.matrix(<double>[
                                -0.9, 0, 0, 0, 230,
                                0, -0.9, 0, 0, 230,
                                0, 0, -0.9, 0, 240,
                                0, 0, 0, 1, 0,
                              ]),
                              child: tileWidget,
                            )
                        : null,
                  ),
                  if (c.showTrail && c.myTrail.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: c.myTrail,
                          strokeWidth: 4,
                          color: Color(c.userColor).withValues(alpha: 0.45),
                        ),
                      ],
                    ),
                  if (c.showTrail && c.memberTrails.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        for (final entry in c.memberTrails.entries)
                          if (entry.value.length >= 2)
                            Polyline(
                              points: entry.value,
                              strokeWidth: 4,
                              color: Color(
                                      c.members[entry.key]?.color ?? 0xFFFF5A79)
                                  .withValues(alpha: 0.55),
                            ),
                      ],
                    ),
                  if (c.connectionLinePoints.length == 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: c.connectionLinePoints,
                          strokeWidth: 3.5,
                          color: AppTheme.primary.withValues(alpha: 0.75),
                          pattern: const StrokePattern.dotted(spacingFactor: 2),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (c.myLocation != null)
                        Marker(
                          point: c.myLocation!.latLng,
                          width: 115,
                          height: 92,
                          child: _UserPin(
                            name: '${c.userName} (Kamu)',
                            color: Color(c.userColor),
                            battery: c.myLocation!.battery,
                            emoji: c.myLocation!.statusEmoji,
                            pulse: _pulseCtrl,
                          ),
                        ),
                      for (final m in c.members.values)
                        if (m.location != null)
                          Marker(
                            point: m.location!.latLng,
                            width: 120,
                            height: 92,
                            child: GestureDetector(
                              onTap: () {
                                c.selectMember(m.userId);
                                _focusPoint(m.location!.latLng);
                              },
                              child: _UserPin(
                                name: m.name,
                                color: Color(m.color),
                                battery: m.location!.battery,
                                emoji: m.location!.statusEmoji,
                                pulse: _pulseCtrl,
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
              ),

              // 2. Top Floating Status & Distance Card
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: _TopStatusCard(
                    controller: c,
                    onProfileTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(controller: c),
                        ),
                      );
                    },
                    onSettingsTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(controller: c),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 3. Right Floating Map Controls
              Positioned(
                right: 14,
                bottom: 108,
                child: Column(
                  children: [
                    _MapActionButton(
                      icon: Icons.fit_screen_rounded,
                      tooltip: 'Lihat Semua',
                      onTap: _fitBoth,
                    ),
                    const SizedBox(height: 8),
                    _MapActionButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Lokasi Kamu',
                      onTap: () => _focusPoint(c.myLocation?.latLng),
                    ),
                    const SizedBox(height: 8),
                    _MapActionButton(
                      icon: Icons.favorite_rounded,
                      iconColor: AppTheme.partnerCoral,
                      tooltip: 'Lokasi Anggota Terpilih',
                      onTap: () => _focusPoint(selectedLatLng),
                    ),
                    const SizedBox(height: 8),
                    _MapActionButton(
                      icon: Icons.route_rounded,
                      iconColor: c.showTrail ? AppTheme.primary : null,
                      tooltip: 'Jejak Rute',
                      onTap: c.toggleTrail,
                    ),
                    const SizedBox(height: 8),
                    _MapActionButton(
                      icon: _darkMap
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      tooltip: 'Tema Peta',
                      onTap: () => setState(() => _darkMap = !_darkMap),
                    ),
                  ],
                ),
              ),

              // 4. Floating Bottom Taskbar (Dock)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 14,
                child: _FloatingTaskbar(
                  messageCount: c.messages.length,
                  onChatTap: _openChatModal,
                  onCameraTap: () => _showCameraOptions(context, c),
                  onNudgeTap: () => _showNudgeMenu(context, c),
                  onMapsTap: () async {
                    final ok = await c.openPartnerInGoogleMaps();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Lokasi anggota belum tersedia untuk navigasi'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FloatingTaskbar extends StatelessWidget {
  final int messageCount;
  final VoidCallback onChatTap;
  final VoidCallback onCameraTap;
  final VoidCallback onNudgeTap;
  final VoidCallback onMapsTap;

  const _FloatingTaskbar({
    required this.messageCount,
    required this.onChatTap,
    required this.onCameraTap,
    required this.onNudgeTap,
    required this.onMapsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (isDark ? AppTheme.surfaceDark : Colors.white)
            .withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _TaskbarItem(
            icon: Icons.chat_bubble_rounded,
            label: 'Chat',
            color: AppTheme.primary,
            badge: messageCount > 0 ? '$messageCount' : null,
            highlighted: true,
            onTap: onChatTap,
          ),
          _TaskbarItem(
            icon: Icons.camera_alt_rounded,
            label: 'Kamera',
            color: const Color(0xFF0EA5E9),
            onTap: onCameraTap,
          ),
          _TaskbarItem(
            icon: Icons.waving_hand_rounded,
            label: 'Colek',
            color: AppTheme.partnerCoral,
            onTap: onNudgeTap,
          ),
          _TaskbarItem(
            icon: Icons.directions_rounded,
            label: 'Rute',
            color: AppTheme.liveGreen,
            onTap: onMapsTap,
          ),
        ],
      ),
    );
  }
}

class _TaskbarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;
  final bool highlighted;
  final VoidCallback onTap;

  const _TaskbarItem({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted
              ? color.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 22),
                if (badge != null)
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.partnerCoral,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: highlighted ? color : null,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickPingTile extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _QuickPingTile({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _UserPin extends StatelessWidget {
  final String name;
  final Color color;
  final int battery;
  final String emoji;
  final AnimationController pulse;

  const _UserPin({
    required this.name,
    required this.color,
    required this.battery,
    required this.emoji,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF141625),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (_, _) {
                  final val = pulse.value;
                  return Container(
                    width: 28 + (val * 20),
                    height: 28 + (val * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: (1 - val) * 0.35),
                    ),
                  );
                },
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141625),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$battery%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopStatusCard extends StatelessWidget {
  final ChikakuController controller;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;

  const _TopStatusCard({
    required this.controller,
    required this.onProfileTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = controller;
    final p = c.selectedMember;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isDark ? AppTheme.surfaceDark : Colors.white)
            .withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: c.roomCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Kode room "${c.roomCode}" disalin!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.isConnected
                              ? AppTheme.liveGreen
                              : AppTheme.warningAmber,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        c.isConnected
                            ? 'LIVE • ${c.roomCode}'
                            : 'SYNC • ${c.roomCode}',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded,
                          size: 12, color: AppTheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.liveGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'NONSTOP',
                  style: TextStyle(
                    color: AppTheme.liveGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: c.togglePauseSharing,
                visualDensity: VisualDensity.compact,
                tooltip: c.isSharingPaused ? 'Lanjutkan GPS' : 'Jeda GPS',
                icon: Icon(
                  c.isSharingPaused
                      ? Icons.play_circle_fill_rounded
                      : Icons.pause_circle_outline_rounded,
                  color: c.isSharingPaused
                      ? AppTheme.warningAmber
                      : theme.iconTheme.color,
                ),
              ),
              IconButton(
                onPressed: onProfileTap,
                visualDensity: VisualDensity.compact,
                tooltip: 'Profil Saya',
                icon: const Icon(Icons.account_circle_outlined),
              ),
              IconButton(
                onPressed: onSettingsTap,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(p?.color ?? 0xFFFF5A79).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  p != null && p.name.isNotEmpty
                      ? p.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Color(p?.color ?? 0xFFFF5A79),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          p?.name ?? 'Menunggu anggota...',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        if (p?.location != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '🔋 ${p!.location!.battery}%',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p?.location != null
                          ? '${p!.location!.statusEmoji} ${p.location!.statusText} • ${c.formattedEta}'
                          : (c.connectionError ??
                              'Bagikan kode ${c.roomCode} ke teman/pasangan'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text(
                      'JARAK',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      c.formattedDistance,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (c.members.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: c.members.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, idx) {
                  final m = c.members.values.elementAt(idx);
                  final isSel = p?.userId == m.userId;
                  return ChoiceChip(
                    label: Text(
                      '${m.name} (${c.formattedDistanceTo(m)})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: isSel,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => c.selectMember(m.userId),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String tooltip;
  final VoidCallback onTap;

  const _MapActionButton({
    required this.icon,
    this.iconColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppTheme.surfaceDark : Colors.white,
      elevation: 4,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, color: iconColor, size: 21),
      ),
    );
  }
}

class _ChatModalSheet extends StatelessWidget {
  final ChikakuController controller;
  final ScrollController chatScrollController;
  final TextEditingController chatCtrl;
  final VoidCallback onSendChat;
  final VoidCallback onOpenCamera;

  const _ChatModalSheet({
    required this.controller,
    required this.chatScrollController,
    required this.chatCtrl,
    required this.onSendChat,
    required this.onOpenCamera,
  });

  static const List<String> _quickReplies = [
    'Lagi di jalan 🚗',
    'Udah sampai?',
    'Hati-hati ya ❤️',
    'Bentar lagi nyampe',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = controller;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                const Text(
                  'Obrolan Grup & Voice Note',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${c.messages.length}',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Messages List (always opens at newest message + floating scroll button)
          Expanded(
            child: c.messages.isEmpty
                ? Center(
                    child: Text(
                      'Belum ada pesan.\nKirim chat, foto, atau voice note sekarang!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: chatScrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        itemCount: c.messages.length,
                        itemBuilder: (context, index) {
                          final msg = c.messages[c.messages.length - 1 - index];
                          return _MessageBubble(
                            message: msg,
                            controller: c,
                          );
                        },
                      ),
                      Positioned(
                        right: 14,
                        bottom: 10,
                        child: AnimatedBuilder(
                          animation: chatScrollController,
                          builder: (_, _) {
                            final showBtn = chatScrollController.hasClients &&
                                chatScrollController.offset > 120;
                            if (!showBtn) return const SizedBox.shrink();
                            return Material(
                              color: AppTheme.primary,
                              elevation: 4,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  chatScrollController.animateTo(
                                    0.0,
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOut,
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.arrow_downward_rounded,
                                          color: Colors.white, size: 16),
                                      SizedBox(width: 4),
                                      Text(
                                        'Terbaru',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),

          // Quick Reply Chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final txt = _quickReplies[idx];
                return ActionChip(
                  label: Text(txt, style: const TextStyle(fontSize: 12)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onPressed: () => c.sendTextMessage(txt),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Input Bar
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: c.isRecording
                  ? _RecordingBar(controller: c)
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: chatCtrl,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => onSendChat(),
                            decoration: const InputDecoration(
                              hintText: 'Tulis pesan...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          onPressed: onOpenCamera,
                          icon: const Icon(Icons.camera_alt_rounded),
                          tooltip: 'Kamera / Minta Foto',
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          onPressed: () async {
                            final ok = await c.startRecording();
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Izinkan akses mikrofon untuk kirim Voice Note'),
                                ),
                              );
                            }
                          },
                          style: IconButton.styleFrom(
                            backgroundColor:
                                AppTheme.partnerCoral.withValues(alpha: 0.14),
                            foregroundColor: AppTheme.partnerCoral,
                          ),
                          icon: const Icon(Icons.mic_rounded),
                          tooltip: 'Rekam Voice Note',
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          onPressed: onSendChat,
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  final ChikakuController controller;

  const _RecordingBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final secs = controller.recordingSeconds;
    final formatted =
        '${(secs ~/ 60).toString().padLeft(1, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.partnerCoral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.partnerCoral.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record,
              color: AppTheme.partnerCoral, size: 16),
          const SizedBox(width: 8),
          Text(
            'Merekam VN... $formatted',
            style: const TextStyle(
              color: AppTheme.partnerCoral,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: controller.cancelRecording,
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: controller.stopAndSendRecording,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.partnerCoral,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Kirim'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final ChikakuController controller;

  const _MessageBubble({
    required this.message,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMe = message.isMe;
    final timeStr = DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(message.timestamp));

    final bgColor = isMe
        ? AppTheme.primary
        : (isDark ? const Color(0xFF25293A) : const Color(0xFFF0F2F8));
    final fgColor = isMe ? Colors.white : theme.colorScheme.onSurface;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              Text(
                message.senderName,
                style: TextStyle(
                  color: Color(message.senderColor),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
            ],
            if (message.type == ChatMessageType.voiceNote)
              _VoiceNoteContent(
                message: message,
                controller: controller,
                fgColor: fgColor,
              )
            else if (message.type == ChatMessageType.image &&
                message.imageBase64 != null)
              _ImageBubbleContent(imageBase64: message.imageBase64!)
            else
              Text(
                message.text ?? '',
                style: TextStyle(color: fgColor, fontSize: 14, height: 1.35),
              ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                color: fgColor.withValues(alpha: 0.65),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceNoteContent extends StatelessWidget {
  final ChatMessage message;
  final ChikakuController controller;
  final Color fgColor;

  const _VoiceNoteContent({
    required this.message,
    required this.controller,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = controller.playingMessageId == message.id;
    final totalMs = message.durationMs > 0 ? message.durationMs : 1000;
    final progress = isPlaying && controller.playbackDuration.inMilliseconds > 0
        ? (controller.playbackPosition.inMilliseconds /
                controller.playbackDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final secs = (totalMs / 1000).ceil();
    final durText =
        '${(secs ~/ 60)}:${(secs % 60).toString().padLeft(2, '0')}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => controller.togglePlayVoiceNote(message),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: fgColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: fgColor,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: isPlaying ? progress : 0,
                backgroundColor: fgColor.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Voice Note • $durText',
              style: TextStyle(
                color: fgColor.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImageBubbleContent extends StatefulWidget {
  final String imageBase64;

  const _ImageBubbleContent({required this.imageBase64});

  @override
  State<_ImageBubbleContent> createState() => _ImageBubbleContentState();
}

class _ImageBubbleContentState extends State<_ImageBubbleContent> {
  late Uint8List _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = base64Decode(widget.imageBase64);
  }

  @override
  void didUpdateWidget(covariant _ImageBubbleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBase64 != widget.imageBase64) {
      _bytes = base64Decode(widget.imageBase64);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                InteractiveViewer(
                  child: Center(
                    child: Image.memory(
                      _bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _bytes,
          width: 210,
          height: 240,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
