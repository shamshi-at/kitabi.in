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

  /// Section header above the personal book sections
  ///
  /// In en, this message translates to:
  /// **'Your copy'**
  String get bookYourCopy;

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

  /// Title of the lend bottom sheet (S9)
  ///
  /// In en, this message translates to:
  /// **'Lend this book'**
  String get lendSheetTitle;

  /// Field label for the borrower on the lend sheet
  ///
  /// In en, this message translates to:
  /// **'TO'**
  String get lendSheetToLabel;

  /// Hint in the borrower field on the lend sheet
  ///
  /// In en, this message translates to:
  /// **'Who are you lending it to?'**
  String get lendSheetToHint;

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
