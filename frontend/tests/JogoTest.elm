module JogoTest exposing (suite)

{-| Testes do domínio do jogo (`Jogo.elm`).

Como `Jogo.elm` é puro (não faz HTTP nem HTML), dá para JOGAR partidas
inteiras aqui sem navegador e sem servidor: o teste faz o papel do jogador
(digitar, apagar, conferir) e do servidor (responder com uma contagem).

Rodar: `cd frontend && npx elm-test`.

-}

import Expect
import Jogo exposing (Contagem, Estado(..), Jogo, Marca(..))
import Test exposing (Test, describe, test)



-- AJUDANTES: o jogador e o servidor de mentira


{-| O jogador digita uma palavra, letra por letra.
-}
digitarPalavra : String -> Jogo -> Jogo
digitarPalavra palavra jogo =
    String.foldl Jogo.digitar jogo palavra


{-| O jogador digita uma palavra e aperta Enter; o "servidor" responde com
a contagem dada. Se o jogo não deixar conferir, nada muda.
-}
jogar : String -> Contagem -> Jogo -> Jogo
jogar palavra resposta jogo =
    case Jogo.conferir (digitarPalavra palavra jogo) of
        Just ( conferindo, _ ) ->
            Jogo.registrar { palavra = palavra, contagem = resposta } conferindo

        Nothing ->
            jogo


{-| Joga várias palavras em sequência, todas com a mesma contagem.
-}
jogarTodas : List String -> Contagem -> Jogo -> Jogo
jogarTodas palavras resposta jogo =
    List.foldl (\p j -> jogar p resposta j) jogo palavras


contagem : Int -> Int -> Int -> Contagem
contagem certas presentes ausentes =
    { certas = certas, presentes = presentes, ausentes = ausentes }


tudoCerto : Contagem
tudoCerto =
    contagem 5 0 0


nadaCerto : Contagem
nadaCerto =
    contagem 0 0 5


inicio : Jogo
inicio =
    Jogo.novo "partida-de-teste"


{-| Dez palavras diferentes, para perder uma partida.
-}
dezErradas : List String
dezErradas =
    [ "terra", "pouco", "lindo", "chuva", "bicho", "porta", "folha", "nuvem", "peixe", "praia" ]


marcasDa : Int -> Jogo -> List (Maybe Marca)
marcasDa indice jogo =
    jogo.tentativas
        |> List.drop indice
        |> List.head
        |> Maybe.map .marcas
        |> Maybe.withDefault []



-- TESTES


suite : Test
suite =
    describe "Jogo"
        [ partidas
        , digitacao
        , respostasDoServidor
        , palavraRepetida
        , anotacoes
        ]


partidas : Test
partidas =
    describe "partidas completas"
        [ test "acertar na primeira tentativa ganha a partida" <|
            \_ ->
                (jogar "termo" tudoCerto inicio).estado
                    |> Expect.equal Venceu
        , test "acertar depois de errar também ganha, e guarda as tentativas" <|
            \_ ->
                let
                    fim =
                        inicio
                            |> jogar "terra" (contagem 3 0 2)
                            |> jogar "tempo" (contagem 3 1 1)
                            |> jogar "termo" tudoCerto
                in
                Expect.all
                    [ \j -> j.estado |> Expect.equal Venceu
                    , \j -> List.map .digitada j.tentativas |> Expect.equal [ "terra", "tempo", "termo" ]
                    , \j -> List.map .contagem j.tentativas |> Expect.equal [ contagem 3 0 2, contagem 3 1 1, tudoCerto ]
                    ]
                    fim
        , test "errar as 10 tentativas perde a partida, ainda sem o segredo" <|
            \_ ->
                (jogarTodas dezErradas nadaCerto inicio).estado
                    |> Expect.equal (Perdeu Nothing)
        , test "com 9 erros a partida continua" <|
            \_ ->
                (jogarTodas (List.take 9 dezErradas) nadaCerto inicio).estado
                    |> Expect.equal (Digitando "")
        , test "acertar na 10ª tentativa ainda é vitória" <|
            \_ ->
                inicio
                    |> jogarTodas (List.take 9 dezErradas) nadaCerto
                    |> jogar "termo" tudoCerto
                    |> .estado
                    |> Expect.equal Venceu
        , test "depois de perder, o segredo revelado aparece" <|
            \_ ->
                inicio
                    |> jogarTodas dezErradas nadaCerto
                    |> Jogo.revelar "termo"
                    |> .estado
                    |> Expect.equal (Perdeu (Just "termo"))
        , test "não dá para jogar depois de ganhar" <|
            \_ ->
                let
                    ganho =
                        jogar "termo" tudoCerto inicio
                in
                jogar "terra" nadaCerto ganho
                    |> Expect.equal ganho
        , test "não dá para jogar depois de perder" <|
            \_ ->
                let
                    perdido =
                        jogarTodas dezErradas nadaCerto inicio
                in
                Jogo.conferir (digitarPalavra "termo" perdido)
                    |> Expect.equal Nothing
        ]


