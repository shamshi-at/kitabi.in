import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/share_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/kitabi_linked_badge.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../share/presentation/entity_share_sheet.dart';
import '../providers/catalog_providers.dart';
import 'catalog_result_tile.dart';
import '../../../core/widgets/net_image.dart';

/// S4c — every catalog work by one author. The owned/not-owned split from
/// the mockup depends on the personal library (Phase 3); until then this
/// shows the full catalog list undivided.
class AuthorBrowseScreen extends ConsumerWidget {
  const AuthorBrowseScreen({super.key, required this.authorId});

  final String authorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(authorWorksProvider(authorId));

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: data.when(
          loading: () => ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(authorWorksProvider(authorId))),
          data: (body) {
            final author = body['author'] as Map<String, dynamic>;
            final works = (body['works'] as List).cast<Map<String, dynamic>>();
            final name = author['name'] as String;
            final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
            final imageUrl = author['image_url'] as String?;
            final penName = author['pen_name'] as String?;
            final linkedUserId = author['linked_user_id'] as String?;
            // Only ever true for the reader who filed the claim — the server
            // discloses it to nobody else (api/app/models/author_claim.py).
            final claimPending = author['claim_pending'] as bool? ?? false;

            return ListView(
              padding: EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppColors.ink),
                      onPressed: () => context.pop(),
                    ),
                    Text(
                      l10n.authorBrowseLabel,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.inkSoft),
                    ),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.ios_share, color: AppColors.oxblood),
                      tooltip: l10n.shareAction,
                      onPressed: () => showEntityShareSheet(
                        context,
                        eyebrow: l10n.shareAuthorEyebrow,
                        name: name,
                        subtitle: l10n.authorBrowseWorksCount(works.length),
                        shareUrl: authorShareUrl(authorId),
                        shareText: l10n.shareAuthorLinkText(name, authorShareUrl(authorId)),
                        imageUrl: imageUrl,
                        circular: true,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.goldSoft,
                      foregroundImage: imageUrl != null ? netImageProvider(imageUrl) : null,
                      child: imageUrl == null
                          ? Text(
                              initials,
                              style: TextStyle(
                                color: Color(0xFF8F681E),
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(name, style: Theme.of(context).textTheme.titleLarge),
                              ),
                              if (linkedUserId != null) ...[
                                SizedBox(width: 8),
                                KitabiLinkedBadge(),
                              ],
                            ],
                          ),
                          if (penName != null && penName.isNotEmpty)
                            Text(
                              l10n.authorWritingAs(penName),
                              style: TextStyle(
                                color: AppColors.oxblood,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          Text(
                            l10n.authorBrowseWorksCount(works.length),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                if (linkedUserId != null)
                  OutlinedButton.icon(
                    onPressed: () => context.push(
                      Routes.publicProfilePath(linkedUserId),
                      extra: name,
                    ),
                    icon: Icon(Icons.person_outline, size: 16, color: AppColors.oxblood),
                    label: Text(l10n.authorBrowseViewProfile),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.oxblood),
                  ),
                // "This is me" is offered again now that it queues for review
                // instead of applying on the spot (owner decision, 22 Jul
                // 2026) — the misuse it was hidden for needs an approval to
                // reach anyone else. Never shown on an author already linked.
                if (linkedUserId == null)
                  claimPending
                      ? const _ClaimPendingNotice()
                      : _LinkAuthorAction(authorId: authorId),
                SizedBox(height: 20),
                if (works.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.browseEmpty,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                  )
                else
                  for (final work in works) CatalogResultTile(work: work),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What the claimant — and only the claimant — sees while their "This is me"
/// waits on a human. Everyone else sees the plain unclaimed author page, which
/// is the point: an unverified claim must not change shared catalog data.
class _ClaimPendingNotice extends StatelessWidget {
  const _ClaimPendingNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(10),
        // Uniform border on purpose: a non-uniform one alongside borderRadius
        // throws at paint time and renders a blank box (CLAUDE.md, 21 Jul).
        border: Border.all(color: AppColors.gold),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top, size: 16, color: AppColors.gold),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.authorClaimPending,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  l10n.authorClaimPendingNote,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "This is me" — files a claim on an unclaimed Author row for manual review
/// (owner decision, 22 Jul 2026; superseded the 14 Jul first-to-tap-wins
/// rule). Its own stateful widget just for the busy flag around the API call;
/// the author page itself stays a plain ConsumerWidget.
class _LinkAuthorAction extends ConsumerStatefulWidget {
  const _LinkAuthorAction({required this.authorId});

  final String authorId;

  @override
  ConsumerState<_LinkAuthorAction> createState() => _LinkAuthorActionState();
}

class _LinkAuthorActionState extends ConsumerState<_LinkAuthorAction> {
  bool _busy = false;

  Future<void> _link() async {
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).linkAuthor(widget.authorId);
      ref.invalidate(authorWorksProvider(widget.authorId));
      messenger.showSnackBar(SnackBar(content: Text(l10n.authorClaimSent)));
    } on DioException catch (err) {
      // 409 is a real answer, not a failure: somebody is already linked here.
      final code = (err.response?.data as Map?)?['code'];
      messenger.showSnackBar(SnackBar(
        content: Text(
          code == 'already_linked' ? l10n.authorClaimAlreadyLinked : l10n.authorLinkFailed,
        ),
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.authorLinkFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OutlinedButton.icon(
      onPressed: _busy ? null : _link,
      icon: _busy
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.inkSoft),
            )
          : Icon(Icons.person_add_alt, size: 16),
      label: Text(l10n.authorBrowseIsMe),
    );
  }
}
