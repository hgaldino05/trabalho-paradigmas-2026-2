/*  
    Uma palavra é uma LISTA DE LETRAS: "termo" vira [t,e,r,m,o]. 
    Assim dá para comparar as palavras posição por posição com maplist/4.

    O retorno de uma tentativa é uma lista de cores, uma por letra:
      - certa = a letra está na palavra, nessa posição;
      - presente  = a letra está na palavra, em outra posição;
      - ausente= a letra não está na palavra (ou já houve tentativa com ela).

    O jogador NÃO vê essas cores letra por letra. O jogo só conta quantas
    letras caíram em cada cor (contagem/2): por exemplo, PASTA contra CASPA
    dá 3 certas, 1 presente e 1 ausente, sem dizer quais.

    Cada partida em andamento é um fato dinâmico partida/3, guardado aqui no
    Prolog. A palavra secreta nunca sai do servidor antes do fim.

    Para testar no terminal:

        $ swipl backend/prolog/jogo.pl
        ?- retorno([t,e,r,r,a], [t,e,r,m,o], Cores).
        ?- retorno([p,a,s,t,a], [c,a,s,p,a], Cores), contagem(Cores, N).
        ?- novo_jogo(Id), jogar(Id, "terra", R).
*/

:- module(jogo,
          [ retorno/3,
            contagem/2,
            palavra/2,
            texto_letras/2,
            % Interface usada pelo Python (backend/app/prolog.py):
            novo_jogo/1,
            jogar/3,
            revelar/2
          ]).

:- encoding(utf8).

:- use_module(library(apply)).    % maplist/4, foldl/6, convlist/3, include/3
:- use_module(library(lists)).    % selectchk/3, nth0/3, member/2
:- use_module(library(random)).   % random_member/2
:- use_module(library(uuid)).     % uuid/2: código aleatório da partida
:- use_module(palavras).          % resposta/2: palavras sorteadas
:- use_module(aceitas).           % aceita/2: outras palavras do dicionário
:- use_module(flexao).            % flexionada/1: plural ou verbo conjugado


/* 
   # RETORNO DE UMA TENTATIVA
   Com o segredo `termo` e a tentativa `terra`, só o PRIMEIRO r fica verde. 
   O segundo é ausente, porque `termo` tem um r só e ele já foi usado.

   Por isso o retorno é feito em duas passadas:
     1. marca as letras certas na posição certa (verdes);
     2. com as letras do segredo que SOBRARAM, decide as amarelas,
        consumindo uma letra da sobra a cada amarela.
*/

%!  retorno(+Tentativa, +Segredo, -Cores) is det.
%
%   Cores é o retorno que o jogo dá quando o jogador tenta Tentativa e a
%   palavra secreta é Segredo.

retorno(Tentativa, Segredo, Cores) :-
    maplist(marca_verde, Tentativa, Segredo, Marcas),
    convlist(letra_livre, Marcas, Sobra),
    foldl(colore, Marcas, Tentativa, Cores, Sobra, _).

%   Para cada posição: `certa`, ou `livre(S)` com a letra S do segredo que
%   ainda pode gerar uma amarela.
marca_verde(T, S, Marca) :-
    (   T == S
    ->  Marca = certa
    ;   Marca = livre(S)
    ).

%   convlist/3 é um maplist que descarta os elementos em que o predicado
%   falha: aqui, fica só com as letras das marcas livre(_).
letra_livre(livre(S), S).

%   colore(+Marca, +Letra, -Cor, +Sobra0, -Sobra)
%
%   foldl/6 percorre as marcas e a tentativa juntas, carregando a Sobra de
%   uma posição para a próxima (é o "acumulador" do fold). A marca vem
%   primeiro porque o SWI-Prolog indexa as cláusulas pelo primeiro
%   argumento: assim ele sabe qual cláusula usar sem deixar um ponto de
%   escolha aberto.
colore(certa, _, certa, Sobra, Sobra).
colore(livre(_), Letra, Cor, Sobra0, Sobra) :-
    (   selectchk(Letra, Sobra0, Sobra)   % tira UMA ocorrência da sobra
    ->  Cor = presente
    ;   Cor = ausente,
        Sobra = Sobra0
    ).

%!  contagem(+Cores, -Contagem) is det.
%
%   Contagem é [Certas, Presentes, Ausentes]: quantas letras caíram em cada
%   cor. É só isso que o jogador fica sabendo de cada tentativa.

contagem(Cores, [Certas, Presentes, Ausentes]) :-
    quantas(certa, Cores, Certas),
    quantas(presente, Cores, Presentes),
    quantas(ausente, Cores, Ausentes).

quantas(Cor, Cores, N) :-
    include(==(Cor), Cores, DessaCor),
    length(DessaCor, N).



/* # PALAVRAS E TEXTO */
%!  palavra(?Letras, ?Texto) is nondet.
%
%   Toda palavra que vale como tentativa: as respostas, sempre, e as
%   outras palavras do dicionário que não são plural nem verbo conjugado
%   (a análise está em flexao.pl).

