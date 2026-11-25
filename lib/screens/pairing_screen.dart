import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chikaku_controller.dart';
import '../theme/app_theme.dart';

class PairingScreen extends StatefulWidget {
  final ChikakuController controller;

  const PairingScreen({super.key, required this.controller});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _nameCtrl = TextEditingController();
  final _joinCodeCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  late String _createdCode;
  bool _isJoinMode = false; // false = Buat Room, true = Gabung Room
  int _selectedColor = 0xFF5B4CF5;
  bool _isJoining = false;

  static const List<int> _avatarColors = [
    0xFF5B4CF5, // Indigo
    0xFFFF5A79, // Coral
    0xFF10B981, // Emerald
    0xFFF59E0B, // Amber
    0xFF0EA5E9, // Sky
    0xFFEC4899, // Pink
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.controller.userName;
    _createdCode = widget.controller.roomCode.isNotEmpty
        ? widget.controller.roomCode
        : widget.controller.generateRoomCode();
    _urlCtrl.text = widget.controller.serverUrl;
    _selectedColor = widget.controller.userColor;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _joinCodeCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteRoomCode() async {
    final clip = await Clipboard.getData('text/plain');
    final text = (clip?.text ?? '').trim().toUpperCase();
    if (text.isEmpty) {
      _showSnack('Clipboard kosong, salin kode dari HP pasanganmu dulu ya');
      return;
    }
    setState(() {
      _joinCodeCtrl.text = text;
    });
    _showSnack('Kode "$text" berhasil ditempel!');
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final code = _isJoinMode
        ? _joinCodeCtrl.text.trim().toUpperCase()
        : _createdCode.trim().toUpperCase();
    final url = _urlCtrl.text.trim();

    if (name.isEmpty) {
      _showSnack('Isi nama panggilan kamu dulu ya');
      return;
    }
    if (code.length < 4) {
      _showSnack(_isJoinMode
          ? 'Tempel atau ketik kode room dari pasanganmu (min. 4 karakter)'
          : 'Kode room minimal 4 karakter');
      return;
    }
    if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      _showSnack('URL server harus diawali ws:// atau wss://');
      return;
    }

    setState(() => _isJoining = true);
    await widget.controller.saveAndJoin(
      name: name,
      color: _selectedColor,
      code: code,
      url: url,
    );
    if (mounted) setState(() => _isJoining = false);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Hero Header
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chikaku',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Live Share 24 Jam • Grup & Berdua',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Pantau jarak & jejak rute 24 jam, kirim voice note, chat, dan notifikasi colek berdua.',
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

              // Profile Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. Profil Kamu',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Nama panggilan (mis. Ihsan)',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Warna Pin Peta',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _avatarColors.map((c) {
                        final selected = c == _selectedColor;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? theme.colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: Color(c).withValues(alpha: 0.4),
                                        blurRadius: 10,
                                      )
                                    ]
                                  : null,
                            ),
                            child: selected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Room Pairing Card (Clear Buat vs Gabung + Paste)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '2. Koneksi Grup / Room',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.add_circle_outline_rounded),
                          label: Text('Buat Room'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.login_rounded),
                          label: Text('Gabung / Paste'),
                        ),
                      ],
                      selected: {_isJoinMode},
                      onSelectionChanged: (s) =>
                          setState(() => _isJoinMode = s.first),
                    ),
                    const SizedBox(height: 16),
                    if (!_isJoinMode) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'KODE ROOM KAMU',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _createdCode,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _createdCode = widget.controller
                                          .generateRoomCode();
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Acak'),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: _createdCode));
                                    _showSnack(
                                        'Kode "$_createdCode" disalin! Kirim ke pasanganmu.');
                                  },
                                  style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.primary),
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('Salin Kode'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Kirim kode ini ke pasanganmu, lalu pasanganmu pilih tab "Gabung / Paste".',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: _joinCodeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'KODE ROOM',
                          prefixIcon: Icon(Icons.vpn_key_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: _pasteRoomCode,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.content_paste_go_rounded),
                        label: const Text(
                          'Tempel Kode dari Clipboard (Paste)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Server URL Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '3. Server WebSocket',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'URL Server',
                        hintText: 'ws://192.168.1.10:3000',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pastikan kedua HP memakai URL server yang sama (mis. ws://IP_SERVER:3000 atau wss://...).',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Submit Button
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _isJoining ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isJoining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.radar_rounded),
                  label: Text(
                    _isJoining
                        ? 'Menghubungkan...'
                        : (_isJoinMode
                            ? 'Gabung & Share Live 24 Jam'
                            : 'Mulai Share Live 24 Jam'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
