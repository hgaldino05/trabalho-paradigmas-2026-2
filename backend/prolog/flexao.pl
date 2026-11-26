/*  flexao.pl: reconhece plurais e verbos conjugados.

    Regra do jogo: plural e verbo conjugado não valem como tentativa (verbo
    só no infinitivo). O dicionário não diz a classe de cada palavra, então
    a análise é feita pelas regras de formação das palavras, escritas como
    uma GRAMÁTICA (DCG):

      - plural   = um singular do dicionário + uma terminação de plural
                   (casa + s, luz + es, tre[m] + ns);
      - conjugado = o radical de um infinitivo do dicionário + uma
                   terminação verbal (fal + ei, com + eu, pens + a).

    A gramática não decide sozinha: cada análise só vale se a palavra-base
    (o singular ou o infinitivo) existir no dicionário (lexema/1). E uma
    palavra pode ter mais de uma análise: flexao/3 devolve todas, por
    backtracking.

        $ swipl backend/prolog/flexao.pl
        ?- flexao([f,a,l,a,s], Base, Tipo).
        Base = [f,a,l,a], Tipo = plural ;
        Base = [f,a,l,a,r], Tipo = verbo.

    É uma aproximação: escapam formas irregulares que não estão na lista
    (sinta), e saem substantivos iguais a formas verbais (baixa, ginga). As
    respostas (palavras.pl) não passam por aqui: valem sempre.
*/

:- module(flexao, [flexao/3, flexionada/1]).

:- encoding(utf8).

:- use_module(library(lists)).    % append/3, memberchk/2
:- use_module(palavras).          % resposta/2
:- use_module(aceitas).           % aceita/2
:- use_module(lexico).            % vocabulo/1: palavras de outros tamanhos


%!  flexao(?Palavra, ?Base, ?Tipo) is nondet.
%
%   Palavra (lista de letras) é uma forma flexionada de Base: o plural de
%   um singular (Tipo = plural) ou uma conjugação de um infinitivo
%   (Tipo = verbo). Cada solução é uma análise diferente.

flexao(Palavra, Singular, plural) :-
    phrase(plural(Singular), Palavra),
    lexema(Singular).
flexao(Palavra, Infinitivo, verbo) :-
    verbo_conjugado(Palavra, Infinitivo).

%!  flexionada(+Palavra) is semidet.
%
%   A palavra tem pelo menos uma análise como plural ou verbo conjugado.

flexionada(Palavra) :-
    once(flexao(Palavra, _, _)).

%   Uma palavra que existe no dicionário, de qualquer tamanho que a análise
%   precise consultar.
lexema(Letras) :- vocabulo(Letras).
lexema(Letras) :- resposta(Letras, _).
lexema(Letras) :- aceita(Letras, _).



/* # PLURAL */

%   A palavra se divide em um radical e uma terminação de plural; a
%   terminação diz como recompor o singular a partir do radical.
plural(Singular) -->
    radical(Radical),
    terminacao_plural(Radical, Singular).

%   radical//1 consome qualquer começo da palavra: do vazio à palavra
%   inteira. É o backtracking que experimenta cada divisão.
radical([]) --> [].
radical([L|Ls]) --> [L], radical(Ls).

terminacao_plural(R, R) --> [s].                         % casas  -> casa
terminacao_plural(R, R) --> [e, s].                      % luzes  -> luz
terminacao_plural(R, S) --> [n, s],                      % trens  -> trem
    { append(R, [m], S) }.
terminacao_plural(R, S) --> [V, e, s],                   % leões  -> leão
    { memberchk(V, [o, a]), append(R, [a, o], S) }.
terminacao_plural(R, S) --> [V, i, s],                   % azuis  -> azul
    { memberchk(V, [a, e, o, u]), append(R, [V, l], S) }.
terminacao_plural(R, S) --> [e, i, s],                   % fósseis -> fóssil
    { append(R, [i, l], S) }.
terminacao_plural(R, S) --> [i, s],                      % fuzis  -> fuzil
    { append(R, [i, l], S) }.



/* # VERBO CONJUGADO */

%   "amamo" está no dicionário por causa de "amamo-lo": é um pedaço de
%   "amamos". A palavra em -amo, -emo ou -imo é verbo se, com o s, for uma
%   forma verbal.
verbo_conjugado(Palavra, Infinitivo) :-
    append(_, [V, m, o], Palavra),
    memberchk(V, [a, e, i]),
    append(Palavra, [s], ComS),
    forma_verbal(ComS, Infinitivo).
