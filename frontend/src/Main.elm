module Main exposing (main)

{-| Interface do jogo, na Arquitetura Elm (Model, Msg, update, view).

As regras de estado ficam em Jogo.elm, e o HTTP em Api.elm. Aqui ficam o
Model da tela, o teclado e o desenho.

TODO (grupo):

  - modo difícil e modo adversário (precisam de rotas novas no backend).

-}

import Api
import Browser
import Browser.Events
import Dict
import Html exposing (Html, aside, button, div, footer, h1, h2, header, input, label, li, main_, p, span, strong, text, ul)
import Html.Attributes exposing (attribute, checked, class, classList, type_, value)
import Html.Events exposing (onCheck, onClick, preventDefaultOn)
import Html.Keyed
import Jogo exposing (Cor(..), Estado(..), Jogo, Retorno, Tentativa)
import Json.Decode as Decode exposing (Decoder)
import Process
import Task


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


{-| Dados que o main.js entrega na inicialização.
-}
type alias Flags =
    { darkTheme : Bool
    }


{-| O que aparece na tela. Enquanto o servidor não sorteia a palavra, não
existe `Jogo`, e o tipo deixa isso explícito (em vez de um `Jogo` com id
falso).
-}
type Tela
    = Iniciando
    | EmJogo Jogo
    | SemServidor String


{-| O toast vermelho de palavra recusada.

Cada toast tem um `id` diferente. Quando um toast é criado, pedimos ao
runtime para nos avisar daqui a alguns segundos (`ToastExpirou id`). Se nesse
meio-tempo o jogador errou de novo, o toast na tela já é outro, com outro
`id`, e o aviso atrasado do primeiro é ignorado.

Para sumir com animação, o toast passa por duas fases. Ao expirar (ou ao ser
fechado), ele vira `Saindo`: continua na tela, mas com a animação de saída.
Só depois de `duracaoDaSaida` ele é tirado do Model de vez.

-}
type alias Toast =
    { id : Int
    , palavra : String
    , motivo : Motivo
    , fase : FaseDoToast
    }


{-| Por que a palavra foi recusada.
-}
type Motivo
    = ForaDaLista
    | JaTentada


type FaseDoToast
    = Visivel
    | Saindo


{-| `toast` é o toast de palavra desconhecida, se houver um na tela.
`aviso` é para os outros erros (rede, servidor), que aparecem numa faixa
acima do tabuleiro. `proximoToast` é o `id` do próximo toast.
-}
type alias Model =
    { tela : Tela
    , toast : Maybe Toast
    , proximoToast : Int
    , aviso : Maybe String
    , darkTheme : Bool
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { tela = Iniciando
      , toast = Nothing
      , proximoToast = 0
      , aviso = Nothing
      , darkTheme = flags.darkTheme
      }
    , Api.novo NovoJogoRecebido
    )


duracaoDoToast : Float
duracaoDoToast =
    2500


{-| Tem que ser igual à duração da animação `subir-toast`, em style.css.
-}
duracaoDaSaida : Float
duracaoDaSaida =
    250



