/*  Testes plunit das regras do jogo.

    Rodar (na raiz do repositório):
        swipl -g run_tests -t halt backend/prolog/test_jogo.pl

    Cada `test(nome)` é um teste. A opção `true(Expressao)` diz o que deve
    valer depois que o corpo roda.
*/

:- use_module(library(plunit)).
:- use_module(jogo).
:- use_module(palavras).
:- encoding(utf8).

:- begin_tests(retorno).

test(tudo_certo, true(Cores == [certa,certa,certa,certa,certa])) :-
    retorno([t,e,r,m,o], [t,e,r,m,o], Cores).

test(nada_em_comum, true(Cores == [ausente,ausente,ausente,ausente,ausente])) :-
    retorno([c,h,u,v,a], [t,e,r,m,o], Cores).

% O segredo tem um r só: o segundo r da tentativa fica cinza.
test(letra_repetida_na_tentativa,
     true(Cores == [certa,certa,certa,ausente,ausente])) :-
    retorno([t,e,r,r,a], [t,e,r,m,o], Cores).

% O segredo `carro` tem dois r: um fica verde, o outro amarelo.
test(letra_repetida_no_segredo,
     true(Cores == [presente,presente,certa,presente,ausente])) :-
    retorno([a,r,r,o,z], [c,a,r,r,o], Cores).

% Dois o na tentativa, um o no segredo: só o primeiro fica amarelo.
test(amarela_gasta_a_letra,
     true(Cores == [presente,ausente,ausente,ausente,ausente])) :-
    retorno([o,s,s,o,s], [t,e,r,m,o], Cores).

% A verde tem prioridade: o o da posição 5 é verde, então o da posição 1
% não pode ficar amarelo.
test(verde_antes_de_amarela,
     true(Cores == [ausente,ausente,ausente,ausente,certa])) :-
    retorno([o,o,o,o,o], [t,e,r,m,o], Cores).

:- end_tests(retorno).


:- begin_tests(palavras).

test(todas_as_palavras_tem_5_letras, true(Erradas == [])) :-
    findall(Texto,
            ( palavra(Letras, Texto),
              \+ ( length(Letras, 5), string_length(Texto, 5) ) ),
            Erradas).

test(texto_bate_com_as_letras, true(Erradas == [])) :-
    findall(Texto,
            ( palavra(Letras, Texto), \+ texto_letras(Texto, Letras) ),
            Erradas).

test(acentos_e_maiusculas, true(L == [r,a,d,i,o])) :-
    texto_letras("Rádio", L).

% Cada combinação de letras aparece uma vez só, somando respostas e aceitas.
test(sem_repeticao, true(Repetidas == [])) :-
    findall(L, palavra(L, _), Todas),
    msort(Todas, Ordenadas),
    findall(L, ( append(_, [L, L | _], Ordenadas) ), Repetidas0),
    sort(Repetidas0, Repetidas).

% Regra do jogo: nada de plural nem de verbo conjugado.
test(plurais_nao_valem) :-
    assertion(\+ palavra([c,a,s,a,s], _)),
    assertion(\+ palavra([t,r,e,n,s], _)),
    assertion(\+ palavra([a,z,u,i,s], _)).

test(verbos_conjugados_nao_valem) :-
    assertion(\+ palavra([f,a,l,e,i], _)),
    assertion(\+ palavra([c,o,m,e,u], _)),
    assertion(\+ palavra([a,n,d,a,m], _)).

% O infinitivo vale, seja resposta (andar) ou só tentativa (latir).
test(infinitivo_vale) :-
    assertion(once(palavra([a,n,d,a,r], _))),
    assertion(once(palavra([l,a,t,i,r], _))).

:- end_tests(palavras).


:- begin_tests(partidas).

% O segredo não sai pela interface: os testes o leem direto do fato
% partida/3, que não é exportado (por isso o prefixo jogo:).
segredo_texto(Id, Texto) :-
    jogo:partida(Id, Segredo, _),
    once(resposta(Segredo, Texto)).

% Seis palavras válidas diferentes do segredo, para perder de propósito.
erradas(Id, Seis) :-
    segredo_texto(Id, Segredo),
    exclude(==(Segredo),
            ["terra", "pouco", "lindo", "chuva", "bicho", "porta", "folha"],
            Erradas),
    length(Seis, 6),
    append(Seis, _, Erradas).

test(codigos_diferentes_e_aleatorios) :-
    novo_jogo(A),
    novo_jogo(B),
    assertion(A \== B),
    assertion(atom_length(A, 36)).

test(acertar_encerra_a_partida, true(Cores == [certa,certa,certa,certa,certa])) :-
    novo_jogo(Id),
    segredo_texto(Id, Texto),
    jogar(Id, Texto, [_, Cores]),
    assertion(\+ jogo:partida(Id, _, _)).

test(palavra_fora_da_base_nao_gasta_tentativa) :-
    novo_jogo(Id),
    jogar(Id, "xxxxx", R),
    assertion(R == invalida),
    assertion(jogo:partida(Id, _, jogando([]))).

% A mesma palavra não vale duas vezes, nem com acento diferente, e a
% repetição não gasta tentativa.
test(palavra_repetida_nao_vale) :-
    novo_jogo(Id),
    segredo_texto(Id, Segredo),
    (   Segredo == "rádio"
    ->  true                       % não dá para testar "radio" contra si mesma
    ;   jogar(Id, "radio", [_, _]),
        jogar(Id, "radio", R1),
        jogar(Id, "rádio", R2),
        assertion(R1 == repetida),
        assertion(R2 == repetida),
        assertion(jogo:partida(Id, _, jogando([[r,a,d,i,o]])))
    ).

% A trapaça antiga: pedir a palavra no meio da partida.
test(nao_revela_antes_do_fim, true(R == negado)) :-
    novo_jogo(Id),
    jogar(Id, "terra", _),
    revelar(Id, R).

test(perder_e_revelar) :-
    novo_jogo(Id),
    erradas(Id, Seis),
    segredo_texto(Id, Segredo),
    forall(member(P, Seis), jogar(Id, P, [_, _])),
    jogar(Id, "lindo", Depois),
    assertion(Depois == encerrada),
    revelar(Id, [Revelada]),
    assertion(Revelada == Segredo),
    revelar(Id, DeNovo),
    assertion(DeNovo == inexistente).

test(partida_inexistente) :-
    jogar("nao-existe", "terra", R1),
    revelar("nao-existe", R2),
    assertion(R1 == inexistente),
    assertion(R2 == inexistente).

% O Id chega do Python como string; o fato guarda um átomo.
test(id_como_string, true(Cores == [certa,certa,certa,certa,certa])) :-
    novo_jogo(Id),
    atom_string(Id, IdTexto),
    segredo_texto(Id, Texto),
    jogar(IdTexto, Texto, [_, Cores]).

:- end_tests(partidas).
