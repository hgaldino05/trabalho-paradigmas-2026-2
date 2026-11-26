"""Gera backend/prolog/aceitas.pl e lexico.pl a partir da lista do IME-USP.

Fonte: "Lista de todas as palavras do português brasileiro", de Paulo
Feofiloff (IME-USP), preparada a partir do Dicionário br.ispell de Ricardo
Ueda Karpischek. Licença Creative Commons BY 4.0.
https://www.ime.usp.br/~pf/dicios/

Uso (na raiz do repositório), depois de baixar br-utf8.txt da página acima:

    python backend/tools/gerar_aceitas.py caminho/para/br-utf8.txt

Este script só EXTRAI dados do dicionário; ele não decide o que é plural ou
verbo conjugado. Quem decide é o Prolog (backend/prolog/flexao.pl), na hora
da tentativa.

- aceitas.pl: as palavras de 5 letras, só com letras minúsculas (com acento
  ou ç); palavras com maiúscula são nomes próprios e ficam de fora. As que já
  são respostas (palavras.pl) não se repetem, e quando duas grafias viram as
  mesmas letras sem acento (abafa e abafá), fica uma só.
- lexico.pl: as palavras de outros tamanhos que flexao.pl consulta para
  analisar uma palavra de 5 letras: as de 3 e 4 letras (singulares, como
  casa e luz, e infinitivos curtos, como amar), e as de 6 letras terminadas
  em -os (plurais, como livros) ou em -ar, -er e -ir (infinitivos, como
  pensar).
"""

import re
import sys
import unicodedata
from pathlib import Path

PROLOG = Path(__file__).resolve().parent.parent / "prolog"
SO_LETRAS = re.compile(r"^[a-záàâãéêíóôõúüç]+$")
RESPOSTA = re.compile(r'resposta\(\[([a-z,]+)\], "([^"]+)"\)')

FONTE = """\
    Fonte: "Lista de todas as palavras do português brasileiro", de Paulo
    Feofiloff (IME-USP), preparada a partir do Dicionário br.ispell de
    Ricardo Ueda Karpischek. Licença Creative Commons BY 4.0.
    https://www.ime.usp.br/~pf/dicios/
"""

CABECALHO_ACEITAS = f"""\
/*  aceitas.pl: palavras de 5 letras do dicionário que não são respostas.

    GERADO por backend/tools/gerar_aceitas.py. Não edite à mão: rode o
    script de novo. As palavras sorteadas (resposta/2) ficam em palavras.pl.

{FONTE}
    Aqui estão TODAS as palavras de 5 letras do dicionário, inclusive
    plurais (casas) e verbos conjugados (falei). Quem os recusa é o Prolog:
    palavra/2, em jogo.pl, usa a análise de flexao.pl.
*/

:- module(aceitas, [aceita/2]).
:- encoding(utf8).

"""

CABECALHO_LEXICO = f"""\
/*  lexico.pl: palavras de outros tamanhos, consultadas por flexao.pl.

    GERADO por backend/tools/gerar_aceitas.py. Não edite à mão.

{FONTE}
    Para saber se "casas" é plural, flexao.pl precisa saber se "casa"
    existe; para saber se "pensa" é verbo conjugado, se "pensar" existe.
    Este arquivo tem essas palavras: as de 3 e 4 letras, e as de 6 letras
    terminadas em -os, -ar, -er ou -ir. As de 5 letras estão em palavras.pl
    e aceitas.pl.
*/

:- module(lexico, [vocabulo/1]).
:- encoding(utf8).

"""


def sem_acento(palavra: str) -> str:
    palavra = palavra.replace("ç", "c")
    decomposta = unicodedata.normalize("NFD", palavra)
    return "".join(c for c in decomposta if not unicodedata.combining(c))


def escolher_grafia(grafias: list[str]) -> str:
    """Entre grafias com as mesmas letras escolhe a sem acento (mais comum)."""
    return min(grafias, key=lambda g: (g != sem_acento(g), g))


def vai_para_o_lexico(letras: str) -> bool:
    if len(letras) in (3, 4):
        return True
    return len(letras) == 6 and letras.endswith(("os", "ar", "er", "ir"))


def lista(letras: str) -> str:
    return "[" + ",".join(letras) + "]"


def main(caminho: str) -> None:
    respostas = {
        letras.replace(",", "")
        for letras, _ in RESPOSTA.findall((PROLOG / "palavras.pl").read_text(encoding="utf-8"))
    }

    todas = [linha.strip() for linha in Path(caminho).read_text(encoding="utf-8").splitlines()]
    grupos: dict[str, list[str]] = {}
    for palavra in todas:
        if SO_LETRAS.match(palavra):
            grupos.setdefault(sem_acento(palavra), []).append(palavra)

    aceitas = [
        f'aceita({lista(letras)}, "{escolher_grafia(grafias)}").'
        for letras, grafias in sorted(grupos.items())
        if len(letras) == 5 and letras not in respostas
    ]
    lexico = [f"vocabulo({lista(letras)})." for letras in sorted(grupos) if vai_para_o_lexico(letras)]

    with open(PROLOG / "aceitas.pl", "w", encoding="utf-8", newline="\n") as saida:
        saida.write(CABECALHO_ACEITAS + "\n".join(aceitas) + "\n")
    with open(PROLOG / "lexico.pl", "w", encoding="utf-8", newline="\n") as saida:
        saida.write(CABECALHO_LEXICO + "\n".join(lexico) + "\n")
    print(f"{len(aceitas)} palavras de 5 letras gravadas em aceitas.pl")
    print(f"{len(lexico)} palavras de outros tamanhos gravadas em lexico.pl")


if __name__ == "__main__":
    main(sys.argv[1])
