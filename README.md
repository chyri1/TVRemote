# TV Remote by Chyri 📺

Aplicativo Windows que fica na bandeja do sistema (system tray) e abre um painel de controle estilo Windows 11/Acrylic para sua Android TV.

Desenvolvido em **Flutter**, com o núcleo totalmente desacoplado para facilitar o futuro port para **Android**.

---

## ✨ Recursos

- 🔹 **Bandeja do Sistema (Tray)**: Ícone discreto perto do relógio e bateria. Clique com o botão esquerdo para abrir o controle; botão direito para menu de contexto (abrir, sair).
- 🔹 **Flyout com efeito Acrylic**: Abre acima da barra de tarefas, com cantos arredondados, adaptado ao tema Claro/Escuro e à cor de destaque do seu Windows.
- 🔹 **Fecha ao perder o foco**: Comportamento idêntico aos menus de Wi-Fi/Bateria do Windows.
- 🔹 **Protocolo Android TV Remote v2**: Conexão segura via TLS e pareamento por código de 6 caracteres na porta 6467/6466 (o mesmo usado pelo app Google TV, sem precisar de root ou modo desenvolvedor na TV).
- 🔹 **Descoberta Automática na Rede (mDNS)** + Inserção Manual de IP.
- 🔹 **Suporte a Múltiplas TVs**: Alterne rapidamente entre TVs da casa pelo menu superior.
- 🔹 **Controles Completos**:
  - D-Pad direcional (Cima, Baixo, Esquerda, Direita) + OK centralizado.
  - Voltar, Início (Home) e Menu.
  - Volume (+ / - com repetição rápida ao segurar) e Mudo com indicador de porcentagem.
  - Ligar / Desligar (Power).
  - Mídia: Play/Pause, Avançar e Retroceder.
  - Digitar do teclado do PC direto na TV.
  - Atalhos para aplicativos: YouTube, Netflix, Prime Video, Disney+.
- 🔹 **Navegação pelo Teclado Físico**: Quando a janela está aberta:
  - Setas: Direcionais da TV
  - `Enter`: OK
  - `Esc` / `Backspace`: Voltar
  - `Home`: Início
  - `+` / `-`: Volume
- 🌐 **Internacionalização (i18n)**:
  - Detecta o idioma do sistema.
  - Suporte nativo para **Português**, **Espanhol** e **Inglês** (fallback).
  - Arquivos abertos em `lib/l10n/` (`.arb`) para a comunidade adicionar novos idiomas.

---

## 🚀 Como executar no Windows

### Pré-requisito: Ativar Modo de Desenvolvedor no Windows
O Windows requer a permissão de links simbólicos para compilar plugins nativos em C++:
1. Pressione `Win + I` ou abra as Configurações do Windows.
2. Vá em **Atualização e Segurança** › **Para desenvolvedores** (ou digite `Modo de desenvolvedor` no menu Iniciar).
3. Ative a chave **Modo de desenvolvedor**.

### Executando em desenvolvimento:
```bash
flutter run -d windows
```

### Gerando o executável final:
```bash
flutter build windows --release
```
O executável compilado ficará em `build\windows\x64\runner\Release\tv_remote.exe`.

---

## 🌍 Como contribuir com novas traduções

Os textos estão definidos no formato padrão Flutter ARB (JSON):
- `lib/l10n/app_pt.arb` (Português)
- `lib/l10n/app_es.arb` (Espanhol)
- `lib/l10n/app_en.arb` (Inglês)

Para adicionar uma nova língua (ex.: Francês `app_fr.arb` ou Alemão `app_de.arb`):
1. Duplique `app_en.arb` e renomeie para `app_<código>.arb`.
2. Traduza as frases mantendo as chaves.
3. Execute `flutter gen-l10n`.
