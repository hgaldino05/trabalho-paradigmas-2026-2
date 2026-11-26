"""Ponte entre Python e Prolog usando a biblioteca janus.

janus (pacote `janus-swi`) embute o SWI-Prolog dentro do processo Python.
Chamamos predicados diretamente e recebemos as respostas como dicionários.

Conversão de tipos: int vira inteiro, str vira string, list vira lista. No
sentido inverso, átomos chegam como str (por exemplo, "certa") e listas
como list. Termos compostos não passam, por isso os predicados de
interface em jogo.pl devolvem listas ou átomos.

Este é o ÚNICO arquivo do projeto que conhece o janus. Não há regra do
jogo aqui: só tradução entre Python e Prolog.
"""

from pathlib import Path

import janus_swi as janus

PROLOG_FILE = Path(__file__).parent.parent / "prolog" / "jogo.pl"

janus.consult(str(PROLOG_FILE))


class PalavraInvalida(Exception):
    """A tentativa não está na base de palavras."""


class PalavraRepetida(Exception):
    """A palavra já foi tentada nesta partida."""


class PartidaInexistente(Exception):
    """Não há partida com esse código (nunca houve, já foi ganha ou revelada)."""


class PartidaEncerrada(Exception):
    """A partida já foi perdida: não aceita mais tentativas."""


class RevelacaoNegada(Exception):
    """A palavra só é revelada depois que a partida é perdida."""


ERROS = {
    "invalida": PalavraInvalida,
    "repetida": PalavraRepetida,
    "inexistente": PartidaInexistente,
    "encerrada": PartidaEncerrada,
    "negado": RevelacaoNegada,
}


def _resultado(predicado: str, resultado):
    """Os predicados devolvem uma lista quando dá certo e um átomo de erro."""
    if isinstance(resultado, list):
        return resultado
    if resultado in ERROS:
        raise ERROS[resultado]
    raise ValueError(f"resultado inesperado de {predicado}: {resultado!r}")


def novo_jogo() -> str:
    """Abre uma partida e devolve o seu código aleatório."""
    return janus.query_once("jogo:novo_jogo(Id)")["Id"]


def jogar(jogo: str, palavra: str) -> tuple[str, list[int]]:
    """Devolve a palavra como deve ser exibida e a contagem das cores:
    [certas, presentes, ausentes]. A cor de cada letra nunca sai do Prolog."""
    resultado = janus.query_once(
        "jogo:jogar(Id, Texto, R)", {"Id": jogo, "Texto": palavra}
    )["R"]
    exibicao, contagem = _resultado("jogar/3", resultado)
    return exibicao, contagem


def revelar(jogo: str) -> str:
    resultado = janus.query_once("jogo:revelar(Id, R)", {"Id": jogo})["R"]
    [texto] = _resultado("revelar/2", resultado)
    return texto
