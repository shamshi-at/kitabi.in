import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';

/// Pick the Kitabi account a private contact really is — a live user search,
/// same shape as the lend sheet's borrower field. Returns the picked user map
/// (`id` / `username` / `full_name`), or null on dismiss.
Future<Map<String, dynamic>?> showLinkContactDialog(
  BuildContext context, {
  required String name,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _LinkContactDialog(name: name),
  );
}

class _LinkContactDialog extends ConsumerStatefulWidget {
  const _LinkContactDialog({required this.name});

  final String name;

  @override
  ConsumerState<_LinkContactDialog> createState() => _LinkContactDialogState();
}

class _LinkContactDialogState extends ConsumerState<_LinkContactDialog> {
  late final TextEditingController _query = TextEditingController(text: widget.name);
  Timer? _debounce;
  List<Map<String, dynamic>> _users = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // The contact's name is the obvious first query — search it right away.
    _search(widget.name);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    setState(() => _searching = q.isNotEmpty);
    if (q.isEmpty) {
      setState(() => _users = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final rows = await ref.read(apiClientProvider).searchUsers(q);
      if (mounted && _query.text.trim() == q.trim()) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(l10n.linkContactTitle(widget.name), style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.linkContactBody,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.inkSoft),
            ),
            SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.words,
              controller: _query,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: l10n.linkContactSearchHint,
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                suffixIcon: _searching
                    ? Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.gold),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            SizedBox(height: 8),
            if (!_searching && _users.isEmpty && _query.text.trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  l10n.linkContactNoResults,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in _users)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(Icons.person, size: 20, color: AppColors.oxblood),
                      title: Text(
                        (u['full_name'] as String?)?.trim().isNotEmpty == true
                            ? u['full_name'] as String
                            : '@${u['username']}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: u['username'] != null
                          ? Text('@${u['username']}',
                              style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft))
                          : null,
                      onTap: () => Navigator.of(context).pop(u),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            MaterialLocalizations.of(context).cancelButtonLabel,
            style: TextStyle(color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}
