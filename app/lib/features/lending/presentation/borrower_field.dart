import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import 'sheet_fields.dart';

/// The "lent to / borrowed from" field. Type a name for a **private contact**
/// (not shared — stays a free-text borrower on the record), or match an existing
/// **Kitabi user** by their username to link the loan to them (sets
/// `borrower_user_id`, so the record can later mirror onto their account).
/// Past contacts are offered as quick-picks as you type.
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
  bool _picked = false;

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
    setState(() {
      _picked = false;
      _contacts = query.isEmpty
          ? const []
          : _allContacts
              .where((c) => c.toLowerCase().contains(query.toLowerCase()) && c != raw)
              .take(4)
              .toList();
    });
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _users = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _searchUsers(query));
  }

  Future<void> _searchUsers(String query) async {
    try {
      final rows = await ref.read(apiClientProvider).searchUsers(query);
      if (mounted && widget.controller.text.trim() == query) {
        setState(() => _users = rows);
      }
    } catch (_) {
      if (mounted) setState(() => _users = []);
    }
  }

  void _pickUser(Map<String, dynamic> user) {
    final display = (user['full_name'] as String?)?.trim();
    final username = user['username'] as String?;
    widget.controller.text = (display != null && display.isNotEmpty) ? display : (username ?? '');
    widget.onUserIdChanged(user['id'] as String?);
    widget.onChanged();
    setState(() {
      _picked = true;
      _users = [];
      _contacts = [];
    });
  }

  void _pickContact(String name) {
    widget.controller.text = name;
    widget.onUserIdChanged(null);
    widget.onChanged();
    setState(() {
      _picked = true;
      _users = [];
      _contacts = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showResults = !_picked && (_users.isNotEmpty || _contacts.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetLabel(widget.label),
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          autocorrect: false,
          onChanged: _onChanged,
          decoration: sheetInputDecoration(widget.hint),
        ),
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
      ],
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
