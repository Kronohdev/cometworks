# Cometworks

**Cometworks** é um jogo de gestão de agência espacial com visual voxel. Você comanda uma pequena
agência de Cometinhos numa corrida contra agências rivais: projetar missões, montar foguetes,
lançar, explorar a Lua e chegar ao cometa **Mãe-Gelo** antes que ele passe pela Terra.

Projeto desenvolvido para o **NASA Space Apps Challenge 2026** (desafio *Space Mission Design Game*).

- Engine: **Godot 4.6** (GDScript), física **Jolt**
- Idiomas: **português e inglês**
- Plataforma: **Windows**

## O jogo

- **Campus da agência**: uma ilha voxel com prédios que evoluem por era, Cometinhos que andam,
  trabalham e conversam, ciclo de dia e noite e trilha sonora.
- **Projetos de missão**: escolha uma missão no quadro de briefings, defina alvo, tipo, carga
  útil e equipe. A revisão de projeto mostra os riscos e um checklist de maturidade do conceito
  (CML, inspirado na escala da NASA/JPL).
- **Hangar**: montagem de foguetes peça por peça, com centro de massa, empuxo e sustentação,
  estágios automáticos, Δv e TWR.
- **Lançamento e voo**: física de voo com órbitas reais (efemérides do Sistema Solar),
  transferências, captura lunar, pouso e retorno. Dá para acompanhar o voo, acelerar o tempo ou
  simular até o fim e ver o voo contado em quadrinhos pelo Vovô Edmundo Halleyzinho.
- **Rovers e superfícies**: monte rovers e explore a superfície da Lua e de outros corpos com
  objetivos científicos.
- **Corrida espacial**: agências rivais disputando os mesmos marcos, jornal mensal e, a cada
  três anos, a **Conferência dos Cometinhos**: uma feira para conversar com as Lendas e com os
  líderes rivais.
- **Lendas**: personagens inspirados em grandes nomes da ciência espacial, que narram as missões
  ligadas a eles e podem ser contratados como mentores.
- **Equipe com memória**: cada Cometinho lembra das missões em que trabalhou e ganha marcos.
- **Fotos das missões**: missões com câmera mandam fotos para o álbum da agência.
- **Pesquisa, finanças e falência**: árvore de pesquisa, contratos, orçamento e empréstimos.
- **Acessibilidade**: tamanho do texto, modo para daltônicos, troca de teclas e presets
  gráficos (Baixo / Médio / Alto).

## Como rodar

1. Instale o [Godot 4.6](https://godotengine.org/download).
2. Abra a pasta do projeto no Godot (`project.godot`) e aperte **F5**.

### Testes

Os testes rodam sem janela:

```
godot --headless --path . --script res://tests/<teste>.gd
```

## Documentos

| Arquivo | Conteúdo |
|---|---|
| [GDD_MARGIN_Space_Mission_Design_Game.md](GDD_MARGIN_Space_Mission_Design_Game.md) | Game design e análise do desafio |

## Créditos

Fontes Bricolage Grotesque, Fredoka e Nunito sob a SIL Open Font License (veja `ui/fonts/`).
