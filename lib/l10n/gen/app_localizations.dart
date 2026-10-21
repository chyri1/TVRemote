import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'TV Remote'**
  String get appTitle;

  /// No description provided for @byChyri.
  ///
  /// In en, this message translates to:
  /// **'by Chyri'**
  String get byChyri;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get statusConnecting;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline · retrying'**
  String get statusOffline;

  /// No description provided for @statusNeedsPairing.
  ///
  /// In en, this message translates to:
  /// **'Pairing required'**
  String get statusNeedsPairing;

  /// No description provided for @statusNoTv.
  ///
  /// In en, this message translates to:
  /// **'No TV added'**
  String get statusNoTv;

  /// No description provided for @addTv.
  ///
  /// In en, this message translates to:
  /// **'Add TV'**
  String get addTv;

  /// No description provided for @myTvs.
  ///
  /// In en, this message translates to:
  /// **'My TVs'**
  String get myTvs;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Forget device'**
  String get remove;

  /// No description provided for @removeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Forget {name}?'**
  String removeConfirm(String name);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @pairAgain.
  ///
  /// In en, this message translates to:
  /// **'Reconfigure PIN'**
  String get pairAgain;

  /// No description provided for @pairTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a TV'**
  String get pairTitle;

  /// No description provided for @pairSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your PC and TV must be on the same network.'**
  String get pairSubtitle;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching the network…'**
  String get searching;

  /// No description provided for @noTvsFound.
  ///
  /// In en, this message translates to:
  /// **'No TV found automatically. Enter the IP address below.'**
  String get noTvsFound;

  /// No description provided for @searchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// No description provided for @manualIp.
  ///
  /// In en, this message translates to:
  /// **'TV IP address'**
  String get manualIp;

  /// No description provided for @manualIpHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 192.168.0.42'**
  String get manualIpHint;

  /// No description provided for @tvName.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get tvName;

  /// No description provided for @tvNameHint.
  ///
  /// In en, this message translates to:
  /// **'Living room TV'**
  String get tvNameHint;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @ipHelp.
  ///
  /// In en, this message translates to:
  /// **'On the TV: Settings › Network & Internet › your network.'**
  String get ipHelp;

  /// No description provided for @enterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get enterCodeTitle;

  /// No description provided for @enterCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type the 6-character code shown on your TV.'**
  String get enterCodeSubtitle;

  /// No description provided for @pair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get pair;

  /// No description provided for @wrongCode.
  ///
  /// In en, this message translates to:
  /// **'Wrong code. Check the TV and try again.'**
  String get wrongCode;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'The code has 6 characters (0–9, A–F).'**
  String get invalidCode;

  /// No description provided for @pairingFailed.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed. Try again.'**
  String get pairingFailed;

  /// No description provided for @tvUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the TV. Check the IP and that it\'s on.'**
  String get tvUnreachable;

  /// No description provided for @pairingSuccess.
  ///
  /// In en, this message translates to:
  /// **'Paired!'**
  String get pairingSuccess;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing secure identity…'**
  String get preparing;

  /// No description provided for @needsPairingBody.
  ///
  /// In en, this message translates to:
  /// **'This TV doesn\'t recognize this PC yet.'**
  String get needsPairingBody;

  /// No description provided for @noTvBody.
  ///
  /// In en, this message translates to:
  /// **'Add your Android TV to start controlling it from here.'**
  String get noTvBody;

  /// No description provided for @power.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get power;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @volumeUp.
  ///
  /// In en, this message translates to:
  /// **'Volume up'**
  String get volumeUp;

  /// No description provided for @volumeDown.
  ///
  /// In en, this message translates to:
  /// **'Volume down'**
  String get volumeDown;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @playPause.
  ///
  /// In en, this message translates to:
  /// **'Play/Pause'**
  String get playPause;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @rewind.
  ///
  /// In en, this message translates to:
  /// **'Rewind'**
  String get rewind;

  /// No description provided for @fastForward.
  ///
  /// In en, this message translates to:
  /// **'Fast forward'**
  String get fastForward;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'TV settings'**
  String get settings;

  /// No description provided for @input.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get input;

  /// No description provided for @apps.
  ///
  /// In en, this message translates to:
  /// **'Apps'**
  String get apps;

  /// No description provided for @keyboardHint.
  ///
  /// In en, this message translates to:
  /// **'Tip: use arrows, Enter, Esc and +/− on your keyboard'**
  String get keyboardHint;

  /// No description provided for @trayOpen.
  ///
  /// In en, this message translates to:
  /// **'Open remote'**
  String get trayOpen;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;
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
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
