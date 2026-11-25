import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';

class PermissionGateScreen extends StatefulWidget {
  final Widget child;

  const PermissionGateScreen({super.key, required this.child});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _allGranted = false;

  bool _locGranted = false;
  bool _gpsEnabled = true;
  bool _camGranted = false;
  bool _micGranted = false;
  bool _notifGranted = false;
  bool _anyPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) {
        setState(() {
          _allGranted = true;
          _checking = false;
        });
      }
      return;
    }

    try {
      final loc = await Permission.location.status;
      final cam = await Permission.camera.status;
      final mic = await Permission.microphone.status;
      final notif = await Permission.notification.status;
      final gpsOn = await Geolocator.isLocationServiceEnabled();

      final allOk = loc.isGranted &&
          cam.isGranted &&
          mic.isGranted &&
          notif.isGranted &&
          gpsOn;

      final permDenied = loc.isPermanentlyDenied ||
          cam.isPermanentlyDenied ||
          mic.isPermanentlyDenied ||
          notif.isPermanentlyDenied;

      if (mounted) {
        setState(() {
          _locGranted = loc.isGranted;
          _gpsEnabled = gpsOn;
          _camGranted = cam.isGranted;
          _micGranted = mic.isGranted;
          _notifGranted = notif.isGranted;
          _anyPermanentlyDenied = permDenied;
          _allGranted = allOk;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _allGranted = true;
          _checking = false;
        });
      }
    }
  }

  Future<void> _requestMissing() async {
    if (!_gpsEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    await [
      Permission.location,
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();

    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }

    await _checkAllPermissions();

    if (!_allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.partnerCoral,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            _anyPermanentlyDenied
                ? 'Izin masih ditolak permanen. Tap "Buka Pengaturan HP" lalu aktifkan semua izin ya!'
                : 'Masih ada izin yang belum diaktifkan. Mohon klik "Izinkan / Allow" semua ya!',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_allGranted) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_user_rounded,
                        color: Colors.white, size: 34),
                    SizedBox(height: 12),
                    Text(
                      'Aktifkan Izin Aplikasi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Agar Chikaku bisa berbagi lokasi 24 jam, kirim foto kamera, voice note, dan notifikasi chat, aktifkan semua izin di bawah ini dulu ya:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _PermissionTile(
                icon: Icons.location_on_rounded,
                title: 'Lokasi & GPS HP',
                subtitle: !_gpsEnabled
                    ? 'GPS HP masih mati — aktifkan lokasi di HP kamu'
                    : 'Wajib untuk share live 24 jam & hitung jarak',
                granted: _locGranted && _gpsEnabled,
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _PermissionTile(
                icon: Icons.camera_alt_rounded,
                title: 'Kamera',
                subtitle: 'Untuk ambil & kirim foto kamera depan/belakang',
                granted: _camGranted,
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _PermissionTile(
                icon: Icons.mic_rounded,
                title: 'Mikrofon',
                subtitle: 'Untuk rekam dan kirim Voice Note ke pasangan',
                granted: _micGranted,
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _PermissionTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notifikasi Pop-up',
                subtitle: 'Agar chat, VN, & colek tetap muncul saat app ditutup',
                granted: _notifGranted,
                isDark: isDark,
              ),

              if (_anyPermanentlyDenied) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.warningAmber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.warningAmber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cara Mengaktifkan Manual:',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '1. Tap tombol "Buka Pengaturan HP" di bawah.\n'
                        '2. Pilih menu "Izin" atau "Permissions".\n'
                        '3. Izinkan Lokasi, Kamera, Mikrofon, & Notifikasi.\n'
                        '4. Kembali ke aplikasi Chikaku.',
                        style: TextStyle(fontSize: 12.5, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _requestMissing,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: Icon(!_gpsEnabled
                    ? Icons.gps_fixed_rounded
                    : Icons.check_circle_outline_rounded),
                label: Text(
                  !_gpsEnabled
                      ? 'Nyalakan GPS HP Sekarang'
                      : 'Izinkan Semua Sekarang',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (_anyPermanentlyDenied) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: openAppSettings,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text(
                    'Buka Pengaturan HP',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final bool isDark;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: granted
              ? AppTheme.liveGreen.withValues(alpha: 0.45)
              : AppTheme.partnerCoral.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (granted ? AppTheme.liveGreen : AppTheme.primary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: granted ? AppTheme.liveGreen : AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (granted ? AppTheme.liveGreen : AppTheme.partnerCoral)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              granted ? 'Aktif ✓' : 'Wajib',
              style: TextStyle(
                color: granted ? AppTheme.liveGreen : AppTheme.partnerCoral,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
