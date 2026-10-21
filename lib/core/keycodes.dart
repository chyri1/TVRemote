/// Android KeyEvent codes used by the remote.
abstract final class KeyCode {
  static const home = 3;
  static const back = 4;
  static const dpadUp = 19;
  static const dpadDown = 20;
  static const dpadLeft = 21;
  static const dpadRight = 22;
  static const dpadCenter = 23;
  static const volumeUp = 24;
  static const volumeDown = 25;
  static const power = 26;
  static const enter = 66;
  static const del = 67;
  static const menu = 82;
  static const search = 84;
  static const mediaPlayPause = 85;
  static const mediaStop = 86;
  static const mediaNext = 87;
  static const mediaPrevious = 88;
  static const mediaRewind = 89;
  static const mediaFastForward = 90;
  static const channelUp = 166;
  static const channelDown = 167;
  static const volumeMute = 164;
  static const info = 165;
  static const guide = 172;
  static const settings = 176;
  static const tvInput = 178;
  static const assist = 219;
  static const voiceAssist = 231;
}

/// Key press direction as defined by the Remote v2 protocol.
enum KeyDirection {
  startLong(1),
  endLong(2),
  short(3);

  final int value;
  const KeyDirection(this.value);
}

/// Built-in app shortcuts (deep links handled by the TV).
class AppShortcut {
  final String id;
  final String label;
  final String link;
  final int color;
  const AppShortcut(this.id, this.label, this.link, this.color);

  static const defaults = <AppShortcut>[
    AppShortcut('youtube', 'YouTube', 'https://www.youtube.com', 0xFFFF0033),
    AppShortcut('netflix', 'Netflix', 'https://www.netflix.com/title', 0xFFE50914),
    AppShortcut('prime', 'Prime Video', 'https://app.primevideo.com', 0xFF1A98FF),
    AppShortcut('disney', 'Disney+', 'https://www.disneyplus.com', 0xFF113CCF),
  ];
}
