// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'TV Remote';

  @override
  String get byChyri => 'por Chyri';

  @override
  String get statusConnected => 'Conectado';

  @override
  String get statusConnecting => 'Conectando…';

  @override
  String get statusOffline => 'Offline · tentando de novo';

  @override
  String get statusNeedsPairing => 'Pareamento necessário';

  @override
  String get statusNoTv => 'Nenhuma TV adicionada';

  @override
  String get addTv => 'Adicionar TV';

  @override
  String get myTvs => 'Minhas TVs';

  @override
  String get rename => 'Renomear';

  @override
  String get remove => 'Esquecer dispositivo';

  @override
  String removeConfirm(String name) {
    return 'Esquecer $name?';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Salvar';

  @override
  String get retry => 'Tentar de novo';

  @override
  String get pairAgain => 'Reconfigurar PIN';

  @override
  String get pairTitle => 'Conectar uma TV';

  @override
  String get pairSubtitle => 'O PC e a TV precisam estar na mesma rede.';

  @override
  String get searching => 'Procurando na rede…';

  @override
  String get noTvsFound =>
      'Nenhuma TV encontrada automaticamente. Digite o IP abaixo.';

  @override
  String get searchAgain => 'Procurar de novo';

  @override
  String get manualIp => 'Endereço IP da TV';

  @override
  String get manualIpHint => 'ex.: 192.168.0.42';

  @override
  String get tvName => 'Nome (opcional)';

  @override
  String get tvNameHint => 'TV da sala';

  @override
  String get connect => 'Conectar';

  @override
  String get ipHelp => 'Na TV: Configurações › Rede e Internet › sua rede.';

  @override
  String get enterCodeTitle => 'Digite o código';

  @override
  String get enterCodeSubtitle =>
      'Digite o código de 6 caracteres que aparece na TV.';

  @override
  String get pair => 'Parear';

  @override
  String get wrongCode => 'Código incorreto. Confira na TV e tente de novo.';

  @override
  String get invalidCode => 'O código tem 6 caracteres (0–9, A–F).';

  @override
  String get pairingFailed => 'Falha no pareamento. Tente de novo.';

  @override
  String get tvUnreachable =>
      'Não foi possível acessar a TV. Confira o IP e se ela está ligada.';

  @override
  String get pairingSuccess => 'Pareado!';

  @override
  String get preparing => 'Preparando identidade segura…';

  @override
  String get needsPairingBody => 'Esta TV ainda não reconhece este PC.';

  @override
  String get noTvBody => 'Adicione sua Android TV para controlá-la daqui.';

  @override
  String get power => 'Ligar/Desligar';

  @override
  String get home => 'Início';

  @override
  String get back => 'Voltar';

  @override
  String get menu => 'Menu';

  @override
  String get volumeUp => 'Aumentar volume';

  @override
  String get volumeDown => 'Diminuir volume';

  @override
  String get mute => 'Mudo';

  @override
  String get playPause => 'Reproduzir/Pausar';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Próximo';

  @override
  String get rewind => 'Retroceder';

  @override
  String get fastForward => 'Avançar';

  @override
  String get settings => 'Configurações da TV';

  @override
  String get input => 'Entrada';

  @override
  String get apps => 'Apps';

  @override
  String get keyboardHint => 'Dica: use as setas, Enter, Esc e +/− do teclado';

  @override
  String get trayOpen => 'Abrir controle';

  @override
  String get trayQuit => 'Sair';
}
