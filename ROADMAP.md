# 📋 Roadmap & Lista de Implementações - TV Remote

Documento de acompanhamento para as próximas versões e melhorias do **TV Remote by Chyri**.

---

## 🚀 Versão 1.0.1 (Próxima)

### 🔊 Controle de Volume & Feedback Visual
- [ ] **Exibição dinâmica do nível de volume no botão MUDO**:
  - **Gatilho 1 (Ação)**: Ao clicar em Volume Up (`+`) ou Volume Down (`-`), substituir temporariamente o texto `"MUDO"` pelo valor numérico/porcentagem do nível de volume (ex.: `45%`, `70%`) durante alguns segundos (ex: 2 a 3 segundos), retornando suavemente para `"MUDO"`.
  - **Gatilho 2 (Hover)**: Ao passar o mouse (ou após um breve tempo de cursor sobre o botão/pilar de volume), exibir o nível percentual no lugar do texto `"MUDO"`.
  - **Prioridade de Estado**: Se o dispositivo estiver em Mudo (`isMuted == true`), avaliar transição suave ou manter o ícone de mudo evidente enquanto o nível é ajustado.
  - **Arquivos relacionados**:
    - `lib/ui/remote_view.dart` (`_buildVolumePillar`)
    - `lib/ui/widgets/volume_controls.dart` (se aplicável ao espelhamento/cards)

### 📺 Espelhamento & Conexão ADB
- [ ] **Troca de porta ADB sob demanda (ao clicar pela segunda vez no botão ADB)**:
  - **1º Clique em ADB**: Se o modo ADB não estiver ativo, alterna para ele e conecta/inicia a transmissão da tela da TV normalmente, mantendo a interface limpa (sem poluir com o seletor de porta de imediato).
  - **2º Clique em ADB (com ADB já ativo/aberto)**: Como o modo já está aberto, um novo clique no botão/aba de ADB exibe o controle/diálogo para trocar a porta ADB (ou abre diretamente o `showAdbPortDialog`).
  - **Arquivos relacionados**:
    - `lib/ui/widgets/screen_mirror_card.dart` (`_buildModeTab` de Depuração ADB)
    - `lib/ui/mirror_window.dart` (se aplicável na janela destacada)

---

## 📌 Ideias Futuras / Backlog
- *(Novas sugestões e funcionalidades serão adicionadas aqui)*
