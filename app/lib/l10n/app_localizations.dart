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

  /// Generic friendly error message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get commonError;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Offline banner text
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — changes will sync when you\'re back.'**
  String get commonOffline;

  /// Sync-in-progress indicator
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncPending;

  /// Sync-failed banner
  ///
  /// In en, this message translates to:
  /// **'Some changes haven\'t synced. Tap to retry.'**
  String get syncError;

  /// Tagline shown on the placeholder home screen and sign-in
  ///
  /// In en, this message translates to:
  /// **'Beyond the Bookshelf'**
  String get homeGreeting;

  /// Tagline under the brand name on the animated splash
  ///
  /// In en, this message translates to:
  /// **'Beyond the Bookshelf'**
  String get splashTagline;

  /// Loading status line on the splash while auth and profile resolve
  ///
  /// In en, this message translates to:
  /// **'Opening your reading room…'**
  String get splashLoading;

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

  /// Label on the visibility pill when a setting is public
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get visibilityPublic;

  /// Label on the visibility pill when a setting is private
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get visibilityPrivate;

  /// Snackbar when a visibility toggle fails to persist
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that — check your connection.'**
  String get profileVisibilitySaveError;

  /// Dark-mode toggle title on the profile screen
  ///
  /// In en, this message translates to:
  /// **'Night reading'**
  String get profileDarkMode;

  /// Dark-mode toggle subtitle on the profile screen
  ///
  /// In en, this message translates to:
  /// **'A warm dark theme for low light'**
  String get profileDarkModeDesc;

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

  /// Profile screen action button that opens the same bookplate view other readers see (respects the visibility toggles above — a private profile shows the quiet 'keeps their profile private' state)
  ///
  /// In en, this message translates to:
  /// **'View my public profile'**
  String get profileViewPublicEntry;

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

  /// Section header above personal-library search matches
  ///
  /// In en, this message translates to:
  /// **'IN YOUR LIBRARY · {count}'**
  String catalogSearchSectionLibrary(int count);

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

  /// Small pill on an author's name marking them as a linked, registered Kitabi reader
  ///
  /// In en, this message translates to:
  /// **'On Kitabi'**
  String get linkedAuthorBadge;

  /// Self-link button on an unclaimed author's browse page
  ///
  /// In en, this message translates to:
  /// **'This is me'**
  String get authorBrowseIsMe;

  /// Button on a linked author's browse page, opens their public profile
  ///
  /// In en, this message translates to:
  /// **'View their Kitabi profile'**
  String get authorBrowseViewProfile;

  /// Error snackbar when self-linking an author fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t link this author right now'**
  String get authorLinkFailed;

  /// Shows an author's pen name under their real name
  ///
  /// In en, this message translates to:
  /// **'writing as {name}'**
  String authorWritingAs(String name);

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

  /// Shown in place of the camera preview when the camera can't start (e.g. permission denied) and the Search/Add fallback buttons are visible
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable — you can search the catalog or add the book manually below.'**
  String get scanCameraUnavailable;

  /// Camera-failure message when the scanner was opened from the add-book form (no fallback buttons on screen)
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable — check the app\'s camera permission.'**
  String get scanCameraUnavailableShort;

  /// Confirms adding the detected book to the user's library
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

  /// Placeholder option in the language dropdown when no language is chosen
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get formLanguageUnset;

  /// Note under the book language dropdown pointing to profile settings
  ///
  /// In en, this message translates to:
  /// **'Add more languages in your profile to see them here.'**
  String get formLanguageProfileNote;

  /// Title of the onboarding reading-languages picker
  ///
  /// In en, this message translates to:
  /// **'Which languages do you read?'**
  String get langPickerTitle;

  /// Subtitle of the onboarding reading-languages picker
  ///
  /// In en, this message translates to:
  /// **'Pick one or more. We\'ll list these first when you add a book — you can change them anytime in your profile.'**
  String get langPickerSubtitle;

  /// Button to save the picked reading languages and continue
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get langPickerContinue;

  /// Profile section header for the reader's languages
  ///
  /// In en, this message translates to:
  /// **'Reading languages'**
  String get profileLanguagesTitle;

  /// Shown in profile when no reading languages are set
  ///
  /// In en, this message translates to:
  /// **'Not set — tap to choose'**
  String get profileLanguagesEmpty;

  /// Title of the profile reading-languages edit sheet
  ///
  /// In en, this message translates to:
  /// **'Languages you read'**
  String get profileLanguagesSheetTitle;

  /// Save reading languages
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileLanguagesSave;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'SERIES NAME'**
  String get formFieldSeries;

  /// Form field label — position within a series
  ///
  /// In en, this message translates to:
  /// **'WHICH BOOK?'**
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

  /// Capture-strip tile at the top of the add-book form: open the barcode scanner
  ///
  /// In en, this message translates to:
  /// **'Scan the barcode'**
  String get formCaptureScan;

  /// Capture-strip tile at the top of the add-book form: photograph the front cover
  ///
  /// In en, this message translates to:
  /// **'Photograph the covers'**
  String get formCapturePhoto;

  /// One-line helper under the capture strip on the add-book form
  ///
  /// In en, this message translates to:
  /// **'Either one fills the form — everything stays editable. Or just type:'**
  String get formCaptureHelp;

  /// Section label for the single-select literary form (Novel, Short stories, ...) chips
  ///
  /// In en, this message translates to:
  /// **'TYPE · PICK ONE'**
  String get formFieldType;

  /// Chip at the end of the Type row that opens a field to name a type not in the suggested list
  ///
  /// In en, this message translates to:
  /// **'＋ Other'**
  String get formTypeOther;

  /// Title of the dialog for typing a custom book type
  ///
  /// In en, this message translates to:
  /// **'What kind of book is it?'**
  String get formTypeOtherTitle;

  /// Placeholder in the custom book-type field, showing example types
  ///
  /// In en, this message translates to:
  /// **'Novella, Screenplay, Devotional…'**
  String get formTypeOtherHint;

  /// Section label for the multi-select genre chips on the add-book form
  ///
  /// In en, this message translates to:
  /// **'GENRE · TAP ALL THAT FIT'**
  String get formFieldGenrePrimary;

  /// Title of the dialog for typing a genre that isn't among the suggested chips
  ///
  /// In en, this message translates to:
  /// **'Add a genre'**
  String get formGenreOtherTitle;

  /// Placeholder in the custom-genre field; commas separate several
  ///
  /// In en, this message translates to:
  /// **'Sufi, Devotional, Magical realism…'**
  String get formGenreOtherHint;

  /// Header of the collapsible section holding the less-essential book fields
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get formMoreDetails;

  /// One-line summary of what the collapsed More details section contains
  ///
  /// In en, this message translates to:
  /// **'Series · publisher · ISBN · pages · format · description'**
  String get formMoreDetailsSummary;

  /// Banner after a barcode scan prefilled the add-book form
  ///
  /// In en, this message translates to:
  /// **'Filled from your barcode scan — check and edit anything'**
  String get formPrefillScan;

  /// Banner after the cover-photo extraction prefilled the add-book form
  ///
  /// In en, this message translates to:
  /// **'Read from your photos — check and edit anything'**
  String get formPrefillPhotos;

  /// One-line consequence note under the sticky Save button on the add-book form
  ///
  /// In en, this message translates to:
  /// **'Saved books join the shared catalog for every reader'**
  String get formSaveHint;

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

  /// Button that creates a library entry for the current edition
  ///
  /// In en, this message translates to:
  /// **'Add to my library'**
  String get bookAddToLibrary;

  /// Section header above the personal book sections
  ///
  /// In en, this message translates to:
  /// **'Your copy'**
  String get bookYourCopy;

  /// Snackbar when a cover upload fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the cover. Try again.'**
  String get coverUploadFailed;

  /// Snackbar when a cover upload succeeds
  ///
  /// In en, this message translates to:
  /// **'Cover updated'**
  String get coverUploaded;

  /// Label under the star rating control on the book detail screen
  ///
  /// In en, this message translates to:
  /// **'your rating'**
  String get bookYourRating;

  /// Eyebrow label on the progress card
  ///
  /// In en, this message translates to:
  /// **'PROGRESS'**
  String get bookProgressLabel;

  /// Progress card value — current page of total pages with percent
  ///
  /// In en, this message translates to:
  /// **'p. {page} of {total} · {percent}%'**
  String bookProgressValue(int page, int total, int percent);

  /// Progress card value when the total page count is unknown
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String bookProgressPage(int page);

  /// Title of the warning when lending a book that's currently being read
  ///
  /// In en, this message translates to:
  /// **'You\'re reading this'**
  String get lendReadingWarnTitle;

  /// Body of the reading-state lend warning
  ///
  /// In en, this message translates to:
  /// **'This book is on your Reading shelf. Lend it out anyway?'**
  String get lendReadingWarnBody;

  /// Confirm lending a book that's being read
  ///
  /// In en, this message translates to:
  /// **'Lend anyway'**
  String get lendReadingWarnConfirm;

  /// Eyebrow label for the start date on the progress card
  ///
  /// In en, this message translates to:
  /// **'STARTED'**
  String get bookStartedLabel;

  /// Progress card placeholder when no start date is set
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get bookNotStarted;

  /// Dialog title for editing reading progress
  ///
  /// In en, this message translates to:
  /// **'Edit progress'**
  String get bookEditProgress;

  /// Inline edit action beside the started date on the reading card
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get bookProgressEdit;

  /// Started-date line on the reading card
  ///
  /// In en, this message translates to:
  /// **'Started {date}'**
  String bookStartedOn(String date);

  /// Primary button on the reading card that opens the reading timer
  ///
  /// In en, this message translates to:
  /// **'Start a session'**
  String get bookStartSession;

  /// Title of the reading-log bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Reading log'**
  String get bookReadingLogTitle;

  /// Count of reading sessions
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sessions} =1{1 session} other{{count} sessions}}'**
  String bookLogSessions(int count);

  /// Footer on the reading card showing when the book was last read
  ///
  /// In en, this message translates to:
  /// **'Last read {when}'**
  String bookLogLastRead(String when);

  /// Page range a session moved through
  ///
  /// In en, this message translates to:
  /// **'p. {from} → {to}'**
  String bookLogPages(int from, int to);

  /// Shown for a session that logged no page range
  ///
  /// In en, this message translates to:
  /// **'Page not noted'**
  String get bookLogNoPages;

  /// Empty state in the reading-log sheet
  ///
  /// In en, this message translates to:
  /// **'No reading sessions yet — start one to build your log.'**
  String get bookLogEmpty;

  /// Swipe action to remove a reading session
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get bookLogDelete;

  /// Snackbar after deleting a reading session
  ///
  /// In en, this message translates to:
  /// **'Session removed'**
  String get bookLogDeleted;

  /// Label above the reading-log week sparkline
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get bookLogWeek;

  /// Text field label in the edit-progress dialog
  ///
  /// In en, this message translates to:
  /// **'Current page'**
  String get bookCurrentPage;

  /// Eyebrow label on the review card
  ///
  /// In en, this message translates to:
  /// **'MY REVIEW'**
  String get bookReviewLabel;

  /// Review card placeholder before a review exists
  ///
  /// In en, this message translates to:
  /// **'No review yet — tap to write one.'**
  String get bookReviewEmpty;

  /// Review visibility toggle option
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get bookReviewVisibilityPrivate;

  /// Review visibility toggle option
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get bookReviewVisibilityPublic;

  /// Dialog title for editing a review
  ///
  /// In en, this message translates to:
  /// **'Edit review'**
  String get bookEditReview;

  /// Eyebrow label over the list of other readers' public reviews
  ///
  /// In en, this message translates to:
  /// **'WHAT READERS ARE SAYING'**
  String get bookReadersReviewsLabel;

  /// Empty state when no other reader has left a public review
  ///
  /// In en, this message translates to:
  /// **'No public reviews yet.'**
  String get bookReadersReviewsEmpty;

  /// Book page tab: the reader's own copy — status, review, notes, lending
  ///
  /// In en, this message translates to:
  /// **'Yours'**
  String get bookYoursTab;

  /// Book page tab: the shared catalogue record — description, reviews, editions
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get bookAboutTab;

  /// Tappable label next to the current reading status, opens the status-change sheet
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get bookChangeStatus;

  /// Title of the bottom sheet listing the five reading statuses
  ///
  /// In en, this message translates to:
  /// **'Set status'**
  String get bookStatusSheetTitle;

  /// Review sort option: newest first
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get bookSortNewest;

  /// Review sort option: highest star rating first
  ///
  /// In en, this message translates to:
  /// **'Highest rated'**
  String get bookSortRatingHigh;

  /// Review sort option: lowest star rating first
  ///
  /// In en, this message translates to:
  /// **'Lowest rated'**
  String get bookSortRatingLow;

  /// Heading over the public reviews list
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No reviews yet} =1{1 review} other{{count} reviews}}'**
  String bookReviewsCount(int count);

  /// Caption under the numeric average in the rating distribution
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No ratings yet} =1{1 rating} other{{count} ratings}}'**
  String bookRatingsCount(int count);

  /// Button revealing the next batch of already-fetched reviews
  ///
  /// In en, this message translates to:
  /// **'Show {count} more reviews'**
  String bookShowMoreReviews(int count);

  /// Shown instead of stars when a public reviewer left text but no star rating
  ///
  /// In en, this message translates to:
  /// **'no rating'**
  String get bookNoRatingLabel;

  /// App bar title of the dedicated review/rating editor page
  ///
  /// In en, this message translates to:
  /// **'Rate & review'**
  String get reviewPageTitle;

  /// Eyebrow label above the star row on the review editor page
  ///
  /// In en, this message translates to:
  /// **'YOUR RATING'**
  String get reviewRatingLabel;

  /// Placeholder inside the review text area
  ///
  /// In en, this message translates to:
  /// **'What did you think?'**
  String get reviewBodyHint;

  /// Hint under the review visibility toggle explaining what public means
  ///
  /// In en, this message translates to:
  /// **'Public reviews will be visible to others when Kitabi\'s community features launch.'**
  String get reviewVisibilityHint;

  /// Snackbar after the review editor saves
  ///
  /// In en, this message translates to:
  /// **'Review saved'**
  String get reviewSaved;

  /// Title of the popup shown after marking a book as read, inviting a rating/review
  ///
  /// In en, this message translates to:
  /// **'You finished it!'**
  String get reviewFinishedTitle;

  /// Subtitle under the finished-reading popup's title
  ///
  /// In en, this message translates to:
  /// **'How was it? Tap a star to rate, or write a few words.'**
  String get reviewFinishedSubtitle;

  /// Primary button on the finished-reading popup that opens the full review editor
  ///
  /// In en, this message translates to:
  /// **'Write a review'**
  String get reviewFinishedAction;

  /// Low-emphasis dismiss action on the finished-reading popup
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get reviewFinishedSkip;

  /// Tooltip on the expand icon that opens a text field full screen
  ///
  /// In en, this message translates to:
  /// **'Edit full screen'**
  String get formFieldExpand;

  /// Action that closes the full-screen text editor
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get formEditorDone;

  /// Caption in the full-screen cover viewer for the front photo
  ///
  /// In en, this message translates to:
  /// **'Front cover'**
  String get coverFrontLabel;

  /// Caption in the full-screen cover viewer for the back photo
  ///
  /// In en, this message translates to:
  /// **'Back cover'**
  String get coverBackLabel;

  /// Title of the popup after a new book is created
  ///
  /// In en, this message translates to:
  /// **'Added to the catalog'**
  String get createdDialogTitle;

  /// Popup action that puts the just-created book into the user's library
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get createdAddToLibrary;

  /// Popup action label while the add-to-library write is running
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get createdAdding;

  /// Popup action label once the book is in the library
  ///
  /// In en, this message translates to:
  /// **'Added ✓'**
  String get createdAdded;

  /// Popup action that clears the form to add one more book
  ///
  /// In en, this message translates to:
  /// **'Create another'**
  String get createdCreateAnother;

  /// Popup action that dismisses the popup and leaves the add-book screen
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get createdClose;

  /// Header of the description/details section on the book page
  ///
  /// In en, this message translates to:
  /// **'About this book'**
  String get bookAboutSection;

  /// Placeholder when a book has no description
  ///
  /// In en, this message translates to:
  /// **'No description yet — know this book? Improve the entry.'**
  String get bookDescriptionEmpty;

  /// Encyclopedia-style edit affordance on the book page
  ///
  /// In en, this message translates to:
  /// **'Improve this entry'**
  String get bookImproveEntry;

  /// Snackbar when a catalog edit is queued for the contributor's approval instead of applying live
  ///
  /// In en, this message translates to:
  /// **'Edit sent — the reader who added this book will review it.'**
  String get editPendingApproval;

  /// Title of the approval inbox screen and its profile row
  ///
  /// In en, this message translates to:
  /// **'Pending edits'**
  String get revisionsTitle;

  /// Profile row subtitle for the approval inbox
  ///
  /// In en, this message translates to:
  /// **'Suggested changes to books you added'**
  String get revisionsSubtitle;

  /// Empty state of the approval inbox
  ///
  /// In en, this message translates to:
  /// **'Nothing to review — suggested edits to books you added will appear here.'**
  String get revisionsEmpty;

  /// Who proposed a pending edit
  ///
  /// In en, this message translates to:
  /// **'Suggested by {name}'**
  String revisionsProposedBy(String name);

  /// Apply a pending edit
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get revisionsApprove;

  /// Discard a pending edit
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get revisionsReject;

  /// Snackbar after approving a pending edit
  ///
  /// In en, this message translates to:
  /// **'Edit approved and applied.'**
  String get revisionsApproved;

  /// Snackbar after rejecting a pending edit
  ///
  /// In en, this message translates to:
  /// **'Edit rejected.'**
  String get revisionsRejected;

  /// Tappable action in the borrower field when no Kitabi user matches
  ///
  /// In en, this message translates to:
  /// **'Keep “{name}” as a private contact'**
  String borrowerKeepPrivate(String name);

  /// Subtitle under the keep-as-private action
  ///
  /// In en, this message translates to:
  /// **'They don\'t need Kitabi — the loan stays in your own ledger.'**
  String get borrowerKeepPrivateHint;

  /// Connections screen section for free-text lending contacts
  ///
  /// In en, this message translates to:
  /// **'Private contacts'**
  String get connectionsPrivateSection;

  /// Private contact card subtitle
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No open loans} =1{1 book out} other{{count} books out}} · not on Kitabi'**
  String connectionsPrivateLoans(int count);

  /// Button that links a private contact to a Kitabi account
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get connectionsLinkAction;

  /// Title of the link-contact dialog
  ///
  /// In en, this message translates to:
  /// **'Link “{name}” to a Kitabi account'**
  String linkContactTitle(String name);

  /// Explainer in the link-contact dialog
  ///
  /// In en, this message translates to:
  /// **'Their loans move onto the linked account and a connection request is sent.'**
  String get linkContactBody;

  /// Search hint in the link-contact dialog
  ///
  /// In en, this message translates to:
  /// **'Search by name or @username'**
  String get linkContactSearchHint;

  /// Empty result in the link-contact dialog
  ///
  /// In en, this message translates to:
  /// **'No matching readers.'**
  String get linkContactNoResults;

  /// Snackbar after linking a private contact
  ///
  /// In en, this message translates to:
  /// **'Linked — connection request sent.'**
  String get linkContactDone;

  /// Open-loan count on an accepted connection card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open loan} other{{count} open loans}}'**
  String connectionsLoansWithThem(int count);

  /// Ledger summary chip: books currently lent out
  ///
  /// In en, this message translates to:
  /// **'{count} out'**
  String lendingSummaryOut(int count);

  /// Ledger summary chip: overdue loans
  ///
  /// In en, this message translates to:
  /// **'{count} overdue'**
  String lendingSummaryOverdue(int count);

  /// Ledger summary chip: books borrowed right now
  ///
  /// In en, this message translates to:
  /// **'{count} with you'**
  String lendingSummaryBorrowed(int count);

  /// Bottom-nav label for the global search
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// Home greeting before noon, with the reader's first name
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String homeGreetingMorning(String name);

  /// Home greeting 12–17h
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}'**
  String homeGreetingAfternoon(String name);

  /// Home greeting from 17h
  ///
  /// In en, this message translates to:
  /// **'Good evening, {name}'**
  String homeGreetingEvening(String name);

  /// Home greeting before noon, no name known
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGreetingMorningAnon;

  /// Home greeting 12–17h, no name known
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGreetingAfternoonAnon;

  /// Home greeting from 17h, no name known
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGreetingEveningAnon;

  /// Section label over the recently-added cover strip
  ///
  /// In en, this message translates to:
  /// **'Fresh on your shelf'**
  String get homeFreshShelf;

  /// Eyebrow on the home goal slip
  ///
  /// In en, this message translates to:
  /// **'Reading goal'**
  String get homeGoalLabel;

  /// Suffix beside the hero number on the goal slip, e.g. "of 30 books this year"
  ///
  /// In en, this message translates to:
  /// **'of {goal} books this year'**
  String homeGoalOf(int goal);

  /// Goal slip line when nothing read yet
  ///
  /// In en, this message translates to:
  /// **'Set a goal for {year} — even a small one.'**
  String homeGoalStart(int year);

  /// Empty-home step 1 title
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get homeStepScanTitle;

  /// Empty-home step 1 body
  ///
  /// In en, this message translates to:
  /// **'Point the camera at any barcode — the book fills itself in.'**
  String get homeStepScanBody;

  /// Empty-home step 2 title
  ///
  /// In en, this message translates to:
  /// **'Shelve'**
  String get homeStepShelveTitle;

  /// Empty-home step 2 body
  ///
  /// In en, this message translates to:
  /// **'Track what you own, what you\'ve read, and what you wish for.'**
  String get homeStepShelveBody;

  /// Empty-home step 3 title
  ///
  /// In en, this message translates to:
  /// **'Lend'**
  String get homeStepLendTitle;

  /// Empty-home step 3 body
  ///
  /// In en, this message translates to:
  /// **'Hand a book to a friend and never lose track of it again.'**
  String get homeStepLendBody;

  /// Empty-home tertiary action
  ///
  /// In en, this message translates to:
  /// **'Browse the catalogue'**
  String get homeBrowseCatalogue;

  /// Eyebrow on the rotating reading-fact card
  ///
  /// In en, this message translates to:
  /// **'Did you know'**
  String get insightsFactLabel;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'Reading just 20 minutes a day adds up to nearly two million words a year.'**
  String get insightsFact1;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'Six minutes of reading can lower stress by more than two-thirds — faster than music or a walk.'**
  String get insightsFact2;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'The average paperback is about 300 pages — a chapter a night finishes it in a month.'**
  String get insightsFact3;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'Malayalam\'s first novel, Kundalatha, was published in 1887.'**
  String get insightsFact4;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'Readers who set a goal finish about twice as many books as those who don\'t.'**
  String get insightsFact5;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'The word \'bookworm\' predates the printing press — it first meant an actual insect.'**
  String get insightsFact6;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'Re-reading a loved book is proven to feel as rewarding as the first time — comfort reads count.'**
  String get insightsFact7;

  /// Rotating reading fact
  ///
  /// In en, this message translates to:
  /// **'Kerala runs one of the world\'s densest library networks — over 8,000 public libraries.'**
  String get insightsFact8;

  /// Fresh-user insights headline
  ///
  /// In en, this message translates to:
  /// **'Your reading year starts here'**
  String get insightsFreshTitle;

  /// Fresh-user insights sub-line
  ///
  /// In en, this message translates to:
  /// **'Finish your first book and this page becomes your personal reading almanac.'**
  String get insightsFreshBody;

  /// Label over the fresh-user preview rows
  ///
  /// In en, this message translates to:
  /// **'What grows here'**
  String get insightsGrowsLabel;

  /// Fresh-user preview row
  ///
  /// In en, this message translates to:
  /// **'Books per month, charted'**
  String get insightsComingBars;

  /// Fresh-user preview row
  ///
  /// In en, this message translates to:
  /// **'Pages over the year'**
  String get insightsComingPages;

  /// Fresh-user preview row
  ///
  /// In en, this message translates to:
  /// **'Your language mix'**
  String get insightsComingLangs;

  /// Fresh-user preview row
  ///
  /// In en, this message translates to:
  /// **'Your most-read author'**
  String get insightsComingAuthor;

  /// Fresh-user insights CTA
  ///
  /// In en, this message translates to:
  /// **'Add your first book'**
  String get insightsAddFirstBook;

  /// Goal ring caption when no goal-progress exists yet
  ///
  /// In en, this message translates to:
  /// **'Tap to set your {year} goal'**
  String insightsSetGoalHint(int year);

  /// Stat tile label
  ///
  /// In en, this message translates to:
  /// **'Most-read author'**
  String get insightsTopAuthor;

  /// Stat tile label
  ///
  /// In en, this message translates to:
  /// **'Longest book finished'**
  String get insightsLongestBook;

  /// Stat tile label
  ///
  /// In en, this message translates to:
  /// **'Avg pages per book'**
  String get insightsAvgPages;

  /// Search field hint in the lend pick-book sheet
  ///
  /// In en, this message translates to:
  /// **'Search your books'**
  String get lendingPickSearchHint;

  /// Button on a wishlist entry's book page that makes it owned
  ///
  /// In en, this message translates to:
  /// **'I got this book — move to my library'**
  String get bookGotIt;

  /// Snackbar after a wishlist entry becomes owned
  ///
  /// In en, this message translates to:
  /// **'Moved to your library.'**
  String get bookMovedToLibrary;

  /// Global search section header for Kitabi users
  ///
  /// In en, this message translates to:
  /// **'Readers'**
  String get searchReadersHeader;

  /// App bar title of another reader's public profile
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get publicProfileTitle;

  /// Shown when a visited profile is not public
  ///
  /// In en, this message translates to:
  /// **'This reader keeps their profile private.'**
  String get publicProfilePrivate;

  /// Section header over a public library grid
  ///
  /// In en, this message translates to:
  /// **'Their shelf'**
  String get publicLibrarySection;

  /// Shown when the visited reader's library is not public
  ///
  /// In en, this message translates to:
  /// **'Their library is private.'**
  String get publicLibraryPrivate;

  /// Search field placeholder inside a public shelf grid
  ///
  /// In en, this message translates to:
  /// **'Search their shelf'**
  String get publicShelfSearchHint;

  /// Empty state when a public shelf search has no matches
  ///
  /// In en, this message translates to:
  /// **'No books match your search.'**
  String get publicShelfSearchEmpty;

  /// Caption under the tracked-books count on a public profile
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get publicProfileBooksLabel;

  /// Caption under the contribution score on a public profile
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get publicProfileScoreLabel;

  /// Caption under the connections count on a public profile
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get publicProfileConnectionsLabel;

  /// Small eyebrow label above a reader's name on their bookplate-style profile header
  ///
  /// In en, this message translates to:
  /// **'Ex Libris'**
  String get publicProfileExLibris;

  /// Profile tab: the lending ledger between you and this reader
  ///
  /// In en, this message translates to:
  /// **'Ledger'**
  String get publicProfileTabLedger;

  /// Profile tab: this reader's public library
  ///
  /// In en, this message translates to:
  /// **'Shelf'**
  String get publicProfileTabShelf;

  /// Profile tab: catalog works this reader is the linked author of — only shown when they have at least one
  ///
  /// In en, this message translates to:
  /// **'Works'**
  String get publicProfileTabWorks;

  /// Button to send a connection request from a public profile
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get publicProfileConnect;

  /// Snackbar after sending a request from a public profile
  ///
  /// In en, this message translates to:
  /// **'Connection request sent.'**
  String get publicProfileRequestSent;

  /// Eyebrow label on the personal notes card
  ///
  /// In en, this message translates to:
  /// **'PERSONAL NOTES · always private'**
  String get bookNotesLabel;

  /// Personal notes card placeholder
  ///
  /// In en, this message translates to:
  /// **'Tap to add a private note — edition, condition, why this copy matters.'**
  String get bookNotesEmpty;

  /// Dialog title for editing personal notes
  ///
  /// In en, this message translates to:
  /// **'Edit notes'**
  String get bookEditNotes;

  /// Lending card status when the book isn't currently lent
  ///
  /// In en, this message translates to:
  /// **'Not lent out.'**
  String get bookLendingNotLentOut;

  /// Fragment before the tappable borrower name on the book page's lending header
  ///
  /// In en, this message translates to:
  /// **'With'**
  String get bookLendingWithFragment;

  /// Section label above the per-book lending/borrowing history rows
  ///
  /// In en, this message translates to:
  /// **'Lending history'**
  String get bookLendingHistoryLabel;

  /// Stamp on an active (not yet returned) row in the book's lending history
  ///
  /// In en, this message translates to:
  /// **'Out now'**
  String get bookLendingOutStamp;

  /// Lending card status when the book is currently lent out
  ///
  /// In en, this message translates to:
  /// **'With {name}'**
  String bookLendingWithSomeone(String name);

  /// Lending card secondary line
  ///
  /// In en, this message translates to:
  /// **'{count} past {count, plural, one{lending} other{lendings}}'**
  String bookLendingPastCount(int count);

  /// Lending card action button when not currently lent
  ///
  /// In en, this message translates to:
  /// **'Lend'**
  String get bookLendAction;

  /// Fragment before the tappable lender name on the lending header, for a borrowed copy
  ///
  /// In en, this message translates to:
  /// **'Borrowed from'**
  String get bookBorrowedFromFragment;

  /// Lending card status once a borrowed copy has been given back, but stays on the shelf
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get bookBorrowedReturnedFragment;

  /// Lending card action: the reader bought their own copy of a book they'd borrowed
  ///
  /// In en, this message translates to:
  /// **'Make this mine'**
  String get bookMakeMineAction;

  /// Confirmation dialog title for the make-this-mine action
  ///
  /// In en, this message translates to:
  /// **'Make this your own copy?'**
  String get bookMakeMineConfirmTitle;

  /// Confirmation dialog body for the make-this-mine action
  ///
  /// In en, this message translates to:
  /// **'This moves the book to your library as your own copy. Your reading status, progress, and notes stay exactly as they are — the record of borrowing it stays too, in the lending history below.'**
  String get bookMakeMineConfirmBody;

  /// Lending card action button when currently lent out
  ///
  /// In en, this message translates to:
  /// **'Mark returned'**
  String get bookMarkReturnedAction;

  /// Dialog title for recording a new loan
  ///
  /// In en, this message translates to:
  /// **'Lend this book'**
  String get bookLendDialogTitle;

  /// Text field label in the lend dialog
  ///
  /// In en, this message translates to:
  /// **'Borrower\'s name'**
  String get bookLendBorrowerName;

  /// Generic cancel button in book detail dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get bookCancel;

  /// Generic save button in book detail dialogs
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get bookSave;

  /// ISBN footer on the book detail screen
  ///
  /// In en, this message translates to:
  /// **'ISBN {isbn}'**
  String bookIsbnLabel(String isbn);

  /// Author byline on the book page hero
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String bookByAuthor(String name);

  /// Page count in the book page's compact meta line
  ///
  /// In en, this message translates to:
  /// **'{count} pp'**
  String bookPagesShort(int count);

  /// Title on the personal library grid screen
  ///
  /// In en, this message translates to:
  /// **'My Library'**
  String get libraryTitle;

  /// Band on a borrowed book cover naming the lender
  ///
  /// In en, this message translates to:
  /// **'FROM {name}'**
  String libraryBorrowedFrom(String name);

  /// Book count subtitle on the library grid screen
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{book} other{books}}'**
  String libraryBookCount(int count);

  /// Library grid filter chip
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libraryFilterAll;

  /// Library grid filter chip
  ///
  /// In en, this message translates to:
  /// **'★ Favourites'**
  String get libraryFilterFavourites;

  /// Title of the empty library state
  ///
  /// In en, this message translates to:
  /// **'Your shelf is waiting'**
  String get libraryEmptyTitle;

  /// Empty state on the library grid screen
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet — search or scan a book to add it.'**
  String get libraryEmpty;

  /// Shown when active filters exclude every book
  ///
  /// In en, this message translates to:
  /// **'No books match these filters.'**
  String get libraryNoMatches;

  /// Library view toggle: the flat grid of every book
  ///
  /// In en, this message translates to:
  /// **'All books'**
  String get libraryViewAll;

  /// Library view toggle: books grouped onto shelves (statuses, favourites, personal tags)
  ///
  /// In en, this message translates to:
  /// **'Shelves'**
  String get libraryViewShelves;

  /// Tile in the shelves view that creates a new personal shelf
  ///
  /// In en, this message translates to:
  /// **'New shelf'**
  String get libraryNewShelf;

  /// Dialog title when creating a new shelf from the shelves view
  ///
  /// In en, this message translates to:
  /// **'Name your shelf'**
  String get libraryNewShelfTitle;

  /// Text-field hint in the new-shelf dialog
  ///
  /// In en, this message translates to:
  /// **'e.g. Signed copies'**
  String get libraryNewShelfHint;

  /// Header over the status/Favourites shelf row — the shelves the app gives you
  ///
  /// In en, this message translates to:
  /// **'Where your books stand'**
  String get libraryShelvesStatusSection;

  /// Header over the grid of shelves the reader created
  ///
  /// In en, this message translates to:
  /// **'Your shelves'**
  String get libraryShelvesYoursSection;

  /// The built-in shelf holding every favourited book
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get libraryShelfFavourites;

  /// Filter sheet section header for the reader's personal shelves
  ///
  /// In en, this message translates to:
  /// **'Shelf'**
  String get libraryFilterShelf;

  /// Title of the library sort sheet, and the sort action's label on the floating control
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get librarySortTitle;

  /// Sort option: newest additions first (the default)
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get librarySortRecent;

  /// Sort option: alphabetical by title
  ///
  /// In en, this message translates to:
  /// **'Title A–Z'**
  String get librarySortAZ;

  /// Sort option: alphabetical by author, then title
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get librarySortAuthor;

  /// Accessibility label for the collapsed floating library control
  ///
  /// In en, this message translates to:
  /// **'Search, filter and sort'**
  String get libraryFabLabel;

  /// Title of the library filter sheet (S4b)
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get libraryFilterTitle;

  /// Filter sheet section header for reading status
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get libraryFilterStatus;

  /// Filter sheet section header for language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get libraryFilterLanguage;

  /// Filter sheet section header for the literary form (Novel, Short stories, ...)
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get libraryFilterType;

  /// Filter sheet section header for genre
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get libraryFilterGenre;

  /// Filter sheet toggle to show only favourited books
  ///
  /// In en, this message translates to:
  /// **'Favourites only'**
  String get libraryFilterFavouritesOnly;

  /// Clears all active filters
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get libraryFilterClear;

  /// Apply button on the filter sheet with a live count
  ///
  /// In en, this message translates to:
  /// **'Show {count} {count, plural, one{book} other{books}}'**
  String libraryFilterShow(int count);

  /// Menu action that removes the book from the user's library
  ///
  /// In en, this message translates to:
  /// **'Remove from library'**
  String get bookRemoveFromLibrary;

  /// Confirmation dialog body before removing a library entry
  ///
  /// In en, this message translates to:
  /// **'Remove this book from your library? Your rating and review stay on the shared catalog entry, but this copy, its reading progress, and its notes are gone.'**
  String get bookRemoveConfirm;

  /// Eyebrow label on the personal tags/shelves row
  ///
  /// In en, this message translates to:
  /// **'SHELVES · yours only'**
  String get bookTagsLabel;

  /// Eyebrow above the book page's shelf card when the book is on a shelf
  ///
  /// In en, this message translates to:
  /// **'On a shelf'**
  String get bookShelfLabel;

  /// Eyebrow above the book page's shelf card when the book is on no shelf
  ///
  /// In en, this message translates to:
  /// **'Shelf · yours only'**
  String get bookShelfLabelEmpty;

  /// Count of the other books sharing this shelf
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Just this copy on it} =1{This copy + 1 other} other{This copy + {count} others}}'**
  String bookShelfOthers(int count);

  /// Action on the book page shelf card that opens the shelf picker
  ///
  /// In en, this message translates to:
  /// **'Move to another shelf'**
  String get bookShelfMove;

  /// Action that takes the book off its shelf
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get bookShelfRemove;

  /// Title of the book page shelf card when the book is on no shelf
  ///
  /// In en, this message translates to:
  /// **'Not on a shelf yet'**
  String get bookShelfEmptyTitle;

  /// Subtitle of the empty shelf card
  ///
  /// In en, this message translates to:
  /// **'Keep it somewhere of your own'**
  String get bookShelfEmptyBody;

  /// Action that opens the shelf picker from the empty shelf card
  ///
  /// In en, this message translates to:
  /// **'Choose a shelf'**
  String get bookShelfChoose;

  /// Chip that opens the new-tag dialog
  ///
  /// In en, this message translates to:
  /// **'+ add'**
  String get bookAddTag;

  /// Dialog title for creating/choosing a personal tag
  ///
  /// In en, this message translates to:
  /// **'Add to a shelf'**
  String get bookNewTagTitle;

  /// Text field hint in the new-tag dialog
  ///
  /// In en, this message translates to:
  /// **'e.g. beach reads'**
  String get bookNewTagHint;

  /// Title of the sheet that picks which shelves a book sits on
  ///
  /// In en, this message translates to:
  /// **'Add to a shelf'**
  String get shelfPickerTitle;

  /// Subtitle on the shelf-picker sheet
  ///
  /// In en, this message translates to:
  /// **'Tap a shelf to add or remove this book'**
  String get shelfPickerHint;

  /// Shown in the shelf-picker sheet when the reader has no shelves
  ///
  /// In en, this message translates to:
  /// **'No shelves yet — create your first below.'**
  String get shelfPickerEmpty;

  /// Title of the empty state for an opened personal shelf with no books
  ///
  /// In en, this message translates to:
  /// **'This shelf is empty'**
  String get libraryShelfEmptyTitle;

  /// Body of the empty-shelf state
  ///
  /// In en, this message translates to:
  /// **'Shelves are yours to arrange — move a book you already own onto this one.'**
  String get libraryShelfEmptyBody;

  /// Button that opens the picker to add existing library books to a shelf
  ///
  /// In en, this message translates to:
  /// **'Add books to this shelf'**
  String get libraryShelfAddBooks;

  /// Title of the sheet that adds existing books to a named shelf
  ///
  /// In en, this message translates to:
  /// **'Add to {shelf}'**
  String libraryAddToShelfTitle(String shelf);

  /// Subtitle on the add-books-to-shelf sheet
  ///
  /// In en, this message translates to:
  /// **'Tap a book to shelve or unshelve it'**
  String get libraryAddBooksHint;

  /// Shown when there are no library books to add to a shelf
  ///
  /// In en, this message translates to:
  /// **'Your library is empty — add a book first.'**
  String get libraryAddBooksEmpty;

  /// Short label for the add-books action on an open shelf
  ///
  /// In en, this message translates to:
  /// **'Add books'**
  String get libraryShelfAddBooksShort;

  /// Hint in the search field on the add-books-to-shelf sheet
  ///
  /// In en, this message translates to:
  /// **'Search your library'**
  String get libraryAddBooksSearchHint;

  /// Title when the add-books search matches no owned book
  ///
  /// In en, this message translates to:
  /// **'Not in your library'**
  String get libraryAddBooksNoMatchTitle;

  /// Body guiding the reader to the catalogue when a shelf search matches nothing
  ///
  /// In en, this message translates to:
  /// **'Only books you already have can go on a shelf. Find it in the catalogue to add it to your library first.'**
  String get libraryAddBooksNoMatchBody;

  /// Button that leaves the add-books sheet for the catalogue search
  ///
  /// In en, this message translates to:
  /// **'Browse the catalogue'**
  String get libraryAddBooksBrowse;

  /// Snackbar confirming a scanned book was added to the personal library
  ///
  /// In en, this message translates to:
  /// **'Added to your library'**
  String get scanAddedToLibrary;

  /// Section header on the home screen for books with the reading status
  ///
  /// In en, this message translates to:
  /// **'Currently reading'**
  String get homeCurrentlyReading;

  /// Section header on the home screen previewing the personal library
  ///
  /// In en, this message translates to:
  /// **'Your library'**
  String get homeYourLibrary;

  /// Link to the full library grid from the home screen preview
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get homeSeeAll;

  /// Title of the empty state on the home screen
  ///
  /// In en, this message translates to:
  /// **'Your first shelf awaits'**
  String get homeEmptyTitle;

  /// Body of the empty state on the home screen
  ///
  /// In en, this message translates to:
  /// **'Every library starts with one book. Scan the one nearest you — the rest follows.'**
  String get homeEmptyBody;

  /// Primary call to action on the home screen that opens search/add
  ///
  /// In en, this message translates to:
  /// **'Add a book'**
  String get homeAddBook;

  /// Secondary call to action on the home screen that opens the ISBN scanner
  ///
  /// In en, this message translates to:
  /// **'Scan a barcode'**
  String get homeScanBarcode;

  /// Hint in the author autocomplete field on the add/edit form
  ///
  /// In en, this message translates to:
  /// **'Type to search or add an author'**
  String get formAuthorAddHint;

  /// Hint in the publisher autocomplete field on the add/edit form
  ///
  /// In en, this message translates to:
  /// **'Type to search or add a publisher'**
  String get formPublisherHint;

  /// Autocomplete option that creates a new author/publisher from the typed text
  ///
  /// In en, this message translates to:
  /// **'Add \"{name}\"'**
  String formAddNew(String name);

  /// Title of the lending ledger screen (S8)
  ///
  /// In en, this message translates to:
  /// **'Lending ledger'**
  String get lendingLedgerTitle;

  /// Subtitle counting books currently lent out
  ///
  /// In en, this message translates to:
  /// **'{count} out'**
  String lendingOutSubtitle(int count);

  /// Section header for books currently lent out
  ///
  /// In en, this message translates to:
  /// **'Out now'**
  String get lendingOutNowSection;

  /// Section header for books that have been returned
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get lendingReturnedSection;

  /// Lending card subtitle: borrower and lent-on date
  ///
  /// In en, this message translates to:
  /// **'to {name} · since {date}'**
  String lendingToPersonSince(String name, String date);

  /// Returned lending card: borrower and the lent–returned date range
  ///
  /// In en, this message translates to:
  /// **'{name} · {start} – {end}'**
  String lendingReturnedRange(String name, String start, String end);

  /// Fragment before a tappable borrower name on a lent card ('to' + name)
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get lendingToFragment;

  /// Fragment before a tappable lender name on a borrowed card ('from' + name)
  ///
  /// In en, this message translates to:
  /// **'from'**
  String get lendingFromFragment;

  /// Fragment after the tappable name on an active loan card
  ///
  /// In en, this message translates to:
  /// **'· since {date}'**
  String lendingSinceFragment(String date);

  /// Fragment after the tappable name on a returned loan card
  ///
  /// In en, this message translates to:
  /// **'· {start} – {end}'**
  String lendingRangeFragment(String start, String end);

  /// Due stamp when no due date is set
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get lendingNoDueDate;

  /// Due stamp counting days until the due date
  ///
  /// In en, this message translates to:
  /// **'Due in {days}d'**
  String lendingDueInDays(int days);

  /// Due stamp showing the due date
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String lendingDueOn(String date);

  /// Due stamp when the due date has passed
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get lendingOverdue;

  /// Stamp on a returned lending record
  ///
  /// In en, this message translates to:
  /// **'Returned ✓'**
  String get lendingReturnedStamp;

  /// Button that closes a lending record
  ///
  /// In en, this message translates to:
  /// **'Mark returned ✓'**
  String get lendingMarkReturned;

  /// Empty state on the lending ledger
  ///
  /// In en, this message translates to:
  /// **'Nothing lent out yet.\nLend a book from its page to start the ledger.'**
  String get lendingEmpty;

  /// Label for the optional due-date picker in the lend dialog
  ///
  /// In en, this message translates to:
  /// **'Due date · optional'**
  String get lendingDueDateOptional;

  /// Button/hint to pick a due date in the lend dialog
  ///
  /// In en, this message translates to:
  /// **'Set a due date'**
  String get lendingSetDueDate;

  /// Lent-out tab label with count
  ///
  /// In en, this message translates to:
  /// **'Lent out · {count}'**
  String lendingLentOutTab(int count);

  /// Borrowed tab label with count
  ///
  /// In en, this message translates to:
  /// **'Borrowed · {count}'**
  String lendingBorrowedTab(int count);

  /// Rejected tab label with count — lent books whose borrower declined the connection
  ///
  /// In en, this message translates to:
  /// **'Rejected · {count}'**
  String lendingRejectedTab(int count);

  /// Intro text on the Rejected tab of the lending ledger
  ///
  /// In en, this message translates to:
  /// **'These readers declined your connection request. The book is still with them — re-send the request, or make them a private contact you track yourself.'**
  String get lendingRejectedIntro;

  /// Empty state on the Rejected tab
  ///
  /// In en, this message translates to:
  /// **'No declined loans.\nIf someone declines your connection, the loan shows here.'**
  String get lendingRejectedEmpty;

  /// Stamp on a lent card whose borrower declined the connection
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get lendingDeclinedStamp;

  /// Button to re-send a declined connection request
  ///
  /// In en, this message translates to:
  /// **'Resend request'**
  String get lendingResendRequest;

  /// Snackbar after re-sending a connection request
  ///
  /// In en, this message translates to:
  /// **'Request re-sent.'**
  String get lendingResendSent;

  /// Button to unlink a Kitabi user from a loan and keep them as a private contact
  ///
  /// In en, this message translates to:
  /// **'Make private contact'**
  String get lendingMakePrivate;

  /// Confirm-dialog title for unlinking a Kitabi user from a loan
  ///
  /// In en, this message translates to:
  /// **'Make a private contact?'**
  String get lendingMakePrivateTitle;

  /// Confirm-dialog body for unlinking a Kitabi user from a loan
  ///
  /// In en, this message translates to:
  /// **'This unlinks {name}\'s Kitabi account from the loan. It stays on your ledger as a private contact you track yourself — they won\'t see it or get reminders.'**
  String lendingMakePrivateBody(String name);

  /// Confirm button for unlinking a Kitabi user from a loan
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get lendingMakePrivateConfirm;

  /// Text field label for the private contact name when unlinking
  ///
  /// In en, this message translates to:
  /// **'Contact name'**
  String get lendingContactNameLabel;

  /// Button to nudge a connected borrower to return a book
  ///
  /// In en, this message translates to:
  /// **'Remind'**
  String get lendingRemind;

  /// Snackbar after sending a return reminder
  ///
  /// In en, this message translates to:
  /// **'Reminder sent to {name}.'**
  String lendingReminderSent(String name);

  /// Snackbar when a return reminder fails to send
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the reminder. You may not be connected.'**
  String get lendingReminderFailed;

  /// Section header for books currently borrowed
  ///
  /// In en, this message translates to:
  /// **'With you now'**
  String get lendingWithYouNowSection;

  /// Borrowed card subtitle: lender and borrowed-on date
  ///
  /// In en, this message translates to:
  /// **'from {name} · since {date}'**
  String lendingFromPersonSince(String name, String date);

  /// Returned borrowed card: lender and the borrowed–returned date range
  ///
  /// In en, this message translates to:
  /// **'{name} · {start} – {end}'**
  String lendingBorrowedRange(String name, String start, String end);

  /// Sublabel on a self-logged borrowed record
  ///
  /// In en, this message translates to:
  /// **'Self-logged — just for your own tracking.'**
  String get lendingSelfLogged;

  /// Button that closes a borrowed record
  ///
  /// In en, this message translates to:
  /// **'I\'ve returned it ✓'**
  String get lendingReturnedIt;

  /// Empty state on the borrowed tab
  ///
  /// In en, this message translates to:
  /// **'Nothing borrowed yet.'**
  String get lendingBorrowedEmpty;

  /// Opens the log-a-borrowed-book sheet
  ///
  /// In en, this message translates to:
  /// **'+ Log a borrowed book'**
  String get lendingLogBorrowed;

  /// Floating action button on the lending ledger to start a new lend
  ///
  /// In en, this message translates to:
  /// **'Lend a book'**
  String get lendingLendBook;

  /// Title of the connections/requests inbox screen
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get connectionsTitle;

  /// Section header for incoming pending connection requests
  ///
  /// In en, this message translates to:
  /// **'Requests to approve'**
  String get connectionsIncomingSection;

  /// Section header for outgoing pending connection requests
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get connectionsOutgoingSection;

  /// Section header for accepted connections
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionsAcceptedSection;

  /// Section header — books lent to this connection
  ///
  /// In en, this message translates to:
  /// **'Lent to them'**
  String get connectionLoansLent;

  /// Section header — books borrowed from this connection
  ///
  /// In en, this message translates to:
  /// **'Borrowed from them'**
  String get connectionLoansBorrowed;

  /// Empty state on the per-connection loans screen
  ///
  /// In en, this message translates to:
  /// **'No books lent or borrowed with them yet.'**
  String get connectionLoansEmpty;

  /// Marks a loan that's been returned
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get connectionLoanReturned;

  /// Section header for requests the other person declined
  ///
  /// In en, this message translates to:
  /// **'Declined — you can resend'**
  String get connectionsRejectedSection;

  /// Section header for users you've blocked
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get connectionsBlockedSection;

  /// Subtitle under a declined (resendable) request
  ///
  /// In en, this message translates to:
  /// **'Declined your request'**
  String get connectionsDeclinedYou;

  /// Resend a previously declined connection request
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get connectionsResend;

  /// Block a user so they can't resend requests
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get connectionsBlock;

  /// Unblock a previously blocked user
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get connectionsUnblock;

  /// Empty state on the connections screen
  ///
  /// In en, this message translates to:
  /// **'No connections yet. When you lend a book to a Kitabi user, a connection request goes out here.'**
  String get connectionsEmpty;

  /// Subtitle under an incoming request
  ///
  /// In en, this message translates to:
  /// **'wants to connect'**
  String get connectionsWantsToConnect;

  /// Subtitle under an outgoing pending request
  ///
  /// In en, this message translates to:
  /// **'Waiting for them to accept'**
  String get connectionsAwaitingReply;

  /// Accept an incoming connection request
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get connectionsAccept;

  /// Deny an incoming connection request
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get connectionsDeny;

  /// Cancel an outgoing pending request
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get connectionsCancel;

  /// Disconnect an accepted connection
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get connectionsDisconnect;

  /// Tooltip for the connections icon on the lending ledger
  ///
  /// In en, this message translates to:
  /// **'Connection requests'**
  String get connectionsTooltip;

  /// Pill on a lent card when the borrower is a Kitabi user who hasn't accepted the connection yet
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get lendingPendingLink;

  /// Pill on a lent card when the borrower is a connected Kitabi user
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get lendingLinkedUser;

  /// Title of the sheet that picks which owned book to lend
  ///
  /// In en, this message translates to:
  /// **'Which book?'**
  String get lendingPickTitle;

  /// Empty state when there are no lendable books to pick
  ///
  /// In en, this message translates to:
  /// **'Add a book to your library first, then lend it from here.'**
  String get lendingPickEmpty;

  /// Row under the borrow sheet's book search: create the typed book in the catalog, then come back with it selected
  ///
  /// In en, this message translates to:
  /// **'＋ Add \"{title}\" to the catalog'**
  String logBorrowedAddNew(String title);

  /// Helper shown under the borrow sheet's book search when nothing matches the typed title
  ///
  /// In en, this message translates to:
  /// **'Not in the catalog yet? Add it — you\'ll come right back here.'**
  String get logBorrowedNotFound;

  /// Title of the log-borrowed bottom sheet (S8c)
  ///
  /// In en, this message translates to:
  /// **'Log a borrowed book'**
  String get logBorrowedTitle;

  /// Field label for the book picker
  ///
  /// In en, this message translates to:
  /// **'BOOK'**
  String get logBorrowedBookLabel;

  /// Hint in the book search field
  ///
  /// In en, this message translates to:
  /// **'Search a book…'**
  String get logBorrowedSearchHint;

  /// Field label for who lent the book
  ///
  /// In en, this message translates to:
  /// **'FROM'**
  String get logBorrowedFromLabel;

  /// Hint in the lender name field
  ///
  /// In en, this message translates to:
  /// **'Name, or search a Kitabi user'**
  String get logBorrowedFromHint;

  /// Field label for the borrowed-on date
  ///
  /// In en, this message translates to:
  /// **'BORROWED ON'**
  String get logBorrowedOnLabel;

  /// Field label for the optional reminder date
  ///
  /// In en, this message translates to:
  /// **'Remind me · optional'**
  String get logBorrowedRemindLabel;

  /// Field label for the optional note
  ///
  /// In en, this message translates to:
  /// **'Note · optional'**
  String get logBorrowedNoteLabel;

  /// Submit button on the log-borrowed sheet
  ///
  /// In en, this message translates to:
  /// **'Save to my borrowed shelf'**
  String get logBorrowedSave;

  /// Placeholder for an unset date field
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get logBorrowedNoDate;

  /// Verb prefix on the lend bottom sheet's title, styled distinctly from the book name that follows it (e.g. "Lend Chemmeen")
  ///
  /// In en, this message translates to:
  /// **'Lend'**
  String get lendSheetTitlePrefix;

  /// Field label for the borrower on the lend sheet
  ///
  /// In en, this message translates to:
  /// **'TO'**
  String get lendSheetToLabel;

  /// Hint in the borrower field on the lend sheet
  ///
  /// In en, this message translates to:
  /// **'Name, or search a Kitabi user'**
  String get lendSheetToHint;

  /// Subtitle on a matched Kitabi user in the borrower search
  ///
  /// In en, this message translates to:
  /// **'On Kitabi · {handle}'**
  String borrowerKitabiUser(String handle);

  /// Subtitle on a past free-text borrower suggestion
  ///
  /// In en, this message translates to:
  /// **'Private contact'**
  String get borrowerPrivateContact;

  /// Header above matched Kitabi users in the search results
  ///
  /// In en, this message translates to:
  /// **'KITABI USERS'**
  String get borrowerUsersHeader;

  /// Header above past-contact suggestions in the search results
  ///
  /// In en, this message translates to:
  /// **'RECENT'**
  String get borrowerRecentHeader;

  /// Shown when a search finds no Kitabi user
  ///
  /// In en, this message translates to:
  /// **'No Kitabi user “{query}”. It\'ll be saved as a private contact.'**
  String borrowerNoMatch(String query);

  /// Chip shown when a Kitabi user is picked/linked
  ///
  /// In en, this message translates to:
  /// **'Linked · {handle}'**
  String borrowerLinkedTo(String handle);

  /// Button to clear a linked Kitabi user and search again
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get borrowerChange;

  /// Field label for the lent-on date
  ///
  /// In en, this message translates to:
  /// **'LENT ON'**
  String get lendSheetLentOnLabel;

  /// Field label for the optional due date
  ///
  /// In en, this message translates to:
  /// **'Due date · optional'**
  String get lendSheetDueLabel;

  /// Submit button on the lend sheet
  ///
  /// In en, this message translates to:
  /// **'Lend it'**
  String get lendSheetSave;

  /// Notification title for a lent-book due-date reminder
  ///
  /// In en, this message translates to:
  /// **'A lent book is due'**
  String get reminderLentTitle;

  /// Notification body for a lent-book reminder
  ///
  /// In en, this message translates to:
  /// **'{title} — with {name}'**
  String reminderLentBody(String title, String name);

  /// Notification title for a borrowed-book due-date reminder
  ///
  /// In en, this message translates to:
  /// **'A borrowed book is due'**
  String get reminderBorrowedTitle;

  /// Notification body for a borrowed-book reminder
  ///
  /// In en, this message translates to:
  /// **'Return {title} to {name}'**
  String reminderBorrowedBody(String title, String name);

  /// Bottom navigation label for the home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation label for the library tab
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// Bottom navigation label for the lending tab
  ///
  /// In en, this message translates to:
  /// **'Lending'**
  String get navLending;

  /// Bottom navigation label for the insights tab
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get navInsights;

  /// Bottom navigation label for the add-a-book action
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get navAdd;

  /// Onboarding page 1 title
  ///
  /// In en, this message translates to:
  /// **'Beyond the bookshelf'**
  String get welcomeTitle1;

  /// Onboarding page 1 body
  ///
  /// In en, this message translates to:
  /// **'Track the books you own, what you\'re reading, and how your year is going — all yours, offline-first.'**
  String get welcomeBody1;

  /// Onboarding page 2 title
  ///
  /// In en, this message translates to:
  /// **'Lend, first-class and free'**
  String get welcomeTitle2;

  /// Onboarding page 2 body
  ///
  /// In en, this message translates to:
  /// **'Keep a real ledger of who has your books — and what you\'ve borrowed — with gentle due-date reminders.'**
  String get welcomeBody2;

  /// Onboarding page 3 title
  ///
  /// In en, this message translates to:
  /// **'Private by default'**
  String get welcomeTitle3;

  /// Onboarding page 3 body
  ///
  /// In en, this message translates to:
  /// **'Your library, reviews, and notes stay yours. Nothing is shared unless you choose to.'**
  String get welcomeBody3;

  /// Onboarding next button
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get welcomeNext;

  /// Onboarding finish button
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get welcomeGetStarted;

  /// Onboarding skip button
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get welcomeSkip;

  /// Title of the forced-update screen
  ///
  /// In en, this message translates to:
  /// **'Time to update'**
  String get updateTitle;

  /// Body of the forced-update screen
  ///
  /// In en, this message translates to:
  /// **'This version of Kitabi is out of date. Please update from the App Store to keep going.'**
  String get updateBody;

  /// Title of the import screen (S2)
  ///
  /// In en, this message translates to:
  /// **'Import books'**
  String get importTitle;

  /// Subtitle on the import screen
  ///
  /// In en, this message translates to:
  /// **'From a Goodreads export or any book CSV.'**
  String get importSubtitle;

  /// Button that opens the file picker
  ///
  /// In en, this message translates to:
  /// **'Choose a CSV file'**
  String get importPickFile;

  /// Instruction for pasting CSV text
  ///
  /// In en, this message translates to:
  /// **'…or open your Goodreads export (any book CSV) and paste its contents here.'**
  String get importPasteHint;

  /// Button that parses the pasted CSV and previews matches
  ///
  /// In en, this message translates to:
  /// **'Preview matches'**
  String get importPreviewButton;

  /// Progress text while parsing the CSV
  ///
  /// In en, this message translates to:
  /// **'Reading your file…'**
  String get importParsing;

  /// Summary of how many CSV rows matched the catalog
  ///
  /// In en, this message translates to:
  /// **'{matched} of {total} matched to the catalog'**
  String importMatched(int matched, int total);

  /// Note that unmatched rows won't be imported
  ///
  /// In en, this message translates to:
  /// **'Unmatched rows are skipped for now.'**
  String get importUnmatchedNote;

  /// Button that imports the matched books
  ///
  /// In en, this message translates to:
  /// **'Import {count} {count, plural, one{book} other{books}}'**
  String importAdd(int count);

  /// Snackbar after a successful import
  ///
  /// In en, this message translates to:
  /// **'Imported {count} {count, plural, one{book} other{books}}'**
  String importDone(int count);

  /// Shown when the CSV has no usable rows
  ///
  /// In en, this message translates to:
  /// **'No book rows found in that file.'**
  String get importEmpty;

  /// Profile entry point to the import screen
  ///
  /// In en, this message translates to:
  /// **'Import from Goodreads / CSV'**
  String get importEntry;

  /// Profile action that exports the library to CSV
  ///
  /// In en, this message translates to:
  /// **'Export my library (CSV)'**
  String get exportEntry;

  /// Shown when trying to export an empty library
  ///
  /// In en, this message translates to:
  /// **'Your library is empty — nothing to export yet.'**
  String get exportEmpty;

  /// Text accompanying the shared CSV file
  ///
  /// In en, this message translates to:
  /// **'My Kitabi library'**
  String get exportShareText;

  /// Title bar of the profile / account settings screen
  ///
  /// In en, this message translates to:
  /// **'Profile & settings'**
  String get profileTitle;

  /// Prompt on the profile when no username is set yet
  ///
  /// In en, this message translates to:
  /// **'Set a username'**
  String get profileUsernameSet;

  /// Explains why to set a username
  ///
  /// In en, this message translates to:
  /// **'A handle so friends can find you to lend books.'**
  String get profileUsernameHint;

  /// Header of the reputation/score card
  ///
  /// In en, this message translates to:
  /// **'REPUTATION'**
  String get profileScoreHeader;

  /// Unit label next to the score number
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{point} other{points}}'**
  String profileScorePoints(int count);

  /// Score breakdown row
  ///
  /// In en, this message translates to:
  /// **'Books added'**
  String get profileScoreBooksAdded;

  /// Score breakdown row
  ///
  /// In en, this message translates to:
  /// **'Authors added'**
  String get profileScoreAuthorsAdded;

  /// Score breakdown row
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get profileScoreReviews;

  /// Score breakdown row — books added to the library
  ///
  /// In en, this message translates to:
  /// **'Tracked'**
  String get profileScoreTracked;

  /// Score breakdown row — books read
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get profileScoreFinished;

  /// Score breakdown row
  ///
  /// In en, this message translates to:
  /// **'Lending'**
  String get profileScoreLending;

  /// Title of the set-username sheet
  ///
  /// In en, this message translates to:
  /// **'Your username'**
  String get usernameSheetTitle;

  /// Placeholder in the username field
  ///
  /// In en, this message translates to:
  /// **'e.g. shamshi_reads'**
  String get usernameFieldHint;

  /// Username is free
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get usernameAvailable;

  /// Username is taken
  ///
  /// In en, this message translates to:
  /// **'Already taken'**
  String get usernameTaken;

  /// Username format rule
  ///
  /// In en, this message translates to:
  /// **'3–20 characters: a letter, then letters, digits or _'**
  String get usernameInvalid;

  /// Save button on the username sheet
  ///
  /// In en, this message translates to:
  /// **'Save username'**
  String get usernameSave;

  /// Snackbar after saving a username
  ///
  /// In en, this message translates to:
  /// **'Username saved'**
  String get usernameSaved;

  /// Tooltip/label for the profile button on the home screen
  ///
  /// In en, this message translates to:
  /// **'Profile & settings'**
  String get profileEntry;

  /// Title of the activity screen
  ///
  /// In en, this message translates to:
  /// **'Your activity'**
  String get activityTitle;

  /// Profile entry to the activity screen
  ///
  /// In en, this message translates to:
  /// **'Your activity'**
  String get activityEntry;

  /// Empty state on the activity screen
  ///
  /// In en, this message translates to:
  /// **'Your reading activity — books added, finished, rated, lent — will show up here.'**
  String get activityEmpty;

  /// Activity: added a book
  ///
  /// In en, this message translates to:
  /// **'Added a book'**
  String get activityAddedBook;

  /// Activity: finished a book
  ///
  /// In en, this message translates to:
  /// **'Finished a book'**
  String get activityFinishedBook;

  /// Activity: rated a book
  ///
  /// In en, this message translates to:
  /// **'Rated a book'**
  String get activityRatedBook;

  /// Activity: wrote a review
  ///
  /// In en, this message translates to:
  /// **'Wrote a review'**
  String get activityWroteReview;

  /// Activity: lent a book
  ///
  /// In en, this message translates to:
  /// **'Lent a book'**
  String get activityLentBook;

  /// Relative day count for an activity entry
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{just now} one{1 day ago} other{{count} days ago}}'**
  String activityWhen(int count);

  /// Eyebrow label at the top of the share card
  ///
  /// In en, this message translates to:
  /// **'SHARE A BOOK'**
  String get shareEyebrow;

  /// Caption next to the stars when showing the user's own rating
  ///
  /// In en, this message translates to:
  /// **'your rating'**
  String get shareYourRating;

  /// Caption next to the stars when showing the catalog average rating
  ///
  /// In en, this message translates to:
  /// **'catalog avg'**
  String get shareCatalogAvg;

  /// Tagline in the share card footer
  ///
  /// In en, this message translates to:
  /// **'beyond the bookshelf'**
  String get shareTagline;

  /// Title of the share bottom sheet (S6c)
  ///
  /// In en, this message translates to:
  /// **'Share this book'**
  String get shareTitle;

  /// Toggle that folds the user's rating and review into the card
  ///
  /// In en, this message translates to:
  /// **'Include my rating & note'**
  String get shareIncludeRating;

  /// Copies a link to the book
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get shareCopyLink;

  /// Renders the card to an image and opens the OS share sheet
  ///
  /// In en, this message translates to:
  /// **'Share card'**
  String get shareCardButton;

  /// Snackbar shown after copying the book link
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get shareLinkCopied;

  /// The text shared alongside the card image
  ///
  /// In en, this message translates to:
  /// **'{title} by {author} — on Kitabi, kitabi.in'**
  String shareBookText(String title, String author);

  /// Title of the recommendations screen (S11)
  ///
  /// In en, this message translates to:
  /// **'Picked for your shelf'**
  String get recsTitle;

  /// Subtitle on the recommendations screen
  ///
  /// In en, this message translates to:
  /// **'Reasoned from your ratings — never from ads.'**
  String get recsSubtitle;

  /// Title of the loader shown while recommendations are being reasoned
  ///
  /// In en, this message translates to:
  /// **'Thinking about your shelf…'**
  String get recsLoadingTitle;

  /// Subtitle under the recommendations loading title
  ///
  /// In en, this message translates to:
  /// **'Reasoning from your ratings — this can take a few seconds.'**
  String get recsLoadingSubtitle;

  /// Eyebrow label on the book page's timer card
  ///
  /// In en, this message translates to:
  /// **'Reading Session'**
  String get timerSessionLabel;

  /// Button that starts a reading session
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get timerStart;

  /// Eyebrow label on the full-screen running-timer view
  ///
  /// In en, this message translates to:
  /// **'Session in Progress'**
  String get timerInProgress;

  /// Caption under the live clock on the running-timer view
  ///
  /// In en, this message translates to:
  /// **'elapsed'**
  String get timerElapsed;

  /// Badge shown once a session has run past 20 minutes
  ///
  /// In en, this message translates to:
  /// **'In the zone — {minutes} min'**
  String timerInTheZone(int minutes);

  /// Button that stops the running session and logs it
  ///
  /// In en, this message translates to:
  /// **'Stop & log'**
  String get timerStopAndLog;

  /// Title on the wax-seal confirmation after a session is logged
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =0{Under a minute, logged} =1{1 minute, well spent} other{{minutes} minutes, well spent}}'**
  String timerLoggedTitle(int minutes);

  /// Stat label on the wax-seal screen
  ///
  /// In en, this message translates to:
  /// **'This session'**
  String get timerThisSession;

  /// Stat label on the wax-seal screen
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get timerThisWeek;

  /// Optional page-number field on the wax-seal screen
  ///
  /// In en, this message translates to:
  /// **'Read up to page'**
  String get timerPageFieldLabel;

  /// Suffix after the page-number field, e.g. "of 320"
  ///
  /// In en, this message translates to:
  /// **'of {total}'**
  String timerPageFieldOf(int total);

  /// Precedes the editable total-pages field on the wax-seal screen, shown when the book has no page count yet
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get timerTotalFieldLabel;

  /// Placeholder in the editable total-pages field on the wax-seal screen
  ///
  /// In en, this message translates to:
  /// **'total'**
  String get timerTotalFieldHint;

  /// Placeholder digit shown in the empty page-number field
  ///
  /// In en, this message translates to:
  /// **'0'**
  String get timerPageFieldHint;

  /// Closes the wax-seal confirmation and returns to the book page
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get timerDone;

  /// Label over the session log on the book page's timer card
  ///
  /// In en, this message translates to:
  /// **'Recent sessions'**
  String get timerRecentSessions;

  /// Empty state for the session log
  ///
  /// In en, this message translates to:
  /// **'No sessions logged yet — tap Start to begin one.'**
  String get timerNoSessionsYet;

  /// Text on the persistent mini-timer bar
  ///
  /// In en, this message translates to:
  /// **'{elapsed} · tap to open'**
  String timerMiniBarLive(String elapsed);

  /// Date label in the session log when the session was today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get timerToday;

  /// Date label in the session log when the session was yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timerYesterday;

  /// Chart label on Insights for the weekly reading-time area chart
  ///
  /// In en, this message translates to:
  /// **'Reading time'**
  String get insightsReadingTime;

  /// Headline total above the weekly reading-time chart
  ///
  /// In en, this message translates to:
  /// **'{duration} this week'**
  String insightsWeekTotal(String duration);

  /// Delta caption beside the weekly reading-time total
  ///
  /// In en, this message translates to:
  /// **'{duration} vs last week'**
  String insightsVsLastWeek(String duration);

  /// Plain-language observation derived from reading-session timestamps
  ///
  /// In en, this message translates to:
  /// **'You read most on {day}s, often around {hourRange}.'**
  String insightsReadingTimeInsight(String day, String hourRange);

  /// Title of the page-number popup shown after stopping a session from the mini-bar's own quick-stop control
  ///
  /// In en, this message translates to:
  /// **'Session logged — {duration}'**
  String timerMiniBarStopped(String duration);

  /// Dismisses the mini-bar quick-stop's page-number popup without logging a page
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get timerPageDialogSkip;

  /// Accessibility label for the mini-bar's icon-only quick-stop control
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get timerStop;

  /// Title of the notification checking in on a long-running reading session
  ///
  /// In en, this message translates to:
  /// **'Still reading?'**
  String get timerCheckInTitle;

  /// Body of the still-reading check-in notification. Android shows the Yes/No actions directly; iOS only reveals them on a swipe/long-press, so the copy must not promise a bare tap shows them — a plain tap opens the running timer screen instead (see reading_timer_notifications.dart's _openReadingTimer), where Stop & log is always available.
  ///
  /// In en, this message translates to:
  /// **'It\'s been a while. Press & hold for Yes/No, or tap to open the timer.'**
  String get timerCheckInBody;

  /// Check-in notification action that keeps the timer running
  ///
  /// In en, this message translates to:
  /// **'Yes, still reading'**
  String get timerCheckInYes;

  /// Check-in notification action that stops the timer
  ///
  /// In en, this message translates to:
  /// **'No, stop it'**
  String get timerCheckInNo;

  /// Title of the notification shown after a session is auto-stopped
  ///
  /// In en, this message translates to:
  /// **'Reading timer stopped'**
  String get timerAutoStoppedTitle;

  /// Body of the notification shown after a session is auto-stopped
  ///
  /// In en, this message translates to:
  /// **'Logged {duration} while you were away.'**
  String timerAutoStoppedBody(String duration);

  /// Snackbar shown when the app itself notices and stops a long-forgotten timer on resume
  ///
  /// In en, this message translates to:
  /// **'Your timer was still running, so we stopped it — logged {duration}.'**
  String timerResumeSafetyNetMessage(String duration);

  /// Book page link that opens the manual session-logging sheet
  ///
  /// In en, this message translates to:
  /// **'Log manually'**
  String get timerLogManually;

  /// Title of the manual session-logging bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Log a reading session'**
  String get timerManualSheetTitle;

  /// Label above the minutes field in the manual-log sheet
  ///
  /// In en, this message translates to:
  /// **'How long did you read?'**
  String get timerManualDurationLabel;

  /// Unit suffix next to the manual-log duration field
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get timerManualDurationUnit;

  /// Button that saves a manually logged session
  ///
  /// In en, this message translates to:
  /// **'Save session'**
  String get timerManualSave;

  /// Pages read shown next to a session's duration
  ///
  /// In en, this message translates to:
  /// **'{pages, plural, =1{1 page} other{{pages} pages}}'**
  String timerSessionPages(int pages);

  /// The pill on the running timer face that opens the note page (N1)
  ///
  /// In en, this message translates to:
  /// **'Note a thought'**
  String get noteAThought;

  /// Beside the live clock on the note page — the timer never paused
  ///
  /// In en, this message translates to:
  /// **'still running'**
  String get noteStillRunning;

  /// Subtitle on the note page while a session is live
  ///
  /// In en, this message translates to:
  /// **'{book} · note {n} of this sitting'**
  String noteOfThisSitting(String book, int n);

  /// Label above the writing area
  ///
  /// In en, this message translates to:
  /// **'Your thought · only you'**
  String get noteYourThought;

  /// Placeholder in the empty note field
  ///
  /// In en, this message translates to:
  /// **'What are you thinking?'**
  String get noteHint;

  /// Label above the page/range row on the note page
  ///
  /// In en, this message translates to:
  /// **'Pages · optional'**
  String get notePagesLabel;

  /// Widens a single page into a range
  ///
  /// In en, this message translates to:
  /// **'range'**
  String get noteAddRange;

  /// Collapses a range back to one page
  ///
  /// In en, this message translates to:
  /// **'single'**
  String get noteSingle;

  /// Explains that pages are optional and rangeable
  ///
  /// In en, this message translates to:
  /// **'Starts at the page you\'re on. Leave it, widen it to a range, or clear it — a thought doesn\'t have to live anywhere.'**
  String get notePagesHelp;

  /// Primary action on the note page during a live session
  ///
  /// In en, this message translates to:
  /// **'Save & keep reading'**
  String get noteSaveKeepReading;

  /// Primary action when editing an existing note
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get noteSaveChanges;

  /// Reassurance under the save button during a live session
  ///
  /// In en, this message translates to:
  /// **'Saved to this book only you can read. The timer never paused.'**
  String get noteTimerNeverPaused;

  /// Header when editing a past note
  ///
  /// In en, this message translates to:
  /// **'Written on {date}'**
  String noteWrittenOn(String date);

  /// Provenance line when editing a note that came from a session
  ///
  /// In en, this message translates to:
  /// **'From your sitting · {duration} · p. {from} to {to}'**
  String noteFromSitting(String duration, int from, int to);

  /// Explains that editing does not re-date a note
  ///
  /// In en, this message translates to:
  /// **'Editing the words never moves the note — it stays under the sitting it was written in, so the journal keeps telling the truth about when you thought it.'**
  String get noteEditNeverMoves;

  /// Title of the free-rotation step before cropping a cover
  ///
  /// In en, this message translates to:
  /// **'Straighten the photo'**
  String get rotateTitle;

  /// Explains the two-finger rotate gesture
  ///
  /// In en, this message translates to:
  /// **'Twist with two fingers to set any angle, or nudge a quarter-turn at a time.'**
  String get rotateHint;

  /// Confirms the rotation and continues to cropping
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get rotateApply;

  /// Option on the cover sheet opening the free-rotation step
  ///
  /// In en, this message translates to:
  /// **'Rotate — set any angle by hand'**
  String get coverRotate;

  /// Turns the read-only note view into the editor
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get noteEdit;

  /// Quiet destructive action at the foot of the note editor
  ///
  /// In en, this message translates to:
  /// **'Delete this note'**
  String get noteDelete;

  /// Confirm dialog title before deleting a note
  ///
  /// In en, this message translates to:
  /// **'Delete this note?'**
  String get noteDeleteConfirm;

  /// Title of the book's note journal (N4)
  ///
  /// In en, this message translates to:
  /// **'Your notes'**
  String get notesTitle;

  /// Stated once at the top of the journal; there is no visibility toggle
  ///
  /// In en, this message translates to:
  /// **'always private'**
  String get notesAlwaysPrivate;

  /// Counts under the journal title
  ///
  /// In en, this message translates to:
  /// **'{notes} notes across {sittings} sittings'**
  String notesSummary(int notes, int sittings);

  /// Group header in the journal — the sitting is the timestamp
  ///
  /// In en, this message translates to:
  /// **'{date} · {duration}'**
  String notesSessionHeader(String date, String duration);

  /// Group header for notes that belong to the book rather than a session
  ///
  /// In en, this message translates to:
  /// **'Not from a sitting'**
  String get notesNoSitting;

  /// Affordance line above the journal's actions
  ///
  /// In en, this message translates to:
  /// **'Tap any note to open and edit it.'**
  String get notesTapToEdit;

  /// Creates a standalone note from the journal
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get notesAdd;

  /// Empty state of the journal
  ///
  /// In en, this message translates to:
  /// **'No notes yet. Anything you jot while reading lands here.'**
  String get notesEmpty;

  /// Header of the notes section on the stop sheet (N3)
  ///
  /// In en, this message translates to:
  /// **'Notes from this sitting · {n}'**
  String notesSectionThisSitting(int n);

  /// Row on the stop sheet opening the note page for a final note
  ///
  /// In en, this message translates to:
  /// **'Add a closing thought…'**
  String get notesClosingThought;

  /// Skip copy on the stop sheet when notes exist — they were saved as they were written
  ///
  /// In en, this message translates to:
  /// **'Skip — your {n} notes are already saved'**
  String stopSkipNotesSafe(int n);

  /// Prompt above the big page numeral on the stop-session sheet (R1)
  ///
  /// In en, this message translates to:
  /// **'Where did you get to?'**
  String get stopWhereDidYouGet;

  /// Label under the numeral when the book's total page count is unknown
  ///
  /// In en, this message translates to:
  /// **'page'**
  String get stopPageUnit;

  /// Confirmation eyebrow on the stop sheet — the session is already saved before any page is entered
  ///
  /// In en, this message translates to:
  /// **'Session logged'**
  String get stopSessionLogged;

  /// Anchor line telling the reader where the session began, so the number they type is easy to judge
  ///
  /// In en, this message translates to:
  /// **'You started this session at p. {page}'**
  String stopStartedAtPage(int page);

  /// The previous sitting, shown under the anchor line
  ///
  /// In en, this message translates to:
  /// **'Last time · {date} · {duration} · p. {from} → {to}'**
  String stopLastSession(String date, String duration, int from, int to);

  /// Link on the stop sheet opening the full list of sittings (R3)
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get stopOpenLog;

  /// Primary action on the stop sheet
  ///
  /// In en, this message translates to:
  /// **'Save the page'**
  String get stopSavePage;

  /// Skip action naming its consequence when the book already has a page
  ///
  /// In en, this message translates to:
  /// **'Skip — keep the time, leave the page at {page}'**
  String stopSkipWithPage(int page);

  /// Skip action when there is no existing page to leave behind
  ///
  /// In en, this message translates to:
  /// **'Skip — keep the time only'**
  String get stopSkipNoPage;

  /// Label on the gold total-pages line, shown only when the catalogue has no page count
  ///
  /// In en, this message translates to:
  /// **'How long is this book?'**
  String get stopTotalQuestion;

  /// Unit beside the total-pages field
  ///
  /// In en, this message translates to:
  /// **'pages'**
  String get stopTotalUnit;

  /// Why the total is worth entering — it improves the shared Edition, not just this reader's view
  ///
  /// In en, this message translates to:
  /// **'Optional. Nobody has told the catalogue yet — filling it in gives you a % here, and helps every other reader of this book.'**
  String get stopTotalWhy;

  /// Validation message for a page below 1
  ///
  /// In en, this message translates to:
  /// **'Pages start at 1.'**
  String get stopErrorBelowOne;

  /// Validation message for a page beyond the book's length
  ///
  /// In en, this message translates to:
  /// **'This book has {total} pages.'**
  String stopErrorAboveTotal(int total);

  /// Validation message preventing a session from logging backwards, pointing at the place that can
  ///
  /// In en, this message translates to:
  /// **'That\'s before p. {page}, where this sitting began. To correct earlier progress, edit it from the book page.'**
  String stopErrorBelowStart(int page);

  /// Title of the sittings log (R3)
  ///
  /// In en, this message translates to:
  /// **'{title} · your sessions'**
  String stopSessionsTitle(String title);

  /// Totals line under the sittings-log title
  ///
  /// In en, this message translates to:
  /// **'{duration} · {pages} pages · {count} sittings'**
  String stopSessionsSummary(String duration, int pages, int count);

  /// Shown for a sitting the reader skipped the page on — still a sitting
  ///
  /// In en, this message translates to:
  /// **'no page noted'**
  String get stopSessionsNoPage;

  /// Reassurance at the foot of the sittings log that skipping is normal
  ///
  /// In en, this message translates to:
  /// **'A sitting with no page is still a sitting — the time counts toward your week either way.'**
  String get stopSessionsSkipNote;

  /// Returns from the sittings log to the page entry
  ///
  /// In en, this message translates to:
  /// **'Back to the page'**
  String get stopBackToPage;

  /// Reading pace shown on the wax-seal stop screen
  ///
  /// In en, this message translates to:
  /// **'{rate} pages/hr'**
  String timerPagesPerHour(String rate);

  /// Pages-read figure under the Insights weekly reading-time chart
  ///
  /// In en, this message translates to:
  /// **'{pages, plural, =1{1 page} other{{pages} pages}} this week'**
  String insightsPagesThisWeek(int pages);

  /// Reading pace figure under the Insights weekly reading-time chart
  ///
  /// In en, this message translates to:
  /// **'{rate} pages/hr average'**
  String insightsPagesPace(String rate);

  /// Explainer shown before the reader opts into recommendations
  ///
  /// In en, this message translates to:
  /// **'Opt in and Kitabi suggests books from your ratings, each with a plain-words \"why\". Off by default — turn it off anytime.'**
  String get recsOptInBody;

  /// Button that opts into recommendations
  ///
  /// In en, this message translates to:
  /// **'Turn on recommendations'**
  String get recsEnable;

  /// Action that opts out of recommendations
  ///
  /// In en, this message translates to:
  /// **'Turn off recommendations'**
  String get recsTurnOff;

  /// Eyebrow above the reasoned explanation on a recommendation card
  ///
  /// In en, this message translates to:
  /// **'WHY THIS?'**
  String get recsWhy;

  /// Adds a recommended book to the wishlist
  ///
  /// In en, this message translates to:
  /// **'+ Wishlist'**
  String get recsWishlist;

  /// Dismisses a recommendation
  ///
  /// In en, this message translates to:
  /// **'Not for me'**
  String get recsNotForMe;

  /// Shown when the server has no recommendation engine configured
  ///
  /// In en, this message translates to:
  /// **'Recommendations aren\'t switched on yet — check back soon.'**
  String get recsUnavailable;

  /// Shown when there are no ratings to reason from yet
  ///
  /// In en, this message translates to:
  /// **'Rate a few books and Kitabi will start suggesting what to read next.'**
  String get recsColdStart;

  /// Footer reassurance on the recommendations screen
  ///
  /// In en, this message translates to:
  /// **'Recommendations run on your ratings only.'**
  String get recsFooter;

  /// Profile entry point to recommendations
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get recsProfileEntry;

  /// Badge on the home dashboard AI-pick card
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get recsForYou;

  /// Label on the home dashboard entry point to recommendations
  ///
  /// In en, this message translates to:
  /// **'A pick for your shelf'**
  String get recsHomePick;

  /// Title of the insights/stats screen
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get insightsTitle;

  /// Placeholder body on the insights screen before stats are built
  ///
  /// In en, this message translates to:
  /// **'Your reading stats — books a month, languages, pages, and a reading goal — land here soon.'**
  String get insightsComingSoon;

  /// Year-selector chip for all-time stats
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get insightsAllTime;

  /// Caption under the reading-goal ring
  ///
  /// In en, this message translates to:
  /// **'of {goal} books'**
  String insightsGoalRing(int goal);

  /// Reading pace: on track
  ///
  /// In en, this message translates to:
  /// **'On track 🎯'**
  String get insightsOnTrack;

  /// Reading pace: ahead
  ///
  /// In en, this message translates to:
  /// **'{count} ahead of pace'**
  String insightsAhead(int count);

  /// Reading pace: behind
  ///
  /// In en, this message translates to:
  /// **'{count} behind pace'**
  String insightsBehind(int count);

  /// Caption under the all-time books-read number
  ///
  /// In en, this message translates to:
  /// **'books read'**
  String get insightsBooksReadTotal;

  /// Stat tile label for total pages read
  ///
  /// In en, this message translates to:
  /// **'Pages read'**
  String get insightsPagesRead;

  /// Stat tile label for books currently being read
  ///
  /// In en, this message translates to:
  /// **'Reading now'**
  String get insightsReadingNow;

  /// Stat tile label for finished books
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get insightsBooksReadLabel;

  /// Section header for the books-per-month bars
  ///
  /// In en, this message translates to:
  /// **'Books per month'**
  String get insightsPerMonth;

  /// Section header for the language donut
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get insightsLanguages;

  /// Section header for the pages-per-month line
  ///
  /// In en, this message translates to:
  /// **'Pages per month'**
  String get insightsPagesPerMonth;

  /// Empty state on the insights screen
  ///
  /// In en, this message translates to:
  /// **'Finish a book and your reading stats will grow here.'**
  String get insightsNoData;

  /// Title of the set-reading-goal dialog
  ///
  /// In en, this message translates to:
  /// **'Reading goal'**
  String get insightsGoalDialogTitle;

  /// Hint in the reading-goal input
  ///
  /// In en, this message translates to:
  /// **'Books per year'**
  String get insightsGoalDialogHint;

  /// Quick page-update action on the currently-reading card
  ///
  /// In en, this message translates to:
  /// **'Update progress'**
  String get homeUpdateProgress;

  /// Section header above the shelf-count cards on the home dashboard
  ///
  /// In en, this message translates to:
  /// **'Your shelves'**
  String get homeYourShelves;

  /// Shelf-count card label for total owned books
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get homeShelfOwned;

  /// Shelf-count card label for finished books
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get homeShelfRead;

  /// Shelf-count card label for books currently lent out
  ///
  /// In en, this message translates to:
  /// **'Lent out'**
  String get homeShelfLentOut;

  /// Shelf-count card label for wishlisted books
  ///
  /// In en, this message translates to:
  /// **'Wishlist'**
  String get homeShelfWishlist;

  /// Reading progress line on a currently-reading card
  ///
  /// In en, this message translates to:
  /// **'p. {page} of {total} · {percent}%'**
  String homeProgressLine(int page, int total, int percent);

  /// Reading progress line on a currently-reading card when the book's total page count isn't known, so no 'of N' or percent/progress bar can be shown
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String homeProgressLineNoTotal(int page);

  /// Lending nudge with a due date
  ///
  /// In en, this message translates to:
  /// **'{title} is with {name} — due in {days}d'**
  String homeNudgeDue(String title, String name, int days);

  /// Lending nudge when the book is overdue
  ///
  /// In en, this message translates to:
  /// **'{title} is with {name} — overdue'**
  String homeNudgeOverdue(String title, String name);

  /// Lending nudge with no due date
  ///
  /// In en, this message translates to:
  /// **'{title} is with {name}'**
  String homeNudgeNoDue(String title, String name);

  /// Title/tooltip for the global search entry point
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// Section header above author search results
  ///
  /// In en, this message translates to:
  /// **'AUTHORS'**
  String get catalogSearchSectionAuthors;

  /// Section header above publisher search results
  ///
  /// In en, this message translates to:
  /// **'PUBLISHERS'**
  String get catalogSearchSectionPublishers;

  /// Trailing count on an author search result
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{work} other{works}}'**
  String searchAuthorWorks(int count);

  /// Button on the add-book form that opens the author picker
  ///
  /// In en, this message translates to:
  /// **'＋ Add or choose an author'**
  String get formAuthorAddButton;

  /// Placeholder on the add-book form's publisher field before one is chosen
  ///
  /// In en, this message translates to:
  /// **'Choose a publisher'**
  String get formPublisherChoose;

  /// Title of the author picker page
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get authorPickerTitle;

  /// Search field hint on the author picker
  ///
  /// In en, this message translates to:
  /// **'Search authors by name'**
  String get authorPickerSearchHint;

  /// Empty state on the author picker
  ///
  /// In en, this message translates to:
  /// **'No authors match — add a new one below.'**
  String get authorPickerEmpty;

  /// Expands the add-new-author form on the picker
  ///
  /// In en, this message translates to:
  /// **'Add a new author'**
  String get authorPickerAddNew;

  /// Checkbox on the add-new-author form, self-links the new author
  ///
  /// In en, this message translates to:
  /// **'This is me — I wrote this book'**
  String get authorPickerIsMe;

  /// Primary-language line under an author in the picker
  ///
  /// In en, this message translates to:
  /// **'Writes in {language}'**
  String authorPickerLanguage(String language);

  /// Title of the publisher picker page
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get publisherPickerTitle;

  /// Search field hint on the publisher picker
  ///
  /// In en, this message translates to:
  /// **'Search publishers by name'**
  String get publisherPickerSearchHint;

  /// Empty state on the publisher picker
  ///
  /// In en, this message translates to:
  /// **'No publishers match — add a new one below.'**
  String get publisherPickerEmpty;

  /// Expands the add-new-publisher form on the picker
  ///
  /// In en, this message translates to:
  /// **'Add a new publisher'**
  String get publisherPickerAddNew;

  /// Name field label on the author/publisher picker add-new form
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get pickerFieldName;

  /// Primary-language field label on the picker add-new form
  ///
  /// In en, this message translates to:
  /// **'PRIMARY LANGUAGE · optional'**
  String get pickerFieldLanguage;

  /// Bio field label on the author picker add-new form
  ///
  /// In en, this message translates to:
  /// **'BIO · optional'**
  String get pickerFieldBio;

  /// Validation message for the picker name field
  ///
  /// In en, this message translates to:
  /// **'A name is required'**
  String get pickerNameRequired;

  /// Submit button on the author picker add-new form
  ///
  /// In en, this message translates to:
  /// **'Add this author'**
  String get pickerSaveAuthor;

  /// Submit button on the publisher picker add-new form
  ///
  /// In en, this message translates to:
  /// **'Add this publisher'**
  String get pickerSavePublisher;

  /// Header above the most-used author suggestions shown when the author picker search is empty
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED'**
  String get pickerSuggestedAuthors;

  /// Header above the most-used publisher suggestions shown when the publisher picker search is empty
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED'**
  String get pickerSuggestedPublishers;

  /// Placeholder for the optional primary-language dropdown on the picker add-new forms
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get pickerLanguageHint;

  /// Label for the author portrait photo picker on the author add-new form
  ///
  /// In en, this message translates to:
  /// **'PHOTO · optional'**
  String get pickerFieldPhoto;

  /// Label for the publisher logo picker on the publisher add-new form
  ///
  /// In en, this message translates to:
  /// **'LOGO · optional'**
  String get pickerFieldLogo;

  /// Button that opens the gallery to pick an author portrait
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get pickerPhotoAdd;

  /// Button that replaces the chosen author portrait
  ///
  /// In en, this message translates to:
  /// **'Replace photo'**
  String get pickerPhotoReplace;

  /// Button that opens the gallery to pick a publisher logo
  ///
  /// In en, this message translates to:
  /// **'Add a logo'**
  String get pickerLogoAdd;

  /// Button that replaces the chosen publisher logo
  ///
  /// In en, this message translates to:
  /// **'Replace logo'**
  String get pickerLogoReplace;

  /// Snackbar when an author/publisher image upload fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload that image. Try again.'**
  String get pickerImageUploadFailed;

  /// Helper text under the Series field on the add-book form
  ///
  /// In en, this message translates to:
  /// **'Leave blank if it\'s a standalone book'**
  String get formSeriesHelp;

  /// Toggle that reveals the series fields on the add-book form
  ///
  /// In en, this message translates to:
  /// **'Part of a series'**
  String get formSeriesToggle;

  /// Sub-label under the series toggle explaining when to use it
  ///
  /// In en, this message translates to:
  /// **'Turn on for a book that belongs to a series'**
  String get formSeriesToggleSub;

  /// Help text shown when the series fields are revealed
  ///
  /// In en, this message translates to:
  /// **'Name the series, then which book this is in it.'**
  String get formSeriesHint;

  /// Helper text under the series name field
  ///
  /// In en, this message translates to:
  /// **'e.g. Harry Potter'**
  String get formSeriesNameHelp;

  /// Helper text under the Book № field on the add-book form
  ///
  /// In en, this message translates to:
  /// **'e.g. 3'**
  String get formBookNumberHelp;

  /// Button on the add-book form to add a further co-author once one is chosen
  ///
  /// In en, this message translates to:
  /// **'＋ Add another author'**
  String get formAuthorAddAnother;

  /// Tappable line under the author field that jumps to the author picker with This is me pre-checked
  ///
  /// In en, this message translates to:
  /// **'Is this your book? Tag yourself as the author'**
  String get formAuthorAddSelf;

  /// Helper text under the author field clarifying multiple authors are supported
  ///
  /// In en, this message translates to:
  /// **'Add each co-author for books with more than one'**
  String get formAuthorHelp;

  /// Tooltip on the scan button inside the ISBN field
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get formIsbnScan;

  /// Helper text under the ISBN field on the add-book form
  ///
  /// In en, this message translates to:
  /// **'Scan the barcode to fill this in — edit if needed'**
  String get formIsbnScanHelp;

  /// Form field label — the work's blurb/synopsis
  ///
  /// In en, this message translates to:
  /// **'DESCRIPTION'**
  String get formFieldDescription;

  /// Helper text under the description field on the add-book form
  ///
  /// In en, this message translates to:
  /// **'The back-cover blurb — appears on share cards'**
  String get formDescriptionHelp;

  /// Button under the cover slots: read title/author/publisher/blurb off the photographed covers and prefill the empty fields
  ///
  /// In en, this message translates to:
  /// **'Fill in from photos'**
  String get formFillFromPhotos;

  /// Header of the quiet duplicate-suggestions panel under the title field on the add-book form
  ///
  /// In en, this message translates to:
  /// **'Already in the catalog?'**
  String get formSimilarHeader;

  /// One-line explanation inside the duplicate-suggestions panel
  ///
  /// In en, this message translates to:
  /// **'Tap a match to open it instead of adding a copy — or keep typing.'**
  String get formSimilarHelp;

  /// Title of the full-screen loader shown while the cover photos are being read
  ///
  /// In en, this message translates to:
  /// **'Reading your cover…'**
  String get formExtractingTitle;

  /// Subtitle under the extraction loader
  ///
  /// In en, this message translates to:
  /// **'Pulling the title, author, publisher, and blurb'**
  String get formExtractingSubtitle;

  /// Snackbar when extraction returned nothing usable (or every field was already filled)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read any details from the photos.'**
  String get formExtractNothing;

  /// Snackbar when the server has no LLM key (extraction dormant)
  ///
  /// In en, this message translates to:
  /// **'Reading details from photos isn\'t available right now.'**
  String get formExtractUnavailable;

  /// Snackbar when the extraction call failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the photos. Try again.'**
  String get formExtractFailed;

  /// Button to restart the scanner after a miss
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get scanAgain;

  /// On the form scanner, carries the raw scanned ISBN back to the form when no catalog match was found
  ///
  /// In en, this message translates to:
  /// **'Use this ISBN anyway'**
  String get scanUseIsbnAnyway;

  /// On the form scanner, confirms the looked-up book and prefills the add-book form
  ///
  /// In en, this message translates to:
  /// **'Use these details'**
  String get scanUseDetails;

  /// Label above the front-cover capture slot on the add-book form
  ///
  /// In en, this message translates to:
  /// **'FRONT'**
  String get formCoverFront;

  /// Label above the back-cover capture slot on the add-book form
  ///
  /// In en, this message translates to:
  /// **'BACK'**
  String get formCoverBack;

  /// Helper text beside the cover capture slots on the add-book form
  ///
  /// In en, this message translates to:
  /// **'Tap a cover to photograph the front and back of your copy.'**
  String get formCoverHelp;

  /// Option in the image-source sheet to capture with the camera
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get imageSourceCamera;

  /// Option in the image-source sheet to pick an existing photo
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get imageSourceGallery;

  /// Dismisses the image-source / cover-options sheet without changing anything
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get imageSourceCancel;

  /// Cover-options sheet: re-open the cropper on the current cover photo
  ///
  /// In en, this message translates to:
  /// **'Adjust — crop, rotate, reframe'**
  String get coverActionAdjust;

  /// Cover-options sheet: replace the current cover by taking a new photo
  ///
  /// In en, this message translates to:
  /// **'Retake photo'**
  String get coverActionReplaceCamera;

  /// Cover-options sheet: replace the current cover from the gallery
  ///
  /// In en, this message translates to:
  /// **'Replace from gallery'**
  String get coverActionReplaceGallery;

  /// Cover-options sheet: clear the current cover photo
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get coverActionRemove;

  /// Snackbar when re-cropping an existing cover fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that image to adjust. Try replacing it instead.'**
  String get coverAdjustFailed;

  /// Title of the option-picker bottom sheet (e.g. Choose format)
  ///
  /// In en, this message translates to:
  /// **'Choose {label}'**
  String pickerChoose(String label);

  /// Label under the back-cover thumbnail on the book page
  ///
  /// In en, this message translates to:
  /// **'Back cover'**
  String get bookCoverBack;

  /// Placeholder label prompting the user to add a back cover on the book page
  ///
  /// In en, this message translates to:
  /// **'Add back'**
  String get bookAddBackCover;

  /// Generic share button tooltip/label
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareAction;

  /// Text put on the clipboard / share sheet with a real book link
  ///
  /// In en, this message translates to:
  /// **'{title} by {author} — on Kitabi\n{url}'**
  String shareBookLinkText(String title, String author, String url);

  /// Share text for an author link
  ///
  /// In en, this message translates to:
  /// **'{name} on Kitabi\n{url}'**
  String shareAuthorLinkText(String name, String url);

  /// Share text for a publisher link
  ///
  /// In en, this message translates to:
  /// **'{name} on Kitabi\n{url}'**
  String sharePublisherLinkText(String name, String url);

  /// Snackbar when the OS share sheet fails to open
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the share sheet. Try again.'**
  String get shareFailed;

  /// Title of the work picker used when linking a translation
  ///
  /// In en, this message translates to:
  /// **'Choose a book'**
  String get workPickerTitle;

  /// Search hint on the work picker
  ///
  /// In en, this message translates to:
  /// **'Search the catalogue by title'**
  String get workPickerSearchHint;

  /// Empty state on the work picker
  ///
  /// In en, this message translates to:
  /// **'No matches — add that book to the catalogue first, then link it.'**
  String get workPickerEmpty;

  /// Title of the add-edition screen
  ///
  /// In en, this message translates to:
  /// **'Add an edition'**
  String get addEditionTitle;

  /// Subtitle on the add-edition screen when the book title is unknown
  ///
  /// In en, this message translates to:
  /// **'Another printing of this book'**
  String get addEditionSubtitle;

  /// Save button on the add-edition screen
  ///
  /// In en, this message translates to:
  /// **'Add edition'**
  String get addEditionSave;

  /// Header for the editions list on the book page
  ///
  /// In en, this message translates to:
  /// **'Editions'**
  String get bookEditionsSection;

  /// Button on the book page to add a new edition
  ///
  /// In en, this message translates to:
  /// **'Add another edition'**
  String get bookAddEdition;

  /// Snackbar after an edition is added
  ///
  /// In en, this message translates to:
  /// **'Edition added'**
  String get bookEditionAdded;

  /// Header for the linked-translations list on the book page
  ///
  /// In en, this message translates to:
  /// **'Also in other languages'**
  String get bookTranslationsSection;

  /// Button on the book page to link another Work as a translation
  ///
  /// In en, this message translates to:
  /// **'Link a translation'**
  String get bookLinkTranslation;

  /// Snackbar after two works are linked as translations
  ///
  /// In en, this message translates to:
  /// **'Linked as a translation'**
  String get bookTranslationLinked;

  /// Card on a translation's book page pointing at its original
  ///
  /// In en, this message translates to:
  /// **'Translation of {title}'**
  String bookTranslationOf(String title);

  /// Button on a book page: create a new translation of this work
  ///
  /// In en, this message translates to:
  /// **'Add a translation'**
  String get bookAddTranslation;

  /// Byline credit for the translator on the book page header
  ///
  /// In en, this message translates to:
  /// **'trans. {name}'**
  String bookTranslatedBy(String name);

  /// Label of the add-form row linking the original work (T1)
  ///
  /// In en, this message translates to:
  /// **'Translated from'**
  String get formFieldTranslatedFrom;

  /// Empty-state action on the Translated-from row
  ///
  /// In en, this message translates to:
  /// **'Link the original work'**
  String get formLinkOriginal;

  /// Helper line under the empty Translated-from row
  ///
  /// In en, this message translates to:
  /// **'Reading a translation? Linking the original lets readers hop between versions.'**
  String get formTranslatedFromHelp;

  /// Label of the translator chip field on the add form (T4)
  ///
  /// In en, this message translates to:
  /// **'Translator'**
  String get formFieldTranslator;

  /// Helper line under the translator field
  ///
  /// In en, this message translates to:
  /// **'Credited on this book, alongside the author — a translator has their own page too.'**
  String get formTranslatorHelp;

  /// Chip that opens the author picker to add a translator
  ///
  /// In en, this message translates to:
  /// **'Add translator'**
  String get formAddTranslator;

  /// Title of the work picker when choosing a translation's original (T2)
  ///
  /// In en, this message translates to:
  /// **'The original work'**
  String get workPickerOriginalTitle;

  /// Subtitle under the original-picker title
  ///
  /// In en, this message translates to:
  /// **'Search the shared catalogue in any script'**
  String get workPickerOriginalSubtitle;

  /// Card on the original picker opening the add-a-stub form (T3)
  ///
  /// In en, this message translates to:
  /// **'Not here? Add the original'**
  String get workPickerAddOriginal;

  /// Helper line on the add-original stub form
  ///
  /// In en, this message translates to:
  /// **'A catalogue entry, not a book you own — nothing lands on your shelf.'**
  String get workPickerAddOriginalHelp;

  /// Badge on a picker row that is a group's original work
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get workPickerStampOriginal;

  /// Badge on a picker row already in the translation group
  ///
  /// In en, this message translates to:
  /// **'in group'**
  String get workPickerStampInGroup;

  /// Title field on the add-original stub form
  ///
  /// In en, this message translates to:
  /// **'Original title'**
  String get stubFieldTitle;

  /// First-publish-year field on the add-original stub form
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get stubFieldYear;

  /// Banner on the stub form explaining the carried-over fields
  ///
  /// In en, this message translates to:
  /// **'Author, type and genre are copied from your book — a translation shares them. Everything stays editable later.'**
  String get stubCarriedOver;

  /// Save button on the add-original stub form
  ///
  /// In en, this message translates to:
  /// **'Add & link'**
  String get stubSave;

  /// Title of the duplicate-match fork sheet (M1)
  ///
  /// In en, this message translates to:
  /// **'Kitabi already has this book.'**
  String get forkAlreadyHere;

  /// Question line on the fork sheet
  ///
  /// In en, this message translates to:
  /// **'So what are you adding?'**
  String get forkQuestion;

  /// Fork option: add the matched edition to the library
  ///
  /// In en, this message translates to:
  /// **'I own this one — put it on my shelf'**
  String get forkOwnThis;

  /// Snackbar after the fork adds the matched book to the library
  ///
  /// In en, this message translates to:
  /// **'On your shelf'**
  String get forkOwnThisAdded;

  /// Fork option: add a new edition to the matched work
  ///
  /// In en, this message translates to:
  /// **'Mine\'s a different printing'**
  String get forkDifferentPrinting;

  /// Helper under the different-printing fork option
  ///
  /// In en, this message translates to:
  /// **'Other ISBN, cover or page count — add an edition'**
  String get forkDifferentPrintingHelp;

  /// Fork option: mark the book being typed as a translation of the match
  ///
  /// In en, this message translates to:
  /// **'Mine\'s a translation'**
  String get forkTranslation;

  /// Helper under the translation fork option
  ///
  /// In en, this message translates to:
  /// **'Its own book, linked to this one'**
  String get forkTranslationHelp;

  /// Fork option: dismiss the match and continue the add
  ///
  /// In en, this message translates to:
  /// **'Different book, same title — keep typing'**
  String get forkDifferentBook;

  /// Eyebrow label on the shareable author card
  ///
  /// In en, this message translates to:
  /// **'AN AUTHOR ON KITABI'**
  String get shareAuthorEyebrow;

  /// Eyebrow label on the shareable publisher card
  ///
  /// In en, this message translates to:
  /// **'A PUBLISHER ON KITABI'**
  String get sharePublisherEyebrow;

  /// Title of the Discover/browse screen
  ///
  /// In en, this message translates to:
  /// **'Browse the catalogue'**
  String get browseTitle;

  /// Entry-point label/tooltip that opens the browse screen
  ///
  /// In en, this message translates to:
  /// **'Browse the catalogue'**
  String get browseEntry;

  /// Section header for the reader's recent searches (S4h)
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get searchRecentSection;

  /// Action that empties the recent-searches list
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get searchRecentClear;

  /// Section header for newest catalogue arrivals in one of the reader's languages
  ///
  /// In en, this message translates to:
  /// **'New in {language}'**
  String searchNewInLanguage(String language);

  /// Caption under the new-in-language row explaining where it comes from
  ///
  /// In en, this message translates to:
  /// **'Newest in the catalogue · from your profile languages'**
  String get searchNewInLanguageNote;

  /// Header for the newest-arrivals row when no reading language is known — the fallback for the new-in-language row
  ///
  /// In en, this message translates to:
  /// **'New in the catalogue'**
  String get searchNewInCatalogue;

  /// Caption under the unfiltered newest-arrivals row, pointing at the profile setting that filters it
  ///
  /// In en, this message translates to:
  /// **'Newest additions · set your reading languages to narrow this'**
  String get searchNewInCatalogueNote;

  /// Search field hint in the Type/Genre picker sheet
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get pickerSearchHint;

  /// Title of the genre picker sheet — the plain noun, not the shouted field label
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get pickerGenreTitle;

  /// Title of the type picker sheet — the plain noun, not the shouted field label
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get pickerTypeTitle;

  /// Section label above existing matches in the picker sheet
  ///
  /// In en, this message translates to:
  /// **'Already in the catalogue'**
  String get pickerAlreadyHere;

  /// Empty state in the picker sheet when no option matches and none can be created
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that.'**
  String get pickerNoMatches;

  /// How many books carry a genre, shown beside it in the picker so the established spelling is the obvious pick
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 book} other{{count} books}}'**
  String pickerBookCount(int count);

  /// The last-resort row in the genre picker that makes a brand-new genre
  ///
  /// In en, this message translates to:
  /// **'Create “{value}”'**
  String pickerCreate(String value);

  /// Line under Create, spelling out that genres are a shared facet
  ///
  /// In en, this message translates to:
  /// **'Only if none of the above is it — a new genre joins the shared filter for every reader.'**
  String get pickerCreateSharedNote;

  /// Confirm button in the multi-select picker sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Done} =1{Done · 1 selected} other{Done · {count} selected}}'**
  String pickerDone(int count);

  /// Subtitle of the genre picker sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 in the catalogue · tap all that fit} other{{count} in the catalogue · tap all that fit}}'**
  String pickerGenreSubtitle(int count);

  /// Subtitle of the type picker sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 to choose from} other{{count} to choose from}}'**
  String pickerTypeSubtitle(int count);

  /// The door beside the Type/Genre label opening the full picker — shows the honest total
  ///
  /// In en, this message translates to:
  /// **'All {count}'**
  String formPickerAll(int count);

  /// Caption under the genre row explaining why those chips are there
  ///
  /// In en, this message translates to:
  /// **'Your most-used genres first.'**
  String get formGenreYoursNote;

  /// Section header for authors with the most works — deliberately not called 'popular', since it counts works, not readers
  ///
  /// In en, this message translates to:
  /// **'Most in the catalogue'**
  String get searchPopularAuthors;

  /// Browse screen tab for all books
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get browseTabBooks;

  /// Browse screen tab for all authors
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get browseTabAuthors;

  /// Browse screen tab for all publishers
  ///
  /// In en, this message translates to:
  /// **'Publishers'**
  String get browseTabPublishers;

  /// Header above the list of external retailer buy links on the book page
  ///
  /// In en, this message translates to:
  /// **'Where to buy'**
  String get bookBuySection;

  /// Snackbar when the external buy link fails to open
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the store link.'**
  String get bookBuyFailed;

  /// Label on the browse sort control
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get browseSortLabel;

  /// Browse sort option: alphabetical by title
  ///
  /// In en, this message translates to:
  /// **'Title (A–Z)'**
  String get browseSortTitle;

  /// Browse sort option: newest publication year first
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get browseSortNewest;

  /// Browse sort option: oldest publication year first
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get browseSortOldest;

  /// Browse sort option: alphabetical by author
  ///
  /// In en, this message translates to:
  /// **'Author (A–Z)'**
  String get browseSortAuthor;

  /// Browse language filter: no language filter
  ///
  /// In en, this message translates to:
  /// **'All languages'**
  String get browseFilterAllLanguages;

  /// Browse Type (literary form) filter: no type filter
  ///
  /// In en, this message translates to:
  /// **'All types'**
  String get browseFilterAllTypes;

  /// Browse genre filter: no genre filter
  ///
  /// In en, this message translates to:
  /// **'All genres'**
  String get browseFilterAllGenres;

  /// Title of the catalogue filter/sort bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Filter & sort'**
  String get browseFilterHeading;

  /// Apply button on the catalogue filter sheet
  ///
  /// In en, this message translates to:
  /// **'Show books'**
  String get browseFilterApply;

  /// Reset action on the catalogue filter sheet
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get browseFilterClear;

  /// Catalogue filter chip that clears a single facet (type/genre/language)
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get browseFilterAllTitle;

  /// Accessibility label for the catalogue floating search/filter control
  ///
  /// In en, this message translates to:
  /// **'Search and filter the catalogue'**
  String get browseFabLabel;
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
