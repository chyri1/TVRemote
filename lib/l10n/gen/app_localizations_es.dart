// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'TV Remote';

  @override
  String get byChyri => 'por Chyri';

  @override
  String get statusConnected => 'Conectado';

  @override
  String get statusConnecting => 'Conectando…';

  @override
  String get statusOffline => 'Sin conexión · reintentando';

  @override
  String get statusNeedsPairing => 'Se requiere vincular';

  @override
  String get statusNoTv => 'Ningún TV agregado';

  @override
  String get addTv => 'Agregar TV';

  @override
  String get myTvs => 'Mis TV';

  @override
  String get rename => 'Renombrar';

  @override
  String get remove => 'Olvidar dispositivo';

  @override
  String removeConfirm(String name) {
    return '¿Olvidar $name?';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get retry => 'Reintentar';

  @override
  String get pairAgain => 'Reconfigurar PIN';

  @override
  String get pairTitle => 'Conectar un TV';

  @override
  String get pairSubtitle => 'La PC y el TV deben estar en la misma red.';

  @override
  String get searching => 'Buscando en la red…';

  @override
  String get noTvsFound =>
      'No se encontró ningún TV. Escribe la dirección IP abajo.';

  @override
  String get searchAgain => 'Buscar de nuevo';

  @override
  String get manualIp => 'Dirección IP del TV';

  @override
  String get manualIpHint => 'ej.: 192.168.0.42';

  @override
  String get tvName => 'Nombre (opcional)';

  @override
  String get tvNameHint => 'TV de la sala';

  @override
  String get connect => 'Conectar';

  @override
  String get ipHelp => 'En el TV: Configuración › Red e Internet › tu red.';

  @override
  String get enterCodeTitle => 'Escribe el código';

  @override
  String get enterCodeSubtitle =>
      'Escribe el código de 6 caracteres que aparece en el TV.';

  @override
  String get pair => 'Vincular';

  @override
  String get wrongCode =>
      'Código incorrecto. Revisa el TV e inténtalo de nuevo.';

  @override
  String get invalidCode => 'El código tiene 6 caracteres (0–9, A–F).';

  @override
  String get pairingFailed => 'Error al vincular. Inténtalo de nuevo.';

  @override
  String get tvUnreachable =>
      'No se pudo acceder al TV. Revisa la IP y que esté encendido.';

  @override
  String get pairingSuccess => '¡Vinculado!';

  @override
  String get preparing => 'Preparando identidad segura…';

  @override
  String get needsPairingBody => 'Este TV aún no reconoce esta PC.';

  @override
  String get noTvBody => 'Agrega tu Android TV para controlarlo desde aquí.';

  @override
  String get power => 'Encender/Apagar';

  @override
  String get home => 'Inicio';

  @override
  String get back => 'Atrás';

  @override
  String get menu => 'Menú';

  @override
  String get volumeUp => 'Subir volumen';

  @override
  String get volumeDown => 'Bajar volumen';

  @override
  String get mute => 'Silenciar';

  @override
  String get playPause => 'Reproducir/Pausar';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Siguiente';

  @override
  String get rewind => 'Retroceder';

  @override
  String get fastForward => 'Adelantar';

  @override
  String get settings => 'Configuración del TV';

  @override
  String get input => 'Entrada';

  @override
  String get apps => 'Apps';

  @override
  String get keyboardHint =>
      'Consejo: usa las flechas, Enter, Esc y +/− del teclado';

  @override
  String get trayOpen => 'Abrir control';

  @override
  String get trayQuit => 'Salir';
}
