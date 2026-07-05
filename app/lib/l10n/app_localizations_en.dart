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
  String catalogSearchSectionLibrary(int count) {
    return 'IN YOUR LIBRARY · $count';
  }

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

  @override
  String get bookAddToLibrary => 'Add to my library';

  @override
  String get bookYourRating => 'your rating';

  @override
  String get bookProgressLabel => 'PROGRESS';

  @override
  String bookProgressValue(int page, int total) {
    return 'p. $page of $total';
  }

  @override
  String get bookStartedLabel => 'STARTED';

  @override
  String get bookNotStarted => 'Not started';

  @override
  String get bookEditProgress => 'Edit progress';

  @override
  String get bookCurrentPage => 'Current page';

  @override
  String get bookReviewLabel => 'MY REVIEW';

  @override
  String get bookReviewEmpty => 'No review yet — tap to write one.';

  @override
  String get bookReviewVisibilityPrivate => 'Private';

  @override
  String get bookReviewVisibilityPublic => 'Public';

  @override
  String get bookEditReview => 'Edit review';

  @override
  String get bookNotesLabel => 'PERSONAL NOTES · always private';

  @override
  String get bookNotesEmpty =>
      'Tap to add a private note — edition, condition, why this copy matters.';

  @override
  String get bookEditNotes => 'Edit notes';

  @override
  String get bookLendingNotLentOut => 'Not lent out.';

  @override
  String bookLendingWithSomeone(String name) {
    return 'With $name';
  }

  @override
  String bookLendingPastCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'lendings',
      one: 'lending',
    );
    return '$count past $_temp0';
  }

  @override
  String get bookLendAction => 'Lend';

  @override
  String get bookMarkReturnedAction => 'Mark returned';

  @override
  String get bookLendDialogTitle => 'Lend this book';

  @override
  String get bookLendBorrowerName => 'Borrower\'s name';

  @override
  String get bookCancel => 'Cancel';

  @override
  String get bookSave => 'Save';

  @override
  String bookIsbnLabel(String isbn) {
    return 'ISBN $isbn';
  }

  @override
  String get libraryTitle => 'My Library';

  @override
  String libraryBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'books',
      one: 'book',
    );
    return '$count $_temp0';
  }

  @override
  String get libraryFilterAll => 'All';

  @override
  String get libraryFilterFavourites => '★ Favourites';

  @override
  String get libraryEmpty =>
      'Nothing here yet — search or scan a book to add it.';

  @override
  String get bookRemoveFromLibrary => 'Remove from library';

  @override
  String get bookRemoveConfirm =>
      'Remove this book from your library? Your rating and review stay on the shared catalog entry, but this copy, its reading progress, and its notes are gone.';

  @override
  String get bookTagsLabel => 'SHELVES · yours only';

  @override
  String get bookAddTag => '+ add';

  @override
  String get bookNewTagTitle => 'Add to a shelf';

  @override
  String get bookNewTagHint => 'e.g. beach reads';

  @override
  String get scanAddedToLibrary => 'Added to your library';

  @override
  String get homeCurrentlyReading => 'Currently reading';

  @override
  String get homeYourLibrary => 'Your library';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeEmptyTitle => 'Your shelf is empty';

  @override
  String get homeEmptyBody => 'Add a book to start building your library.';

  @override
  String get homeAddBook => 'Add a book';

  @override
  String get homeScanBarcode => 'Scan a barcode';

  @override
  String get formAuthorAddHint => 'Type to search or add an author';

  @override
  String get formPublisherHint => 'Type to search or add a publisher';

  @override
  String formAddNew(String name) {
    return 'Add \"$name\"';
  }

  @override
  String get lendingLedgerTitle => 'Lending ledger';

  @override
  String lendingOutSubtitle(int count) {
    return '$count out';
  }

  @override
  String get lendingOutNowSection => 'Out now';

  @override
  String get lendingReturnedSection => 'Returned';

  @override
  String lendingToPersonSince(String name, String date) {
    return 'to $name · since $date';
  }

  @override
  String lendingReturnedRange(String name, String start, String end) {
    return '$name · $start – $end';
  }

  @override
  String get lendingNoDueDate => 'No due date';

  @override
  String lendingDueInDays(int days) {
    return 'Due in ${days}d';
  }

  @override
  String lendingDueOn(String date) {
    return 'Due $date';
  }

  @override
  String get lendingOverdue => 'Overdue';

  @override
  String get lendingReturnedStamp => 'Returned ✓';

  @override
  String get lendingMarkReturned => 'Mark returned ✓';

  @override
  String get lendingEmpty =>
      'Nothing lent out yet.\nLend a book from its page to start the ledger.';

  @override
  String get lendingDueDateOptional => 'Due date · optional';

  @override
  String get lendingSetDueDate => 'Set a due date';

  @override
  String lendingLentOutTab(int count) {
    return 'Lent out · $count';
  }

  @override
  String lendingBorrowedTab(int count) {
    return 'Borrowed · $count';
  }

  @override
  String get lendingWithYouNowSection => 'With you now';

  @override
  String lendingFromPersonSince(String name, String date) {
    return 'from $name · since $date';
  }

  @override
  String lendingBorrowedRange(String name, String start, String end) {
    return '$name · $start – $end';
  }

  @override
  String get lendingSelfLogged => 'Self-logged — just for your own tracking.';

  @override
  String get lendingReturnedIt => 'I\'ve returned it ✓';

  @override
  String get lendingBorrowedEmpty => 'Nothing borrowed yet.';

  @override
  String get lendingLogBorrowed => '+ Log a borrowed book';

  @override
  String get logBorrowedTitle => 'Log a borrowed book';

  @override
  String get logBorrowedBookLabel => 'BOOK';

  @override
  String get logBorrowedSearchHint => 'Search a book…';

  @override
  String get logBorrowedFromLabel => 'FROM';

  @override
  String get logBorrowedFromHint => 'Who lent it to you?';

  @override
  String get logBorrowedOnLabel => 'BORROWED ON';

  @override
  String get logBorrowedRemindLabel => 'Remind me · optional';

  @override
  String get logBorrowedNoteLabel => 'Note · optional';

  @override
  String get logBorrowedSave => 'Save to my borrowed shelf';

  @override
  String get logBorrowedNoDate => 'Pick a date';

  @override
  String get lendSheetTitle => 'Lend this book';

  @override
  String get lendSheetToLabel => 'TO';

  @override
  String get lendSheetToHint => 'Who are you lending it to?';

  @override
  String get lendSheetLentOnLabel => 'LENT ON';

  @override
  String get lendSheetDueLabel => 'Due date · optional';

  @override
  String get lendSheetSave => 'Lend it';

  @override
  String get reminderLentTitle => 'A lent book is due';

  @override
  String reminderLentBody(String title, String name) {
    return '$title — with $name';
  }

  @override
  String get reminderBorrowedTitle => 'A borrowed book is due';

  @override
  String reminderBorrowedBody(String title, String name) {
    return 'Return $title to $name';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get navLending => 'Lending';

  @override
  String get navInsights => 'Insights';

  @override
  String get navAdd => 'Add';

  @override
  String get insightsTitle => 'Insights';

  @override
  String get insightsComingSoon =>
      'Your reading stats — books a month, languages, pages, and a reading goal — land here soon.';

  @override
  String get homeYourShelves => 'Your shelves';

  @override
  String get homeShelfOwned => 'Owned';

  @override
  String get homeShelfRead => 'Read';

  @override
  String get homeShelfLentOut => 'Lent out';

  @override
  String get homeShelfWishlist => 'Wishlist';

  @override
  String homeProgressLine(int page, int total, int percent) {
    return 'p. $page of $total · $percent%';
  }

  @override
  String homeNudgeDue(String title, String name, int days) {
    return '$title is with $name — due in ${days}d';
  }

  @override
  String homeNudgeOverdue(String title, String name) {
    return '$title is with $name — overdue';
  }

  @override
  String homeNudgeNoDue(String title, String name) {
    return '$title is with $name';
  }
}
