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

  /// Button that creates a library entry for the current edition
  ///
  /// In en, this message translates to:
  /// **'Add to my library'**
  String get bookAddToLibrary;

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

  /// Progress card value — current page of total pages
  ///
  /// In en, this message translates to:
  /// **'p. {page} of {total}'**
  String bookProgressValue(int page, int total);

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

  /// Title on the personal library grid screen
  ///
  /// In en, this message translates to:
  /// **'My Library'**
  String get libraryTitle;

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

  /// Empty state on the library grid screen
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet — search or scan a book to add it.'**
  String get libraryEmpty;

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
  /// **'Your shelf is empty'**
  String get homeEmptyTitle;

  /// Body of the empty state on the home screen
  ///
  /// In en, this message translates to:
  /// **'Add a book to start building your library.'**
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
  /// **'Who lent it to you?'**
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
