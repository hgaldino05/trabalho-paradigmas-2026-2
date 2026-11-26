module Jogo exposing
    ( Contagem
    , Estado(..)
    , Jogo
    , Marca(..)
    , Retorno
    , Tentativa
    , acertou
    , alternarMarca
    , apagar
    , conferir
    , digitar
    , jaTentada
    , maxTentativas
    , novo
    , recusar
    , registrar
    , revelar
    , tamanhoPalavra
    )

{-| Domínio do jogo: tipos e transições de estado.

Este módulo é PURO: não faz HTTP nem HTML. Quem confere uma tentativa é o
Prolog (pelo backend). Aqui só guardamos o que já aconteceu e controlamos o
que o jogador pode fazer em cada momento.

A regra do jogo: a cada tentativa, o jogador só fica sabendo QUANTAS letras
estão no lugar certo, quantas estão em outro lugar e quantas não estão na
palavra. Nunca quais. Por isso não existe aqui uma cor por letra: o
navegador nem recebe essa informação.

-}


tamanhoPalavra : Int
tamanhoPalavra =
    5


maxTentativas : Int
maxTentativas =
    10


{-| Quantas letras da tentativa caíram em cada cor: verde (`certas`),
amarela (`presentes`) e vermelha (`ausentes`). As três somam sempre 5.
-}
type alias Contagem =
    { certas : Int
    , presentes : Int
    , ausentes : Int
    }


{-| O que o servidor responde a uma tentativa: a palavra do jeito que é
escrita (com acentos) e a contagem das cores.
-}
type alias Retorno =
    { palavra : String
    , contagem : Contagem
    }


{-| Uma tentativa já conferida. `digitada` é o que o jogador digitou (sem
acentos, usado para recusar palavra repetida); `exibida` é como a palavra
aparece no tabuleiro.

`marcas` são as anotações do próprio jogador, uma por letra (veja `Marca`).
Elas não vêm do servidor e não mudam nada no jogo: servem para o jogador
organizar o raciocínio.

-}
type alias Tentativa =
    { digitada : String
    , exibida : String
    , contagem : Contagem
    , marcas : List (Maybe Marca)
    }


{-| A cor que o jogador escolheu para uma letra de uma tentativa, clicando
nela: o palpite dele sobre aquela letra, não uma informação do jogo.
-}
type Marca
    = Verde
    | Amarela
    | Vermelha


{-| Acertou quando as 5 letras estão no lugar certo.
-}
acertou : Contagem -> Bool
acertou contagem =
    contagem.certas == tamanhoPalavra


{-| Em que ponto da partida estamos.

Um único custom type no lugar de vários `Bool` (`venceu`, `perdeu`,
`esperando`...): assim não existe um estado "venceu e perdeu ao mesmo
tempo", e cada função trata exatamente os casos em que faz sentido.

  - `Digitando atual`: o jogador está escrevendo a próxima palavra.
  - `Conferindo palavra`: a palavra foi enviada; esperamos o servidor.
  - `Venceu`: acertou.
  - `Perdeu segredo`: acabaram as tentativas. O segredo começa como
    `Nothing` e vira `Just` quando o servidor o revela.

-}
type Estado
    = Digitando String
    | Conferindo String
    | Venceu
    | Perdeu (Maybe String)


{-| `id` é o código da partida, sorteado pelo servidor. Ele não revela nada
sobre a palavra secreta, que só o servidor conhece.
-}
type alias Jogo =
    { id : String
    , tentativas : List Tentativa
    , estado : Estado
    }


novo : String -> Jogo
novo id =
    { id = id, tentativas = [], estado = Digitando "" }



-- AÇÕES DO JOGADOR


digitar : Char -> Jogo -> Jogo
digitar letra jogo =
    case jogo.estado of
        Digitando atual ->
            if Char.isAlpha letra && String.length atual < tamanhoPalavra then
                { jogo | estado = Digitando (atual ++ String.fromChar (Char.toLower letra)) }

            else
                jogo

        _ ->
            jogo


apagar : Jogo -> Jogo
apagar jogo =
    case jogo.estado of
        Digitando atual ->
            { jogo | estado = Digitando (String.dropRight 1 atual) }

        _ ->
            jogo


{-| Se a palavra está completa, passa para `Conferindo` e devolve a palavra
a enviar ao servidor. Se não está, devolve `Nothing`, e não há o que enviar.
-}
conferir : Jogo -> Maybe ( Jogo, String )
conferir jogo =
    case jogo.estado of
        Digitando atual ->
            if String.length atual == tamanhoPalavra then
                Just ( { jogo | estado = Conferindo atual }, atual )

            else
                Nothing

        _ ->
            Nothing



-- RESPOSTAS DO SERVIDOR


{-| Registra o retorno da palavra que estava sendo conferida e decide se o
jogo continua, foi ganho ou foi perdido.
-}
registrar : Retorno -> Jogo -> Jogo
registrar retorno jogo =
    case jogo.estado of
        Conferindo digitada ->
            let
                tentativas =
                    jogo.tentativas
                        ++ [ { digitada = digitada
                             , exibida = retorno.palavra
                             , contagem = retorno.contagem
                             , marcas = List.repeat tamanhoPalavra Nothing
                             }
                           ]

                estado =
                    if acertou retorno.contagem then
                        Venceu

                    else if List.length tentativas >= maxTentativas then
                        Perdeu Nothing

                    else
                        Digitando ""
            in
            { jogo | tentativas = tentativas, estado = estado }

        _ ->
            jogo


{-| A palavra já foi tentada nesta partida? A mesma palavra não vale duas
vezes. O servidor também confere isso (jogo.pl), mas conferir aqui evita
uma ida ao servidor e deixa o aviso aparecer na hora.
-}
jaTentada : String -> Jogo -> Bool
jaTentada palavra jogo =
    List.any (\t -> t.digitada == palavra) jogo.tentativas


{-| O servidor recusou a palavra (não está na lista, ou houve erro de rede):
o jogador volta a editar a mesma palavra.
-}
recusar : Jogo -> Jogo
recusar jogo =
    case jogo.estado of
        Conferindo atual ->
            { jogo | estado = Digitando atual }

        _ ->
            jogo


revelar : String -> Jogo -> Jogo
revelar segredo jogo =
    case jogo.estado of
        Perdeu _ ->
            { jogo | estado = Perdeu (Just segredo) }

        _ ->
            jogo



-- ANOTAÇÕES DO JOGADOR


{-| O jogador clicou na letra `posicao` da tentativa `indice`: a marca dela
passa para a próxima da ordem verde, amarela, vermelha, sem marca.
-}
alternarMarca : Int -> Int -> Jogo -> Jogo
alternarMarca indice posicao jogo =
    let
        naPosicao i transforma lista =
            List.indexedMap
                (\j x ->
                    if j == i then
                        transforma x

                    else
                        x
                )
                lista
    in
    { jogo
        | tentativas =
            naPosicao indice
                (\tentativa -> { tentativa | marcas = naPosicao posicao proximaMarca tentativa.marcas })
                jogo.tentativas
    }


proximaMarca : Maybe Marca -> Maybe Marca
proximaMarca marca =
    case marca of
        Nothing ->
            Just Verde

        Just Verde ->
            Just Amarela

        Just Amarela ->
            Just Vermelha

        Just Vermelha ->
            Nothing
