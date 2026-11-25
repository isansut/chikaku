import 'package:flutter/material.dart';

import '../services/chikaku_controller.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final ChikakuController controller;

  const ProfileScreen({super.key, required this.controller});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _statusTextCtrl;
  late int _selectedColor;
  late String _statusEmoji;

  static const List<int> _avatarColors = [
    0xFF5B4CF5,
    0xFFFF5A79,
    0xFF10B981,
    0xFFF59E0B,
    0xFF0EA5E9,
    0xFFEC4899,
  ];
  static const List<String> _emojis = ['📍', '🚗', '🏠', '☕', '💼', '❤️', '😴'];

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _nameCtrl = TextEditingController(text: c.userName);
    _bioCtrl = TextEditingController(text: c.userBio);
    _statusTextCtrl = TextEditingController(text: c.myStatusText);
    _selectedColor = c.userColor;
    _statusEmoji = c.myStatusEmoji;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _statusTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.controller.updateProfile(
      name: _nameCtrl.text,
      color: _selectedColor,
      bio: _bioCtrl.text,
      statusEmoji: _statusEmoji,
      statusText: _statusTextCtrl.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profil berhasil diperbarui!'),
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
    final initial =
        _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Saya',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: Color(_selectedColor),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$_statusEmoji ${_statusTextCtrl.text}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${c.userId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Identitas Tampil di Grup & Peta',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Nama Panggilan',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bioCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bio Singkat',
                      hintText: 'Mis. Lagi di kampus / Anak kopi',
                      prefixIcon: Icon(Icons.info_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Warna Pin & Nama Chat',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _avatarColors.map((col) {
                      final sel = col == _selectedColor;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = col),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Color(col),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sel
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: sel
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Status Live Sekarang',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: _emojis.map((e) {
                      return ChoiceChip(
                        label: Text(e, style: const TextStyle(fontSize: 18)),
                        selected: e == _statusEmoji,
                        onSelected: (_) => setState(() => _statusEmoji = e),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _statusTextCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Teks Status',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          FilledButton.icon(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Simpan Profil',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
