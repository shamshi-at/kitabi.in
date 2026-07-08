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
  String get commonError => 'Something went wrong.';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonOffline =>
      'You\'re offline — changes will sync when you\'re back.';

  @override
  String get syncPending => 'Syncing…';

  @override
  String get syncError => 'Some changes haven\'t synced. Tap to retry.';

  @override
  String get homeGreeting => 'Beyond the Bookshelf';

  @override
  String get splashTagline => 'Beyond the Bookshelf';

  @override
  String get splashLoading => 'Opening your reading room…';

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
  String get visibilityPublic => 'Public';

  @override
  String get visibilityPrivate => 'Private';

  @override
  String get profileVisibilitySaveError =>
      'Couldn\'t save that — check your connection.';

  @override
  String get profileDarkMode => 'Night reading';

  @override
  String get profileDarkModeDesc => 'A warm dark theme for low light';

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
  String authorWritingAs(String name) {
    return 'writing as $name';
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
  String get scanCameraUnavailable =>
      'Camera unavailable — you can search the catalog or add the book manually below.';

  @override
  String get scanCameraUnavailableShort =>
      'Camera unavailable — check the app\'s camera permission.';

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
  String get formLanguageUnset => 'Not set';

  @override
  String get formLanguageProfileNote =>
      'Add more languages in your profile to see them here.';

  @override
  String get langPickerTitle => 'Which languages do you read?';

  @override
  String get langPickerSubtitle =>
      'Pick one or more. We\'ll list these first when you add a book — you can change them anytime in your profile.';

  @override
  String get langPickerContinue => 'Continue';

  @override
  String get profileLanguagesTitle => 'Reading languages';

  @override
  String get profileLanguagesEmpty => 'Not set — tap to choose';

  @override
  String get profileLanguagesSheetTitle => 'Languages you read';

  @override
  String get profileLanguagesSave => 'Save';

  @override
  String get formFieldSeries => 'SERIES NAME';

  @override
  String get formFieldBookNumber => 'WHICH BOOK?';

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
  String get formSave => 'Save to catalog';

  @override
  String get formTitleRequired => 'Title is required';

  @override
  String get bookAddToLibrary => 'Add to my library';

  @override
  String get bookYourCopy => 'Your copy';

  @override
  String get coverUploadFailed => 'Couldn\'t upload the cover. Try again.';

  @override
  String get coverUploaded => 'Cover updated';

  @override
  String get bookYourRating => 'your rating';

  @override
  String get bookProgressLabel => 'PROGRESS';

  @override
  String bookProgressValue(int page, int total, int percent) {
    return 'p. $page of $total · $percent%';
  }

  @override
  String bookProgressPage(int page) {
    return 'p. $page';
  }

  @override
  String get lendReadingWarnTitle => 'You\'re reading this';

  @override
  String get lendReadingWarnBody =>
      'This book is on your Reading shelf. Lend it out anyway?';

  @override
  String get lendReadingWarnConfirm => 'Lend anyway';

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
  String get reviewPageTitle => 'Rate & review';

  @override
  String get reviewRatingLabel => 'YOUR RATING';

  @override
  String get reviewBodyHint => 'What did you think?';

  @override
  String get reviewVisibilityHint =>
      'Public reviews will be visible to others when Kitabi\'s community features launch.';

  @override
  String get reviewSaved => 'Review saved';

  @override
  String get reviewFinishedPrompt => 'Finished! What did you think?';

  @override
  String get reviewFinishedAction => 'Review';

  @override
  String get formFieldExpand => 'Edit full screen';

  @override
  String get formEditorDone => 'Done';

  @override
  String get coverFrontLabel => 'Front cover';

  @override
  String get coverBackLabel => 'Back cover';

  @override
  String get createdDialogTitle => 'Added to the catalog';

  @override
  String get createdAddToLibrary => 'Add to library';

  @override
  String get createdAdding => 'Adding…';

  @override
  String get createdAdded => 'Added ✓';

  @override
  String get createdCreateAnother => 'Create another';

  @override
  String get createdClose => 'Close';

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
  String get bookLendingWithFragment => 'With';

  @override
  String get bookLendingHistoryLabel => 'Lending history';

  @override
  String get bookLendingOutStamp => 'Out now';

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
  String get libraryBorrowedSection => 'Borrowed';

  @override
  String libraryBorrowedFrom(String name) {
    return 'FROM $name';
  }

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
  String get libraryEmptyTitle => 'Your shelf is waiting';

  @override
  String get libraryEmpty =>
      'Nothing here yet — search or scan a book to add it.';

  @override
  String get libraryNoMatches => 'No books match these filters.';

  @override
  String get libraryFilterTitle => 'Filter';

  @override
  String get libraryFilterStatus => 'Status';

  @override
  String get libraryFilterLanguage => 'Language';

  @override
  String get libraryFilterGenre => 'Genre';

  @override
  String get libraryFilterFavouritesOnly => 'Favourites only';

  @override
  String get libraryFilterClear => 'Clear';

  @override
  String libraryFilterShow(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'books',
      one: 'book',
    );
    return 'Show $count $_temp0';
  }

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
  String get lendingToFragment => 'to';

  @override
  String get lendingFromFragment => 'from';

  @override
  String lendingSinceFragment(String date) {
    return '· since $date';
  }

  @override
  String lendingRangeFragment(String start, String end) {
    return '· $start – $end';
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
  String lendingRejectedTab(int count) {
    return 'Rejected · $count';
  }

  @override
  String get lendingRejectedIntro =>
      'These readers declined your connection request. The book is still with them — re-send the request, or make them a private contact you track yourself.';

  @override
  String get lendingRejectedEmpty =>
      'No declined loans.\nIf someone declines your connection, the loan shows here.';

  @override
  String get lendingDeclinedStamp => 'Declined';

  @override
  String get lendingResendRequest => 'Resend request';

  @override
  String get lendingResendSent => 'Request re-sent.';

  @override
  String get lendingMakePrivate => 'Make private contact';

  @override
  String get lendingMakePrivateTitle => 'Make a private contact?';

  @override
  String lendingMakePrivateBody(String name) {
    return 'This unlinks $name\'s Kitabi account from the loan. It stays on your ledger as a private contact you track yourself — they won\'t see it or get reminders.';
  }

  @override
  String get lendingMakePrivateConfirm => 'Unlink';

  @override
  String get lendingContactNameLabel => 'Contact name';

  @override
  String get lendingRemind => 'Remind';

  @override
  String lendingReminderSent(String name) {
    return 'Reminder sent to $name.';
  }

  @override
  String get lendingReminderFailed =>
      'Couldn\'t send the reminder. You may not be connected.';

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
  String get lendingLendBook => 'Lend a book';

  @override
  String get connectionsTitle => 'Connections';

  @override
  String get connectionsIncomingSection => 'Requests to approve';

  @override
  String get connectionsOutgoingSection => 'Sent';

  @override
  String get connectionsAcceptedSection => 'Connected';

  @override
  String get connectionLoansLent => 'Lent to them';

  @override
  String get connectionLoansBorrowed => 'Borrowed from them';

  @override
  String get connectionLoansEmpty => 'No books lent or borrowed with them yet.';

  @override
  String get connectionLoanReturned => 'Returned';

  @override
  String get connectionsRejectedSection => 'Declined — you can resend';

  @override
  String get connectionsBlockedSection => 'Blocked';

  @override
  String get connectionsDeclinedYou => 'Declined your request';

  @override
  String get connectionsResend => 'Resend';

  @override
  String get connectionsBlock => 'Block';

  @override
  String get connectionsUnblock => 'Unblock';

  @override
  String get connectionsEmpty =>
      'No connections yet. When you lend a book to a Kitabi user, a connection request goes out here.';

  @override
  String get connectionsWantsToConnect => 'wants to connect';

  @override
  String get connectionsAwaitingReply => 'Waiting for them to accept';

  @override
  String get connectionsAccept => 'Accept';

  @override
  String get connectionsDeny => 'Deny';

  @override
  String get connectionsCancel => 'Cancel';

  @override
  String get connectionsDisconnect => 'Disconnect';

  @override
  String get connectionsTooltip => 'Connection requests';

  @override
  String get lendingPendingLink => 'Request pending';

  @override
  String get lendingLinkedUser => 'Linked';

  @override
  String get lendingPickTitle => 'Which book?';

  @override
  String get lendingPickEmpty =>
      'Add a book to your library first, then lend it from here.';

  @override
  String get logBorrowedTitle => 'Log a borrowed book';

  @override
  String get logBorrowedBookLabel => 'BOOK';

  @override
  String get logBorrowedSearchHint => 'Search a book…';

  @override
  String get logBorrowedFromLabel => 'FROM';

  @override
  String get logBorrowedFromHint => 'Name, or search a Kitabi user';

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
  String get lendSheetToHint => 'Name, or search a Kitabi user';

  @override
  String borrowerKitabiUser(String handle) {
    return 'On Kitabi · $handle';
  }

  @override
  String get borrowerPrivateContact => 'Private contact';

  @override
  String get borrowerUsersHeader => 'KITABI USERS';

  @override
  String get borrowerRecentHeader => 'RECENT';

  @override
  String borrowerNoMatch(String query) {
    return 'No Kitabi user “$query”. It\'ll be saved as a private contact.';
  }

  @override
  String borrowerLinkedTo(String handle) {
    return 'Linked · $handle';
  }

  @override
  String get borrowerChange => 'Change';

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
  String get welcomeTitle1 => 'Beyond the bookshelf';

  @override
  String get welcomeBody1 =>
      'Track the books you own, what you\'re reading, and how your year is going — all yours, offline-first.';

  @override
  String get welcomeTitle2 => 'Lend, first-class and free';

  @override
  String get welcomeBody2 =>
      'Keep a real ledger of who has your books — and what you\'ve borrowed — with gentle due-date reminders.';

  @override
  String get welcomeTitle3 => 'Private by default';

  @override
  String get welcomeBody3 =>
      'Your library, reviews, and notes stay yours. Nothing is shared unless you choose to.';

  @override
  String get welcomeNext => 'Next';

  @override
  String get welcomeGetStarted => 'Get started';

  @override
  String get welcomeSkip => 'Skip';

  @override
  String get updateTitle => 'Time to update';

  @override
  String get updateBody =>
      'This version of Kitabi is out of date. Please update from the App Store to keep going.';

  @override
  String get importTitle => 'Import books';

  @override
  String get importSubtitle => 'From a Goodreads export or any book CSV.';

  @override
  String get importPickFile => 'Choose a CSV file';

  @override
  String get importPasteHint =>
      '…or open your Goodreads export (any book CSV) and paste its contents here.';

  @override
  String get importPreviewButton => 'Preview matches';

  @override
  String get importParsing => 'Reading your file…';

  @override
  String importMatched(int matched, int total) {
    return '$matched of $total matched to the catalog';
  }

  @override
  String get importUnmatchedNote => 'Unmatched rows are skipped for now.';

  @override
  String importAdd(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'books',
      one: 'book',
    );
    return 'Import $count $_temp0';
  }

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'books',
      one: 'book',
    );
    return 'Imported $count $_temp0';
  }

  @override
  String get importEmpty => 'No book rows found in that file.';

  @override
  String get importEntry => 'Import from Goodreads / CSV';

  @override
  String get exportEntry => 'Export my library (CSV)';

  @override
  String get exportEmpty => 'Your library is empty — nothing to export yet.';

  @override
  String get exportShareText => 'My Kitabi library';

  @override
  String get profileTitle => 'Profile & settings';

  @override
  String get profileUsernameSet => 'Set a username';

  @override
  String get profileUsernameHint =>
      'A handle so friends can find you to lend books.';

  @override
  String get profileScoreHeader => 'REPUTATION';

  @override
  String profileScorePoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'points',
      one: 'point',
    );
    return '$_temp0';
  }

  @override
  String get profileScoreBooksAdded => 'Books added';

  @override
  String get profileScoreAuthorsAdded => 'Authors added';

  @override
  String get profileScoreReviews => 'Reviews';

  @override
  String get profileScoreTracked => 'Tracked';

  @override
  String get profileScoreFinished => 'Finished';

  @override
  String get profileScoreLending => 'Lending';

  @override
  String get usernameSheetTitle => 'Your username';

  @override
  String get usernameFieldHint => 'e.g. shamshi_reads';

  @override
  String get usernameAvailable => 'Available';

  @override
  String get usernameTaken => 'Already taken';

  @override
  String get usernameInvalid =>
      '3–20 characters: a letter, then letters, digits or _';

  @override
  String get usernameSave => 'Save username';

  @override
  String get usernameSaved => 'Username saved';

  @override
  String get profileEntry => 'Profile & settings';

  @override
  String get activityTitle => 'Your activity';

  @override
  String get activityEntry => 'Your activity';

  @override
  String get activityEmpty =>
      'Your reading activity — books added, finished, rated, lent — will show up here.';

  @override
  String get activityAddedBook => 'Added a book';

  @override
  String get activityFinishedBook => 'Finished a book';

  @override
  String get activityRatedBook => 'Rated a book';

  @override
  String get activityWroteReview => 'Wrote a review';

  @override
  String get activityLentBook => 'Lent a book';

  @override
  String activityWhen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
      zero: 'just now',
    );
    return '$_temp0';
  }

  @override
  String get shareEyebrow => 'SHARE A BOOK';

  @override
  String get shareYourRating => 'your rating';

  @override
  String get shareCatalogAvg => 'catalog avg';

  @override
  String get shareTagline => 'beyond the bookshelf';

  @override
  String get shareTitle => 'Share this book';

  @override
  String get shareIncludeRating => 'Include my rating & note';

  @override
  String get shareCopyLink => 'Copy link';

  @override
  String get shareCardButton => 'Share card';

  @override
  String get shareLinkCopied => 'Link copied';

  @override
  String shareBookText(String title, String author) {
    return '$title by $author — on Kitabi, kitabi.in';
  }

  @override
  String get recsTitle => 'Picked for your shelf';

  @override
  String get recsSubtitle => 'Reasoned from your ratings — never from ads.';

  @override
  String get recsOptInBody =>
      'Opt in and Kitabi suggests books from your ratings, each with a plain-words \"why\". Off by default — turn it off anytime.';

  @override
  String get recsEnable => 'Turn on recommendations';

  @override
  String get recsTurnOff => 'Turn off recommendations';

  @override
  String get recsWhy => 'WHY THIS?';

  @override
  String get recsWishlist => '+ Wishlist';

  @override
  String get recsNotForMe => 'Not for me';

  @override
  String get recsUnavailable =>
      'Recommendations aren\'t switched on yet — check back soon.';

  @override
  String get recsColdStart =>
      'Rate a few books and Kitabi will start suggesting what to read next.';

  @override
  String get recsFooter => 'Recommendations run on your ratings only.';

  @override
  String get recsProfileEntry => 'Recommendations';

  @override
  String get recsForYou => 'For you';

  @override
  String get recsHomePick => 'A pick for your shelf';

  @override
  String get insightsTitle => 'Insights';

  @override
  String get insightsComingSoon =>
      'Your reading stats — books a month, languages, pages, and a reading goal — land here soon.';

  @override
  String get insightsAllTime => 'All time';

  @override
  String insightsGoalRing(int goal) {
    return 'of $goal books';
  }

  @override
  String get insightsOnTrack => 'On track 🎯';

  @override
  String insightsAhead(int count) {
    return '$count ahead of pace';
  }

  @override
  String insightsBehind(int count) {
    return '$count behind pace';
  }

  @override
  String get insightsBooksReadTotal => 'books read';

  @override
  String get insightsPagesRead => 'Pages read';

  @override
  String get insightsReadingNow => 'Reading now';

  @override
  String get insightsBooksReadLabel => 'Read';

  @override
  String get insightsPerMonth => 'Books per month';

  @override
  String get insightsLanguages => 'Languages';

  @override
  String get insightsPagesPerMonth => 'Pages per month';

  @override
  String get insightsNoData =>
      'Finish a book and your reading stats will grow here.';

  @override
  String get insightsGoalDialogTitle => 'Reading goal';

  @override
  String get insightsGoalDialogHint => 'Books per year';

  @override
  String get homeUpdateProgress => 'Update progress';

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

  @override
  String get searchTitle => 'Search';

  @override
  String get catalogSearchSectionAuthors => 'AUTHORS';

  @override
  String get catalogSearchSectionPublishers => 'PUBLISHERS';

  @override
  String searchAuthorWorks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'works',
      one: 'work',
    );
    return '$count $_temp0';
  }

  @override
  String get formAuthorAddButton => '＋ Add or choose an author';

  @override
  String get formPublisherChoose => 'Choose a publisher';

  @override
  String get authorPickerTitle => 'Author';

  @override
  String get authorPickerSearchHint => 'Search authors by name';

  @override
  String get authorPickerEmpty => 'No authors match — add a new one below.';

  @override
  String get authorPickerAddNew => 'Add a new author';

  @override
  String authorPickerLanguage(String language) {
    return 'Writes in $language';
  }

  @override
  String get publisherPickerTitle => 'Publisher';

  @override
  String get publisherPickerSearchHint => 'Search publishers by name';

  @override
  String get publisherPickerEmpty =>
      'No publishers match — add a new one below.';

  @override
  String get publisherPickerAddNew => 'Add a new publisher';

  @override
  String get pickerFieldName => 'NAME';

  @override
  String get pickerFieldLanguage => 'PRIMARY LANGUAGE · optional';

  @override
  String get pickerFieldBio => 'BIO · optional';

  @override
  String get pickerNameRequired => 'A name is required';

  @override
  String get pickerSaveAuthor => 'Add this author';

  @override
  String get pickerSavePublisher => 'Add this publisher';

  @override
  String get pickerSuggestedAuthors => 'SUGGESTED';

  @override
  String get pickerSuggestedPublishers => 'SUGGESTED';

  @override
  String get pickerLanguageHint => 'Not set';

  @override
  String get pickerFieldPhoto => 'PHOTO · optional';

  @override
  String get pickerFieldLogo => 'LOGO · optional';

  @override
  String get pickerPhotoAdd => 'Add a photo';

  @override
  String get pickerPhotoReplace => 'Replace photo';

  @override
  String get pickerLogoAdd => 'Add a logo';

  @override
  String get pickerLogoReplace => 'Replace logo';

  @override
  String get pickerImageUploadFailed =>
      'Couldn\'t upload that image. Try again.';

  @override
  String get formSeriesHelp => 'Leave blank if it\'s a standalone book';

  @override
  String get formSeriesToggle => 'Part of a series';

  @override
  String get formSeriesToggleSub =>
      'Turn on for a book that belongs to a series';

  @override
  String get formSeriesHint =>
      'Name the series, then which book this is in it.';

  @override
  String get formSeriesNameHelp => 'e.g. Harry Potter';

  @override
  String get formBookNumberHelp => 'e.g. 3';

  @override
  String get formAuthorAddAnother => '＋ Add another author';

  @override
  String get formAuthorHelp =>
      'Add each co-author for books with more than one';

  @override
  String get formIsbnScan => 'Scan barcode';

  @override
  String get formIsbnScanHelp =>
      'Scan the barcode to fill this in — edit if needed';

  @override
  String get formFieldDescription => 'DESCRIPTION';

  @override
  String get formDescriptionHelp =>
      'The back-cover blurb — appears on share cards';

  @override
  String get formFillFromPhotos => 'Fill in from photos';

  @override
  String get formSimilarHeader => 'Already in the catalog?';

  @override
  String get formSimilarHelp =>
      'Tap a match to open it instead of adding a copy — or keep typing.';

  @override
  String get formExtractingTitle => 'Reading your cover…';

  @override
  String get formExtractingSubtitle =>
      'Pulling the title, author, publisher, and blurb';

  @override
  String get formExtractNothing =>
      'Couldn\'t read any details from the photos.';

  @override
  String get formExtractUnavailable =>
      'Reading details from photos isn\'t available right now.';

  @override
  String get formExtractFailed => 'Couldn\'t read the photos. Try again.';

  @override
  String get scanAgain => 'Scan again';

  @override
  String get scanUseIsbnAnyway => 'Use this ISBN anyway';

  @override
  String get scanUseDetails => 'Use these details';

  @override
  String get formCoverFront => 'FRONT';

  @override
  String get formCoverBack => 'BACK';

  @override
  String get formCoverHelp =>
      'Tap a cover to photograph the front and back of your copy.';

  @override
  String get imageSourceCamera => 'Take a photo';

  @override
  String get imageSourceGallery => 'Choose from gallery';

  @override
  String get imageSourceCancel => 'Cancel';

  @override
  String get coverActionAdjust => 'Adjust — crop, rotate, reframe';

  @override
  String get coverActionReplaceCamera => 'Retake photo';

  @override
  String get coverActionReplaceGallery => 'Replace from gallery';

  @override
  String get coverActionRemove => 'Remove photo';

  @override
  String get coverAdjustFailed =>
      'Couldn\'t open that image to adjust. Try replacing it instead.';

  @override
  String pickerChoose(String label) {
    return 'Choose $label';
  }

  @override
  String get bookCoverBack => 'Back cover';

  @override
  String get bookAddBackCover => 'Add back';

  @override
  String get shareAction => 'Share';

  @override
  String shareBookLinkText(String title, String author, String url) {
    return '$title by $author — on Kitabi\n$url';
  }

  @override
  String shareAuthorLinkText(String name, String url) {
    return '$name on Kitabi\n$url';
  }

  @override
  String sharePublisherLinkText(String name, String url) {
    return '$name on Kitabi\n$url';
  }

  @override
  String get shareFailed => 'Couldn\'t open the share sheet. Try again.';

  @override
  String get workPickerTitle => 'Choose a book';

  @override
  String get workPickerSearchHint => 'Search the catalogue by title';

  @override
  String get workPickerEmpty =>
      'No matches — add that book to the catalogue first, then link it.';

  @override
  String get addEditionTitle => 'Add an edition';

  @override
  String get addEditionSubtitle => 'Another printing of this book';

  @override
  String get addEditionSave => 'Add edition';

  @override
  String get bookEditionsSection => 'Editions';

  @override
  String get bookAddEdition => 'Add another edition';

  @override
  String get bookEditionAdded => 'Edition added';

  @override
  String get bookTranslationsSection => 'Also in other languages';

  @override
  String get bookLinkTranslation => 'Link a translation';

  @override
  String get bookTranslationLinked => 'Linked as a translation';

  @override
  String get shareAuthorEyebrow => 'AN AUTHOR ON KITABI';

  @override
  String get sharePublisherEyebrow => 'A PUBLISHER ON KITABI';

  @override
  String get browseTitle => 'Browse the catalogue';

  @override
  String get browseEntry => 'Browse the catalogue';

  @override
  String get browseTabBooks => 'Books';

  @override
  String get browseTabAuthors => 'Authors';

  @override
  String get browseTabPublishers => 'Publishers';

  @override
  String get bookBuySection => 'Where to buy';

  @override
  String get bookBuyFailed => 'Couldn\'t open the store link.';

  @override
  String get browseSortLabel => 'Sort';

  @override
  String get browseSortTitle => 'Title (A–Z)';

  @override
  String get browseSortNewest => 'Newest first';

  @override
  String get browseSortOldest => 'Oldest first';

  @override
  String get browseSortAuthor => 'Author (A–Z)';

  @override
  String get browseFilterAllLanguages => 'All languages';
}
