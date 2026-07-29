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
  String get signInQuote1Author => 'George R.R. Martin';

  @override
  String get signInQuote2 =>
      'I have always imagined that Paradise will be a kind of library.';

  @override
  String get signInQuote2Author => 'Jorge Luis Borges';

  @override
  String get signInQuote3 =>
      'A book must be the axe for the frozen sea within us.';

  @override
  String get signInQuote3Author => 'Franz Kafka';

  @override
  String get quoteTapForNew => 'Tap for a new one';

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
      'Visibility · everything starts private';

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
  String get profileViewPublicEntry => 'View my public profile';

  @override
  String get signOutConfirmTitle => 'Sign out?';

  @override
  String get signOutConfirmBody =>
      'Your library stays on this device and picks up where you left off when you sign back in.';

  @override
  String get profileSignOut => 'Sign out';

  @override
  String get profileDeleteAccount => 'Delete account';

  @override
  String get profileDeleteAccountConfirm =>
      'This deletes your Kitabi account and library. This can\'t be undone.';

  @override
  String profileBooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String profileReadingSince(int year) {
    return 'Reading since $year';
  }

  @override
  String get catalogSearchHint => 'Title, author, or ISBN';

  @override
  String get catalogSearchSectionCatalog => 'In the catalogue';

  @override
  String catalogSearchSectionLibrary(int count) {
    return 'In your library · $count';
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
    return '$count $_temp0 in the catalogue';
  }

  @override
  String get linkedAuthorBadge => 'On Kitabi';

  @override
  String get authorBrowseIsMe => 'This is me';

  @override
  String get authorBrowseViewProfile => 'View their Kitabi profile';

  @override
  String get authorLinkFailed => 'Couldn\'t link this author right now';

  @override
  String get authorClaimPending => 'Pending review';

  @override
  String get authorClaimPendingNote =>
      'We\'ll check this before it shows on the book for others.';

  @override
  String get authorClaimSent => 'Sent for review';

  @override
  String get authorClaimAlreadyLinked =>
      'Someone is already linked as this author';

  @override
  String get pickerIsMe => 'This is me';

  @override
  String get pickerIsMeNote =>
      'Checked claims are reviewed before they go live.';

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
    return '$count $_temp0 in the catalogue';
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
      'Camera unavailable — you can search the catalogue or add the book manually below.';

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
  String get formSubtitle => 'catalogue entry · shared';

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
      'Your languages are listed first — manage them in your profile.';

  @override
  String get langPickerTitle => 'Which languages do you read?';

  @override
  String get langPickerSubtitle =>
      'Pick one or more. We\'ll list these first when you add a book — you can change them anytime in your profile.';

  @override
  String get langPickerSaveError => 'Couldn\'t save — try again.';

  @override
  String get langPickerPickOne => 'Pick at least one';

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
  String get formCaptureScan => 'Scan the barcode';

  @override
  String get formCapturePhoto => 'Photograph the covers';

  @override
  String get formCaptureHelp =>
      'Either one fills the form, or just type — everything stays editable.';

  @override
  String get formFieldType => 'TYPE · PICK ONE';

  @override
  String get formTypeOther => '＋ Other';

  @override
  String get formTypeOtherTitle => 'What kind of book is it?';

  @override
  String get formTypeOtherHint => 'Novella, Screenplay, Devotional…';

  @override
  String get formFieldGenrePrimary => 'GENRE · TAP ALL THAT FIT';

  @override
  String get formGenreOtherTitle => 'Add a genre';

  @override
  String get formGenreOtherHint => 'Sufi, Devotional, Magical realism…';

  @override
  String get formMoreDetails => 'More details';

  @override
  String get formMoreDetailsSummary =>
      'Series · publisher · ISBN · pages · format · description';

  @override
  String get formPrefillScan =>
      'Filled from your barcode scan — check and edit anything';

  @override
  String get formPrefillPhotos =>
      'Read from your photos — check and edit anything';

  @override
  String get formSaveHint =>
      'Saved books join the shared catalogue for every reader';

  @override
  String get formSave => 'Save to catalogue';

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
  String get bookStartDateUnset => 'No start date yet';

  @override
  String get bookChangeDate => 'Change';

  @override
  String get bookEditProgress => 'Edit progress';

  @override
  String get bookProgressEdit => 'Edit';

  @override
  String bookStartedOn(String date) {
    return 'Started $date';
  }

  @override
  String get bookStartSession => 'Start a session';

  @override
  String get bookWhereItStands => 'WHERE IT STANDS';

  @override
  String get bookStartReading => 'Start reading';

  @override
  String get bookSecondaryPage => 'Page';

  @override
  String get bookSecondaryNote => 'Note';

  @override
  String get bookReadingLogTitle => 'Reading log';

  @override
  String bookLogSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
      zero: 'No sessions',
    );
    return '$_temp0';
  }

  @override
  String bookLogLastRead(String when) {
    return 'Last read $when';
  }

  @override
  String bookLogTimeRange(String from, String to) {
    return '$from – $to';
  }

  @override
  String bookLogTimeRangeNextDay(String from, String to) {
    return '$from – $to (+1)';
  }

  @override
  String bookLogPages(int from, int to) {
    return 'p. $from → $to';
  }

  @override
  String bookLogPagesRead(int count) {
    return '+$count';
  }

  @override
  String bookLogPagesReadA11y(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages read',
      one: '1 page read',
    );
    return '$_temp0';
  }

  @override
  String bookLogTotalPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get bookLogNoPages => 'Page not noted';

  @override
  String get bookLogEmpty =>
      'No reading sessions yet — start one to build your log.';

  @override
  String get bookLogDelete => 'Delete';

  @override
  String get bookLogDeleted => 'Session removed';

  @override
  String get bookLogWeek => 'Last 7 days';

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
  String get bookReviewShareTooltip => 'Share my review';

  @override
  String get bookEditReview => 'Edit review';

  @override
  String get bookReadersReviewsLabel => 'WHAT READERS ARE SAYING';

  @override
  String get bookReadersReviewsEmpty => 'No public reviews yet.';

  @override
  String get bookYoursTab => 'Yours';

  @override
  String get bookAboutTab => 'About';

  @override
  String get bookChangeStatus => 'Change';

  @override
  String get bookStatusSheetTitle => 'Set status';

  @override
  String get bookSortNewest => 'Newest';

  @override
  String get bookSortRatingHigh => 'Highest rated';

  @override
  String get bookSortRatingLow => 'Lowest rated';

  @override
  String bookReviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reviews',
      one: '1 review',
      zero: 'No reviews yet',
    );
    return '$_temp0';
  }

  @override
  String bookRatingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings',
      one: '1 rating',
      zero: 'No ratings yet',
    );
    return '$_temp0';
  }

  @override
  String bookShowMoreReviews(int count) {
    return 'Show $count more reviews';
  }

  @override
  String get bookNoRatingLabel => 'no rating';

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
  String get reviewDeleted => 'Review deleted';

  @override
  String get ratingSaved => 'Rating saved';

  @override
  String get ratingCleared => 'Rating cleared';

  @override
  String get reviewFinishedTitle => 'You finished it!';

  @override
  String get reviewFinishedSubtitle =>
      'How was it? Tap a star to rate, or write a few words.';

  @override
  String get reviewFinishedAction => 'Write a review';

  @override
  String get reviewFinishedSkip => 'Not now';

  @override
  String get formFieldExpand => 'Edit full screen';

  @override
  String get formEditorDone => 'Done';

  @override
  String get coverFrontLabel => 'Front cover';

  @override
  String get coverBackLabel => 'Back cover';

  @override
  String get coverReturnedStamp => 'Returned';

  @override
  String coverLentBand(String name) {
    return 'With $name';
  }

  @override
  String coverBorrowedBand(String name) {
    return 'From $name';
  }

  @override
  String get createdDialogTitle => 'Added to the catalogue';

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
  String get bookAboutSection => 'About this book';

  @override
  String get bookDescriptionEmpty =>
      'No description yet — know this book? Improve the entry.';

  @override
  String get bookImproveEntry => 'Improve this entry';

  @override
  String get editPendingApproval =>
      'Edit sent — the reader who added this book will review it.';

  @override
  String get revisionsTitle => 'Pending edits';

  @override
  String get revisionsSubtitle => 'Suggested changes to books you added';

  @override
  String get revisionsEmpty =>
      'Nothing to review — suggested edits to books you added will appear here.';

  @override
  String get claimsSectionTitle => 'YOUR AUTHOR CLAIMS';

  @override
  String get claimsPending => 'Waiting for review';

  @override
  String get claimsApproved => 'Approved';

  @override
  String get claimsRejected => 'Not approved';

  @override
  String get claimsWithdraw => 'Withdraw';

  @override
  String get claimsWithdrawTitle => 'Withdraw this claim?';

  @override
  String claimsWithdrawBody(String name) {
    return '$name will no longer be marked as waiting for review. You can claim it again later.';
  }

  @override
  String get claimsWithdrawn => 'Claim withdrawn';

  @override
  String get revisionsSectionTitle => 'SUGGESTED EDITS';

  @override
  String revisionsProposedBy(String name) {
    return 'Suggested by $name';
  }

  @override
  String get revisionsApprove => 'Approve';

  @override
  String get revisionsReject => 'Reject';

  @override
  String get revisionsApproved => 'Edit approved and applied.';

  @override
  String get revisionsRejected => 'Edit rejected.';

  @override
  String borrowerKeepPrivate(String name) {
    return 'Keep “$name” as a private contact';
  }

  @override
  String get borrowerKeepPrivateHint =>
      'They don\'t need Kitabi — the loan stays in your own ledger.';

  @override
  String get connectionsPrivateSection => 'Private contacts';

  @override
  String connectionsPrivateLoans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books out',
      one: '1 book out',
      zero: 'No open loans',
    );
    return '$_temp0 · not on Kitabi';
  }

  @override
  String get connectionsLinkAction => 'Link';

  @override
  String linkContactTitle(String name) {
    return 'Link “$name” to a Kitabi account';
  }

  @override
  String get linkContactBody =>
      'Their loans move onto the linked account and a connection request is sent.';

  @override
  String get linkContactSearchHint => 'Search by name or @username';

  @override
  String get linkContactNoResults => 'No matching readers.';

  @override
  String linkContactConfirm(int count, String handle) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Link $count loans to $handle?',
      one: 'Link 1 loan to $handle?',
    );
    return '$_temp0';
  }

  @override
  String get linkContactDone => 'Linked — connection request sent.';

  @override
  String connectionsLoansWithThem(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open loans',
      one: '1 open loan',
    );
    return '$_temp0';
  }

  @override
  String lendingSummaryOut(int count) {
    return '$count out';
  }

  @override
  String lendingSummaryOverdue(int count) {
    return '$count overdue';
  }

  @override
  String lendingSummaryBorrowed(int count) {
    return '$count with you';
  }

  @override
  String get navSearch => 'Search';

  @override
  String homeGreetingMorning(String name) {
    return 'Good morning, $name';
  }

  @override
  String homeGreetingAfternoon(String name) {
    return 'Good afternoon, $name';
  }

  @override
  String homeGreetingEvening(String name) {
    return 'Good evening, $name';
  }

  @override
  String get homeGreetingMorningAnon => 'Good morning';

  @override
  String get homeGreetingAfternoonAnon => 'Good afternoon';

  @override
  String get homeGreetingEveningAnon => 'Good evening';

  @override
  String get homeFreshShelf => 'Fresh on your shelf';

  @override
  String get homeGoalLabel => 'Reading goal';

  @override
  String homeGoalOf(int goal) {
    return 'of $goal books this year';
  }

  @override
  String homeGoalStart(int year) {
    return 'Set a goal for $year — even a small one.';
  }

  @override
  String get homeStepScanTitle => 'Scan';

  @override
  String get homeStepScanBody =>
      'Point the camera at any barcode — the book fills itself in.';

  @override
  String get homeStepShelveTitle => 'Shelve';

  @override
  String get homeStepShelveBody =>
      'Track what you own, what you\'ve read, and what you wish for.';

  @override
  String get homeStepLendTitle => 'Lend';

  @override
  String get homeStepLendBody =>
      'Hand a book to a friend and never lose track of it again.';

  @override
  String get homeBrowseCatalogue => 'Browse the catalogue';

  @override
  String get insightsFactLabel => 'Did you know';

  @override
  String get insightsFact1 =>
      'Reading just 20 minutes a day adds up to nearly two million words a year.';

  @override
  String get insightsFact2 =>
      'Six minutes of reading can lower stress by more than two-thirds — faster than music or a walk.';

  @override
  String get insightsFact3 =>
      'The average paperback is about 300 pages — a chapter a night finishes it in a month.';

  @override
  String get insightsFact4 =>
      'Malayalam\'s first novel, Kundalatha, was published in 1887.';

  @override
  String get insightsFact5 =>
      'Readers who set a goal finish about twice as many books as those who don\'t.';

  @override
  String get insightsFact6 =>
      'The word \'bookworm\' predates the printing press — it first meant an actual insect.';

  @override
  String get insightsFact7 =>
      'Re-reading a loved book is proven to feel as rewarding as the first time — comfort reads count.';

  @override
  String get insightsFact8 =>
      'Kerala runs one of the world\'s densest library networks — over 8,000 public libraries.';

  @override
  String get insightsFreshTitle => 'Your reading year starts here';

  @override
  String get insightsFreshBody =>
      'Finish your first book and this page becomes your personal reading almanac.';

  @override
  String get insightsGrowsLabel => 'What grows here';

  @override
  String get insightsComingBars => 'Books per month, charted';

  @override
  String get insightsComingPages => 'Pages over the year';

  @override
  String get insightsComingLangs => 'Your language mix';

  @override
  String get insightsComingAuthor => 'Your most-read author';

  @override
  String get insightsAddFirstBook => 'Add your first book';

  @override
  String insightsSetGoalHint(int year) {
    return 'Tap to set your $year goal';
  }

  @override
  String get insightsTopAuthor => 'Most-read author';

  @override
  String get insightsLongestBook => 'Longest book finished';

  @override
  String get insightsAvgPages => 'Avg pages per book';

  @override
  String get lendingPickSearchHint => 'Search your books';

  @override
  String get bookGotIt => 'I got this book — move to my library';

  @override
  String get bookMovedToLibrary => 'Moved to your library — off your wishlist.';

  @override
  String statusReadAllPages(int total) {
    return 'Marked read — p. $total of $total.';
  }

  @override
  String get statusClearTitle => 'Start this book over?';

  @override
  String get statusClearBody =>
      'Back to To read. Would you like to clear its reading log and notes as well, or keep them?';

  @override
  String get statusClearKeep => 'Keep them';

  @override
  String get statusClearWipe => 'Clear them';

  @override
  String get statusCleared => 'Log and notes cleared.';

  @override
  String get bookWishlistAdd => 'Add to wishlist';

  @override
  String get bookWishlistShort => 'Wishlist';

  @override
  String get bookWishlistRemove => 'Remove from wishlist';

  @override
  String get bookWishlistAdded => 'On your wishlist.';

  @override
  String get bookWishlistRemoved => 'Off your wishlist — kept as To read.';

  @override
  String get bookWishlistNotOwned =>
      'You don\'t own this one yet — it\'s on your wishlist.';

  @override
  String get searchReadersHeader => 'Readers';

  @override
  String get publicProfileTitle => 'Reader';

  @override
  String get publicProfilePrivate => 'This reader keeps their profile private.';

  @override
  String get publicLibrarySection => 'Their shelf';

  @override
  String get publicLibraryPrivate => 'Their library is private.';

  @override
  String get publicShelfSearchHint => 'Search their shelf';

  @override
  String get publicShelfSearchEmpty => 'No books match your search.';

  @override
  String get publicProfileBooksLabel => 'Books';

  @override
  String get publicProfileScoreLabel => 'Score';

  @override
  String get publicProfileConnectionsLabel => 'Links';

  @override
  String get publicProfileExLibris => 'Ex Libris';

  @override
  String get publicProfileTabLedger => 'Ledger';

  @override
  String get publicProfileTabShelf => 'Shelf';

  @override
  String get publicProfileTabWorks => 'Works';

  @override
  String get publicProfileConnect => 'Connect';

  @override
  String get publicProfileRequestSent => 'Connection request sent.';

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
  String get bookBorrowedFromFragment => 'Borrowed from';

  @override
  String get bookBorrowedReturnedFragment => 'Returned';

  @override
  String get bookMakeMineAction => 'Make this mine';

  @override
  String get bookMakeMineConfirmTitle => 'Make this your own copy?';

  @override
  String get bookMakeMineConfirmBody =>
      'This moves the book to your library as your own copy. Your reading status, progress, and notes stay exactly as they are — the record of borrowing it stays too, in the lending history below.';

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
  String bookByAuthor(String name) {
    return 'by $name';
  }

  @override
  String bookPagesShort(int count) {
    return '$count pp';
  }

  @override
  String get libraryTitle => 'My Library';

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
  String get libraryViewAll => 'All books';

  @override
  String get libraryViewShelves => 'Shelves';

  @override
  String get libraryNewShelf => 'New shelf';

  @override
  String get libraryNewShelfTitle => 'Name your shelf';

  @override
  String get libraryNewShelfHint => 'e.g. Signed copies';

  @override
  String get libraryShelvesStatusSection => 'Where your books stand';

  @override
  String get libraryShelvesYoursSection => 'Your shelves';

  @override
  String get libraryShelfFavourites => 'Favourites';

  @override
  String get libraryFilterShelf => 'Shelf';

  @override
  String get librarySortTitle => 'Sort';

  @override
  String get librarySortRecent => 'Recently added';

  @override
  String get librarySortAZ => 'Title A–Z';

  @override
  String get librarySortAuthor => 'Author';

  @override
  String get libraryFabLabel => 'Search, filter and sort';

  @override
  String get libraryFilterTitle => 'Filter';

  @override
  String get libraryFilterStatus => 'Status';

  @override
  String get libraryFilterLanguage => 'Language';

  @override
  String get libraryFilterType => 'Type';

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
      'Remove this book from your library? Your rating and review stay on the shared catalogue entry, but this copy, its reading progress, and its notes are gone.';

  @override
  String get bookTagsLabel => 'SHELVES · yours only';

  @override
  String get bookShelfLabel => 'On a shelf';

  @override
  String get bookShelfLabelEmpty => 'Shelf · yours only';

  @override
  String bookShelfOthers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This copy + $count others',
      one: 'This copy + 1 other',
      zero: 'Just this copy on it',
    );
    return '$_temp0';
  }

  @override
  String get bookShelfMove => 'Move to another shelf';

  @override
  String get bookShelfRemove => 'Remove';

  @override
  String bookShelfRemoved(String shelf) {
    return 'Taken off $shelf';
  }

  @override
  String get bookShelfEmptyTitle => 'Not on a shelf yet';

  @override
  String get bookShelfEmptyBody => 'Keep it somewhere of your own';

  @override
  String get bookShelfChoose => 'Choose a shelf';

  @override
  String get bookAddTag => '+ add';

  @override
  String get bookNewTagTitle => 'Add to a shelf';

  @override
  String get bookNewTagHint => 'e.g. beach reads';

  @override
  String get shelfPickerTitle => 'Choose a shelf';

  @override
  String get shelfPickerHint =>
      'One shelf per book — picking a shelf moves it here.';

  @override
  String get shelfPickerEmpty => 'No shelves yet — create your first below.';

  @override
  String get libraryShelfEmptyTitle => 'This shelf is empty';

  @override
  String get libraryShelfEmptyBody =>
      'Shelves are yours to arrange — move a book you already own onto this one.';

  @override
  String get libraryShelfAddBooks => 'Add books to this shelf';

  @override
  String libraryAddToShelfTitle(String shelf) {
    return 'Add to $shelf';
  }

  @override
  String get libraryAddBooksHint =>
      'Tap a book to move it here — off any other shelf — or take it off this one.';

  @override
  String get libraryAddBooksEmpty =>
      'Your library is empty — add a book first.';

  @override
  String get libraryShelfAddBooksShort => 'Add books';

  @override
  String get libraryAddBooksSearchHint => 'Search your library';

  @override
  String get libraryAddBooksNoMatchTitle => 'Not in your library';

  @override
  String get libraryAddBooksNoMatchBody =>
      'Only books you already have can go on a shelf. Find it in the catalogue to add it to your library first.';

  @override
  String get libraryAddBooksBrowse => 'Browse the catalogue';

  @override
  String get scanAddedToLibrary => 'Added to your library';

  @override
  String get homeCurrentlyReading => 'Currently reading';

  @override
  String get homeYourLibrary => 'Your library';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeEmptyTitle => 'Your first shelf awaits';

  @override
  String get homeEmptyBody =>
      'Every library starts with one book. Scan the one nearest you — the rest follows.';

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
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Due in ${days}d',
      zero: 'Due today',
    );
    return '$_temp0';
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
  String get lendingLendBook => 'Lend a book';

  @override
  String get lendingLogBorrowedFab => 'Log a borrowed book';

  @override
  String get lendingReturnedSnack => 'Marked as returned.';

  @override
  String get undoAction => 'Undo';

  @override
  String get lendingDueHelper => 'A due date sets a quiet reminder.';

  @override
  String get lendingNoteLabel => 'Note · optional';

  @override
  String get lendingNoDate => 'Pick a date';

  @override
  String get lendingSaveFailed => 'Couldn\'t save the loan.';

  @override
  String get lendingSearchOffline =>
      'Search is offline — you can still add the book to the catalogue.';

  @override
  String lendingPickNoMatch(String query) {
    return 'Nothing matching “$query”.';
  }

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
  String connectionsDisconnectConfirm(String name) {
    return 'Disconnect from $name? The loans on your ledger stay put.';
  }

  @override
  String get connectionsActionFailed => 'That didn\'t go through — try again.';

  @override
  String get connectionLoanOut => 'Out';

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
  String logBorrowedAddNew(String title) {
    return '＋ Add \"$title\" to the catalogue';
  }

  @override
  String get logBorrowedNotFound =>
      'Not in the catalogue yet? Add it — you\'ll come right back here.';

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
  String get logBorrowedSave => 'Save to my borrowed shelf';

  @override
  String get lendSheetTitlePrefix => 'Lend';

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
  String get welcomeTitle1 => 'Beyond the Bookshelf';

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
  String get updateBodyAppStore =>
      'This version of Kitabi is out of date. Please update from the App Store to keep going.';

  @override
  String get updateBodyPlayStore =>
      'This version of Kitabi is out of date. Please update from Google Play to keep going.';

  @override
  String get updateTryAgain => 'Try again';

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
    return '$matched of $total matched to the catalogue';
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
  String get importStartOver => 'Start over';

  @override
  String get importParseFailed =>
      'Couldn\'t read that CSV — is it a Goodreads export?';

  @override
  String get importFailed => 'Couldn\'t finish the import — try again.';

  @override
  String importUnmatchedCount(int skipped, int total) {
    return '$skipped of $total couldn\'t be matched and will be skipped.';
  }

  @override
  String get importCsvHint => 'Title,Author,ISBN,My Rating,Exclusive Shelf…';

  @override
  String importDoneWithSkipped(int count, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'books',
      one: 'book',
    );
    return 'Imported $count $_temp0 ($skipped already in your library)';
  }

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
  String get profileScoreHeader => 'Reputation';

  @override
  String get reputationEmpty => 'Add your first book to start earning.';

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
  String activityAddedBookTitled(String title) {
    return 'Added $title';
  }

  @override
  String activityFinishedBookTitled(String title) {
    return 'Finished $title';
  }

  @override
  String activityRatedBookTitled(String title) {
    return 'Rated $title';
  }

  @override
  String activityWroteReviewTitled(String title) {
    return 'Reviewed $title';
  }

  @override
  String activityLentBookTitled(String title) {
    return 'Lent $title';
  }

  @override
  String get activityGeneric => 'Activity';

  @override
  String get activityEmptyTitle => 'Nothing yet';

  @override
  String get shareEyebrow => 'SHARE A BOOK';

  @override
  String get shareEyebrowPersonal => 'From my shelf';

  @override
  String get shareYourRating => 'your rating';

  @override
  String get shareCatalogAvg => 'catalogue avg';

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
  String get recsLoadingTitle => 'Thinking about your shelf…';

  @override
  String get recsLoadingSubtitle =>
      'Reasoning from your ratings — this can take a few seconds.';

  @override
  String get timerSessionLabel => 'Reading Session';

  @override
  String get timerStart => 'Start';

  @override
  String get timerInProgress => 'Session in progress';

  @override
  String get timerMinimizeHint => 'Keep reading — the timer stays on';

  @override
  String get timerElapsed => 'elapsed';

  @override
  String timerInTheZone(int minutes) {
    return 'In the zone — $minutes min';
  }

  @override
  String get timerStopAndLog => 'Stop & log';

  @override
  String timerLoggedTitle(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes, well spent',
      one: '1 minute, well spent',
      zero: 'Under a minute, logged',
    );
    return '$_temp0';
  }

  @override
  String get timerThisSession => 'This session';

  @override
  String get timerThisWeek => 'This week';

  @override
  String get timerPageFieldLabel => 'Read up to page';

  @override
  String timerPageFieldOf(int total) {
    return 'of $total';
  }

  @override
  String get timerTotalFieldLabel => 'of';

  @override
  String get timerTotalFieldHint => 'total';

  @override
  String get timerPageFieldHint => '0';

  @override
  String get timerDone => 'Done';

  @override
  String get timerDoneKeepsPage =>
      'Done keeps the page — clear the field to keep only the time.';

  @override
  String get timerRecentSessions => 'Recent sessions';

  @override
  String get timerNoSessionsYet =>
      'No sessions logged yet — tap Start to begin one.';

  @override
  String timerMiniBarLive(String elapsed) {
    return '$elapsed · tap to open';
  }

  @override
  String get timerToday => 'Today';

  @override
  String get timerYesterday => 'Yesterday';

  @override
  String get insightsReadingTime => 'Reading time';

  @override
  String insightsWeekTotal(String duration) {
    return '$duration this week';
  }

  @override
  String insightsVsLastWeek(String duration) {
    return '$duration vs last week';
  }

  @override
  String insightsReadingTimeInsight(String day, String hourRange) {
    return 'You read most on ${day}s, often around $hourRange.';
  }

  @override
  String timerMiniBarStopped(String duration) {
    return 'Session logged — $duration';
  }

  @override
  String get timerPageDialogSkip => 'Skip';

  @override
  String get timerStop => 'Stop';

  @override
  String get timerCheckInTitle => 'Still reading?';

  @override
  String get timerCheckInBody =>
      'It\'s been a while. Press & hold for Yes/No, or tap to open the timer.';

  @override
  String get timerCheckInYes => 'Yes, still reading';

  @override
  String get timerCheckInNo => 'No, stop it';

  @override
  String get timerAutoStoppedTitle => 'Reading timer stopped';

  @override
  String timerAutoStoppedBody(String duration) {
    return 'Logged $duration while you were away.';
  }

  @override
  String timerResumeSafetyNetMessage(String duration) {
    return 'Your timer was still running, so we stopped it — logged $duration.';
  }

  @override
  String get timerLogManually => 'Log manually';

  @override
  String get timerManualSheetTitle => 'Log a reading session';

  @override
  String get timerManualDurationLabel => 'How long did you read?';

  @override
  String get timerManualDurationUnit => 'minutes';

  @override
  String get timerManualSave => 'Save session';

  @override
  String timerSessionPages(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get noteAThought => 'Note a thought';

  @override
  String get noteStillRunning => 'still running';

  @override
  String noteOfThisSitting(String book, int n) {
    return '$book · note $n of this sitting';
  }

  @override
  String get noteYourThought => 'Your thought · only you';

  @override
  String get noteHint => 'What are you thinking?';

  @override
  String get notePagesLabel => 'Pages · optional';

  @override
  String get noteAddRange => 'range';

  @override
  String get noteSingle => 'single';

  @override
  String get notePagesHelp =>
      'Starts at the page you\'re on. Leave it, widen it to a range, or clear it — a thought doesn\'t have to live anywhere.';

  @override
  String get noteSaveKeepReading => 'Save & keep reading';

  @override
  String get noteSaveChanges => 'Save changes';

  @override
  String get noteSave => 'Save note';

  @override
  String get noteTimerNeverPaused =>
      'Saved to this book only you can read. The timer never paused.';

  @override
  String noteWrittenOn(String date) {
    return 'Written on $date';
  }

  @override
  String noteFromSitting(String duration, int from, int to) {
    return 'From your sitting · $duration · p. $from to $to';
  }

  @override
  String get noteEditNeverMoves =>
      'Editing the words never moves the note — it stays under the sitting it was written in, so the journal keeps telling the truth about when you thought it.';

  @override
  String get rotateTitle => 'Straighten the photo';

  @override
  String get rotateHint =>
      'Twist with two fingers to set any angle, or nudge a quarter-turn at a time.';

  @override
  String get rotateApply => 'Apply';

  @override
  String get coverRotate => 'Rotate — set any angle by hand';

  @override
  String get noteEdit => 'Edit';

  @override
  String get noteDelete => 'Delete this note';

  @override
  String get noteDeleteConfirm => 'Delete this note?';

  @override
  String get notesTitle => 'Your notes';

  @override
  String get notesAlwaysPrivate => 'always private';

  @override
  String notesSummary(int notes, int sittings) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes notes',
      one: '1 note',
    );
    String _temp1 = intl.Intl.pluralLogic(
      sittings,
      locale: localeName,
      other: '$sittings sittings',
      one: '1 sitting',
    );
    return '$_temp0 across $_temp1';
  }

  @override
  String notesSessionHeader(String date, String duration) {
    return '$date · $duration';
  }

  @override
  String get notesNoSitting => 'Not from a sitting';

  @override
  String get notesTapToEdit => 'Tap any note to open and edit it.';

  @override
  String get notesAdd => 'Add a note';

  @override
  String get notesEmpty =>
      'No notes yet. Anything you jot while reading lands here.';

  @override
  String notesSectionThisSitting(int n) {
    return 'Notes from this sitting · $n';
  }

  @override
  String get notesClosingThought => 'Add a closing thought…';

  @override
  String stopSkipNotesSafe(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'your $n notes are already saved',
      one: 'your note is already saved',
    );
    return 'Skip — $_temp0';
  }

  @override
  String stopSkipNotesAndPage(int n, int page) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'your $n notes are saved',
      one: 'your note is saved',
    );
    return 'Skip — $_temp0; the page stays at $page';
  }

  @override
  String get stopWhereDidYouGet => 'Where did you get to?';

  @override
  String get stopPageUnit => 'page';

  @override
  String get stopHoldForTen => 'hold − / + for 10';

  @override
  String get stopSessionLogged => 'Session logged';

  @override
  String stopStartedAtPage(int page) {
    return 'You started this session at p. $page';
  }

  @override
  String stopLastSession(String date, String duration, int from, int to) {
    return 'Last time · $date · $duration · p. $from → $to';
  }

  @override
  String get stopOpenLog => 'Log';

  @override
  String get stopSavePage => 'Save the page';

  @override
  String stopSkipWithPage(int page) {
    return 'Skip — keep the time, leave the page at $page';
  }

  @override
  String get stopSkipNoPage => 'Skip — keep the time only';

  @override
  String get stopTotalQuestion => 'How long is this book?';

  @override
  String get stopTotalUnit => 'pages';

  @override
  String get stopTotalWhy =>
      'Optional. Nobody has told the catalogue yet — filling it in gives you a % here, and helps every other reader of this book.';

  @override
  String get stopErrorBelowOne => 'Pages start at 1.';

  @override
  String stopErrorAboveTotal(int total) {
    return 'This book has $total pages.';
  }

  @override
  String stopErrorBelowStart(int page) {
    return 'That\'s before p. $page, where this sitting began. To correct earlier progress, edit it from the book page.';
  }

  @override
  String stopSessionsTitle(String title) {
    return '$title · your sessions';
  }

  @override
  String stopSessionsSummary(String duration, int pages, int count) {
    return '$duration · $pages pages · $count sittings';
  }

  @override
  String get stopSessionsNoPage => 'no page noted';

  @override
  String get stopSessionsSkipNote =>
      'A sitting with no page is still a sitting — the time counts toward your week either way.';

  @override
  String get stopBackToPage => 'Back to the page';

  @override
  String timerPagesPerHour(String rate) {
    return '$rate pages/hr';
  }

  @override
  String insightsPagesThisWeek(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages',
      one: '1 page',
    );
    return '$_temp0 this week';
  }

  @override
  String insightsPagesPace(String rate) {
    return '$rate pages/hr average';
  }

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
  String get recsWishlistedSnack => 'Added to your wishlist';

  @override
  String get recsDismissedSnack => 'Okay, noted';

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
  String get insightsPeriodToday => 'Today';

  @override
  String get insightsPeriodWeek => 'Week';

  @override
  String get insightsPeriodMonth => 'Month';

  @override
  String get insightsPeriod3Months => '3 months';

  @override
  String get insightsPeriod6Months => '6 months';

  @override
  String get insightsPeriodYear => 'Year';

  @override
  String get insightsEyebrowThisWeek => 'This week';

  @override
  String get insightsEyebrowLast3Months => 'Last 3 months';

  @override
  String get insightsEyebrowLast6Months => 'Last 6 months';

  @override
  String get insightsPeriodTodayHeadline => 'Today\'s sitting.';

  @override
  String get insightsPeriodWeekHeadline => 'This week, in books.';

  @override
  String get insightsPeriodMonthHeadline => 'This month, so far.';

  @override
  String get insightsPeriodMultiMonthHeadline => 'A good stretch of reading.';

  @override
  String get insightsYearHeadlineAhead => 'Ahead of your own pace.';

  @override
  String get insightsYearHeadlineOnTrack => 'Right on your own pace.';

  @override
  String get insightsYearHeadlineBehind => 'Behind your own pace, for now.';

  @override
  String get insightsYearHeadlineAllTime => 'Your library, so far.';

  @override
  String get insightsReadToday => 'read today';

  @override
  String insightsPagesGained(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count pages',
      one: '+1 page',
    );
    return '$_temp0';
  }

  @override
  String insightsStreakDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days running',
      one: '1 day running',
    );
    return '$_temp0';
  }

  @override
  String insightsStreakPill(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days-day streak',
      one: '1-day streak',
    );
    return '$_temp0';
  }

  @override
  String get insightsNoSessionToday =>
      'No sitting yet today — even a few pages count.';

  @override
  String get insightsLast7Days => 'Last 7 days';

  @override
  String get insightsFinishedSection => 'Finished';

  @override
  String get insightsClosingWeekUp =>
      'A fuller week than last — the story kept you.';

  @override
  String get insightsClosingWeekSteady => 'Every sitting this week counted.';

  @override
  String get insightsClosingWeekNone =>
      'A quiet week so far — the book will wait.';

  @override
  String insightsClosingMonthDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reading days this month, and counting.',
      one: '1 reading day this month, and counting.',
      zero: 'No reading days yet this month — there\'s still time.',
    );
    return '$_temp0';
  }

  @override
  String insightsClosingStretch(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books finished over this stretch — steady wins.',
      one: '1 book finished over this stretch — steady wins.',
      zero: 'No finishes this stretch — good books take their time.',
    );
    return '$_temp0';
  }

  @override
  String insightsBooksFinished(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books finished',
      one: '1 book finished',
      zero: 'No books finished',
    );
    return '$_temp0';
  }

  @override
  String insightsDaysRead(int read, int elapsed) {
    return '$read of $elapsed days read';
  }

  @override
  String insightsHoursReading(String duration) {
    return '$duration reading';
  }

  @override
  String get insightsShareTooltip => 'Share';

  @override
  String insightsBooksLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'books',
      one: 'book',
    );
    return '$_temp0';
  }

  @override
  String insightsShareSubLineAllTime(String pages, String duration) {
    return '$pages · $duration · all time';
  }

  @override
  String insightsShareSubLineYear(String pages, String duration, int year) {
    return '$pages · $duration · $year';
  }

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
  String homeProgressOfTotal(int total) {
    return 'of $total pages';
  }

  @override
  String homeProgressTooFar(int total) {
    return 'This book has $total pages.';
  }

  @override
  String get homeProgressInvalid => 'Enter a valid page number.';

  @override
  String homeProgressLineNoTotal(int page) {
    return 'p. $page';
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
  String get homeNudgeView => 'View';

  @override
  String homeNudgeNoDue(String title, String name) {
    return '$title is with $name';
  }

  @override
  String get searchTitle => 'Search';

  @override
  String get catalogSearchSectionAuthors => 'Authors';

  @override
  String get catalogSearchSectionPublishers => 'Publishers';

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
  String get authorPickerIsMe => 'This is me — I wrote this book';

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
  String get formAuthorAddSelf =>
      'Is this your book? Tag yourself as the author';

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
  String get formScanBackCover => 'Scan back cover';

  @override
  String get formSimilarHeader => 'Already in the catalogue?';

  @override
  String get formSimilarHelp =>
      'Tap a match to open it instead of adding a copy — or keep typing.';

  @override
  String get formExtractingTitle => 'Reading your cover…';

  @override
  String get formExtractingSubtitle =>
      'Pulling the title, author, publisher, blurb, and type';

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
  String get pickerSearchHint => 'Search';

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
  String get insightsShareSheetTitle => 'Share your reading';

  @override
  String get insightsShareFormatStory => 'Story';

  @override
  String get insightsShareFormatSquare => 'Square';

  @override
  String get insightsShareCaptionLabel => 'Caption';

  @override
  String get insightsShareCopyCaption => 'Copy caption';

  @override
  String get insightsShareImageButton => 'Share image';

  @override
  String get insightsShareCaptionCopied => 'Caption copied';

  @override
  String get insightsShareCaptionSuffix => '— logged with Kitabi.';

  @override
  String get insightsShareLine1 => 'Time well spent, one page at a time.';

  @override
  String get insightsShareLine2 => 'Some days are made of paper.';

  @override
  String get insightsShareLine3 => 'A little further into the story.';

  @override
  String get insightsShareLine4 => 'Quietly, a few more chapters.';

  @override
  String get insightsShareLine5 => 'Books first, everything else after.';

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
  String get bookEditionFallback => 'Edition';

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
  String bookTranslationOf(String title) {
    return 'Translation of $title';
  }

  @override
  String get bookAddTranslation => 'Add a translation';

  @override
  String bookTranslatedBy(String name) {
    return 'trans. $name';
  }

  @override
  String get formFieldTranslatedFrom => 'Translated from';

  @override
  String get formLinkOriginal => 'Link the original work';

  @override
  String get formTranslatedFromHelp =>
      'Reading a translation? Linking the original lets readers hop between versions.';

  @override
  String get formFieldTranslator => 'Translator';

  @override
  String get formTranslatorHelp =>
      'Credited on this book, alongside the author — a translator has their own page too.';

  @override
  String get formAddTranslator => 'Add translator';

  @override
  String get workPickerOriginalTitle => 'The original work';

  @override
  String get workPickerOriginalSubtitle =>
      'Search the shared catalogue in any script';

  @override
  String get workPickerAddOriginal => 'Not here? Add the original';

  @override
  String get workPickerAddOriginalHelp =>
      'A catalogue entry, not a book you own — nothing lands on your shelf.';

  @override
  String get workPickerStampOriginal => 'Original';

  @override
  String get workPickerStampInGroup => 'in group';

  @override
  String get stubFieldTitle => 'Original title';

  @override
  String get stubFieldYear => 'Year';

  @override
  String get stubCarriedOver =>
      'Author, type and genre are copied from your book — a translation shares them. Everything stays editable later.';

  @override
  String get stubSave => 'Add & link';

  @override
  String get forkAlreadyHere => 'Kitabi already has this book.';

  @override
  String get forkQuestion => 'So what are you adding?';

  @override
  String get forkOwnThis => 'I own this one — put it on my shelf';

  @override
  String get forkOwnThisAdded => 'On your shelf';

  @override
  String get forkDifferentPrinting => 'Mine\'s a different printing';

  @override
  String get forkDifferentPrintingHelp =>
      'Other ISBN, cover or page count — add an edition';

  @override
  String get forkTranslation => 'Mine\'s a translation';

  @override
  String get forkTranslationHelp => 'Its own book, linked to this one';

  @override
  String get forkDifferentBook => 'Different book, same title — keep typing';

  @override
  String get shareAuthorEyebrow => 'AN AUTHOR ON KITABI';

  @override
  String get sharePublisherEyebrow => 'A PUBLISHER ON KITABI';

  @override
  String get browseTitle => 'Browse the catalogue';

  @override
  String get browseEntry => 'Browse the catalogue';

  @override
  String get searchRecentSection => 'Recent';

  @override
  String get searchRecentClear => 'Clear';

  @override
  String searchNewInLanguage(String language) {
    return 'New in $language';
  }

  @override
  String get searchNewInLanguageNote =>
      'Newest in the catalogue · from your profile languages';

  @override
  String get searchNewInCatalogue => 'New in the catalogue';

  @override
  String get searchNewInCatalogueNote =>
      'Newest additions · set your reading languages to narrow this';

  @override
  String get pickerGenreTitle => 'Genre';

  @override
  String get pickerTypeTitle => 'Type';

  @override
  String get pickerAlreadyHere => 'Already in the catalogue';

  @override
  String get pickerNoMatches => 'Nothing matches that.';

  @override
  String pickerBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String pickerCreate(String value) {
    return 'Create “$value”';
  }

  @override
  String get pickerCreateSharedNote =>
      'Only if none of the above is it — a new genre joins the shared filter for every reader.';

  @override
  String pickerDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Done · $count selected',
      one: 'Done · 1 selected',
      zero: 'Done',
    );
    return '$_temp0';
  }

  @override
  String pickerGenreSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count in the catalogue · tap all that fit',
      one: '1 in the catalogue · tap all that fit',
    );
    return '$_temp0';
  }

  @override
  String pickerTypeSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to choose from',
      one: '1 to choose from',
    );
    return '$_temp0';
  }

  @override
  String get formPickerMore => 'Search or add';

  @override
  String get formGenreYoursNote => 'Your most-used genres first.';

  @override
  String get searchPopularAuthors => 'Most in the catalogue';

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

  @override
  String get browseFilterAllTypes => 'All types';

  @override
  String get browseFilterAllGenres => 'All genres';

  @override
  String get browseFilterHeading => 'Filter & sort';

  @override
  String get browseFilterApply => 'Show books';

  @override
  String get browseFilterClear => 'Clear';

  @override
  String get browseFilterAllTitle => 'All';

  @override
  String get browseFilterYourLanguages => 'Your languages';

  @override
  String get browseEmptyInYourLanguages =>
      'Nothing here in your languages yet.';

  @override
  String get browseShowAllBooks => 'Show all books';

  @override
  String get browseFabLabel => 'Search and filter the catalogue';

  @override
  String get paceLabel => 'Time to finish';

  @override
  String get paceLabelYours => 'your pace';

  @override
  String get paceLabelAssumed => 'not yours yet';

  @override
  String get paceOfReading => 'of reading';

  @override
  String get paceLeft => 'left';

  @override
  String pacePages(int count) {
    return '$count pages';
  }

  @override
  String paceSittings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $count sittings',
      one: '≈ 1 sitting',
    );
    return '$_temp0';
  }

  @override
  String get paceSittingsUnit => 'sittings';

  @override
  String paceWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $count weeks',
      one: '≈ 1 week',
    );
    return '$_temp0';
  }

  @override
  String paceDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $count days',
      one: '≈ 1 day',
    );
    return '$_temp0';
  }

  @override
  String get paceAtYourRate => 'at your rate';

  @override
  String paceYourPaceLine(String pph, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your pace $pph pages/hour, from $count sittings.',
      one: 'Your pace $pph pages/hour, from 1 sitting.',
    );
    return '$_temp0';
  }

  @override
  String paceLanguageLine(String language, String pph) {
    return 'Your pace in $language: $pph pages/hour.';
  }

  @override
  String paceWeeklyHabit(String duration) {
    return 'You\'ve read $duration a week lately.';
  }

  @override
  String paceAssumedValue(String pph) {
    return 'at a typical $pph pages/hour';
  }

  @override
  String paceAssumedHint(int have, int need) {
    return '$have of $need timed sittings. Log a page when you stop and this becomes your number.';
  }

  @override
  String paceFinishAround(String date) {
    return 'Keep this up and you\'d finish around $date';
  }

  @override
  String paceBookPaceLine(String pph, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Measured on this book: $pph pages/hour over $count sittings.',
      one: 'Measured on this book: $pph pages/hour over 1 sitting.',
    );
    return '$_temp0';
  }

  @override
  String paceVsUsual(String pph) {
    return 'Your usual is $pph.';
  }

  @override
  String get paceNoPageCount =>
      'Nobody has told the catalogue how long this book is.';

  @override
  String get paceNoPageCountSub =>
      'Your pace is fine — it\'s the pages that are missing.';

  @override
  String get paceAddPageCount => 'How long is it?';

  @override
  String get paceAddPageCountHint =>
      'Check the last numbered page. It fixes this for every reader of this edition, not just you.';

  @override
  String get paceHiddenFromFilters => 'Hidden from time-to-finish filters';

  @override
  String get paceFinished => 'Finished';

  @override
  String get paceYouReadItIn => 'you read it in';

  @override
  String paceActualSittings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sittings',
      one: '1 sitting',
    );
    return '$_temp0';
  }

  @override
  String paceCalibration(String estimate) {
    return 'At your usual pace this would have been $estimate.';
  }

  @override
  String paceCalibrationOver(int percent, String pph) {
    return 'You ran $percent% over — $pph pages/hour here.';
  }

  @override
  String paceCalibrationUnder(int percent, String pph) {
    return 'You came in $percent% under — $pph pages/hour here.';
  }

  @override
  String paceStripValue(String duration) {
    return '≈ $duration for you';
  }

  @override
  String paceStripAssumed(String duration) {
    return '≈ $duration at a typical pace';
  }

  @override
  String get paceFilterLabel => 'Time to finish';

  @override
  String get paceFilterAny => 'Any';

  @override
  String paceFilterUnder(int hours) {
    return 'Under ${hours}h';
  }

  @override
  String paceFilterRange(int from, int to) {
    return '$from – ${to}h';
  }

  @override
  String paceFilterOver(int hours) {
    return '${hours}h +';
  }

  @override
  String paceFilterExcluded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books have no page count, so they can\'t be estimated.',
      one: '1 book has no page count, so it can\'t be estimated.',
    );
    return '$_temp0';
  }

  @override
  String get paceFilterAssumedNote =>
      'Estimates use a typical pace until you\'ve timed a few sittings.';

  @override
  String timerLiveProgress(int page, int total) {
    return 'p. $page of $total';
  }

  @override
  String timerLiveProgressPage(int page) {
    return 'p. $page';
  }

  @override
  String get timerLiveRunning => 'Reading now';

  @override
  String get timerMarkFinished => 'I finished the book';

  @override
  String get timerMarkFinishedHint => 'Marks it Read and settles the last page';

  @override
  String get timerMarkFinishedDone => 'Marked as Read';

  @override
  String get timerLiveElapsed => 'Reading';

  @override
  String get quickAddFailed => 'Couldn\'t add it to your library — try again.';

  @override
  String get formSaveFailed =>
      'Couldn\'t save — check your connection and try again.';

  @override
  String get formDiscardTitle => 'Discard this book?';

  @override
  String get formDiscardEditTitle => 'Discard your edits?';

  @override
  String get formDiscardBody => 'Nothing here is saved yet.';

  @override
  String get formDiscardConfirm => 'Discard';

  @override
  String get formEditReviewBanner =>
      'A shared entry — if another reader contributed this book, your edit goes to them for review.';

  @override
  String get formSaveHintEdit =>
      'Edits publish to the shared catalogue — another reader\'s book goes to its contributor for review.';

  @override
  String get formFormatUnset => 'Not set';

  @override
  String get formatPaperback => 'Paperback';

  @override
  String get formatHardcover => 'Hardcover';

  @override
  String get formatEbook => 'eBook';

  @override
  String get formatAudiobook => 'Audiobook';

  @override
  String get genreFiction => 'Fiction';

  @override
  String get genreNonFiction => 'Non-fiction';

  @override
  String get genrePoetry => 'Poetry';

  @override
  String get genreHistorical => 'Historical';

  @override
  String get genreMystery => 'Mystery';

  @override
  String get genreRomance => 'Romance';

  @override
  String get genreFantasy => 'Fantasy';

  @override
  String get genreBiography => 'Biography';

  @override
  String get genreScience => 'Science';

  @override
  String get genreSelfHelp => 'Self-help';

  @override
  String get addEditionSaveHint =>
      'New editions join the shared catalogue for every reader';

  @override
  String addEditionAdded(String title) {
    return 'Edition added to $title';
  }

  @override
  String get addEditionAddedNoTitle => 'Edition added';

  @override
  String get scanLookupFailed =>
      'Couldn\'t check the catalogue — try again when you\'re online.';

  @override
  String get scanAlreadyOnShelf => 'Already on your shelf — opening it.';

  @override
  String get pickerSearchFailed =>
      'Couldn\'t search the catalogue — check your connection.';

  @override
  String get pickerSaveAuthorFailed => 'Couldn\'t save the author — try again.';

  @override
  String get pickerSavePublisherFailed =>
      'Couldn\'t save the publisher — try again.';

  @override
  String get pickerNone => 'None';

  @override
  String browseFilterAllCount(int count) {
    return 'All $count';
  }

  @override
  String get claimsWithdrawFailed =>
      'Couldn\'t withdraw the claim — try again.';

  @override
  String get claimsLoadFailed => 'Couldn\'t load your author claims.';

  @override
  String get revisionsDecideFailed =>
      'Couldn\'t save that decision — try again.';

  @override
  String get commonGoHome => 'Go home';
}