%   "livro" parece "eu livro" (de livrar), mas tem plural no dicionário
%   (livros): é substantivo.
verbo_conjugado(Palavra, Infinitivo) :-
    forma_verbal(Palavra, Infinitivo),
    \+ substantivo_em_o(Palavra).

substantivo_em_o(Palavra) :-
    append(_, [o], Palavra),
    append(Palavra, [s], Plural),
    lexema(Plural).

forma_verbal(Palavra, Infinitivo) :-
    irregular(Infinitivo, Formas),
    memberchk(Palavra, Formas).
forma_verbal(Palavra, Infinitivo) :-
    phrase(conjugacao(Infinitivo), Palavra).

%   A palavra se divide no que vem antes da terminação (Antes) e numa
%   terminação verbal de uma das conjugações. A grafia do radical pode
%   mudar antes da terminação (fiquei, de ficar); radical_verbal/4 desfaz
%   essas mudanças. O infinitivo é o radical mais ar, er ou ir.
conjugacao(Infinitivo) -->
    radical(Antes),
    terminacao_verbal(Conjugacao, Fim),
    {   radical_verbal(Conjugacao, Antes, Fim, Radical),
        append(Radical, Conjugacao, Infinitivo),
        infinitivo(Infinitivo)
    }.

terminacao_verbal(Conjugacao, Fim) -->
    { terminacao(Conjugacao, Fim) },
    letras(Fim).

letras([]) --> [].
letras([L|Ls]) --> [L], letras(Ls).

%   Um infinitivo do dicionário. Infinitivos de 3 letras só os verbos
%   curtos de verdade: bar, mar e par são substantivos e gerariam formas
%   falsas.
infinitivo(Letras) :-
    length(Letras, N),
    (   N >= 4
    ->  lexema(Letras)
    ;   verbo_curto(Letras)
    ).

verbo_curto([l,e,r]).  verbo_curto([t,e,r]).  verbo_curto([v,e,r]).
verbo_curto([d,a,r]).  verbo_curto([s,e,r]).  verbo_curto([r,i,r]).
verbo_curto([v,i,r]).  verbo_curto([c,r,e,r]).


%!  radical_verbal(+Conjugacao, +Antes, +Fim, -Radical) is nondet.
%
%   Radical é o radical do infinitivo, sabendo que a palavra é Antes
%   seguido da terminação Fim. Desfaz as mudanças de grafia mais comuns.

%   ficar -> fiquei: o c vira qu antes de e.
radical_verbal([a,r], Antes, [e|_], Radical) :-
    append(Base, [q,u], Antes),
    append(Base, [c], Radical).
%   pagar -> paguei: o g ganha u antes de e.
radical_verbal([a,r], Antes, [e|_], Radical) :-
    append(Base, [g,u], Antes),
    append(Base, [g], Radical).
%   passear -> passeio: entra um i depois do e do radical.
radical_verbal([a,r], Antes, Fim, Radical) :-
    memberchk(Fim, [[o], [a], [a,s], [a,m], [e], [e,s], [e,m]]),
    append(Radical, [i], Antes),
    append(_, [e], Radical).
%   fugir -> fujo: o g vira j antes de a e o.
radical_verbal(Conjugacao, Antes, [V|_], Radical) :-
    memberchk(Conjugacao, [[e,r], [i,r]]),
    memberchk(V, [a, o]),
    append(Base, [j], Antes),
    append(Base, [g], Radical).
%   seguir -> sego: o u de gu cai antes de a e o.
radical_verbal(Conjugacao, Antes, [V|_], Radical) :-
    memberchk(Conjugacao, [[e,r], [i,r]]),
    memberchk(V, [a, o]),
    append(_, [g], Antes),
    append(Antes, [u], Radical).
%   cair -> caio: entra um i depois de a, o ou u.
radical_verbal(Conjugacao, Antes, [V|_], Radical) :-
    memberchk(Conjugacao, [[e,r], [i,r]]),
    memberchk(V, [a, o]),
    append(Radical, [i], Antes),
    append(_, [U], Radical),
    memberchk(U, [a, o, u]),
    \+ append(_, [g,u], Radical).
