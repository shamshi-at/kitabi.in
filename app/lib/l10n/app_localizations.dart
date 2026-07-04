import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The application name
  ///
  /// In en, this message translates to:
  /// **'Kitabi'**
  String get appTitle;

  /// Tagline shown on the placeholder home screen and sign-in
  ///
  /// In en, this message translates to:
  /// **'Beyond the Bookshelf'**
  String get homeGreeting;

  /// Rotating literary quote on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'A reader lives a thousand lives before he dies.'**
  String get signInQuote1;

  /// Rotating literary quote on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'I have always imagined that Paradise will be a kind of library.'**
  String get signInQuote2;

  /// Rotating literary quote on the sign-in screen (Kafka, German)
  ///
  /// In en, this message translates to:
  /// **'Ein Buch muss die Axt sein für das gefrorene Meer in uns.'**
  String get signInQuote3;

  /// Google sign-in button
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get signInGoogle;

  /// Apple sign-in button (iOS only)
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get signInApple;

  /// Footer reassurance on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Your library is private by default.\nNothing is shared unless you choose to.'**
  String get signInPrivacyNote;

  /// Generic sign-in failure message
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign in. Please try again.'**
  String get signInError;

  /// Section header on the profile screen's visibility switchboard
  ///
  /// In en, this message translates to:
  /// **'VISIBILITY · everything starts private'**
  String get profileVisibilityHeader;

  /// Visibility toggle label
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileVisibilityProfileTitle;

  /// Visibility toggle description
  ///
  /// In en, this message translates to:
  /// **'Name & reading stats'**
  String get profileVisibilityProfileDesc;

  /// Visibility toggle label
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get profileVisibilityLibraryTitle;

  /// Visibility toggle description
  ///
  /// In en, this message translates to:
  /// **'What\'s on your shelves'**
  String get profileVisibilityLibraryDesc;

  /// Visibility toggle label
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get profileVisibilityReviewsTitle;

  /// Visibility toggle description
  ///
  /// In en, this message translates to:
  /// **'Default for new reviews'**
  String get profileVisibilityReviewsDesc;

  /// Sign-out action on the profile screen
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get profileSignOut;

  /// Account-deletion action on the profile screen
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get profileDeleteAccount;

  /// Confirmation copy shown before deleting the account
  ///
  /// In en, this message translates to:
  /// **'This deletes your Kitabi account and library. This can\'t be undone.'**
  String get profileDeleteAccountConfirm;

  /// Profile subtitle
  ///
  /// In en, this message translates to:
  /// **'Reading since {year}'**
  String profileReadingSince(int year);

  /// Search box placeholder on the catalog search screen
  ///
  /// In en, this message translates to:
  /// **'Title, author, or ISBN'**
  String get catalogSearchHint;

  /// Section header above catalog-only search results
  ///
  /// In en, this message translates to:
  /// **'IN THE CATALOG'**
  String get catalogSearchSectionCatalog;

  /// Empty state on the catalog search screen
  ///
  /// In en, this message translates to:
  /// **'No matches yet — scan the barcode or add it by hand.'**
  String get catalogSearchEmpty;

  /// Footer help text on the catalog search screen
  ///
  /// In en, this message translates to:
  /// **'Tap an author or publisher name to browse everything by them.'**
  String get catalogSearchHelp;

  /// Entry point to the barcode scanner
  ///
  /// In en, this message translates to:
  /// **'Scan ISBN'**
  String get catalogScanButton;

  /// Entry point to the manual add/edit form
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get catalogAddManualButton;

  /// Action on a search/browse result row that opens the catalog edit form
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get catalogEditAction;

  /// Eyebrow label on the author browse screen
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get authorBrowseLabel;

  /// Subheader on the author browse screen
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{work} other{works}} in the catalog'**
  String authorBrowseWorksCount(int count);

  /// Eyebrow label on the publisher browse screen
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get publisherBrowseLabel;

  /// Subheader on the publisher browse screen
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{title} other{titles}} in the catalog'**
  String publisherBrowseWorksCount(int count);

  /// Empty state on author/publisher browse screens
  ///
  /// In en, this message translates to:
  /// **'Nothing catalogued here yet.'**
  String get browseEmpty;

  /// Title on the ISBN scan screen
  ///
  /// In en, this message translates to:
  /// **'Add a book'**
  String get scanTitle;

  /// Subtitle on the ISBN scan screen
  ///
  /// In en, this message translates to:
  /// **'Point at the barcode on the back cover'**
  String get scanSubtitle;

  /// Shown once a barcode has been decoded
  ///
  /// In en, this message translates to:
  /// **'ISBN detected — {isbn}'**
  String scanDetected(String isbn);

  /// Shown when the ISBN doesn't resolve to a book
  ///
  /// In en, this message translates to:
  /// **'No book found for that ISBN.'**
  String get scanNotFound;

  /// Confirms adding the detected book to the catalog
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get scanConfirmAdd;

  /// Falls back to catalog search from the scan screen
  ///
  /// In en, this message translates to:
  /// **'Search instead'**
  String get scanSearchInstead;

  /// Falls back to the manual add form from the scan screen
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get scanAddManually;

  /// Title on the add/edit catalog form when creating
  ///
  /// In en, this message translates to:
  /// **'Add a book'**
  String get formTitleAdd;

  /// Title on the add/edit catalog form when editing
  ///
  /// In en, this message translates to:
  /// **'Edit book'**
  String get formTitleEdit;

  /// Subheader clarifying the catalog entry is shared, not personal
  ///
  /// In en, this message translates to:
  /// **'catalog entry · shared'**
  String get formSubtitle;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'TITLE'**
  String get formFieldTitle;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'AUTHOR'**
  String get formFieldAuthor;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get formFieldLanguage;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'SERIES'**
  String get formFieldSeries;

  /// Form field label — position within a series
  ///
  /// In en, this message translates to:
  /// **'BOOK №'**
  String get formFieldBookNumber;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'PUBLISHER'**
  String get formFieldPublisher;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'PAGES'**
  String get formFieldPages;

  /// Form field label — scoped to the specific edition, not the work
  ///
  /// In en, this message translates to:
  /// **'ISBN · THIS EDITION'**
  String get formFieldIsbn;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'FORMAT'**
  String get formFieldFormat;

  /// Form field label — clarifies genres are shared, not personal tags
  ///
  /// In en, this message translates to:
  /// **'GENRES · GLOBAL'**
  String get formFieldGenres;

  /// Cover-field caption when no image has been uploaded
  ///
  /// In en, this message translates to:
  /// **'Typeset cover in use'**
  String get formCoverTypeset;

  /// Submit button on the add/edit catalog form
  ///
  /// In en, this message translates to:
  /// **'Save to catalog'**
  String get formSave;

  /// Validation message for the title field
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get formTitleRequired;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
