import 'package:flutter/material.dart';

/// What the create/edit sheet hands back once the user hits Save.
class ListDraft {
  final String name;
  final String emoji;
  final bool isPublic;
  const ListDraft(this.name, this.emoji, this.isPublic);
}

const _bg = Color(0xFF16161E);
const _field = Color(0xFF1E1E2A);
const _kText = Color(0xFFF0F0F0);
const _muted = Color(0xFF6B6B80);
const _accent = Color(0xFFE8002D);

const _emojiChoices = [
  '🎮', '🩸', '🌍', '⚔️', '📖', '🏆', '👻', '🚀', '🧩', '❤️', '🔥', '⭐'
];

/// The create/edit-a-list sheet: name, icon, and whether it's public.
///
/// Shared by the profile's My Lists section and the "New list" button on a
/// game's Add to List sheet, so making a list is the same act wherever you
/// start it. It carries its own palette rather than the host screen's — the
/// two callers disagree about what `accent` means, and the sheet should look
/// the same in both.
///
/// Returns null if the user backs out.
Future<ListDraft?> showListEditor(
  BuildContext context, {
  required String title,
  String name = '',
  String emoji = '🎮',
  bool isPublic = false,
}) {
  final controller = TextEditingController(text: name);
  var pickedEmoji = emoji;
  var pickedPublic = isPublic;

  return showModalBottomSheet<ListDraft>(
    context: context,
    backgroundColor: _bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          // Keeps the Save button above the keyboard while the name is typed.
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title,
                  style: const TextStyle(
                      color: _kText,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 50,
                style: const TextStyle(color: _kText, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'List name',
                  hintStyle: const TextStyle(color: _muted),
                  counterText: '',
                  filled: true,
                  fillColor: _field,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Icon',
                  style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _emojiChoices.map((e) {
                  final selected = e == pickedEmoji;
                  return GestureDetector(
                    onTap: () => setSheetState(() => pickedEmoji = e),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? _accent.withValues(alpha: 0.15)
                            : _field,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? _accent : Colors.transparent,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: _accent,
                value: pickedPublic,
                onChanged: (v) => setSheetState(() => pickedPublic = v),
                title: const Text('Public list',
                    style: TextStyle(color: _kText, fontSize: 14)),
                subtitle: Text(
                  pickedPublic
                      ? 'Anyone can see this on your profile'
                      : 'Only you can see this',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final typed = controller.text.trim();
                    if (typed.isEmpty) return;
                    Navigator.pop(
                      ctx,
                      ListDraft(typed, pickedEmoji, pickedPublic),
                    );
                  },
                  child: const Text('Save',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
