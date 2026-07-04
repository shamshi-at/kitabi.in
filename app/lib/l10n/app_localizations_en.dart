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
}