palavra(Letras, Texto) :- resposta(Letras, Texto).
palavra(Letras, Texto) :- aceita(Letras, Texto), \+ flexionada(Letras).

%!  texto_letras(+Texto, -Letras) is det.
%
%   "Rádio" vira [r,a,d,i,o]: minúsculas e sem acento

texto_letras(Texto, Letras) :-
    string_lower(Texto, Minusculo),
    string_chars(Minusculo, Caracteres),
    maplist(sem_acento, Caracteres, Letras).

sem_acento(C0, C) :-
    (   acento(C0, C1)
    ->  C = C1
    ;   C = C0
    ).

%   Base de conhecimento: cada letra acentuada e a letra sem acento.
acento('á', a).  acento('à', a).  acento('â', a).  acento('ã', a).
acento('é', e).  acento('ê', e).
acento('í', i).
acento('ó', o).  acento('ô', o).  acento('õ', o).
acento('ú', u).  acento('ü', u).
acento('ç', c).



/* # PARTIDAS
   Cada partida em andamento é um fato partida(Id, Segredo, Situacao):
     Id = código aleatório (UUID versão 4), que vai para o navegador;
     Segredo =  a palavra secreta, como lista de letras;
     Situacao =  jogando(Tentadas), com a lista das palavras já tentadas
               (como listas de letras, da mais recente para a mais antiga),
               ou perdeu, depois da última tentativa errada.

   Os fatos mudam durante a execução (assertz/retract), por isso partida/3
   é declarado dinâmico. Como o servidor atende várias requisições ao mesmo
   tempo, toda mudança passa por with_mutex/2: duas tentativas da mesma
   partida não podem ler e regravar o fato juntas.

   O segredo fica guardado no fato, e não é calculado a partir de um número:
   mudar a ordem das respostas em palavras.pl não muda a palavra de uma
   partida. Como o navegador só conhece o Id, não há como descobrir a
   palavra antes do fim (revelar/2 só responde depois que a partida é
   perdida).
*/

:- dynamic partida/3.

%   Tentativas por partida. Precisa bater com `maxTentativas` em Jogo.elm.
max_tentativas(10).



/* # INTERFACE COM O PYTHON
   O janus não converte termos compostos como `a-b` ou `f(1, x)` para
   Python. Por isso estes predicados devolvem listas (o resultado normal)
   ou átomos (os casos de erro), que prolog.py traduz.

   O Id chega do Python como string; atom_string/2 o converte no átomo
   guardado em partida/3.
*/

%!  novo_jogo(-Id) is det.
%
%   Sorteia uma resposta e abre uma partida com um código aleatório.

novo_jogo(Id) :-
    findall(P, resposta(P, _), Respostas),
    random_member(Segredo, Respostas),
    uuid(Id, [version(4)]),
    with_mutex(partidas, assertz(partida(Id, Segredo, jogando([])))).

%!  jogar(+Id, +Texto, -Resultado) is det.
%
%   Resultado é [TextoDaPalavra, [Certas, Presentes, Ausentes]], só a
%   contagem das cores, nunca a cor de cada letra; ou um átomo:
%     invalida     Texto não está na base de palavras (não gasta tentativa);
%     repetida     Texto já foi tentado nesta partida (não gasta tentativa);
%     encerrada    a partida já foi perdida;
%     inexistente  não há partida com esse Id (ou ela já foi ganha).

jogar(IdTexto, Texto, Resultado) :-
    atom_string(Id, IdTexto),
    texto_letras(Texto, Tentativa),
    with_mutex(partidas, jogada(Id, Tentativa, Resultado)).

jogada(Id, Tentativa, Resultado) :-
    (   partida(Id, Segredo, Situacao)
    ->  avancar(Situacao, Id, Segredo, Tentativa, Resultado)
    ;   Resultado = inexistente
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
        contagem(Cores, Contagem),
        Resultado = [Exibicao, Contagem]
    ).

%   Ganhou: a partida acaba e o fato some. Esgotou as tentativas: fica
%   marcada como perdida até a palavra ser revelada. Senão, continua.
depois_da_jogada(Cores, Tentadas, Id, Segredo) :-
    (   maplist(==(certa), Cores)
    ->  true
    ;   length(Tentadas, Usadas), max_tentativas(Max), Usadas >= Max
    ->  assertz(partida(Id, Segredo, perdeu))
    ;   assertz(partida(Id, Segredo, jogando(Tentadas)))
    ).

%!  revelar(+Id, -Resultado) is det.
%
%   Resultado é [Texto], a palavra secreta, só depois que a partida foi
%   perdida; a partida então some. Antes disso é o átomo `negado`, e
%   `inexistente` quando não há partida com esse Id.

revelar(IdTexto, Resultado) :-
    atom_string(Id, IdTexto),
    with_mutex(partidas, revelacao(Id, Resultado)).

revelacao(Id, Resultado) :-
    (   partida(Id, Segredo, perdeu)
    ->  retract(partida(Id, Segredo, perdeu)),
        once(resposta(Segredo, Texto)),
        Resultado = [Texto]
    ;   partida(Id, _, _)
    ->  Resultado = negado
    ;   Resultado = inexistente
    ).
