import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chikaku_controller.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final ChikakuController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _statusTextCtrl;
  late int _interval;
  late String _statusEmoji;

  static const List<String> _emojis = ['📍', '🚗', '🏠', '☕', '💼', '❤️', '😴'];

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _nameCtrl = TextEditingController(text: c.userName);
    _urlCtrl = TextEditingController(text: c.serverUrl);
    _statusTextCtrl = TextEditingController(text: c.myStatusText);
    _interval = c.updateIntervalSeconds;
    _statusEmoji = c.myStatusEmoji;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _statusTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.controller.updateSettings(
      name: _nameCtrl.text,
      url: _urlCtrl.text,
      intervalSeconds: _interval,
      statusEmoji: _statusEmoji,
      statusText: _statusTextCtrl.text.trim().isEmpty
          ? 'Live 24 Jam'
          : _statusTextCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pengaturan disimpan!'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pengaturan Chikaku',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Room info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.vpn_key_rounded,
                        color: AppTheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Kode Room Aktif',
                            style: TextStyle(fontSize: 12)),
                        Text(
                          c.roomCode,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          'Sisa waktu 24 jam: ${c.remainingSessionText}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.liveGreen),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: c.roomCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kode room disalin!')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Profile & Status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Profil & Status Kamu',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Panggilan',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: _emojis.map((e) {
                      final selected = e == _statusEmoji;
                      return ChoiceChip(
                        label: Text(e, style: const TextStyle(fontSize: 18)),
                        selected: selected,
                        onSelected: (_) => setState(() => _statusEmoji = e),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _statusTextCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Status Singkat',
                      hintText: 'Lagi di jalan / Di rumah',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // GPS & Connection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Koneksi & Akurasi GPS',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'WebSocket Server URL',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Interval Update Lokasi',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2 dtk (Akurat)')),
                      ButtonSegment(value: 5, label: Text('5 dtk (Normal)')),
                      ButtonSegment(value: 15, label: Text('15 dtk (Hemat)')),
                    ],
                    selected: {_interval},
                    onSelectionChanged: (s) =>
                        setState(() => _interval = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Simpan Perubahan',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              c.extend24Hours();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Durasi Share Live diperpanjang 24 jam!')),
              );
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.update_rounded),
            label: const Text('Reset / Perpanjang 24 Jam'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => c.sendTestNotification(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Tes Notifikasi & Suara'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final update = await c.checkForUpdate();
              if (!context.mounted) return;
              if (update == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Chikaku v${c.appVersion} (${c.appBuildNumber}) sudah versi terbaru!'),
                  ),
                );
                return;
              }
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Update Tersedia v${update['version']}'),
                  content: Text(
                    '${update['notes'] ?? 'Versi baru siap diunduh.'}\n\n'
                    'Setelah download selesai, tinggal tap file chikaku.apk untuk update langsung tanpa hapus aplikasi lama.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Nanti'),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        c.openUpdateDownload(update['apkUrl'] as String);
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download & Update'),
                    ),
                  ],
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.system_update_rounded),
            label: Text(
                'Cek Update Aplikasi (v${c.appVersion} • Build ${c.appBuildNumber})'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              await c.leaveRoom();
              if (context.mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.partnerCoral),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Keluar dari Room'),
          ),
        ],
      ),
    );
  }
}
