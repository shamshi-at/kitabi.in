import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import 'sheet_fields.dart';

/// The "lent to / borrowed from" field. It reads as a **search**: a search icon,
/// a live spinner while it queries, matched Kitabi users under a header, and a
/// clear "Linked" chip once one is picked (sets `borrower_user_id`). Type a name
/// that matches no user and it's kept as a free-text **private contact** — the
/// field says so explicitly rather than looking like nothing happened. Past
/// contacts are offered as quick-picks.
class BorrowerField extends ConsumerStatefulWidget {
  const BorrowerField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.onUserIdChanged,
    required this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;

  /// The chosen Kitabi user's id, or null once the text is a plain private
  /// contact (manual edit clears any prior link).
  final ValueChanged<String?> onUserIdChanged;
  final VoidCallback onChanged;

  @override
  ConsumerState<BorrowerField> createState() => _BorrowerFieldState();
}

class _BorrowerFieldState extends ConsumerState<BorrowerField> {
  Timer? _debounce;
  List<Map<String, dynamic>> _users = [];
  List<String> _allContacts = [];
  List<String> _contacts = [];
  bool _searching = false;
  // The @handle of a linked Kitabi user, or null when the text is free-form.
  String? _linkedHandle;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final names = await ref.read(appDatabaseProvider).lendingRecordsDao.pastBorrowerNames();
      if (mounted) setState(() => _allContacts = names);
    } catch (_) {
      // Suggestions are a nicety.
    }
  }

  void _onChanged(String raw) {
    // Any manual edit means "private contact" again until a Kitabi user is tapped.
    widget.onUserIdChanged(null);
    widget.onChanged();
    final query = raw.trim();
    _debounce?.cancel();
    setState(() {
      _linkedHandle = null;
      _contacts = query.isEmpty
          ? const []
          : _allContacts
              .where((c) => c.toLowerCase().contains(query.toLowerCase()) && c != raw)
              .take(4)
              .toList();
      // Show the spinner immediately so the field visibly "searches".
      _searching = query.isNotEmpty;
      if (query.isEmpty) _users = [];
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () => _searchUsers(query));
  }

  Future<void> _searchUsers(String query) async {
    try {
      final rows = await ref.read(apiClientProvider).searchUsers(query);
      if (mounted && widget.controller.text.trim() == query) {
        setState(() {
          _users = rows;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _users = [];
          _searching = false;
        });
      }
    }
  }

  void _pickUser(Map<String, dynamic> user) {
    final display = (user['full_name'] as String?)?.trim();
    final username = user['username'] as String?;
    widget.controller.text = (display != null && display.isNotEmpty) ? display : (username ?? '');
    widget.onUserIdChanged(user['id'] as String?);
    widget.onChanged();
    setState(() {
      _linkedHandle = username != null ? '@$username' : null;
      _users = [];
      _contacts = [];
      _searching = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _pickContact(String name) {
    widget.controller.text = name;
    widget.onUserIdChanged(null);
    widget.onChanged();
    setState(() {
      _linkedHandle = null;
      _users = [];
      _contacts = [];
      _searching = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _clearLink() {
    widget.controller.clear();
    widget.onUserIdChanged(null);
    widget.onChanged();
    setState(() {
      _linkedHandle = null;
      _users = [];
      _contacts = [];
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = widget.controller.text.trim();
    final linked = _linkedHandle != null;
    final showResults = !linked && (_users.isNotEmpty || _contacts.isNotEmpty);
    // No user matched a non-empty query (and we're done searching): tell the user
    // it'll be a private contact, so the field never looks like a dead end.
    final showNoMatch =
        !linked && !_searching && query.isNotEmpty && _users.isEmpty && _contacts.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetLabel(widget.label),
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: _onChanged,
          decoration: sheetInputDecoration(widget.hint).copyWith(
            prefixIcon: Icon(
              linked ? Icons.verified_user : Icons.search,
              size: 18,
              color: linked ? AppColors.moss : AppColors.inkSoft,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
            suffixIcon: _suffixIcon(),
            suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
          ),
        ),
        if (linked) _LinkedChip(handle: _linkedHandle!, onClear: _clearLink, l10n: l10n),
        if (showResults)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                if (_users.isNotEmpty) _ResultHeader(l10n.borrowerUsersHeader),
                for (final u in _users)
                  _ResultRow(
                    icon: Icons.person,
                    iconColor: AppColors.oxblood,
                    title: (u['full_name'] as String?)?.trim().isNotEmpty == true
                        ? u['full_name'] as String
                        : '@${u['username']}',
                    subtitle: l10n.borrowerKitabiUser('@${u['username']}'),
                    onTap: () => _pickUser(u),
                  ),
                if (_contacts.isNotEmpty) _ResultHeader(l10n.borrowerRecentHeader),
                for (final c in _contacts)
                  _ResultRow(
                    icon: Icons.history,
                    iconColor: AppColors.inkSoft,
                    title: c,
                    subtitle: l10n.borrowerPrivateContact,
                    onTap: () => _pickContact(c),
                  ),
              ],
            ),
          ),
        if (showNoMatch)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: AppColors.inkSoft),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.borrowerNoMatch(query),
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _suffixIcon() {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
        ),
      );
    }
    if (widget.controller.text.isNotEmpty) {
      return IconButton(
        icon: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
        splashRadius: 18,
        onPressed: _clearLink,
      );
    }
    return null;
  }
}

class _LinkedChip extends StatelessWidget {
  const _LinkedChip({required this.handle, required this.onClear, required this.l10n});

  final String handle;
  final VoidCallback onClear;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.moss.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.link, size: 15, color: AppColors.moss),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.borrowerLinkedTo(handle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.moss),
              ),
            ),
            GestureDetector(
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  l10n.borrowerChange,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.oxblood,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(subtitle, style: TextStyle(color: AppColors.inkSoft, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
