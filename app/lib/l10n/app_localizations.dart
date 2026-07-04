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
