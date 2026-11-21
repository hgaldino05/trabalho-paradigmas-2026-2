module Jogo exposing
    ( Cor(..)
    , Estado(..)
    , Jogo
    , Retorno
    , Tentativa
    , apagar
    , conferir
    , coresDoTeclado
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

Este módulo é PURO: não faz HTTP nem HTML. Quem decide as cores de uma
tentativa é o Prolog (pelo backend). Aqui só guardamos o que já aconteceu e
controlamos o que o jogador pode fazer em cada momento.

-}

import Dict exposing (Dict)


tamanhoPalavra : Int
tamanhoPalavra =
    5


maxTentativas : Int
maxTentativas =
    6


type Cor
    = Certa
    | Presente
    | Ausente


{-| O que o servidor responde a uma tentativa: a palavra do jeito que é
escrita (com acentos) e a cor de cada letra.
-}
type alias Retorno =
    { palavra : String
    , cores : List Cor
    }


{-| Uma tentativa já conferida. `digitada` é o que o jogador digitou (sem
acentos, usado no teclado virtual); `exibida` é como a palavra aparece no
tabuleiro.
-}
type alias Tentativa =
    { digitada : String
    , exibida : String
    , cores : List Cor
    }


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



-- TECLADO


{-| A cor que cada tecla do teclado virtual deve ter: a "mais forte" que a
letra já recebeu (Certa > Presente > Ausente). Letras nunca usadas ficam
fora do dicionário. Usada pelo teclado virtual (`viewTeclado`, em Main.elm).
-}
coresDoTeclado : Jogo -> Dict Char Cor
coresDoTeclado jogo =
    let
        letrasComCor tentativa =
            List.map2 Tuple.pair (String.toList tentativa.digitada) tentativa.cores
    in
    jogo.tentativas
        |> List.concatMap letrasComCor
        |> List.foldl (\( letra, cor ) -> Dict.update letra (Just << maisForte cor)) Dict.empty


maisForte : Cor -> Maybe Cor -> Cor
maisForte nova anterior =
    case anterior of
        Nothing ->
            nova

        Just velha ->
            if forca nova > forca velha then
                nova

            else
                velha


forca : Cor -> Int
forca cor =
    case cor of
        Certa ->
            3

        Presente ->
            2

        Ausente ->
            1
