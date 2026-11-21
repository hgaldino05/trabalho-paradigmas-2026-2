# Telmo

## 1. Identificação

| Nome completo | Matrícula | Turma (14h/16h) | Usuário GitHub |
|---------------|-----------|-----------------|----------------|
| Daniel dos Santos Barros de Sousa        | 211030980  | 14h     | [daniel-de-sousa](https://github.com/daniel-de-sousa)     |
| Henrique Galdino Couto        | 200058258  | 14h           | [hgaldino05](https://github.com/hgaldino05)     |
| João Paulo Monteiro de Barros Ceva Rodrigues       | 202045141  | 14h    | [joaombc](https://github.com/joaombc)     |

- **Nome do projeto:** tELMo
- **Nome do grupo:** tELMo
- **Repositório:** https://github.com/hgaldino05/trabalho-paradigmas-2026-2
- **Commit ou tag entregue:** `v1.0`
- **Ponto de partida:** outro jogo conhecido
- **Slides da apresentação oral:** `docs/apresentacao.pdf`

## 2. Resumo

**t*ELM*o** é um jogo de adivinhar uma palavra de 5 letras em até 6
tentativas. A cada tentativa, o jogo indica se a letra está na posição certa (cor verde) ou na posição errada (cor amarela), sendo utilizada a cor cinza para letras que não façam parte da palavra a ser adivinhada.

O nome junta **Termo** (nome do jogo que serviu de inspiração) e **Elm** (uma das linguagens aprendidas na disciplina). 

![Captura de tela do sistema](docs/captura.png)

## 3. Como executar

**Requisitos** (com as versões que o grupo usou):

- SWI-Prolog 9.2.9
- Node.js 24.15.0 (com npm)
- uv 0.7.4, que instala o Python 3.13.3 sozinho

**Instalação e execução:**

```sh
# terminal 1: backend (http://localhost:8000/docs)
cd backend
uv sync
uv run fastapi dev app/main.py

# terminal 2: frontend (http://localhost:5173)
cd frontend
npm install
npm run dev
```

Com `make` (Linux/macOS), `make install` e depois `make dev` fazem o mesmo.

No Windows há dois cuidados, descritos no `README.md`:

1. o `uv sync` compila o pacote `janus-swi` e precisa do compilador C++ do
   Visual Studio Build Tools; se ele não for encontrado, rode o `uv sync`
   depois do `vcvars64.bat`, com `set DISTUTILS_USE_SDK=1`;
2. antes de subir o backend ou rodar os testes, defina onde está o
   SWI-Prolog: `$env:SWI_HOME_DIR = "C:\Program Files\swipl"` (PowerShell).

**Testes:**

```sh
swipl -g run_tests -t halt backend/prolog/test_jogo.pl    # Prolog (plunit)
cd backend && uv run pytest                                # API (pytest)
```

## 4. Arquitetura

```
Navegador (Elm + daisyUI)  --HTTP/JSON-->  FastAPI (Python)  --janus-->  SWI-Prolog
```

Cada partida fica guardada no Prolog, como um fato dinâmico `partida/3`
com a palavra secreta e a situação da partida. O navegador só recebe um
código aleatório (UUID versão 4); a palavra secreta não sai do servidor
antes de a partida ser perdida.

| Parte  | Responsabilidade | Arquivos principais |
|--------|------------------|---------------------|
| Prolog | Base de palavras, cores de cada tentativa, sorteio e estado de cada partida (palavras já tentadas, fim de jogo) | `backend/prolog/jogo.pl`, `backend/prolog/palavras.pl`, `backend/prolog/aceitas.pl` |
| Elm    | Estado da partida, teclado físico e virtual, tabuleiro, painel de regras, animações e mensagens de erro | `frontend/src/Jogo.elm`, `frontend/src/Api.elm`, `frontend/src/Main.elm` |
| Python | Integração (valida o formato do JSON e chama o Prolog) | `backend/app/main.py`, `backend/app/prolog.py` |

## 5. Parte em Prolog

### 5.1 Predicados principais

| Predicado | Local | O que faz |
|-----------|-------|-----------|
| `retorno(+Tentativa, +Segredo, -Cores)` | `backend/prolog/jogo.pl:56` | Cores de uma tentativa, com letras repetidas tratadas em duas passadas |
| `palavra(?Letras, ?Texto)` | `backend/prolog/jogo.pl:95` | Tentativas válidas: respostas e aceitas |
| `texto_letras(+Texto, -Letras)` | `backend/prolog/jogo.pl:102` | `"Rádio"` vira `[r,a,d,i,o]`: minúsculas e sem acento |
| `partida(?Id, ?Segredo, ?Situacao)` | `backend/prolog/jogo.pl:143` | Fato dinâmico: uma partida em andamento, com o segredo e `jogando(Tentadas)` (as palavras já tentadas) ou `perdeu` |
| `novo_jogo(-Id)` | `backend/prolog/jogo.pl:163` | Sorteia o segredo e abre uma partida com código aleatório |
| `jogar(+Id, +Texto, -Resultado)` | `backend/prolog/jogo.pl:177` | Cores da tentativa e atualização da partida; ou `invalida`, `repetida`, `encerrada`, `inexistente` |
| `revelar(+Id, -Resultado)` | `backend/prolog/jogo.pl:217` | A palavra secreta, só depois que a partida foi perdida; senão `negado` |
| `resposta/2` e `aceita/2` | `backend/prolog/palavras.pl:32`, `backend/prolog/aceitas.pl:18` | Base de conhecimento: 1000 palavras sorteáveis e 954 tentativas aceitas |

### 5.2 Conceitos do paradigma lógico utilizados

- [x] Fatos e regras como base de conhecimento: as palavras são fatos `resposta/2` (`palavras.pl`) e `aceita/2` (`aceitas.pl`); a tabela de acentos são fatos `acento/2` (`jogo.pl:114`); `palavra/2` é uma regra que une as duas bases (`jogo.pl:95`).
- [x] Unificação e casamento de padrões: as cláusulas de `colore/5` são escolhidas pela forma da marca, `certa` ou `livre(_)` (`jogo.pl:80`); `letra_livre/2` só casa com `livre(S)` e, dentro de `convlist/3`, descarta as marcas `certa` (`jogo.pl:71`); `avancar/5` escolhe a cláusula pela situação da partida, `perdeu` ou `jogando(Tentadas)` (`jogo.pl:188`); `memberchk/2` recusa uma palavra que já está em `Tentadas`.
- [x] Recursão (inclusive sobre listas): feita pelos predicados de ordem superior abaixo, que percorrem as listas de letras.
- [x] Backtracking e múltiplas soluções: `palavra/2` tem duas cláusulas (`jogo.pl:95`); por backtracking, a busca passa das respostas para as aceitas, e `once/1` fica com a primeira solução (`jogo.pl:194`). Nos testes, `exclude/3` e `append/3` montam as tentativas erradas (`test_jogo.pl`).
- [x] `findall/3`, `bagof/3`, `setof/3` ou similares: `findall/3` em `novo_jogo/1` junta as respostas para o sorteio com `random_member/2` (`jogo.pl:164`); `findall/3` e `forall/2` nos testes da base de palavras e das partidas (`test_jogo.pl`).
- [x] Corte (`!`) ou negação (`\+`), e por que foram necessários: não usamos corte. A negação aparece em `avancar/5`, onde `\+ once(palavra(Tentativa, _))` recusa uma palavra fora da base (`jogo.pl:190`). Usamos if-then-else (`->`) para escolhas determinísticas, como em `marca_verde/3` (`jogo.pl:64`), `colore/5` (`jogo.pl:82`) e `depois_da_jogada/4` (`jogo.pl:204`), e `once/1` em `avancar/5` (`jogo.pl:194`) para não deixar pontos de escolha quando uma palavra é encontrada. Os testes usam `\+` para conferir a base (`test_jogo.pl`).
- [ ] Programação por restrições (CLP(FD) ou outra): não usamos; o problema é de busca numa base finita de palavras, não de domínios numéricos.
- [x] Predicados de ordem superior (`maplist`, `foldl`, `include` etc.): `maplist/4`, `convlist/3` e `foldl/6` em `retorno/3` (`jogo.pl:57`); `maplist/3` em `texto_letras/2` (`jogo.pl:105`); `maplist(==(certa), Cores)`, com aplicação parcial, para saber se o jogador ganhou (`jogo.pl:204`).
- [x] Outro: indexação de cláusulas. A marca é o primeiro argumento de `colore/5` porque o SWI-Prolog indexa pelo primeiro argumento; com a ordem invertida, um teste plunit avisava que `retorno/3` deixava um ponto de escolha aberto (`jogo.pl:73`).
- [x] Outro: base de conhecimento dinâmica. Cada partida é um fato `partida/3` declarado com `:- dynamic` (`jogo.pl:143`), criado com `assertz/1` e trocado com `retract/1` a cada tentativa; `with_mutex/2` impede que duas requisições mexam na mesma partida ao mesmo tempo (`jogo.pl:180`).

### 5.3 Trecho em destaque

```prolog
retorno(Tentativa, Segredo, Cores) :-
    maplist(marca_verde, Tentativa, Segredo, Marcas),
    convlist(letra_livre, Marcas, Sobra),
    foldl(colore, Marcas, Tentativa, Cores, Sobra, _).

colore(certa, _, certa, Sobra, Sobra).
colore(livre(_), Letra, Cor, Sobra0, Sobra) :-
    (   selectchk(Letra, Sobra0, Sobra)   % tira UMA ocorrência da sobra
    ->  Cor = presente
    ;   Cor = ausente,
        Sobra = Sobra0
    ).

avancar(perdeu, _, _, _, encerrada).
avancar(jogando(Tentadas), Id, Segredo, Tentativa, Resultado) :-
    (   \+ once(palavra(Tentativa, _))
    ->  Resultado = invalida
    ;   memberchk(Tentativa, Tentadas)
    ->  Resultado = repetida
    ;   once(palavra(Tentativa, Exibicao)),
        retorno(Tentativa, Segredo, Cores),
        retract(partida(Id, Segredo, _)),
        depois_da_jogada(Cores, [Tentativa | Tentadas], Id, Segredo),
        Resultado = [Exibicao, Cores]
    ).
```

`retorno/3` (`jogo.pl:56`) resolve o caso difícil do jogo: letras
repetidas. Com o segredo `termo` e a tentativa `terra`, só o primeiro r
pode ficar verde; o segundo fica cinza, porque `termo` tem um r só. O
predicado declara isso em duas passadas: `maplist/4` marca cada posição
como `certa` ou `livre(S)`; `convlist/3` junta as letras do segredo que
sobraram; e `foldl/6` percorre a tentativa carregando essa sobra, e cada
amarela consome uma letra dela com `selectchk/3`.

`avancar/5` (`jogo.pl:189`) guarda o estado de uma partida como fato. A
situação `jogando(Tentadas)` ou `perdeu` escolhe a cláusula por
unificação: uma partida perdida responde `encerrada` sem olhar a
tentativa. Uma palavra fora da base é `invalida`, e uma que já está em
`Tentadas` é `repetida`; nenhuma das duas gasta tentativa. Numa tentativa
válida, o fato antigo sai com `retract/1` e `depois_da_jogada/4` grava o
novo: nenhum, se o jogador ganhou; `perdeu`, se esgotou as 6 tentativas;
ou `jogando` com a palavra nova na lista. Como o segredo fica no fato, e
não é deduzido de um número, o navegador não tem como descobri-lo, e mudar
a ordem de `palavras.pl` não muda a palavra de nenhuma partida.

## 6. Parte em Elm

### 6.1 Modelo e mensagens

```elm
-- Jogo.elm (domínio puro)
type Cor = Certa | Presente | Ausente

type Estado
    = Digitando String       -- o jogador está escrevendo a próxima palavra
    | Conferindo String      -- a palavra foi enviada; esperamos o servidor
    | Venceu
    | Perdeu (Maybe String)  -- o segredo chega depois, pelo servidor

type alias Jogo = { id : String, tentativas : List Tentativa, estado : Estado }

-- Api.elm
type Erro = Recusada String | Falha String

-- Main.elm
type Tela = Iniciando | EmJogo Jogo | SemServidor String

type alias Model =
    { tela : Tela
    , toast : Maybe Toast
    , proximoToast : Int
    , aviso : Maybe String
    , darkTheme : Bool
    }

type Msg
    = NovoJogoPedido
    | NovoJogoRecebido (Result Api.Erro String)
    | LetraDigitada Char
    | Apagou
    | Enviou
    | RetornoRecebido (Result Api.Erro Retorno)
    | SegredoRecebido (Result Api.Erro String)
    | ToastFechado
    | ToastExpirou Int
    | ToastRemovido Int
    | AvisoFechado
    | TemaTrocado Bool
```

- **`Estado`** (`Jogo.elm:80`) troca vários `Bool` (`venceu`, `perdeu`,
  `esperando`) por um único custom type. Não existe o estado "venceu e
  perdeu" nem "digitando enquanto espera o servidor": em `Conferindo`, as
  funções `digitar` e `apagar` simplesmente não fazem nada.
- **`Perdeu (Maybe String)`**: quando acabam as tentativas, a palavra
  secreta ainda não chegou do servidor. O `Maybe` deixa explícito esse
  intervalo, e a tela mostra “Buscando a palavra” até ele virar `Just`.
- **`Tela`** (`Main.elm:53`): enquanto o servidor não sorteia a palavra não
  existe `Jogo`, em vez de um `Jogo` com `id` falso.
- **`Erro`** (`Api.elm:35`): o servidor responde 422 quando a palavra não
  está na lista ou já foi tentada. Com `Recusada` e `Falha`, o `update` decide pela forma do
  valor se mostra o toast vermelho de palavra desconhecida ou a faixa de
  erro de rede, em vez de comparar o texto da mensagem.
- **`Toast`** (`Main.elm:71`) tem um `id`, um motivo (`ForaDaLista` ou
  `JaTentada`) e uma fase (`Visivel` ou `Saindo`). O `id` faz o aviso
  atrasado de um toast antigo ser ignorado quando já há outro na tela; o
  motivo decide o texto do aviso, e o `case` obriga a tratar os dois.

### 6.2 Conceitos do paradigma funcional utilizados

- [x] Arquitetura Elm (Model, update, view): `Main.elm` (`update` em `Main.elm:147`), com `Jogo.elm` como domínio puro, sem HTTP nem HTML.
- [x] Custom types e `case` exaustivo: `Estado`, `Cor` (`Jogo.elm:41`), `Erro`, `Tela`, `Motivo` (`Main.elm:81`), `FaseDoToast`; o `update` casa padrões em pares, como `( RetornoRecebido (Err (Api.Recusada _)), EmJogo jogo )`.
- [x] `Maybe` e `Result` no lugar de null e exceções: `conferir : Jogo -> Maybe ( Jogo, String )` (`Jogo.elm:133`), `Perdeu (Maybe String)`, `Maybe Toast`; todas as respostas HTTP chegam como `Result Api.Erro a`.
- [x] Funções de ordem superior e aplicação parcial: `List.foldl` com `Dict.update` em `coresDoTeclado` (`Jogo.elm:219`); `List.all ((==) Certa)` em `registrar` (`Jogo.elm:164`); `List.indexedMap` e `List.map2` no tabuleiro.
- [x] Composição (`|>`, `>>`): pipelines em `coresDoTeclado` (`Jogo.elm:226`) e `Just << maisForte cor` (`Jogo.elm:227`).
- [x] Decoders e encoders JSON: `retornoDecoder` (`Api.elm:91`) e `corDecoder` (`Api.elm:101`), que falha para cores desconhecidas; `expectJson` próprio lê o corpo das respostas de erro (`Api.elm:129`).
- [x] Comandos e subscriptions (efeitos controlados): `Browser.Events.onKeyDown` com um decoder que falha para teclas ignoradas (`Main.elm:302`); `Process.sleep` vira comando para o toast sumir sozinho (`Main.elm:284`).
- [x] Imutabilidade e atualização de records: `{ jogo | tentativas = tentativas, estado = estado }` em `registrar` (`Jogo.elm:173`).
- [x] Outro: `Html.Keyed` no tabuleiro (`Main.elm:511`), para a linha atual ser recriada a cada palavra recusada e a animação de tremer tocar de novo.
- [x] Reaproveitamento de mensagens: o teclado virtual (`viewTeclado`, `Main.elm:632`) não cria mensagens novas. Cada tecla dispara as mesmas `LetraDigitada`, `Enviou` e `Apagou` do teclado físico, e as cores vêm de `Jogo.coresDoTeclado`: verde e amarelo como no tabuleiro, e a letra que não está na palavra fica translúcida. As teclas usam `preventDefaultOn "mousedown"` (`Main.elm:643`) para não ganhar foco: senão, um Enter do teclado físico apertaria de novo a última tecla clicada.

### 6.3 Trecho em destaque

```elm
registrar : Retorno -> Jogo -> Jogo
registrar retorno jogo =
    case jogo.estado of
        Conferindo digitada ->
            let
                tentativas =
                    jogo.tentativas
                        ++ [ { digitada = digitada, exibida = retorno.palavra, cores = retorno.cores } ]

                estado =
                    if List.all ((==) Certa) retorno.cores then
                        Venceu

                    else if List.length tentativas >= maxTentativas then
                        Perdeu Nothing

                    else
                        Digitando ""
            in
            { jogo | tentativas = tentativas, estado = estado }

        _ ->
            jogo
```

`registrar` (`Jogo.elm:154`) recebe o retorno do servidor e decide o que
acontece com a partida. Ele só age em `Conferindo`: a palavra digitada que
está guardada nesse construtor é a mesma que foi enviada, então não há como
registrar o retorno de uma palavra contra outra. Uma resposta que chega
fora de hora (por exemplo, depois de o jogador começar um jogo novo) cai no
`_ -> jogo` e é ignorada. O próximo estado é calculado de forma pura, a
partir das cores: todas `Certa` é vitória; esgotar as tentativas é
`Perdeu Nothing`, e o `update` então pede o segredo ao servidor; senão, o
jogador volta a `Digitando ""`.

## 7. Integração

| Rota / chamada | Entrada | Saída | Predicado Prolog |
|----------------|---------|-------|------------------|
| `POST /api/novo` | nada | `{"jogo": "5cf75573-…"}` | `novo_jogo/1` |
| `POST /api/tentativa` | `{"jogo": "5cf75573-…", "palavra": "radio"}` | `{"palavra": "rádio", "cores": ["certa", ...]}`; 422 (fora da lista ou já tentada), 409 (partida já perdida) ou 404 (partida inexistente) | `jogar/3` |
| `POST /api/revelar` | `{"jogo": "5cf75573-…"}` | `{"palavra": "termo"}` só depois da derrota; 403 antes disso, 404 se não existe | `revelar/2` |

As rotas estão em `backend/app/main.py:58` e a ponte com o janus em
`backend/app/prolog.py`. O janus não converte termos compostos, por isso
os predicados de interface devolvem uma lista quando dá certo e um átomo
nos casos de erro (`invalida`, `repetida`, `encerrada`, `inexistente`,
`negado`), que o
Python traduz para exceções e depois para códigos HTTP.

## 8. Testes e validação

- **Testes plunit** (`backend/prolog/test_jogo.pl`): cores de
  uma tentativa, formato da base de palavras e o ciclo de vida das
  partidas (criar, jogar, ganhar, perder, revelar).
- **Testes pytest** (`backend/tests/test_api.py`): rotas, formato
  do JSON e códigos de status.
- **Testes no navegador**: partidas completas jogadas.
- **Casos de borda considerados:**
  - letra repetida na tentativa e não no segredo (`terra` contra `termo`);
  - letra repetida no segredo (`arroz` contra `carro`);
  - amarela que gasta a letra (`ossos` contra `termo`: só um 'o' amarelo);
  - verde com prioridade sobre amarela (`ooooo` contra `termo`);
  - pedir a palavra no meio da partida (`revelar/2` responde `negado`, e a
    API, 403);
  - tentativa depois da derrota (409), partida inexistente ou já ganha
    (404) e palavra revelada uma vez só (depois disso, a partida some);
  - palavra fora da lista não gasta tentativa;
  - palavra repetida na mesma partida é recusada, também com outro
    acento (`radio` e depois `rádio`), e não gasta tentativa; o Elm
    confere antes de enviar, e o Prolog confere de novo;
  - código da partida chegando do Python como string (o fato guarda um
    átomo);
  - palavra fora da lista (422 e toast vermelho) e palavra com tamanho
    errado;
  - acentos e maiúsculas (`"Rádio"` vira `[r,a,d,i,o]`, e `radio` volta como
    `rádio`);
  - plurais e verbos conjugados são recusados (`casas`, `falei`), mas verbos no
    infinitivo são aceitos (`andar`, `latir`);
  - nenhuma combinação de letras repetida na base (por exemplo, `força` e
    `forca` juntas);
  - Enter com menos de 5 letras, teclas com Ctrl ou Cmd (ignoradas para não
    atrapalhar atalhos do navegador) e resposta do servidor que chega depois
    de um jogo novo (ignorada por `registrar`);
  - clique numa tecla do teclado virtual seguido de Enter no teclado
    físico (a tecla não ganha foco, então a letra não se repete).

## 9. Limitações e problemas conhecidos

- As partidas ficam na memória do servidor. Reiniciar o backend apaga as
  partidas abertas: o jogador vê "Partida não encontrada" e precisa começar
  outra.
- Uma partida abandonada no meio nunca é apagada. Com poucos jogadores
  isso não pesa, mas num servidor público seria preciso expirar partidas
  antigas.
- O número de tentativas (6) aparece em dois lugares: `max_tentativas/1`
  no Prolog e `maxTentativas` no Elm. Mudar um exige mudar o outro.
- As 1000 respostas foram escritas com ajuda de IA e ainda precisam de
  revisão do grupo. 27 delas não aparecem no dicionário usado para as
  tentativas aceitas, que é de 2003 e incompleto. Elas continuam valendo,
  porque as respostas são uma lista à parte.
- Plural e verbo conjugado não valem, mas o dicionário não diz a classe
  de cada palavra: o filtro de `gerar_aceitas.py` usa regras e é
  aproximado. Escapam algumas formas irregulares (`sinta`), e alguns
  substantivos que coincidem com verbos ficaram de fora (`baixa`, `ginga`).
- `aceitas.pl` tem cerca de 970 linhas de dados gerados por script. Ele
  aumenta a proporção de linhas em Prolog nas métricas sem ser lógica
  escrita pelo grupo.
- No Windows, o backend exige compilar o `janus-swi` e definir
  `SWI_HOME_DIR` (seção 3).

## 10. Contribuição de cada integrante

| Integrante | Principais contribuições |
|------------|--------------------------|
| Daniel dos Santos Barros de Sousa      | Desenvolvimento do trabalho (frontend e backend); Busca da base de palavras |
| Henrique Galdino Couto     | Desenvolvimento do trabalho (frontend e backend); Preenchimento do RELATORIO.md |
| João Paulo Monteiro de Barros Ceva Rodrigues       | Desenvolvimento do trabalho (frontend e backend); Elaboração dos slides |


## 11. Fontes, código de terceiros e uso de IA

**Código reaproveitado.** Partimos do projeto-modelo do Sudoku
(https://github.com/fabiommendes/paradigmas-trabalho-final). Mantivemos a
infraestrutura: `Makefile`, `vite.config.js`, `package.json`, `index.html`,
`main.js`, a integração Python com o janus, a função `expectJson` de
`Api.elm`, o botão de tema de `Main.elm` e os scripts de `scripts/`. Todas
as regras foram trocadas: `jogo.pl`, `palavras.pl`, `test_jogo.pl`,
`Jogo.elm` e o resto de `Api.elm`, `Main.elm`, `main.py`, `prolog.py` e
`style.css` são deste projeto.

**Referências.**

- Lista de todas as palavras do português brasileiro, de Paulo Feofiloff
  (IME-USP), preparada a partir do Dicionário br.ispell de Ricardo Ueda
  Karpischek, licença Creative Commons BY 4.0:
  https://www.ime.usp.br/~pf/dicios/. Origem de `backend/prolog/aceitas.pl`,
  gerado por `backend/tools/gerar_aceitas.py`.
- Documentação do SWI-Prolog (bibliotecas `apply`, `lists`, `random`,
  `uuid`, `plunit` e janus): https://www.swi-prolog.org/pldoc/
- Documentação do Elm e dos pacotes `elm/browser`, `elm/http` e
  `elm/json`: https://package.elm-lang.org/
- Documentação do Tailwind CSS e do daisyUI.
- A mecânica do jogo vem do Wordle e de sua versão em português, o Termo.
  Nenhum código, lista de palavras ou elemento visual desses jogos foi
  usado.

**Uso de ferramentas de IA.**

- **Faixa de uso no código:** auxiliar

| Ferramenta | Para que foi usada | Como o grupo verificou o resultado |
|------------|--------------------|------------------------------------|
| Claude | Usada pelo grupo para auxiliar na busca pelo banco de palavras, entender melhor como aplicar os conceitos estudados na disciplina dentro do contexto do jogo e desenvolver e para estilização da interface | Testes (plunit e pytest), partidas jogadas no servidor local |

## 12. Apresentação oral

- **Slides:** `docs/apresentacao.pdf`
- **Roteiro:**

| Parte | Duração | Quem apresenta |
|-------|:-------:|----------------|
| Contexto e objetivo | 2 min | Daniel dos Santos Barros de Sousa |
| Demonstração | 5 min | Henrique Galdino Couto e João Paulo Monteiro de Barros Ceva Rodrigues|
| Código Prolog | 3 min | Daniel dos Santos Barros de Sousa |
| Código Elm | 3 min | Henrique Galdino Couto |
| Limitações e aprendizados | 2 min | João Paulo Monteiro de Barros Ceva Rodrigues |

## 13. Reflexão sobre os paradigmas

**Prolog: descrever a regra em vez de escrever o algoritmo.** A primeira
surpresa foi que boa parte do trabalho em Prolog não é dizer *como*
calcular, e sim *o que* é verdade. As palavras são fatos (`resposta/2`,
`aceita/2`), a tabela de acentos também (`acento/2`), e `palavra/2` é só
uma regra que diz que uma tentativa válida é uma resposta ou uma aceita.
Não há laço procurando na lista: a busca e o retrocesso ficam por conta do
Prolog. Em Python, cada uma dessas consultas viraria uma função com um
`for` e um `if`.

**Onde o modelo de execução aparece.** O caso difícil do jogo, as letras
repetidas, mostrou que "declarar" não basta: `retorno/3` (`jogo.pl:56`)
precisou ser pensado em duas passadas, primeiro as verdes e depois as
amarelas, que consomem as letras que sobraram com `foldl/6` e
`selectchk/3`. E um teste do plunit avisou que `retorno/3` deixava um ponto
de escolha aberto. A correção foi trocar a ordem dos argumentos de
`colore/5` (`jogo.pl:80`), para que o SWI-Prolog escolhesse a cláusula
pelo primeiro argumento. Ou seja: mesmo escrevendo de forma declarativa,
foi preciso entender como o Prolog executa a busca.

**Estado num paradigma declarativo.** Guardar as partidas no Prolog foi a
parte que mais fugiu do "puro". Cada partida é um fato dinâmico
`partida/3` (`jogo.pl:143`), trocado com `retract/1` e `assertz/1` a cada
tentativa, e protegido por `with_mutex/2` (`jogo.pl:180`) porque o
servidor atende várias requisições ao mesmo tempo. Ao mesmo tempo, a
unificação deixou essa parte clara: `avancar/5` (`jogo.pl:188`) tem uma
cláusula para cada situação da partida (`perdeu` ou `jogando(Tentadas)`),
e recusar uma palavra repetida é uma linha, `memberchk/2` na lista de
tentadas (`jogo.pl:192`). O lado ruim apareceu na fronteira com o Python:
o janus não converte termos compostos, então a interface teve que
devolver listas e átomos, e o Python teve que traduzi-los de volta.

**Elm: tornar estados impossíveis impossíveis de escrever.** Em Elm, a
mudança de pensamento foi modelar primeiro os estados e só depois a
tela. O tipo `Estado` (`Jogo.elm:80`), com `Digitando`, `Conferindo`,
`Venceu` e `Perdeu`, substitui vários `Bool` que poderiam se contradizer,
como "venceu e perdeu ao mesmo tempo". O estado `Conferindo` resolve sem
esforço um problema que em JavaScript daria trabalho: enquanto o servidor
responde, o teclado não altera a palavra, e uma resposta que chega fora de
hora cai no caso `_ -> jogo` e é ignorada.

**O compilador como revisor.** O que mais ajudou foi o compilador apontar
cada lugar que uma mudança afetava. Quando o erro da API deixou de ser um
`String` e virou o tipo `Api.Erro` (`Api.elm:35`), com `Recusada` e
`Falha`, o compilador listou todos os pontos em que os dois casos
precisavam ser tratados. O mesmo aconteceu quando o código da partida
passou de número para texto, e quando o aviso de palavra recusada ganhou
um motivo (`Motivo`, `Main.elm:81`). Efeitos também ficam explícitos: o
aviso some sozinho porque `Process.sleep` vira um comando devolvido pelo
`update`, e não um temporizador escondido.

**Comparando os dois.** Em Prolog a pergunta era "o que é verdade sobre
uma palavra ou uma partida?"; em Elm, "que estados a tela pode ter e que
mensagens fazem ela mudar?". Os dois paradigmas empurram a lógica para
fora dos efeitos, mas de formas diferentes: o Prolog guarda o estado como
fatos e confia na busca, enquanto o Elm proíbe estado mutável e obriga
cada transição a passar pelo `update`. Para validar, o Prolog dependeu dos
testes do plunit; no Elm, boa parte desse papel foi do compilador. Se
fôssemos começar de novo, usaríamos o Prolog para mais regras do jogo
(por exemplo, um modo difícil, em que cada tentativa precisa respeitar as
cores já vistas), que é onde ele mostrou mais vantagem.

---

