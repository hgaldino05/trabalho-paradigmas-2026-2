# Telmo

O nome junta **Termo**, o jogo que inspirou a mecânica, e **Elm**, a
linguagem da interface.

Jogo de adivinhar uma palavra de 5 letras em 10 tentativas, feito para o
trabalho final de Paradigmas de Programação. A diferença para o Termo: o
jogo nunca diz quais letras acertaram, só **quantas**. Ao lado de cada
tentativa aparecem três números: quantas letras estão na palavra na
posição certa (verde), quantas estão em outra posição (amarelo) e quantas
não estão na palavra (vermelho). Por exemplo, PASTA com o segredo CASPA
mostra 3 · 1 · 1. Cabe ao jogador deduzir quais são.

Para ajudar no raciocínio, o jogador pode clicar nas letras das tentativas
já feitas e anotar uma cor em cada uma (verde, amarelo, vermelho, sem cor).
As anotações são só dele: o jogo não as confere.

O Prolog guarda as palavras e as partidas e calcula a contagem; o Elm
desenha a interface e guarda as anotações; o Python só faz a ponte entre
os dois.

Partimos do [projeto-modelo do Sudoku](https://github.com/fabiommendes/paradigmas-trabalho-final),
mantendo a infraestrutura (FastAPI + janus, Vite, Arquitetura Elm) e
trocando todas as regras.

```
┌──────────────────────┐   HTTP/JSON   ┌───────────────────┐  janus  ┌──────────────────┐
│ Navegador            │ ────────────▶ │ FastAPI (Python)  │ ──────▶ │ SWI-Prolog       │
│ Elm + daisyUI (Vite) │ ◀──────────── │ backend/app/      │ ◀────── │ backend/prolog/  │
└──────────────────────┘               └───────────────────┘         └──────────────────┘
```

## O que cada parte faz

**Prolog** (`backend/prolog/`)

- `palavras.pl`: as 1000 palavras que podem ser sorteadas (`resposta/2`),
  comuns do português brasileiro, escritas do zero para o projeto.
- `aceitas.pl`: as outras 4377 palavras de 5 letras do dicionário
  (`aceita/2`), que nunca são sorteadas. Inclui plurais e verbos
  conjugados: quem os recusa é o `flexao.pl`. Sobram 954 que valem como
  tentativa. É **gerado** a partir de um dicionário aberto (veja
  [A base de palavras](#a-base-de-palavras)).
- `lexico.pl`: 2941 palavras de outros tamanhos (`vocabulo/1`), também
  geradas do dicionário, que o `flexao.pl` consulta: singulares como
  *casa* e infinitivos como *pensar*.
- `flexao.pl`: decide se uma palavra é **plural** ou **verbo conjugado**,
  que não valem (verbo só no infinitivo; a tela avisa isso ao lado do
  tabuleiro). É uma gramática (DCG): a palavra é um radical seguido de uma
  terminação, e a análise só vale se o singular ou o infinitivo existir no
  dicionário. `flexao/3` devolve todas as análises, por backtracking
  (`casas`: plural de *casa* e “tu casas”, de *casar*).
- `jogo.pl`:
  - `retorno/3` calcula a cor de cada letra de uma tentativa, tratando
    letras repetidas (`terra` contra `termo`: só o primeiro r conta como
    certo);
  - `contagem/2` resume essas cores em três números, `[Certas, Presentes,
    Ausentes]`. Só a contagem sai do Prolog: as cores letra por letra
    ficam no servidor;
  - `partida/3` é um fato dinâmico por partida em andamento: o código
    aleatório da partida, a palavra secreta e a situação (`jogando(Tentadas)`,
    com as palavras já tentadas, ou `perdeu`);
  - `novo_jogo/1`, `jogar/3` e `revelar/2` são a interface usada pelo
    Python. `revelar/2` só entrega a palavra depois da derrota.
- `test_jogo.pl`: testes plunit.

**Python** (`backend/app/`). `prolog.py` carrega o `jogo.pl` com o janus;
`main.py` expõe as rotas HTTP. Não há regra do jogo aqui. As partidas ficam
guardadas no Prolog; o navegador só recebe um código aleatório (UUID), e a
palavra secreta não sai do servidor antes do fim da partida. Por isso não
dá para descobrir a palavra pelo navegador, e mudar a ordem de
`palavras.pl` não muda a palavra de nenhuma partida.

**Elm** (`frontend/src/`)

- `Jogo.elm`: domínio puro. O tipo `Estado` (`Digitando`, `Conferindo`,
  `Venceu`, `Perdeu`) impede estados inválidos, e as transições ficam aqui,
  junto com as anotações do jogador (`Marca`: `Verde`, `Amarela`,
  `Vermelha`).
- `Api.elm`: requisições e decoders JSON.
- `Main.elm`: Model, Msg, update, teclado físico, teclado virtual e tela.
  O teclado virtual não tem cores, porque uma tecla colorida diria se a
  letra está na palavra.

## Estado atual e próximos passos

Pronto e testado:

- [x] retorno com letras repetidas, contagem e partidas guardadas no
      Prolog (Prolog + testes)
- [x] rotas `novo`, `tentativa` e `revelar` (Python + testes)
- [x] jogo jogável no navegador com o teclado físico ou com o teclado
      virtual, que também serve no celular (Elm)
- [x] anotações do jogador nas letras das tentativas (Elm)
- [x] painel de regras ao lado do tabuleiro

## Requisitos

- [SWI-Prolog](https://www.swi-prolog.org/Download.html) 9.2 ou mais novo,
  com `swipl` no PATH;
- [uv](https://docs.astral.sh/uv/) para o Python;
- [Node.js](https://nodejs.org) 20 ou mais novo, com `npm`.

## Como rodar

Com `make` (Linux/macOS):

```sh
make install    # uma vez só
make dev        # sobe backend e frontend
```

Sem `make` (por exemplo, no Windows), em dois terminais:

```sh
# terminal 1
cd backend
uv sync
uv run fastapi dev app/main.py

# terminal 2
cd frontend
npm install
npm run dev
```

Abra http://localhost:5173. A documentação da API fica em
http://localhost:8000/docs.

### No Windows

Dois cuidados, testados no Windows 11 com SWI-Prolog 9.2.9:

1. **O `uv sync` compila o `janus-swi`** e precisa do compilador C++ do
   Visual Studio (Build Tools, carga "Desenvolvimento para desktop com
   C++"). Se ele disser `Unable to find a compatible Visual Studio
   installation` mesmo com o Build Tools instalado, rode o `uv sync` num
   *Developer Command Prompt* (ou depois de chamar o `vcvars64.bat`) com
   `set DISTUTILS_USE_SDK=1`.
2. **O Prolog embutido precisa saber onde o SWI-Prolog está instalado.**
   Sem isso, o backend morre com `Could not find system resources`. Antes
   de subir o backend ou rodar os testes, no PowerShell:

   ```powershell
   $env:SWI_HOME_DIR = "C:\Program Files\swipl"
   ```

## Testes

```sh
swipl -g run_tests -t halt backend/prolog/test_jogo.pl    # Prolog (plunit)
cd backend && uv run pytest                                # API (pytest)
cd frontend && npm test                                    # Elm (elm-test)
```

Ou `make test`, que roda os três.

Os testes do Elm (`frontend/tests/JogoTest.elm`) jogam partidas inteiras
sem navegador e sem servidor: como `Jogo.elm` é puro, o teste faz o papel
do jogador (digitar, apagar, conferir) e do servidor (responder com uma
contagem). Eles cobrem vitória, derrota em 10 tentativas, digitação,
palavra recusada, resposta fora de hora e as anotações.

## Brincando com o Prolog no terminal

```
$ swipl backend/prolog/jogo.pl
?- retorno([t,e,r,r,a], [t,e,r,m,o], Cores).
?- retorno([p,a,s,t,a], [c,a,s,p,a], Cores), contagem(Cores, N).   % N = [3,1,1]
?- novo_jogo(Id), jogar(Id, "terra", R).
?- novo_jogo(Id), revelar(Id, R).      % R = negado: a partida não acabou
?- flexao:flexao([c,a,s,a,s], Base, Tipo).   % plural de casa; verbo casar
```

## API

Todas as rotas usam `POST` e JSON. A resposta de uma tentativa traz só a
contagem: quantas letras estão na posição certa (`certas`), em outra
posição (`presentes`) e fora da palavra (`ausentes`). As três somam 5.

| Rota | Corpo enviado | Resposta |
|------|---------------|----------|
| `/api/novo` | (nada) | `{"jogo": "5cf75573-5ce9-4bf1-ad6f-286ae4eeeec8"}` |
| `/api/tentativa` | `{"jogo": "5cf75573-…", "palavra": "radio"}` | `{"palavra": "rádio", "contagem": {"certas": 1, "presentes": 2, "ausentes": 2}}` |
| `/api/revelar` | `{"jogo": "5cf75573-…"}` | `{"palavra": "termo"}` |

Erros, sempre com `{"detail": "mensagem"}` no corpo, que o Elm mostra na
tela:

| Código | Quando |
|:------:|--------|
| 422 | a palavra não está na lista, ou já foi tentada nesta partida (não gasta tentativa) |
| 409 | tentativa numa partida que já foi perdida |
| 403 | pedir a palavra antes de a partida acabar |
| 404 | partida inexistente: já ganha, já revelada, ou o servidor reiniciou |

O jogo não tem dica: não há rota para isso, de propósito.

## A base de palavras

São dois conjuntos, com papéis diferentes:

| Arquivo | O que tem | Pode ser sorteada? | Origem |
|---------|-----------|:------------------:|--------|
| `palavras.pl` | 1000 palavras comuns | sim | escritas para o projeto |
| `aceitas.pl` | 4377 palavras de 5 letras; 954 valem (as outras são plural ou verbo conjugado) | não | dicionário do IME-USP |
| `lexico.pl` | 2941 palavras de outros tamanhos, consultadas pela análise | não | dicionário do IME-USP |

As tentativas aceitas vêm da
[Lista de todas as palavras do português brasileiro](https://www.ime.usp.br/~pf/dicios/),
de Paulo Feofiloff (IME-USP), preparada a partir do Dicionário br.ispell de
Ricardo Ueda Karpischek, sob licença
[Creative Commons BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.pt-br).
A licença permite usar e adaptar a lista desde que a fonte seja citada:
**mantenham esta citação aqui e na seção 11 do relatório**.

`aceitas.pl` e `lexico.pl` são gerados pelo script
`backend/tools/gerar_aceitas.py`, que só **extrai** dados do dicionário:

- `aceitas.pl`: as palavras de 5 letras só com letras minúsculas (as com
  maiúscula são nomes próprios), menos as que já são respostas; quando
  duas grafias viram as mesmas letras sem acento (`abafa` e `abafá`), fica
  uma só, de preferência a sem acento;
- `lexico.pl`: as palavras de 3 e 4 letras e as de 6 letras terminadas em
  `-os`, `-ar`, `-er` ou `-ir`, que a análise precisa consultar.

Quem decide que uma palavra é plural ou verbo conjugado é o Prolog
(`backend/prolog/flexao.pl`), na hora da tentativa. O dicionário não diz a
classe de cada palavra, então a análise é por regras de formação: plural é
a palavra que se divide num singular do dicionário mais uma terminação de
plural (`casas`, `trens`, `azuis`); verbo conjugado é a que se divide no
radical de um infinitivo do dicionário mais uma terminação verbal
(`falei`, `comeu`), desfazendo as mudanças de grafia (`fiquei`, `fujo`),
mais uma lista de irregulares comuns. Isso inclui a 3ª pessoa dos verbos em
`-ar` (`pensa`, `chora`). É aproximado: escapam algumas formas irregulares
(`sinta`), e saem alguns substantivos que coincidem com verbos (`baixa`,
`ginga`). Os comuns (`conta`, `falta`, `busca`) não se perdem, porque
estão em `palavras.pl`, que não passa pela análise. Para corrigir um caso,
ponham a palavra em `palavras.pl` ou ajustem as regras de `flexao.pl`.

Para gerar de novo (por exemplo, depois de mudar `palavras.pl`), baixe o
`br-utf8.txt` da página acima e rode, na raiz do repositório:

```sh
python backend/tools/gerar_aceitas.py caminho/para/br-utf8.txt
```

O dicionário (3 MB) não vai para o repositório; só os arquivos gerados.

## Origem do código (para a seção 11 do relatório)

- Infraestrutura copiada do projeto-modelo: `Makefile`, `vite.config.js`,
  `package.json`, `index.html`, `main.js`, a função `expectJson` de
  `Api.elm`, o botão de tema de `Main.elm`, `scripts/` e os templates
  `RELATORIO.md`, `AVALIACAO.md` e `avaliacao-360/`.
- Esqueleto inicial gerado com o Claude (assistente de IA), a pedido do
  grupo: `jogo.pl`, `palavras.pl` (as 1000 palavras), `test_jogo.pl`,
  `prolog.py`, `main.py`, `test_api.py`, `gerar_aceitas.py`, `Jogo.elm`,
  `Api.elm`, `Main.elm`, `style.css`, `JogoTest.elm` e `flexao.pl`. Declarem isso na tabela de uso de IA e revisem cada linha:
  na apresentação, qualquer integrante pode ter que explicar qualquer
  trecho (AVALIACAO.md, seção 2.1).
- Dados de terceiros: `aceitas.pl` e `lexico.pl` vêm do dicionário do IME-USP (CC BY 4.0),
  como descrito em [A base de palavras](#a-base-de-palavras).

## Equipe

| Integrante | Parte do código | Na apresentação |
|------------|-----------------|-----------------|
| Daniel dos Santos Barros de Sousa | Palavras e integração: `flexao.pl`, `gerar_aceitas.py` (e os arquivos que ele gera), `prolog.py`, `main.py`, `test_api.py` | Contexto e objetivo; código Prolog: a gramática de plural e verbo |
| João Paulo Monteiro de Barros Ceva Rodrigues | Núcleo do jogo em Prolog: `jogo.pl` (cores, contagem, partidas) e `test_jogo.pl` | Demonstração; código Prolog: cores, contagem e partidas; limitações e aprendizados |
| Henrique Galdino Couto | Interface em Elm: `Jogo.elm`, `Api.elm`, `Main.elm`, `style.css`, `JogoTest.elm` | Demonstração; código Elm |

Os três participaram da documentação (este README, o relatório e os
slides). Detalhes nas seções 10 e 12 do `RELATORIO.md`.

## Entrega

Veja `AVALIACAO.md` (critérios e prazos) e `RELATORIO.md` (template do
relatório). Antes de entregar:

```sh
uv run scripts/validar_entrega.py
```

## Estrutura

```
backend/
  prolog/jogo.pl          regras: retorno, contagem, partidas, interface com o Python
  prolog/palavras.pl      as 1000 palavras que podem ser sorteadas
  prolog/aceitas.pl       outras palavras de 5 letras do dicionário (gerado)
  prolog/lexico.pl        palavras de outros tamanhos, para a análise (gerado)
  prolog/flexao.pl        análise de plural e verbo conjugado (DCG)
  prolog/test_jogo.pl     testes plunit
  tools/gerar_aceitas.py  gera aceitas.pl e lexico.pl a partir do dicionário
  app/prolog.py           ponte Python → Prolog (janus)
  app/main.py             rotas HTTP (FastAPI)
  tests/test_api.py       testes da API
frontend/
  src/Jogo.elm            domínio: tipos, transições de estado e anotações
  src/Api.elm             HTTP e JSON
  src/Main.elm            Arquitetura Elm: estado, teclado, tela
  src/main.js             inicia o Elm e lembra o tema escolhido
  src/style.css           visual (Tailwind + daisyUI)
  tests/JogoTest.elm      testes elm-test: partidas simuladas no domínio
scripts/                  validador da entrega e ferramentas do professor
```
