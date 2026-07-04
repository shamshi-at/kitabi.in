// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kitabi';

  @override
  String get homeGreeting => 'Beyond the Bookshelf';

  @override
  String get signInQuote1 => 'A reader lives a thousand lives before he dies.';

  @override
  String get signInQuote2 =>
      'I have always imagined that Paradise will be a kind of library.';

  @override
  String get signInQuote3 =>
      'Ein Buch muss die Axt sein für das gefrorene Meer in uns.';

  @override
  String get signInGoogle => 'Continue with Google';

  @override
  String get signInApple => 'Continue with Apple';

  @override
  String get signInPrivacyNote =>
      'Your library is private by default.\nNothing is shared unless you choose to.';

  @override
  String get signInError => 'Couldn\'t sign in. Please try again.';

  @override
  String get profileVisibilityHeader =>
      'VISIBILITY · everything starts private';

  @override
  String get profileVisibilityProfileTitle => 'Profile';

  @override
  String get profileVisibilityProfileDesc => 'Name & reading stats';

  @override
  String get profileVisibilityLibraryTitle => 'Library';

  @override
  String get profileVisibilityLibraryDesc => 'What\'s on your shelves';

  @override
  String get profileVisibilityReviewsTitle => 'Reviews';

  @override
  String get profileVisibilityReviewsDesc => 'Default for new reviews';

  @override
  String get profileSignOut => 'Sign out';

  @override
  String get profileDeleteAccount => 'Delete account';

  @override
  String get profileDeleteAccountConfirm =>
      'This deletes your Kitabi account and library. This can\'t be undone.';

  @override
  String profileReadingSince(int year) {
    return 'Reading since $year';
  }
}
