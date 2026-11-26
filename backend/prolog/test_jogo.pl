/*  Testes plunit das regras do jogo.

    Rodar (na raiz do repositório):
        swipl -g run_tests -t halt backend/prolog/test_jogo.pl

    Cada `test(nome)` é um teste. A opção `true(Expressao)` diz o que deve
    valer depois que o corpo roda.
*/

:- use_module(library(plunit)).
:- use_module(jogo).
:- use_module(palavras).
:- use_module(flexao).
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

% O exemplo do enunciado: PASTA contra CASPA. Só a contagem sai do Prolog.
test(contagem_pasta_caspa, true(N == [3, 1, 1])) :-
    retorno([p,a,s,t,a], [c,a,s,p,a], Cores),
    contagem(Cores, N).

test(contagem_letra_repetida, true(N == [3, 0, 2])) :-
    retorno([t,e,r,r,a], [t,e,r,m,o], Cores),
    contagem(Cores, N).

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

% As respostas valem sempre, mesmo quando também são forma verbal:
% "conta" é de contar, mas é uma palavra comum.
test(resposta_vale_mesmo_flexionada) :-
    assertion(flexionada([c,o,n,t,a])),
    assertion(once(palavra([c,o,n,t,a], _))).

:- end_tests(palavras).


:- begin_tests(flexao).

test(plural_simples) :-
    assertion(flexao([c,a,s,a,s], [c,a,s,a], plural)).

% Cada terminação de plural sabe recompor o singular.
test(plurais_com_terminacao_propria) :-
    assertion(flexao([l,u,z,e,s], [l,u,z], plural)),
    assertion(flexao([t,r,e,n,s], [t,r,e,m], plural)),
    assertion(flexao([a,z,u,i,s], [a,z,u,l], plural)),
    assertion(flexao([l,e,o,e,s], [l,e,a,o], plural)).

test(verbos_regulares) :-
    assertion(flexao([f,a,l,e,i], [f,a,l,a,r], verbo)),
    assertion(flexao([c,o,m,e,u], [c,o,m,e,r], verbo)),
    assertion(flexao([p,e,n,s,a], [p,e,n,s,a,r], verbo)).

% A grafia do radical muda antes de algumas terminações.
test(grafia_do_radical) :-
    assertion(flexao([f,u,j,a,m], [f,u,g,i,r], verbo)),   % g vira j
    assertion(flexao([c,a,i,a,m], [c,a,i,r], verbo)).     % entra um i

test(verbo_irregular) :-
    assertion(flexao([p,o,s,s,o], [p,o,d,e,r], verbo)).

% Uma palavra pode ter mais de uma análise: "casas" é plural de casa e
% também "tu casas", de casar.
test(varias_analises, true(Analises == [[c,a,s,a]-plural, [c,a,s,a,r]-verbo])) :-
    findall(Base-Tipo, flexao([c,a,s,a,s], Base, Tipo), Analises).

% "livro" parece "eu livro" (de livrar), mas tem plural: é substantivo.
test(substantivo_em_o, fail) :-
    flexao([l,i,v,r,o], _, verbo).

test(infinitivo_nao_e_flexao, fail) :-
    flexao([l,a,t,i,r], _, _).

:- end_tests(flexao).


:- begin_tests(partidas).

% O segredo não sai pela interface: os testes o leem direto do fato
% partida/3, que não é exportado (por isso o prefixo jogo:).
segredo_texto(Id, Texto) :-
    jogo:partida(Id, Segredo, _),
    once(resposta(Segredo, Texto)).

% Dez palavras válidas diferentes do segredo, para perder de propósito.
erradas(Id, Dez) :-
    segredo_texto(Id, Segredo),
    exclude(==(Segredo),
            ["terra", "pouco", "lindo", "chuva", "bicho", "porta", "folha",
             "nuvem", "peixe", "praia", "festa"],
            Erradas),
    length(Dez, 10),
    append(Dez, _, Erradas).

test(codigos_diferentes_e_aleatorios) :-
    novo_jogo(A),
    novo_jogo(B),
    assertion(A \== B),
    assertion(atom_length(A, 36)).

test(acertar_encerra_a_partida, true(Contagem == [5, 0, 0])) :-
    novo_jogo(Id),
    segredo_texto(Id, Texto),
    jogar(Id, Texto, [_, Contagem]),
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
    erradas(Id, Dez),
    segredo_texto(Id, Segredo),
    forall(member(P, Dez), jogar(Id, P, [_, _])),
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
test(id_como_string, true(Contagem == [5, 0, 0])) :-
    novo_jogo(Id),
    atom_string(Id, IdTexto),
    segredo_texto(Id, Texto),
    jogar(IdTexto, Texto, [_, Contagem]).

:- end_tests(partidas).