-- UPDATE


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


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.tela ) of
        ( NovoJogoPedido, _ ) ->
            ( { model | tela = Iniciando, toast = Nothing, aviso = Nothing }
            , Api.novo NovoJogoRecebido
            )

        ( NovoJogoRecebido (Ok id), _ ) ->
            ( { model | tela = EmJogo (Jogo.novo id) }, Cmd.none )

        ( NovoJogoRecebido (Err erro), _ ) ->
            ( { model | tela = SemServidor (Api.mensagem erro) }, Cmd.none )

        ( LetraDigitada letra, EmJogo jogo ) ->
            ( { model | tela = EmJogo (Jogo.digitar letra jogo), aviso = Nothing }, Cmd.none )

        ( Apagou, EmJogo jogo ) ->
            ( { model | tela = EmJogo (Jogo.apagar jogo), aviso = Nothing }, Cmd.none )

        ( Enviou, EmJogo jogo ) ->
            case Jogo.conferir jogo of
                Just ( conferindo, palavra ) ->
                    if Jogo.jaTentada palavra jogo then
                        mostrarToast palavra JaTentada { model | aviso = Nothing }

                    else
                        ( { model | tela = EmJogo conferindo, aviso = Nothing }
                        , Api.tentativa jogo.id palavra RetornoRecebido
                        )

                Nothing ->
                    case jogo.estado of
                        Digitando _ ->
                            ( { model | aviso = Just "A palavra precisa ter 5 letras." }, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

        ( RetornoRecebido (Ok retorno), EmJogo jogo ) ->
            let
                depois =
                    Jogo.registrar retorno jogo

                -- Perdeu agora: pedimos ao servidor a palavra secreta.
                comando =
                    if depois.estado == Perdeu Nothing then
                        Api.revelar depois.id SegredoRecebido

                    else
                        Cmd.none
            in
            ( { model | tela = EmJogo depois }, comando )

        -- 422: a palavra não está na lista.
        ( RetornoRecebido (Err (Api.Recusada _)), EmJogo jogo ) ->
            mostrarToast (palavraConferida jogo) ForaDaLista { model | tela = EmJogo (Jogo.recusar jogo) }

        ( RetornoRecebido (Err (Api.Falha erro)), EmJogo jogo ) ->
            ( { model | tela = EmJogo (Jogo.recusar jogo), aviso = Just erro }, Cmd.none )

        ( SegredoRecebido (Ok segredo), EmJogo jogo ) ->
            ( { model | tela = EmJogo (Jogo.revelar segredo jogo) }, Cmd.none )

        ( SegredoRecebido (Err erro), _ ) ->
            ( { model | aviso = Just (Api.mensagem erro) }, Cmd.none )

        -- ✕ ou Esc: começa a saída do toast que está na tela.
        ( ToastFechado, _ ) ->
            case model.toast of
                Just toast ->
                    comecarSaida toast model

                Nothing ->
                    ( model, Cmd.none )

        -- Só mexe no toast se ele ainda for o mesmo que agendou o aviso.
        ( ToastExpirou id, _ ) ->
            case model.toast of
                Just toast ->
                    if toast.id == id then
                        comecarSaida toast model

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        ( ToastRemovido id, _ ) ->
            if Maybe.map .id model.toast == Just id then
                ( { model | toast = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        ( AvisoFechado, _ ) ->
            ( { model | aviso = Nothing }, Cmd.none )

        ( TemaTrocado escuro, _ ) ->
            ( { model | darkTheme = escuro }, Cmd.none )

        -- Mensagens que não fazem sentido na tela atual (por exemplo, uma
        -- tecla enquanto a palavra ainda está sendo sorteada) são ignoradas.
        _ ->
            ( model, Cmd.none )


{-| Passa o toast para a fase `Saindo` e agenda a remoção para quando a
animação de saída terminar. Um toast que já está saindo fica como está.
-}
comecarSaida : Toast -> Model -> ( Model, Cmd Msg )
comecarSaida toast model =
    case toast.fase of
        Visivel ->
            ( { model | toast = Just { toast | fase = Saindo } }
            , Process.sleep duracaoDaSaida |> Task.perform (\_ -> ToastRemovido toast.id)
            )

        Saindo ->
            ( model, Cmd.none )


{-| Mostra o toast e agenda o fim dele: `Process.sleep` é um efeito, então
também vira um comando. A linha atual treme porque a chave dela muda junto
com `proximoToast` (veja `viewTabuleiro`).
-}
mostrarToast : String -> Motivo -> Model -> ( Model, Cmd Msg )
mostrarToast palavra motivo model =
    let
        id =
            model.proximoToast
    in
    ( { model
        | toast = Just { id = id, palavra = palavra, motivo = motivo, fase = Visivel }
        , proximoToast = id + 1
      }
    , Process.sleep duracaoDoToast |> Task.perform (\_ -> ToastExpirou id)
    )


palavraConferida : Jogo -> String
palavraConferida jogo =
    case jogo.estado of
        Conferindo palavra ->
            palavra

        _ ->
            ""



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onKeyDown teclaDecoder


{-| Para teclas que não interessam, o decoder FALHA, e nenhuma mensagem é
gerada. Com Ctrl ou Cmd apertado também falha, para não atrapalhar atalhos
do navegador (Ctrl+R, por exemplo).
-}
teclaDecoder : Decoder Msg
teclaDecoder =
    Decode.map3 (\tecla ctrl meta -> ( tecla, ctrl || meta ))
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "metaKey" Decode.bool)
        |> Decode.andThen teclaParaMsg


teclaParaMsg : ( String, Bool ) -> Decoder Msg
teclaParaMsg ( tecla, comAtalho ) =
    case ( tecla, comAtalho ) of
        ( _, True ) ->
            Decode.fail "atalho"

        ( "Enter", _ ) ->
            Decode.succeed Enviou

        ( "Backspace", _ ) ->
            Decode.succeed Apagou

        ( "Escape", _ ) ->
            Decode.succeed ToastFechado

        _ ->
            case String.uncons tecla of
                Just ( letra, "" ) ->
                    if Char.isAlpha letra then
                        Decode.succeed (LetraDigitada letra)

                    else
                        Decode.fail "tecla ignorada"

                _ ->
                    Decode.fail "tecla ignorada"



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "app" ]
        [ header [ class "app-header" ]
            [ viewLogo
            , viewTema model
            ]
        , main_ [ class "app-main" ] (viewTela model)
        , footer [ class "app-footer" ]
            [ text "Digite ou toque nas teclas. "
            , kbd [] [ text "Enter" ]
            , text " confere, "
            , kbd [] [ text "⌫" ]
            , text " apaga."
            ]
        , viewToast model.toast
        ]


{-| O nome do jogo, Telmo (Termo + Elm), desenhado como uma linha do
tabuleiro. As letras de "elm" ganham uma cor só delas, que não é nenhuma das
cores do retorno (verde, amarelo, cinza), para não parecer uma letra conferida.
-}
viewLogo : Html msg
viewLogo =
    let
        casa ( letra, destaque ) =
            span
                [ class "logo-tile"
                , classList [ ( "logo-tile--elm", destaque ) ]
                ]
                [ text letra ]
    in
    h1 [ class "logo", attribute "aria-label" "Telmo" ]
        (List.map casa
            [ ( "T", False ), ( "E", True ), ( "L", True ), ( "M", True ), ( "O", False ) ]
        )


viewTela : Model -> List (Html Msg)
viewTela model =
    case model.tela of
        Iniciando ->
            [ div [ class "loading-screen" ]
                [ span [ class "loading loading-dots loading-lg" ] []
                , p [] [ text "Sorteando a palavra..." ]
                ]
            ]

        SemServidor erro ->
            [ div [ class "message message--error" ] [ text erro ]
            , button [ class "btn-novo", onClick NovoJogoPedido ] [ text "Tentar de novo" ]
            ]

        EmJogo jogo ->
            [ viewStatus jogo
            , viewAviso model.aviso
            , div [ class "mesa" ]
                [ viewTabuleiro
                    { tremer = model.toast /= Nothing, chaveAtual = model.proximoToast }
                    jogo
                , case jogo.estado of
                    Venceu ->
                        viewFim jogo

                    Perdeu _ ->
                        viewFim jogo

                    _ ->
                        viewTeclado jogo
                , viewRegras
                ]
            ]


viewStatus : Jogo -> Html msg
viewStatus jogo =
    let
        feitas =
            List.length jogo.tentativas

        texto =
            case jogo.estado of
                Venceu ->
                    "Acertou!"

                Perdeu _ ->
                    "Fim de jogo"

                _ ->
                    "Tentativa "
                        ++ String.fromInt (feitas + 1)
                        ++ " de "
                        ++ String.fromInt Jogo.maxTentativas
    in
    p [ class "game-status" ] [ text texto ]


viewAviso : Maybe String -> Html Msg
viewAviso aviso =
    case aviso of
        Just texto ->
            div [ class "message message--error" ]
                [ span [] [ text texto ]
                , button [ class "message-close", onClick AvisoFechado ] [ text "✕" ]
                ]

        Nothing ->
            text ""


{-| `tremer` faz a linha atual tremer enquanto o toast de palavra recusada
está na tela.

O tabuleiro é um nó com CHAVES (`Html.Keyed`): cada linha tem um nome. A
linha atual se chama "atual-N", e N muda a cada palavra recusada. Com um
nome novo, o Elm cria a linha de novo em vez de só atualizá-la, e o navegador
toca a animação de tremer outra vez, mesmo que o jogador erre duas vezes
seguidas.

-}
viewTabuleiro : { tremer : Bool, chaveAtual : Int } -> Jogo -> Html Msg
viewTabuleiro { tremer, chaveAtual } jogo =
    let
        total =
            List.length jogo.tentativas

        -- Só a última linha comemora, e só quando o jogo foi ganho.
        comemora indice =
            jogo.estado == Venceu && indice == total - 1

        feitas =
            List.indexedMap
                (\i t -> ( "feita-" ++ String.fromInt i, viewTentativa (comemora i) t ))
                jogo.tentativas

        chave =
            "atual-" ++ String.fromInt chaveAtual

        atual =
            case jogo.estado of
                Digitando palavra ->
                    [ ( chave, viewDigitando { conferindo = False, tremendo = tremer } palavra ) ]

                Conferindo palavra ->
                    [ ( chave, viewDigitando { conferindo = True, tremendo = False } palavra ) ]

                _ ->
                    []

        vazias =
            List.range (List.length feitas + List.length atual) (Jogo.maxTentativas - 1)
                |> List.map
                    (\i ->
                        ( "vazia-" ++ String.fromInt i
                        , viewDigitando { conferindo = False, tremendo = False } ""
                        )
                    )
    in
    Html.Keyed.node "div" [ class "board" ] (feitas ++ atual ++ vazias)


{-| As regras ficam sempre à vista, ao lado do tabuleiro (embaixo dele, em
telas estreitas). As regras sobre quais palavras valem precisam bater com
o filtro de backend/tools/gerar\_aceitas.py.
-}
viewRegras : Html msg
viewRegras =
    let
        cor classe significado =
            li [ class "regras-cor" ]
                [ span [ class ("regras-casa tile--revelada " ++ classe) ] []
                , text significado
                ]

        regra vale descricao exemplo =
            li [ class "regras-palavra" ]
                [ span
                    [ classList [ ( "regras-sinal", True ), ( "regras-sinal--nao", not vale ) ] ]
                    [ text
                        (if vale then
                            "✓"

                         else
                            "✗"
                        )
                    ]
                , span [] [ text descricao, span [ class "regras-exemplo" ] [ text exemplo ] ]
                ]
    in
    aside [ class "regras", attribute "aria-label" "Regras do jogo" ]
        [ h2 [ class "regras-titulo" ] [ text "Como jogar" ]
        , p [] [ text ("Descubra a palavra de 5 letras em " ++ String.fromInt Jogo.maxTentativas ++ " tentativas.") ]
        , ul [ class "regras-lista" ]
            [ cor "tile--certa" "letra certa na posição correta"
            , cor "tile--presente" "letra certa na posição errada"
            , cor "tile--ausente" "letra não consta na palavra"
            ]
        , h2 [ class "regras-titulo" ] [ text "Palavras que valem" ]
        , ul [ class "regras-lista" ]
            [ regra False "Plural" "casas, flores"
            , regra False "Verbo conjugado" "pensa, falei, comeu"
            , regra False "Palavra já tentada" "cada palavra vale uma vez"
            , regra True "Verbo no infinitivo" "andar, comer"
            , regra True "Sem acento também vale" "radio → rádio"
            ]
        ]


viewTentativa : Bool -> Tentativa -> Html Msg
viewTentativa venceu tentativa =
    div [ class "row", classList [ ( "row--vitoria", venceu ) ] ]
        (List.indexedMap viewCasaColorida
            (List.map2 Tuple.pair (String.toList tentativa.exibida) tentativa.cores)
        )


{-| A posição da casa vira a variável CSS `--i`, que o style.css usa para
atrasar a animação de cada casa: as letras viram uma depois da outra.
-}
viewCasaColorida : Int -> ( Char, Cor ) -> Html Msg
viewCasaColorida indice ( letra, cor ) =
    div
        [ class "tile tile--revelada"
        , class (classeDaCor cor)
        , attribute "style" ("--i: " ++ String.fromInt indice)
        ]
        [ text (String.fromChar (Char.toUpper letra)) ]


classeDaCor : Cor -> String
classeDaCor cor =
    case cor of
        Certa ->
            "tile--certa"

        Presente ->
            "tile--presente"

        Ausente ->
            "tile--ausente"


{-| Uma linha ainda sem cores: a palavra que está sendo digitada (ou
conferida), completada com casas vazias.
-}
viewDigitando : { conferindo : Bool, tremendo : Bool } -> String -> Html Msg
viewDigitando { conferindo, tremendo } palavra =
    let
        letras =
            List.map Just (String.toList palavra)
                ++ List.repeat (Jogo.tamanhoPalavra - String.length palavra) Nothing

        casa letra =
            case letra of
                Just c ->
                    div [ class "tile tile--preenchida" ] [ text (String.fromChar (Char.toUpper c)) ]

                Nothing ->
                    div [ class "tile" ] []
    in
    div
        [ class "row"
        , classList [ ( "row--conferindo", conferindo ), ( "row--tremendo", tremendo ) ]
        ]
        (List.map casa letras)


{-| Teclado virtual, no lugar do teclado físico (no celular, por exemplo).
O teclado reflete o que já foi descoberto: cada tecla tem a cor mais forte
que a letra já recebeu (`Jogo.coresDoTeclado`), e a letra que não está na
palavra fica translúcida (`key--ausente`, em style.css). Quando o jogo acaba, o quadro de fim toma o lugar
do teclado.

As teclas reagem ao `mousedown` (que também dispara num toque na tela), e
não ao clique, e cancelam o comportamento padrão do navegador. Assim o
botão não ganha foco: se ganhasse, um Enter do teclado físico apertaria de
novo a última tecla clicada, além de conferir a palavra.

-}
viewTeclado : Jogo -> Html Msg
viewTeclado jogo =
    let
        cores =
            Jogo.coresDoTeclado jogo

        tecla classes rotulo nome msg =
            button
                [ type_ "button"
                , class ("key " ++ classes)
                , attribute "aria-label" nome
                , preventDefaultOn "mousedown" (Decode.succeed ( msg, True ))
                ]
                [ text rotulo ]

        letra c =
            let
                cor =
                    case Dict.get c cores of
                        Just Certa ->
                            "key--certa"

                        Just Presente ->
                            "key--presente"

                        Just Ausente ->
                            "key--ausente"

                        Nothing ->
                            ""
            in
            tecla cor (String.fromChar (Char.toUpper c)) (String.fromChar c) (LetraDigitada c)

        linha letras =
            div [ class "keyboard-row" ] (List.map letra (String.toList letras))
    in
    div [ class "keyboard", attribute "aria-label" "Teclado" ]
        [ linha "qwertyuiop"
        , linha "asdfghjkl"
        , div [ class "keyboard-row" ]
            (tecla "key--larga" "Enter" "Conferir" Enviou
                :: List.map letra (String.toList "zxcvbnm")
                ++ [ tecla "key--larga" "⌫" "Apagar" Apagou ]
            )
        ]


viewFim : Jogo -> Html Msg
viewFim jogo =
    let
        fim titulo detalhe =
            div [ class "game-over" ]
                [ h2 [ class "game-over-title" ] [ text titulo ]
                , detalhe
                , button [ class "btn-novo", onClick NovoJogoPedido ] [ text "Jogar de novo" ]
                ]

        plural n =
            if n == 1 then
                "1 tentativa"

            else
                String.fromInt n ++ " tentativas"
    in
    case jogo.estado of
        Venceu ->
            fim "Parabéns!"
                (p [] [ text ("Você acertou em " ++ plural (List.length jogo.tentativas) ++ ".") ])

        Perdeu (Just segredo) ->
            fim "Não foi dessa vez"
                (p [] [ text "A palavra era ", strong [ class "segredo" ] [ text (String.toUpper segredo) ] ])

        Perdeu Nothing ->
            fim "Não foi dessa vez" (p [] [ text "Buscando a palavra..." ])

        _ ->
            text ""


{-| Toast vermelho de palavra desconhecida (estilo em style.css).

Aparece no topo da tela sem bloquear o jogo: o jogador pode continuar
digitando. Some sozinho depois de `duracaoDoToast` milissegundos, ou antes,
com o ✕ ou com Esc.

A área do toast tem chave (`Html.Keyed`) com o `id` do toast. Assim, um
toast novo que chega enquanto o anterior ainda está na tela é um elemento
novo, e a animação de entrada toca de novo.

-}
viewToast : Maybe Toast -> Html Msg
viewToast toast =
    case toast of
        Just { id, palavra, motivo, fase } ->
            Html.Keyed.node "div"
                [ class "toast-area" ]
                [ ( "toast-" ++ String.fromInt id, viewCaixaDoToast palavra motivo fase ) ]

        Nothing ->
            text ""


viewCaixaDoToast : String -> Motivo -> FaseDoToast -> Html Msg
viewCaixaDoToast palavra motivo fase =
    div
        [ class "toast-recusada"
        , classList [ ( "toast-recusada--saindo", fase == Saindo ) ]
        , attribute "role" "alert"
        ]
        [ span [ class "toast-icon" ] [ text "!" ]
        , span [ class "toast-text" ]
            [ strong [] [ text (String.toUpper palavra) ]
            , text
                (case motivo of
                    ForaDaLista ->
                        " não está na lista de palavras."

                    JaTentada ->
                        " já foi tentada nesta partida."
                )
            ]
        , button
            [ class "toast-close"
            , attribute "aria-label" "Fechar aviso"
            , onClick ToastFechado
            ]
            [ text "✕" ]
        ]


{-| Botão sol/lua: o `theme-controller` do daisyUI troca o tema só com CSS.
-}
viewTema : Model -> Html Msg
viewTema model =
    label [ class "theme-toggle", attribute "aria-label" "Alternar tema claro/escuro" ]
        [ input
            [ type_ "checkbox"
            , class "theme-controller"
            , value "dark"
            , checked model.darkTheme
            , onCheck TemaTrocado
            ]
            []
        , span [ class "swap-off" ] [ text "☀" ]
        , span [ class "swap-on" ] [ text "☾" ]
        ]


kbd : List (Html.Attribute msg) -> List (Html msg) -> Html msg
kbd =
    Html.node "kbd"
