# Telmo

O nome junta **Termo**, o jogo que inspirou a mecânica, e **Elm**, a
linguagem da interface.

Jogo de adivinhar uma palavra de 5 letras em 6 tentativas, feito para o
trabalho final de Paradigmas de Programação. A cada tentativa, cada letra
fica verde (lugar certo), amarela (está na palavra, em outro lugar) ou
cinza (não está). O Prolog guarda as palavras, calcula as cores e descobre
quais palavras ainda são possíveis; o Elm desenha a interface; o Python só
faz a ponte entre os dois.

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
- `aceitas.pl`: outras 954 palavras que valem como tentativa, mas nunca
  são sorteadas (`aceita/2`): palavras menos comuns. Plural e verbo
  conjugado não valem (verbo só no infinitivo), e a tela avisa isso ao
  lado do tabuleiro. É **gerado** a partir de um dicionário aberto (veja
  [A base de palavras](#a-base-de-palavras)).
- `jogo.pl`:
  - `retorno/3` calcula as cores de uma tentativa, tratando letras
    repetidas (`terra` contra `termo`: só o primeiro r fica verde);
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
  `Venceu`, `Perdeu`) impede estados inválidos, e as transições ficam aqui.
- `Api.elm`: requisições e decoders JSON.
- `Main.elm`: Model, Msg, update, teclado físico, teclado virtual e tela.

## Estado atual e próximos passos

Pronto e testado:

- [x] retorno com letras repetidas e partidas guardadas no Prolog (Prolog + testes)
- [x] rotas `novo`, `tentativa` e `revelar` (Python + testes)
- [x] jogo jogável no navegador com o teclado físico ou com o teclado
      virtual colorido, que também serve no celular (Elm)
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
```

Ou `make test`, que roda os dois.

## Brincando com o Prolog no terminal

```
$ swipl backend/prolog/jogo.pl
?- retorno([t,e,r,r,a], [t,e,r,m,o], Cores).
?- novo_jogo(Id), jogar(Id, "terra", R).
?- novo_jogo(Id), revelar(Id, R).      % R = negado: a partida não acabou
```

## API

Todas as rotas usam `POST` e JSON. As cores são `"certa"`, `"presente"` e
`"ausente"`.

| Rota | Corpo enviado | Resposta |
|------|---------------|----------|
| `/api/novo` | (nada) | `{"jogo": "5cf75573-5ce9-4bf1-ad6f-286ae4eeeec8"}` |
| `/api/tentativa` | `{"jogo": "5cf75573-…", "palavra": "radio"}` | `{"palavra": "rádio", "cores": [...]}` |
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
| `aceitas.pl` | 954 palavras menos comuns (sem plural nem verbo conjugado) | não | dicionário do IME-USP |

As tentativas aceitas vêm da
[Lista de todas as palavras do português brasileiro](https://www.ime.usp.br/~pf/dicios/),
de Paulo Feofiloff (IME-USP), preparada a partir do Dicionário br.ispell de
Ricardo Ueda Karpischek, sob licença
[Creative Commons BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.pt-br).
A licença permite usar e adaptar a lista desde que a fonte seja citada:
**mantenham esta citação aqui e na seção 11 do relatório**.

`aceitas.pl` é gerado pelo script `backend/tools/gerar_aceitas.py`, que:

- fica com as palavras de 5 letras só com letras minúsculas (as com
  maiúscula são nomes próprios);
- tira as que já são respostas;
- quando duas grafias viram as mesmas letras sem acento (`abafa` e
  `abafá`), fica com uma só, de preferência a sem acento;
- tira plurais e verbos conjugados. O dicionário não diz a classe de cada
  palavra, então o filtro é por regras: plural é a palavra em `-s` cujo
  singular está no dicionário (`casas`, `trens`, `azuis`); verbo conjugado
  é a palavra que sai de algum infinitivo do dicionário pelas terminações
  regulares (`falei`, `comeu`), mais uma lista de irregulares comuns.
  Isso inclui a 3ª pessoa dos verbos em `-ar` (`pensa`, `chora`). É
  aproximado: escapam algumas formas irregulares (`sinta`), e saem alguns
  substantivos que coincidem com verbos (`baixa`, `ginga`). Os comuns
  (`conta`, `falta`, `busca`) não se perdem, porque estão em `palavras.pl`,
  que o filtro não toca. Para corrigir um caso, ponham a palavra em
  `palavras.pl` ou ajustem o script.

Para gerar de novo (por exemplo, depois de mudar `palavras.pl`), baixe o
`br-utf8.txt` da página acima e rode, na raiz do repositório:

```sh
python backend/tools/gerar_aceitas.py caminho/para/br-utf8.txt
```

O dicionário (3 MB) não vai para o repositório; só o `aceitas.pl` gerado.

## Origem do código (para a seção 11 do relatório)

- Infraestrutura copiada do projeto-modelo: `Makefile`, `vite.config.js`,
  `package.json`, `index.html`, `main.js`, a função `expectJson` de
  `Api.elm`, o botão de tema de `Main.elm`, `scripts/` e os templates
  `RELATORIO.md`, `AVALIACAO.md` e `avaliacao-360/`.
- Esqueleto inicial gerado com o Claude (assistente de IA), a pedido do
  grupo: `jogo.pl`, `palavras.pl` (as 1000 palavras), `test_jogo.pl`,
  `prolog.py`, `main.py`, `test_api.py`, `gerar_aceitas.py`, `Jogo.elm`,
  `Api.elm`, `Main.elm` e `style.css`. Declarem isso na tabela de uso de IA e revisem cada linha:
  na apresentação, qualquer integrante pode ter que explicar qualquer
  trecho (AVALIACAO.md, seção 2.1).
- Dados de terceiros: `aceitas.pl` vem do dicionário do IME-USP (CC BY 4.0),
  como descrito em [A base de palavras](#a-base-de-palavras).

## Entrega

Veja `AVALIACAO.md` (critérios e prazos) e `RELATORIO.md` (template do
relatório). Antes de entregar:

```sh
uv run scripts/validar_entrega.py
```

## Estrutura

```
backend/
  prolog/jogo.pl          regras: retorno, partidas, interface com o Python
  prolog/palavras.pl      as 1000 palavras que podem ser sorteadas
  prolog/aceitas.pl       outras tentativas válidas (gerado, não editar)
  prolog/test_jogo.pl     testes plunit
  tools/gerar_aceitas.py  gera aceitas.pl a partir do dicionário
  app/prolog.py           ponte Python → Prolog (janus)
  app/main.py             rotas HTTP (FastAPI)
  tests/test_api.py       testes da API
frontend/
  src/Jogo.elm            domínio: tipos e transições de estado
  src/Api.elm             HTTP e JSON
  src/Main.elm            Arquitetura Elm: estado, teclado, tela
  src/main.js             inicia o Elm e lembra o tema escolhido
  src/style.css           visual (Tailwind + daisyUI)
scripts/                  validador da entrega e ferramentas do professor
```
