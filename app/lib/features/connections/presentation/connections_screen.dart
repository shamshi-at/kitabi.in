import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/net_image.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../connections_providers.dart';
import 'link_contact_dialog.dart';

/// The connections inbox (S8b) — a roster of people, not a form. Every real
/// account (incoming/outgoing/rejected/accepted/blocked) is a person card
/// that opens their [PublicProfileScreen] — that's where Accept/Deny/Block/
/// Cancel/Resend/Disconnect/Unblock actually live now, alongside their shelf
/// and the loans between you, so there's one place to see someone and act on
/// them instead of buttons scattered across a list. **Private contacts**
/// (people you lend to who aren't on Kitabi) are the one exception — they
/// have no account to view, so "Link" still lives on the row.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  /// Attach every loan logged under this free-text [name] to the picked Kitabi
  /// account, then send them a connection request — once they accept, the API
  /// backfills their Borrowed shelf with the pre-existing loans.
  Future<void> _linkContact(
    BuildContext context,
    WidgetRef ref,
    String name,
    List<LendingRecord> records,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final user = await showLinkContactDialog(context, name: name);
    if (user == null) return;
    final userId = user['id'] as String;
    final repo = await ref.read(lendingRepositoryProvider.future);
    for (final r in records) {
      await repo.updateBorrower(r.id, borrowerName: r.borrowerName, borrowerUserId: userId);
    }
    try {
      await ref.read(apiClientProvider).requestConnection(userId);
    } catch (_) {
      // Already pending/connected is fine — the link itself has been made.
    }
    ref.invalidate(connectionsProvider);
    Haptics.success();
    messenger.showSnackBar(SnackBar(content: Text(l10n.linkContactDone)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final connections = ref.watch(connectionsProvider);
    final allLoans =
        ref.watch(allLendingProvider).valueOrNull ?? const <LendingWithBook>[];
    // Private contacts: everyone in the ledger without a linked account,
    // grouped by name, newest activity first.
    final contactRecords = <String, List<LendingRecord>>{};
    for (final item in allLoans) {
      final r = item.record;
      if (r.borrowerUserId == null && r.borrowerName.trim().isNotEmpty) {
        contactRecords.putIfAbsent(r.borrowerName, () => []).add(r);
      }
    }
    // Open loans with a linked user — enriches the accepted cards.
    int openLoansWith(String userId) => allLoans
        .where((i) => i.record.borrowerUserId == userId && i.record.returnedDate == null)
        .length;

    void openProfile(ConnectionUser user) =>
        context.push(Routes.publicProfilePath(user.id), extra: user.display);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(l10n.connectionsTitle, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: connections.when(
        loading: () => ListSkeleton(),
        error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(connectionsProvider)),
        data: (data) {
          final empty = data.incoming.isEmpty &&
              data.outgoing.isEmpty &&
              data.accepted.isEmpty &&
              data.rejected.isEmpty &&
              data.blocked.isEmpty &&
              contactRecords.isEmpty;
          if (empty) {
            return EmptyState(
              icon: Icons.people_outline,
              title: l10n.connectionsTitle,
              body: l10n.connectionsEmpty,
            );
          }
          String? acceptedSubtitle(Connection c) {
            final open = openLoansWith(c.other.id);
            final parts = [
              if (c.other.username != null) '@${c.other.username}',
              if (open > 0) l10n.connectionsLoansWithThem(open),
            ];
            return parts.isEmpty ? null : parts.join(' · ');
          }
          return RefreshIndicator(
            color: AppColors.oxblood,
            onRefresh: () async => ref.invalidate(connectionsProvider),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (data.incoming.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsIncomingSection),
                  for (final c in data.incoming)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: l10n.connectionsWantsToConnect,
                      onTap: () => openProfile(c.other),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.outgoing.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsOutgoingSection),
                  for (final c in data.outgoing)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: l10n.connectionsAwaitingReply,
                      onTap: () => openProfile(c.other),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.rejected.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsRejectedSection),
                  for (final c in data.rejected)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: l10n.connectionsDeclinedYou,
                      onTap: () => openProfile(c.other),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.accepted.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsAcceptedSection),
                  for (final c in data.accepted)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: acceptedSubtitle(c),
                      onTap: () => openProfile(c.other),
                    ),
                  SizedBox(height: 14),
                ],
                if (contactRecords.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsPrivateSection),
                  for (final entry in contactRecords.entries)
                    _ConnectionCard(
                      user: ConnectionUser(id: '', fullName: entry.key),
                      subtitle: l10n.connectionsPrivateLoans(
                        entry.value.where((r) => r.returnedDate == null).length,
                      ),
                      onTap: () => openPersonLoans(context, name: entry.key),
                      trailing: _CardButton(
                        label: l10n.connectionsLinkAction,
                        primary: true,
                        onTap: () => _linkContact(context, ref, entry.key, entry.value),
                      ),
                    ),
                  SizedBox(height: 14),
                ],
                if (data.blocked.isNotEmpty) ...[
                  _SectionLabel(l10n.connectionsBlockedSection),
                  for (final c in data.blocked)
                    _ConnectionCard(
                      user: c.other,
                      subtitle: c.other.username != null ? '@${c.other.username}' : null,
                      onTap: () => openProfile(c.other),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// A person, not a form row — real avatar (falling back to an initial),
/// name, a status line, and a chevron if it opens a profile. Actions live on
/// the profile itself now; [trailing] only exists for private contacts,
/// whose one action ("Link") has nowhere else to go.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.user,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final ConnectionUser user;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final name = user.display.replaceAll('@', '');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.goldSoft,
              foregroundImage:
                  user.avatarUrl != null ? netImageProvider(user.avatarUrl!) : null,
              child: Text(
                initial,
                style: TextStyle(
                  color: Color(0xFF8F681E),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                    ),
                ],
              ),
            ),
            SizedBox(width: 8),
            trailing ??
                (onTap != null
                    ? Icon(Icons.chevron_right, size: 20, color: AppColors.inkSoft)
                    : SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: primary ? AppColors.oxblood : Colors.transparent,
        foregroundColor: primary ? AppColors.paper : AppColors.inkSoft,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: primary ? BorderSide.none : BorderSide(color: AppColors.line),
        ),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
