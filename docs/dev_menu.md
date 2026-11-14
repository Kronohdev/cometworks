# Menu de dev

Uma janelinha flutuante para testar o jogo rápido, em qualquer cena (menu principal, criador de
líder, campus, hangar, voo, durante cenas e lançamentos). Não pausa o jogo (a não ser que você
aperte **Pausar**) e só aparece em builds de debug e no editor. Para forçar numa exportação,
ligue a configuração de projeto `cometworks/dev/enabled`.

## Teclas

| Tecla | O que faz |
| --- | --- |
| **F1** | abre e fecha o menu (onde a cena não usa F1) |
| **F12** | abre e fecha o menu (em qualquer cena) |
| **'** (a tecla abaixo do Esc no teclado ABNT2; \` no americano) | abre e fecha o menu |

- No **hangar** e no **voo** o F1 continua sendo a ajuda da cena: lá use F12 ou '. O
  cabeçalho do menu mostra as teclas que valem na cena.
- As teclas não fazem nada enquanto um campo de texto está com o teclado.
- Arraste o cabeçalho para mover a janela; clique duplo nele (ou **–**) recolhe e expande;
  **×** fecha. Lugar, aba e recolhido ficam salvos em `user://dev.cfg`. O menu sempre começa
  fechado.

## Abas

As abas e seções aparecem só onde fazem sentido (Campanha, Projetos e Telas só no campus).

**Geral**
- Desempenho: FPS, tempo por quadro, draw calls, objetos, nós, memória.
- Ir para: menu principal, nova campanha (com criador de líder), campanha direta (sem criador
  nem abertura), modo feira, hangar, voo de teste, recarregar a cena.
- Velocidade do motor: `Engine.time_scale` de 0,25× a 8×.
- Visual: estilo cartoon, contornos, reduzir movimento.
- Áudio: mudo e volumes (geral, música, efeitos).
- Captura: screenshot em `user://screenshots/`, abrir a pasta `user://`.

**Campanha** (campus)
- Dinheiro +100 mil / +1 mi / −100 mil, reputação ±5, hype ±5.
- Calendário: +1 semana, +1 mês, +1 ano; pausa e velocidades 1 a 3.
- Turbo do relógio: ×1 a ×16 além da velocidade 3.
- Era 1 a 5 (o ano acompanha), cometa em 2 semanas, cometa agora (final, cena e placar).
- Construir tudo (todos os lotes no nível máximo, já prontos), toda a pesquisa.
- Equipe: contratar um Cometinho aleatório, moral máxima, todos sobem de nível, novos candidatos.
- Aceitar um contrato aleatório, tomar o próximo marco da corrida.
- Dia e noite: fase do dia (controle deslizante e atalhos), ou seguir o relógio.
- Salvar nos espaços 1 a 3, carregar 1 a 3 ou o automático.

**Projetos** (campus)
- Concluir a fase do projeto em andamento, concluir o desenvolvimento, abrir o Design Review.
- Próximo lançamento: sorteio, sucesso, parcial ou falha (vale para um lançamento).
- Lançar teste agora: um foguete de sondagem suborbital com quem estiver livre, já no ar.
- Missões e descobertas: revelar todas as descobertas do caderno (proporções, instrumentos,
  ambientes, combinações), abrir o quadro de missões ou o caderno, e gerar qualquer pedido
  (`data/tycoon/briefings.json`, qualquer era, mesmo já cumprido) direto no topo do quadro.
- Rever a cinemática: escolha o destino e o resultado (sucesso, parcial, falha).
- Todas as peças de foguete liberadas.

**Cenas**
- Tocar a abertura, a abertura curta, o final com o cometa e o final perdido.
- Pular a cena, esquecer as vistas (a campanha volta a mostrar as cenas), ligar e desligar as
  cenas e a cinemática de lançamento.

**Telas** (campus)
- Abrir qualquer tela da HUD pelo nome (todas de `scenes/tycoon/ui/screens/`).
- Jornal, final, placar final, fechar a tela.

**Cometinhos** (onde houver Cometinhos)
- Quem: o Cometinho seguido pela câmera (clique num deles) ou todos.
- Ações, emotes, expressões e reações.
- Multidão (campus): criar N Cometinhos extras andando, remover os extras, mostrar a grade de
  caminhada (vermelho bloqueado, laranja perto de algo, azul estrada).

**Log**
- Colisões visíveis (vale para o que for criado depois: recarregue a cena) e modos de desenho
  (normal, sem luz, luz, overdraw, wireframe).
- Os últimos avisos e erros do motor (limpar, copiar). A aba mostra quantos há.

## Para quem mexe no código

- Cena: `scenes/dev/dev_menu.tscn` (autoload `CwDev`), tema denso: `scenes/dev/dev_theme.tres`,
  script: `src/dev/cw_dev.gd` (classe `CwDevMenu`).
- Um botão diz o que faz pelos metadados `action` (e `arg`): apertar chama `_a_<action>(arg)`
  no script; `_s_<action>(arg)` diz a um botão de liga/desliga ou controle deslizante o que
  mostrar. Para um botão novo: crie no editor (copie um vizinho), troque o texto e os
  metadados, e escreva o `_a_` no script.
- Listas vindas de dados (telas, cenas, ações...) usam o `ButtonTemplate` escondido e o
  metadado `fill` do HFlowContainer. Páginas e seções com o metadado `contexts` só aparecem
  nesses contextos (`tycoon`, `menu`, `leader`, `hangar`, `flight`, `cometlings`).
- Ganchos de dev no jogo (todos chamados `dev_*`): `ProjectDesk.dev_force_outcome`,
  `ProjectDesk.dev_finish_phase()` / `dev_finish_development()`, `ProjectFlow.dev_drop_phases()`,
  `TycoonClock.dev_turbo`, `TycoonCrew.dev_ignore_limit` / `dev_refresh_market()`,
  `Campus.dev_spawn_walkers()` / `dev_clear_walkers()` / `dev_show_nav()`, `CampusNav.debug_image()`.
- Teste: `tests/test_dev_menu.gd`; screenshots: `tests/screenshot_dev_menu.gd`.