%   O caso comum: a palavra é o radical seguido da terminação, quando
%   nenhuma das regras acima troca a grafia.
radical_verbal(Conjugacao, Radical, Fim, Radical) :-
    \+ grafia_trocada(Conjugacao, Radical, Fim).

%   Radicais que nunca aparecem sem mudança diante dessa terminação.
grafia_trocada([a,r], Radical, [e|_]) :-
    append(_, [g], Radical).
grafia_trocada(Conjugacao, Radical, [V|_]) :-
    memberchk(Conjugacao, [[e,r], [i,r]]),
    memberchk(V, [a, o]),
    append(_, [g], Radical).
grafia_trocada(Conjugacao, Radical, [V|_]) :-
    memberchk(Conjugacao, [[e,r], [i,r]]),
    memberchk(V, [a, o]),
    append(_, [g,u], Radical).


%   As terminações regulares, sem acento. Ficam de fora o infinitivo e o
%   particípio, que também funcionam como substantivo ou adjetivo. A
%   terminação "a" dos verbos em -ar (ele pensa) entra: alguns substantivos
%   iguais a ela saem junto (baixa, ginga), mas os comuns (conta, falta,
%   busca) estão em palavras.pl, que não passa por esta análise.
terminacao(Conjugacao, Fim) :-
    terminacoes(Conjugacao, Fins),
    member(Atomo, Fins),
    atom_chars(Atomo, Fim).

terminacoes([a,r],
    [ o, a, e, ai, ei, as, am, es, em, aste, ou, amos, ais, astes, aram, ava,
      avas, avamos, aveis, avam, ara, aras, aramos, areis, arei, arao, aria,
      arias, ariamos, arieis, ariam, emos, eis, asse, asses, assemos, asseis,
      assem, armos, ardes, arem, ando ]).
terminacoes([e,r],
    [ o, a, e, ei, es, em, as, am, i, este, eu, emos, eis, estes, eram, ia,
      ias, iamos, ieis, iam, era, eras, eramos, ereis, erei, erao, eria,
      erias, eriamos, erieis, eriam, amos, ais, esse, esses, essemos, esseis,
      essem, ermos, erdes, erem, endo ]).
terminacoes([i,r],
    [ o, a, e, es, em, as, am, i, iste, iu, imos, is, istes, iram, ia, ias,
      iamos, ieis, iam, ira, iras, iramos, ireis, irei, irao, iria, irias,
      iriamos, irieis, iriam, amos, ais, isse, isses, issemos, isseis, issem,
      irmos, irdes, irem, indo ]).


%   Formas irregulares comuns, que as regras acima não geram, agrupadas
%   pelo infinitivo.
irregular(Infinitivo, Formas) :-
    irregulares(Atomo, Atomos),
    atom_chars(Atomo, Infinitivo),
    maplist(atom_chars, Atomos, Formas).

irregulares(ser,    [somos, sois, foram, fomos, foste, fosse, sejam, sejas, seria, serao, eram, sendo]).
irregulares(estar,  [estou, estao, estas, estava, esteve, estive]).
irregulares(ter,    [tenho, temos, tinha, tinham, teria, terao, terei, tiver, tenha, tenham, tendo]).
irregulares(ir,     [vamos, iriam, irao]).
irregulares(vir,    [vimos, vinha, vindo, venho, vens, venha]).
irregulares(ver,    [vemos, veria, vejo, vejam, viram, vendo]).
irregulares(fazer,  [fazem, fazia, fizer, fazes, faria, farao]).
irregulares(dizer,  [disse, dizem, digam, digas, diria, dirao]).
irregulares(poder,  [posso, pode, podem, podia, puder, possa]).
irregulares(querer, [quero, quer, querem, quis, quiser]).
irregulares(trazer, [trago, traga, trouxe]).
irregulares(por,    [ponho, pomos, poem, pondo]).
irregulares(saber,  [soube, sabem, sabia, saiba]).
irregulares(dar,    [dando, deram, demos, dava, davam, desse, dessem, derem]).
irregulares(haver,  [houve, havia, hajam]).
irregulares(rir,    [rindo, rirao, riria]).
irregulares(caber,  [caibo, caiba, coube]).
irregulares(depor,  [depoe, depus]).
irregulares(trair,  [traio, traia]).
irregulares(sair,   [saio, saem]).
irregulares(fugir,  [fujo, fujas, fuja]).
irregulares(odiar,  [odeio]).
