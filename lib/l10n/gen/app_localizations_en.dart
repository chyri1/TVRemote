// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TV Remote';

  @override
  String get byChyri => 'by Chyri';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusConnecting => 'Connecting…';

  @override
  String get statusOffline => 'Offline · retrying';

  @override
  String get statusNeedsPairing => 'Pairing required';

  @override
  String get statusNoTv => 'No TV added';

  @override
  String get addTv => 'Add TV';

  @override
  String get myTvs => 'My TVs';

  @override
  String get rename => 'Rename';

  @override
  String get remove => 'Forget device';

  @override
  String removeConfirm(String name) {
    return 'Forget $name?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get retry => 'Try again';

  @override
  String get pairAgain => 'Reconfigure PIN';

  @override
  String get pairTitle => 'Connect a TV';

  @override
  String get pairSubtitle => 'Your PC and TV must be on the same network.';

  @override
  String get searching => 'Searching the network…';

  @override
  String get noTvsFound =>
      'No TV found automatically. Enter the IP address below.';

  @override
  String get searchAgain => 'Search again';

  @override
  String get manualIp => 'TV IP address';

  @override
  String get manualIpHint => 'e.g. 192.168.0.42';

  @override
  String get tvName => 'Name (optional)';

  @override
  String get tvNameHint => 'Living room TV';

  @override
  String get connect => 'Connect';

  @override
  String get ipHelp =>
      'On the TV: Settings › Network & Internet › your network.';

  @override
  String get enterCodeTitle => 'Enter the code';

  @override
  String get enterCodeSubtitle => 'Type the 6-character code shown on your TV.';

  @override
  String get pair => 'Pair';

  @override
  String get wrongCode => 'Wrong code. Check the TV and try again.';

  @override
  String get invalidCode => 'The code has 6 characters (0–9, A–F).';

  @override
  String get pairingFailed => 'Pairing failed. Try again.';

  @override
  String get tvUnreachable =>
      'Couldn\'t reach the TV. Check the IP and that it\'s on.';

  @override
  String get pairingSuccess => 'Paired!';

  @override
  String get preparing => 'Preparing secure identity…';

  @override
  String get needsPairingBody => 'This TV doesn\'t recognize this PC yet.';

  @override
  String get noTvBody =>
      'Add your Android TV to start controlling it from here.';

  @override
  String get power => 'Power';

  @override
  String get home => 'Home';

  @override
  String get back => 'Back';

  @override
  String get menu => 'Menu';

  @override
  String get volumeUp => 'Volume up';

  @override
  String get volumeDown => 'Volume down';

  @override
  String get mute => 'Mute';

  @override
  String get playPause => 'Play/Pause';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get rewind => 'Rewind';

  @override
  String get fastForward => 'Fast forward';

  @override
  String get settings => 'TV settings';

  @override
  String get input => 'Input';

  @override
  String get apps => 'Apps';

  @override
  String get keyboardHint =>
      'Tip: use arrows, Enter, Esc and +/− on your keyboard';

  @override
  String get trayOpen => 'Open remote';

  @override
  String get trayQuit => 'Quit';
}
