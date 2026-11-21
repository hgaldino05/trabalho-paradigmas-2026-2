module Api exposing
    ( Erro(..)
    , mensagem
    , novo
    , revelar
    , tentativa
    )

{-| Comunicação com o backend (FastAPI + Prolog).

As funções deste módulo devolvem um `Cmd msg`: uma DESCRIÇÃO da requisição.
Quem a executa é o runtime do Elm, que depois chama o `update` com a
mensagem indicada, carregando um `Result Erro a`.

-}

import Http
import Jogo exposing (Cor(..), Retorno)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


{-| Por que uma requisição não deu certo.

  - `Recusada`: o servidor entendeu o pedido e disse não (status 422), por
    exemplo porque a palavra não está na lista.
  - `Falha`: algo deu errado no caminho (servidor fora do ar, rede, resposta
    estranha).

Com um `String` só, o `update` teria que olhar o TEXTO da mensagem para
saber se deve abrir o modal de palavra desconhecida. Com um custom type, o
`case` decide pela forma do valor, e o compilador confere os dois casos.

-}
type Erro
    = Recusada String
    | Falha String


mensagem : Erro -> String
mensagem erro =
    case erro of
        Recusada texto ->
            texto

        Falha texto ->
            texto



-- REQUISIÇÕES


novo : (Result Erro String -> msg) -> Cmd msg
novo toMsg =
    Http.post
        { url = "/api/novo"
        , body = Http.emptyBody
        , expect = expectJson toMsg (Decode.field "jogo" Decode.string)
        }


tentativa : String -> String -> (Result Erro Retorno -> msg) -> Cmd msg
tentativa jogo palavra toMsg =
    Http.post
        { url = "/api/tentativa"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "jogo", Encode.string jogo )
                    , ( "palavra", Encode.string palavra )
                    ]
                )
        , expect = expectJson toMsg retornoDecoder
        }


revelar : String -> (Result Erro String -> msg) -> Cmd msg
revelar jogo toMsg =
    Http.post
        { url = "/api/revelar"
        , body = Http.jsonBody (Encode.object [ ( "jogo", Encode.string jogo ) ])
        , expect = expectJson toMsg (Decode.field "palavra" Decode.string)
        }



-- JSON


retornoDecoder : Decoder Retorno
retornoDecoder =
    Decode.map2 Retorno
        (Decode.field "palavra" Decode.string)
        (Decode.field "cores" (Decode.list corDecoder))


{-| A API manda as cores como texto ("certa", "presente", "ausente"). Um
texto diferente faz o decoder FALHAR, em vez de virar uma cor qualquer.
-}
corDecoder : Decoder Cor
corDecoder =
    Decode.string
        |> Decode.andThen
            (\texto ->
                case texto of
                    "certa" ->
                        Decode.succeed Certa

                    "presente" ->
                        Decode.succeed Presente

                    "ausente" ->
                        Decode.succeed Ausente

                    _ ->
                        Decode.fail ("cor desconhecida: " ++ texto)
            )



-- TRATAMENTO DE ERROS
--
-- `Http.expectJson` descarta o corpo das respostas de erro. Nosso backend
-- manda uma mensagem útil em `{"detail": "..."}` (por exemplo, "Essa palavra
-- não está na lista."), então usamos nossa própria versão.


expectJson : (Result Erro a -> msg) -> Decoder a -> Http.Expect msg
expectJson toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body
                        |> Result.mapError (\_ -> Falha "Resposta inesperada do servidor.")

                Http.BadStatus_ metadata body ->
                    if metadata.statusCode == 422 then
                        Err (Recusada (errorDetail metadata.statusCode body))

                    else
                        Err (Falha (errorDetail metadata.statusCode body))

                Http.BadUrl_ url ->
                    Err (Falha ("URL inválida: " ++ url))

                Http.Timeout_ ->
                    Err (Falha "O servidor demorou demais para responder.")

                Http.NetworkError_ ->
                    Err (Falha "Não foi possível falar com o servidor. O backend está rodando?")


errorDetail : Int -> String -> String
errorDetail status body =
    case Decode.decodeString (Decode.field "detail" Decode.string) body of
        Ok detail ->
            detail

        Err _ ->
            "Erro no servidor (código " ++ String.fromInt status ++ ")."