digitacao : Test
digitacao =
    describe "digitação"
        [ test "letras viram minúsculas" <|
            \_ ->
                (digitarPalavra "TeRmO" inicio).estado
                    |> Expect.equal (Digitando "termo")
        , test "a sexta letra é ignorada" <|
            \_ ->
                (digitarPalavra "termos" inicio).estado
                    |> Expect.equal (Digitando "termo")
        , test "números e símbolos são ignorados" <|
            \_ ->
                (digitarPalavra "t3r-m!o" inicio).estado
                    |> Expect.equal (Digitando "trmo")
        , test "apagar tira a última letra" <|
            \_ ->
                (digitarPalavra "terra" inicio |> Jogo.apagar).estado
                    |> Expect.equal (Digitando "terr")
        , test "apagar sem letras não faz nada" <|
            \_ ->
                (Jogo.apagar inicio).estado
                    |> Expect.equal (Digitando "")
        , test "Enter com menos de 5 letras não envia nada" <|
            \_ ->
                Jogo.conferir (digitarPalavra "ter" inicio)
                    |> Expect.equal Nothing
        , test "Enter com 5 letras envia a palavra e espera o servidor" <|
            \_ ->
                Jogo.conferir (digitarPalavra "terra" inicio)
                    |> Maybe.map (\( j, enviada ) -> ( j.estado, enviada ))
                    |> Expect.equal (Just ( Conferindo "terra", "terra" ))
        , test "enquanto o servidor confere, o teclado não muda a palavra" <|
            \_ ->
                case Jogo.conferir (digitarPalavra "terra" inicio) of
                    Just ( conferindo, _ ) ->
                        (conferindo |> Jogo.digitar 'x' |> Jogo.apagar).estado
                            |> Expect.equal (Conferindo "terra")

                    Nothing ->
                        Expect.fail "a palavra deveria ter sido enviada"
        ]


respostasDoServidor : Test
respostasDoServidor =
    describe "respostas do servidor"
        [ test "a tentativa guarda a palavra como o servidor a escreve (com acento)" <|
            \_ ->
                case Jogo.conferir (digitarPalavra "radio" inicio) of
                    Just ( conferindo, _ ) ->
                        Jogo.registrar { palavra = "rádio", contagem = contagem 1 2 2 } conferindo
                            |> .tentativas
                            |> List.map (\t -> ( t.digitada, t.exibida ))
                            |> Expect.equal [ ( "radio", "rádio" ) ]

                    Nothing ->
                        Expect.fail "a palavra deveria ter sido enviada"
        , test "palavra recusada volta para a edição, sem gastar tentativa" <|
            \_ ->
                case Jogo.conferir (digitarPalavra "xyzwq" inicio) of
                    Just ( conferindo, _ ) ->
                        Jogo.recusar conferindo
                            |> Expect.all
                                [ \j -> j.estado |> Expect.equal (Digitando "xyzwq")
                                , \j -> j.tentativas |> Expect.equal []
                                ]

                    Nothing ->
                        Expect.fail "a palavra deveria ter sido enviada"
        , test "resposta que chega fora de hora é ignorada" <|
            \_ ->
                -- O jogador não enviou nada (ou começou um jogo novo):
                -- registrar não tem palavra em Conferindo para associar.
                Jogo.registrar { palavra = "termo", contagem = tudoCerto } inicio
                    |> Expect.equal inicio
        , test "segredo que chega no meio da partida é ignorado" <|
            \_ ->
                Jogo.revelar "termo" inicio
                    |> Expect.equal inicio
        , test "acertou só com as 5 letras no lugar certo" <|
            \_ ->
                List.map Jogo.acertou [ tudoCerto, contagem 4 1 0, contagem 4 0 1 ]
                    |> Expect.equal [ True, False, False ]
        ]


palavraRepetida : Test
palavraRepetida =
    describe "palavra repetida"
        [ test "uma palavra já tentada é reconhecida" <|
            \_ ->
                jogar "terra" (contagem 3 0 2) inicio
                    |> Jogo.jaTentada "terra"
                    |> Expect.equal True
        , test "uma palavra nova não é" <|
            \_ ->
                jogar "terra" (contagem 3 0 2) inicio
                    |> Jogo.jaTentada "pouco"
                    |> Expect.equal False
        ]


anotacoes : Test
anotacoes =
    let
        umaTentativa =
            jogar "terra" (contagem 3 0 2) inicio

        clicar vezes jogo =
            List.foldl (\_ j -> Jogo.alternarMarca 0 1 j) jogo (List.range 1 vezes)
    in
    describe "anotações do jogador"
        [ test "uma tentativa nova começa sem nenhuma anotação" <|
            \_ ->
                marcasDa 0 umaTentativa
                    |> Expect.equal (List.repeat 5 Nothing)
        , test "cada clique passa para a próxima cor: verde, amarela, vermelha, sem cor" <|
            \_ ->
                List.map (\n -> marcasDa 0 (clicar n umaTentativa) |> List.drop 1 |> List.head) [ 1, 2, 3, 4 ]
                    |> Expect.equal [ Just (Just Verde), Just (Just Amarela), Just (Just Vermelha), Just Nothing ]
        , test "o clique só muda a letra clicada" <|
            \_ ->
                marcasDa 0 (clicar 1 umaTentativa)
                    |> Expect.equal [ Nothing, Just Verde, Nothing, Nothing, Nothing ]
        , test "o clique só muda a tentativa clicada" <|
            \_ ->
                umaTentativa
                    |> jogar "pouco" (contagem 0 1 4)
                    |> Jogo.alternarMarca 1 4
                    |> (\j -> ( marcasDa 0 j, marcasDa 1 j ))
                    |> Expect.equal ( List.repeat 5 Nothing, [ Nothing, Nothing, Nothing, Nothing, Just Verde ] )
        , test "anotar não muda a contagem nem o estado da partida" <|
            \_ ->
                clicar 3 umaTentativa
                    |> Expect.all
                        [ \j -> List.map .contagem j.tentativas |> Expect.equal [ contagem 3 0 2 ]
                        , \j -> j.estado |> Expect.equal umaTentativa.estado
                        ]
        , test "clicar numa tentativa que não existe não muda nada" <|
            \_ ->
                Jogo.alternarMarca 7 0 umaTentativa
                    |> Expect.equal umaTentativa
        ]
