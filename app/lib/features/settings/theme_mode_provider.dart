import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_providers.dart';

const _darkKey = 'dark_mode';

/// Device-local dark-mode preference. Defaults to light and loads the saved
/// value on first read; toggling persists it and rebuilds the whole app theme
/// (the AppColors token getters then resolve to the "at night" palette).
class ThemeModeController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final v = await ref.read(appDatabaseProvider).keyValuesDao.getValue(_darkKey);
    if (v == 'true') state = true;
  }

  Future<void> set(bool dark) async {
    state = dark;
    await ref.read(appDatabaseProvider).keyValuesDao.setValue(_darkKey, '$dark');
  }
}

final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, bool>(ThemeModeController.new);
