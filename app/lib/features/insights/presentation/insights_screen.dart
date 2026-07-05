import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../insights_stats.dart';
import '../providers/insights_providers.dart';

const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// S10 — insights. Reading goal ring, a year selector, headline stats, and a
/// books-per-month bar chart. Dependency-free (custom bars + a progress ring);
/// the language donut / pages-per-month line from the mockup are a follow-up.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  // Default to the current year; null means "all time".
  late int? _year = DateTime.now().year;

  Future<void> _editGoal(int current) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: '$current');
    final goal = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.insightsGoalDialogTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.insightsGoalDialogHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (goal == null || goal <= 0) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.setReadingGoal(goal);
    ref.invalidate(readingGoalProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(libraryWithBooksProvider);
    final goal = ref.watch(readingGoalProvider).valueOrNull ?? 30;
    final thisYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (hits) {
            if (hits.isEmpty) {
              return _Empty(title: l10n.insightsTitle, body: l10n.insightsNoData);
            }
            final stats = computeInsights(hits, year: _year);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(l10n.insightsTitle, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _YearSelector(
                  year: _year,
                  thisYear: thisYear,
                  allTimeLabel: l10n.insightsAllTime,
                  onChanged: (y) => setState(() => _year = y),
                ),
                const SizedBox(height: 16),
                _GoalRing(
                  booksRead: stats.booksRead,
                  goal: goal,
                  showTarget: _year != null,
                  targetCaption: l10n.insightsGoalRing(goal),
                  totalCaption: l10n.insightsBooksReadTotal,
                  onTap: () => _editGoal(goal),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        value: '${stats.pagesRead}',
                        label: l10n.insightsPagesRead,
                        color: AppColors.slate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatTile(
                        value: '${stats.currentlyReading}',
                        label: l10n.insightsReadingNow,
                        color: AppColors.oxblood,
                      ),
                    ),
                  ],
                ),
                if (_year != null && stats.busiestMonthCount > 0) ...[
                  const SizedBox(height: 18),
                  Text(
                    l10n.insightsPerMonth.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MonthBars(counts: stats.booksPerMonth, max: stats.busiestMonthCount),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.year,
    required this.thisYear,
    required this.allTimeLabel,
    required this.onChanged,
  });

  final int? year;
  final int thisYear;
  final String allTimeLabel;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String, int?)>[
      ('$thisYear', thisYear),
      ('${thisYear - 1}', thisYear - 1),
      (allTimeLabel, null),
    ];
    return Row(
      children: [
        for (final (label, value) in options)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: year == value ? AppColors.ink : AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: year == value ? AppColors.ink : AppColors.line),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: year == value ? AppColors.paper : AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.booksRead,
    required this.goal,
    required this.showTarget,
    required this.targetCaption,
    required this.totalCaption,
    required this.onTap,
  });

  final int booksRead;
  final int goal;
  final bool showTarget;
  final String targetCaption;
  final String totalCaption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = showTarget && goal > 0 ? (booksRead / goal).clamp(0.0, 1.0) : 1.0;
    return GestureDetector(
      onTap: showTarget ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 7,
                      backgroundColor: AppColors.line,
                      valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                    ),
                  ),
                  Text(
                    '$booksRead',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: AppColors.oxblood, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                showTarget ? targetCaption : totalCaption,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ),
            if (showTarget) const Icon(Icons.edit, size: 16, color: AppColors.oxblood),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.counts, required this.max});

  final List<int> counts;
  final int max;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (counts[i] > 0)
                    Text(
                      '${counts[i]}',
                      style: const TextStyle(fontSize: 8, color: AppColors.inkSoft),
                    ),
                  const SizedBox(height: 2),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: (60 * (counts[i] / max)).clamp(counts[i] > 0 ? 4.0 : 0.0, 60.0),
                    decoration: BoxDecoration(
                      color: counts[i] > 0 ? AppColors.oxblood : AppColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _monthLetters[i],
                    style: const TextStyle(fontSize: 9, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.donut_large_outlined, size: 44, color: AppColors.inkSoft),
                  const SizedBox(height: 16),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
