"""API HTTP do jogo.

Esta camada é só "cola": recebe JSON, valida o formato com Pydantic, chama o
Prolog (via app/prolog.py) e devolve JSON. Nenhuma regra do jogo mora aqui.

Cada partida é guardada no Prolog (fato partida/3). O navegador só recebe
um código aleatório (`jogo`); a palavra secreta não sai do servidor antes
de a partida ser perdida.

Rodar em modo de desenvolvimento (recarrega ao salvar):
    uv run fastapi dev app/main.py

Documentação interativa: http://localhost:8000/docs
"""

from typing import Annotated, Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app import prolog

app = FastAPI(title="Telmo (Prolog + Elm)")

Palavra = Annotated[str, Field(min_length=5, max_length=5)]
Cor = Literal["certa", "presente", "ausente"]
Cores = Annotated[list[Cor], Field(min_length=5, max_length=5)]


class NovoResponse(BaseModel):
    jogo: str


class JogoRequest(BaseModel):
    jogo: str


class TentativaRequest(BaseModel):
    jogo: str
    palavra: Palavra


class TentativaResponse(BaseModel):
    palavra: str  # como deve ser exibida, com acentos
    cores: Cores


class PalavraResponse(BaseModel):
    palavra: str


PALAVRA_INVALIDA = "Essa palavra não está na lista."
PALAVRA_REPETIDA = "Você já tentou essa palavra."
PARTIDA_INEXISTENTE = "Partida não encontrada. Comece um jogo novo."
PARTIDA_ENCERRADA = "Essa partida já terminou."
REVELACAO_NEGADA = "A palavra só é revelada no fim da partida."


@app.post("/api/novo")
def novo() -> NovoResponse:
    return NovoResponse(jogo=prolog.novo_jogo())


@app.post("/api/tentativa")
def tentativa(request: TentativaRequest) -> TentativaResponse:
    try:
        palavra, cores = prolog.jogar(request.jogo, request.palavra)
    except prolog.PalavraInvalida:
        raise HTTPException(status_code=422, detail=PALAVRA_INVALIDA) from None
    except prolog.PalavraRepetida:
        raise HTTPException(status_code=422, detail=PALAVRA_REPETIDA) from None
    except prolog.PartidaInexistente:
        raise HTTPException(status_code=404, detail=PARTIDA_INEXISTENTE) from None
    except prolog.PartidaEncerrada:
        raise HTTPException(status_code=409, detail=PARTIDA_ENCERRADA) from None
    return TentativaResponse(palavra=palavra, cores=cores)


@app.post("/api/revelar")
def revelar(request: JogoRequest) -> PalavraResponse:
    try:
        palavra = prolog.revelar(request.jogo)
    except prolog.RevelacaoNegada:
        raise HTTPException(status_code=403, detail=REVELACAO_NEGADA) from None
    except prolog.PartidaInexistente:
        raise HTTPException(status_code=404, detail=PARTIDA_INEXISTENTE) from None
    return PalavraResponse(palavra=palavra)

