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

  @override
  String get catalogSearchHint => 'Title, author, or ISBN';

  @override
  String get catalogSearchSectionCatalog => 'IN THE CATALOG';

  @override
  String get catalogSearchEmpty =>
      'No matches yet — scan the barcode or add it by hand.';

  @override
  String get catalogSearchHelp =>
      'Tap an author or publisher name to browse everything by them.';

  @override
  String get catalogScanButton => 'Scan ISBN';

  @override
  String get catalogAddManualButton => 'Add manually';

  @override
  String get catalogEditAction => 'Edit';

  @override
  String get authorBrowseLabel => 'Author';

  @override
  String authorBrowseWorksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'works',
      one: 'work',
    );
    return '$count $_temp0 in the catalog';
  }

  @override
  String get publisherBrowseLabel => 'Publisher';

  @override
  String publisherBrowseWorksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'titles',
      one: 'title',
    );
    return '$count $_temp0 in the catalog';
  }

  @override
  String get browseEmpty => 'Nothing catalogued here yet.';

  @override
  String get scanTitle => 'Add a book';

  @override
  String get scanSubtitle => 'Point at the barcode on the back cover';

  @override
  String scanDetected(String isbn) {
    return 'ISBN detected — $isbn';
  }

  @override
  String get scanNotFound => 'No book found for that ISBN.';

  @override
  String get scanConfirmAdd => 'Add';

  @override
  String get scanSearchInstead => 'Search instead';

  @override
  String get scanAddManually => 'Add manually';

  @override
  String get formTitleAdd => 'Add a book';

  @override
  String get formTitleEdit => 'Edit book';

  @override
  String get formSubtitle => 'catalog entry · shared';

  @override
  String get formFieldTitle => 'TITLE';

  @override
  String get formFieldAuthor => 'AUTHOR';

  @override
  String get formFieldLanguage => 'LANGUAGE';

  @override
  String get formFieldSeries => 'SERIES';

  @override
  String get formFieldBookNumber => 'BOOK №';

  @override
  String get formFieldPublisher => 'PUBLISHER';

  @override
  String get formFieldPages => 'PAGES';

  @override
  String get formFieldIsbn => 'ISBN · THIS EDITION';

  @override
  String get formFieldFormat => 'FORMAT';

  @override
  String get formFieldGenres => 'GENRES · GLOBAL';

  @override
  String get formCoverTypeset => 'Typeset cover in use';

  @override
  String get formSave => 'Save to catalog';

  @override
  String get formTitleRequired => 'Title is required';
}
