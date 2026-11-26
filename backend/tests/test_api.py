"""Testes da API HTTP (pytest).

As regras do jogo são testadas em Prolog (prolog/test_jogo.pl): rotas, formato do JSON e códigos de status.

Rodar: `uv run pytest` (na pasta backend).
"""

import janus_swi as janus
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

TUDO_CERTO = {"certas": 5, "presentes": 0, "ausentes": 0}


def novo() -> str:
    return client.post("/api/novo").json()["jogo"]


def tentar(jogo: str, palavra: str):
    return client.post("/api/tentativa", json={"jogo": jogo, "palavra": palavra})


def segredo(jogo: str) -> str:
    """A API não entrega o segredo antes do fim; o teste lê direto do Prolog."""
    return janus.query_once(
        "atom_string(A, Id), jogo:partida(A, S, _), palavras:resposta(S, T)",
        {"Id": jogo},
    )["T"]


def test_novo_jogo_devolve_codigo_aleatorio():
    a, b = novo(), novo()
    assert isinstance(a, str) and len(a) == 36
    assert a != b


def test_acertar_a_palavra():
    jogo = novo()
    palavra = segredo(jogo)
    response = tentar(jogo, palavra)
    assert response.status_code == 200
    assert response.json() == {"palavra": palavra, "contagem": TUDO_CERTO}


def test_tentativa_sem_acento_volta_com_acento():
    response = tentar(novo(), "radio")
    assert response.status_code == 200
    assert response.json()["palavra"] == "rádio"


def test_plural_e_verbo_conjugado_sao_recusados():
    jogo = novo()
    for palavra in ["casas", "falei"]:
        assert tentar(jogo, palavra).status_code == 422


def test_infinitivo_vale():
    # "latir" não é resposta, mas está em aceitas.pl (veio do dicionário).
    assert tentar(novo(), "latir").status_code == 200


def test_palavra_fora_da_lista():
    response = tentar(novo(), "xxxxx")
    assert response.status_code == 422
    assert response.json()["detail"] == "Essa palavra não está na lista."


def test_palavra_com_tamanho_errado():
    # Quem rejeita é o Pydantic, antes de o Prolog ser chamado.
    assert tentar(novo(), "casa").status_code == 422


def test_nao_revela_no_meio_da_partida():
    jogo = novo()
    tentar(jogo, "terra")
    response = client.post("/api/revelar", json={"jogo": jogo})
    assert response.status_code == 403


def test_perder_revela_a_palavra_e_encerra():
    jogo = novo()
    palavra = segredo(jogo)
    candidatas = ["terra", "pouco", "lindo", "chuva", "bicho", "porta", "folha",
                  "nuvem", "peixe", "praia", "festa"]
    erradas = [p for p in candidatas if p != palavra]
    for p in erradas[:10]:
        assert tentar(jogo, p).status_code == 200
    assert tentar(jogo, erradas[0]).status_code == 409
    response = client.post("/api/revelar", json={"jogo": jogo})
    assert response.status_code == 200
    assert response.json() == {"palavra": palavra}


def test_partida_inexistente():
    assert tentar("nao-existe", "terra").status_code == 404
    assert client.post("/api/revelar", json={"jogo": "nao-existe"}).status_code == 404


def test_palavra_repetida_e_recusada():
    jogo = novo()
    palavra = "terra" if segredo(jogo) != "terra" else "porta"
    assert tentar(jogo, palavra).status_code == 200
    response = tentar(jogo, palavra)
    assert response.status_code == 422
    assert response.json()["detail"] == "Você já tentou essa palavra."


def test_tentativa_so_informa_a_contagem():
    # O jogo diz quantas letras caíram em cada cor, nunca quais.
    response = tentar(novo(), "terra")
    assert response.status_code == 200
    corpo = response.json()
    assert set(corpo) == {"palavra", "contagem"}
    contagem = corpo["contagem"]
    assert set(contagem) == {"certas", "presentes", "ausentes"}
    assert sum(contagem.values()) == 5
