import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format_duration.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/reading_timer_providers.dart';

/// N2/N5 — writing a note.
///
/// A **page, not a sheet**: the scarce resource while reading isn't speed of
/// entry, it's room to write, and a bottom sheet plus a keyboard is a slot.
/// One screen serves both jobs — jotting mid-session and editing something
/// from weeks ago — because they're the same act; only the header differs.
///
/// While a session is live the clock stays pinned to the top and keeps
/// ticking, so "the timer never paused" is something the reader can *see*
/// rather than a caption they have to trust. Nothing on this page can stop or
/// pause the session: that's the governing rule of the whole feature.
class NotePage extends ConsumerStatefulWidget {
  const NotePage({
    super.key,
    required this.libraryEntryId,
    this.existing,
    this.bookTitle,
    this.sessionId,
    this.sessionStartedAt,
    this.currentPage,
    this.noteIndex,
    this.sessionSummary,
    this.startReadOnly = false,
  });

  final String libraryEntryId;

  /// Set when editing (N5); null when writing a new one (N2).
  final ReadingNote? existing;
  final String? bookTitle;

  /// The live sitting this note belongs to, if any.
  final String? sessionId;
  final DateTime? sessionStartedAt;

  /// Seeds the page field — a note usually concerns where you are.
  final int? currentPage;

  /// "note 3 of this sitting".
  final int? noteIndex;

  /// Pre-formatted provenance for N5's header.
  final String? sessionSummary;

  /// Opening an existing note from the journal is *reading* it, not editing it
  /// — a keyboard shouldn't leap up over a thought you came back to re-read
  /// (owner report, 21 Jul 2026). Edit is one tap away.
  final bool startReadOnly;

  @override
  ConsumerState<NotePage> createState() => _NotePageState();
}

class _NotePageState extends ConsumerState<NotePage> {
  late final TextEditingController _body;
  late final TextEditingController _from;
  late final TextEditingController _to;
  Timer? _clock;
  bool _range = false;
  bool _saving = false;
  late bool _reading = widget.startReadOnly && widget.existing != null;

  bool get _isEditing => widget.existing != null;
  bool get _isLive => widget.sessionStartedAt != null && !_isEditing;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _body = TextEditingController(text: existing?.body ?? '');
    _from = TextEditingController(
      text: (existing?.pageStart ?? (existing == null ? widget.currentPage : null))?.toString() ??
          '',
    );
    _to = TextEditingController(text: existing?.pageEnd?.toString() ?? '');
    _range = existing?.pageEnd != null;
    // Only tick while a sitting is actually live — an edit has no clock.
    if (_isLive) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _body.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty || _saving) return;
    setState(() => _saving = true);
    final repo = await ref.read(readingNotesRepositoryProvider.future);
    final from = int.tryParse(_from.text.trim());
    final to = _range ? int.tryParse(_to.text.trim()) : null;
    if (_isEditing) {
      await repo.edit(widget.existing!.id, body: body, pageStart: from, pageEnd: to);
    } else {
      await repo.add(
        libraryEntryId: widget.libraryEntryId,
        body: body,
        sessionId: widget.sessionId,
        pageStart: from,
        pageEnd: to,
      );
    }
    Haptics.success();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(l10n.noteDeleteConfirm, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.noteDelete, style: TextStyle(color: AppColors.oxblood)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = await ref.read(readingNotesRepositoryProvider.future);
    await repo.remove(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  String _monthDay(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Reading the live session keeps the header honest even if the safety net
    // stops the timer while this page is open.
    final active = ref.watch(activeSessionProvider);
    final live = _isLive && active != null;
    final elapsed = widget.sessionStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(widget.sessionStartedAt!);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            if (live) _LiveHeader(
              elapsed: elapsed,
              subtitle: l10n.noteOfThisSitting(
                widget.bookTitle ?? '',
                widget.noteIndex ?? 1,
              ),
              onClose: () => Navigator.of(context).pop(),
              onSave: _saving ? null : _save,
            ) else _PastHeader(
              title: _isEditing
                  ? l10n.noteWrittenOn(_monthDay(widget.existing!.createdAt))
                  : (widget.bookTitle ?? ''),
              subtitle: widget.sessionSummary,
              onBack: () => Navigator.of(context).pop(),
              onSave: _saving ? null : _save,
              // Reading: the action is Edit. Editing: it's Save.
              reading: _reading,
              onEdit: () => setState(() => _reading = false),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_outline, size: 11, color: AppColors.inkSoft),
                        const SizedBox(width: 4),
                        Text(
                          l10n.noteYourThought.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    // Slip paper — the same treatment notes already have on
                    // the book page, so private reads as private everywhere.
                    Container(
                      constraints: const BoxConstraints(minHeight: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6EEDC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE8DCC0)),
                      ),
                      child: TextField(
                        controller: _body,
                        autofocus: !widget.startReadOnly,
                        readOnly: _reading,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(fontSize: 15, height: 1.55, color: AppColors.ink),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: l10n.noteHint,
                          hintStyle: TextStyle(color: AppColors.inkSoft, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.notePagesLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _PageBox(controller: _from),
                        if (_range) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 14, color: AppColors.inkSoft),
                          const SizedBox(width: 8),
                          _PageBox(controller: _to),
                        ],
                        const SizedBox(width: 10),
                        ActionChip(
                          onPressed: () => setState(() {
                            _range = !_range;
                            if (!_range) _to.clear();
                          }),
                          label: Text(
                            _range ? l10n.noteSingle : l10n.noteAddRange,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          avatar: Icon(
                            _range ? Icons.close : Icons.arrow_forward,
                            size: 13,
                            color: AppColors.oxblood,
                          ),
                          backgroundColor: AppColors.card,
                          side: BorderSide(color: AppColors.gold),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.notePagesHelp,
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.45),
                    ),
                    if (_isEditing && !_reading) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.paperDeep,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l10n.noteEditNeverMoves,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.45,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (!_reading)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.oxblood,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          _isEditing ? l10n.noteSaveChanges : l10n.noteSaveKeepReading,
                        ),
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.noteTimerNeverPaused,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                      ),
                    ],
                    if (_isEditing && !_reading) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _delete,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                            child: Text(
                              l10n.noteDelete,
                              style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The clock, pinned and ticking — the promise made visible.
class _LiveHeader extends StatelessWidget {
  const _LiveHeader({
    required this.elapsed,
    required this.subtitle,
    required this.onClose,
    required this.onSave,
  });

  final Duration elapsed;
  final String subtitle;
  final VoidCallback onClose;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: const Color(0xFF17120C),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: const Icon(Icons.close, size: 18, color: Color(0xFF8C7C64)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE3B14C),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatDuration(elapsed),
                      style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFEDE3D0),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      l10n.noteStillRunning,
                      style: const TextStyle(fontSize: 10, color: Color(0xFFA9997F)),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Color(0xFFA9997F)),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onSave,
            behavior: HitTestBehavior.opaque,
            child: Text(
              l10n.bookSave,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE3B14C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editing an old note: the live clock becomes where the note came from.
class _PastHeader extends StatelessWidget {
  const _PastHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onSave,
    this.reading = false,
    this.onEdit,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final bool reading;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: AppColors.paperDeep,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.arrow_back, size: 18, color: AppColors.inkSoft),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: reading ? onEdit : onSave,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reading) ...[
                  Icon(Icons.edit_outlined, size: 14, color: AppColors.oxblood),
                  const SizedBox(width: 4),
                ],
                Text(
                  reading ? l10n.noteEdit : l10n.bookSave,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.oxblood,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageBox extends StatefulWidget {
  const _PageBox({required this.controller});

  final TextEditingController controller;

  @override
  State<_PageBox> createState() => _PageBoxState();
}

class _PageBoxState extends State<_PageBox> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Tapping a page number means "this is wrong, here's the right one" —
    // select it all so typing replaces rather than appends. Same rule the
    // stop sheet's big numeral follows.
    _focus.addListener(() {
      if (!_focus.hasFocus) return;
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 66,
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.oxblood,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: AppColors.line),
          ),
        ),
      ),
    );
  }
}
