"""Gera backend/prolog/aceitas.pl a partir da lista de palavras do IME-USP.

Fonte: "Lista de todas as palavras do português brasileiro", de Paulo
Feofiloff (IME-USP), preparada a partir do Dicionário br.ispell de Ricardo
Ueda Karpischek. Licença Creative Commons BY 4.0.
https://www.ime.usp.br/~pf/dicios/

Uso (na raiz do repositório), depois de baixar br-utf8.txt da página acima: python backend/tools/gerar_aceitas.py caminho/para/br-utf8.txt

Este scriptsó precisa ser rodado de novo se a lista de respostas mudar muito ou em caso de troca de fonte.

- entram as palavras de 5 letras, só com letras minúsculas (com acento ou ç); palavras com maiúscula são nomes próprios e ficam de fora;
- palavras que já são respostas (palavras.pl) não se repetem aqui;
- quando duas grafias viram as mesmas letras sem acento (abafa e abafá), fica uma só: para o jogador, elas são a mesma tentativa;
- plurais e verbos conjugados ficam de fora (regra do jogo: verbo só no
  infinitivo). O dicionário não diz a classe de cada palavra, então isso é
  feito por regras aproximadas, descritas em `eh_plural` e `formas_verbais`.
"""

import re
import sys
import unicodedata
from pathlib import Path

PROLOG = Path(__file__).resolve().parent.parent / "prolog"
SO_LETRAS = re.compile(r"^[a-záàâãéêíóôõúüç]{5}$")
RESPOSTA = re.compile(r'resposta\(\[([a-z,]+)\], "([^"]+)"\)')

CABECALHO = """\
/*  aceitas.pl: palavras que valem como tentativa, mas nunca são sorteadas.

    GERADO por backend/tools/gerar_aceitas.py. Não edite à mão: rode o
    script de novo. As palavras sorteadas (resposta/2) ficam em palavras.pl.

    Fonte: "Lista de todas as palavras do português brasileiro", de Paulo
    Feofiloff (IME-USP), preparada a partir do Dicionário br.ispell de
    Ricardo Ueda Karpischek. Licença Creative Commons BY 4.0.
    https://www.ime.usp.br/~pf/dicios/

    Plurais (casas) e verbos conjugados (falei) foram tirados: verbo só vale
    no infinitivo. O filtro é aproximado; veja o script.
*/

:- module(aceitas, [aceita/2]).
:- encoding(utf8).

"""

# Terminações regulares, sem acento (a comparação é feita sem acento).
# Ficam de fora infinitivo e particípio, que também funcionam como
# substantivo ou adjetivo. A terminação "-a" dos verbos em -ar (ele pensa,
# ele chora) entra: alguns substantivos iguais a ela saem junto (baixa,
# ginga), mas os comuns (conta, falta, busca) estão em palavras.pl, que
# este filtro não toca.
TERMINACOES = {
    "ar": "o a e ai ei as am es em aste ou amos ais astes aram ava avas avamos aveis avam "
    "ara aras aramos areis arei arao aria arias ariamos arieis ariam emos eis "
    "asse asses assemos asseis assem armos ardes arem ando",
    "er": "o a e ei es em as am i este eu emos eis estes eram ia ias iamos ieis iam "
    "era eras eramos ereis erei erao eria erias eriamos erieis eriam amos ais "
    "esse esses essemos esseis essem ermos erdes erem endo",
    "ir": "o a e es em as am i iste iu imos is istes iram ia ias iamos ieis iam "
    "ira iras iramos ireis irei irao iria irias iriamos irieis iriam amos ais "
    "isse isses issemos isseis issem irmos irdes irem indo",
}

# Verbos curtos de verdade. Outros infinitivos de 3 letras (bar, mar, par)
# são substantivos e gerariam formas falsas.
VERBOS_CURTOS = {"ler", "ter", "ver", "dar", "ser", "rir", "vir", "crer"}

# Formas irregulares comuns que as regras acima não geram.
IRREGULARES = set(
    """
    somos sois foram fomos foste fosse sejam sejas seria serao eram estou estao
    estas estava esteve estive tenho temos tinha tinham teria terao terei tiver
    tenha tenham vamos vimos vinha vindo venho vens venha vemos veria iriam irao
    fazem fazia fizer fazes faria farao disse dizem digam digas diria dirao
    posso pode podem podia puder possa quero quer querem quis quiser trago
    traga trouxe ponho pomos poem soube sabem sabia saiba vejo vejam viram
    vendo dando deram demos dava davam desse dessem derem houve havia hajam
    sendo pondo rindo tendo caibo caiba coube depoe depus traio traia saio
    saem fujo fujas fuja odeio rirao riria
    """.split()
)


def sem_acento(palavra: str) -> str:
    palavra = palavra.replace("ç", "c")
    decomposta = unicodedata.normalize("NFD", palavra)
    return "".join(c for c in decomposta if not unicodedata.combining(c))


def escolher_grafia(grafias: list[str]) -> str:
    """Entre grafias com as mesmas letras escolhe a sem acento (mais comum)."""
    return min(grafias, key=lambda g: (g != sem_acento(g), g))


def singulares(palavra: str) -> list[str]:
    """Os singulares possíveis de uma palavra terminada em s."""
    if not palavra.endswith("s"):
        return []
    opcoes = [palavra[:-1]]  # casas -> casa
    if palavra.endswith("es"):
        opcoes.append(palavra[:-2])  # luzes -> luz
    if palavra.endswith("ns"):
        opcoes.append(palavra[:-2] + "m")  # trens -> trem
    if palavra.endswith(("oes", "aes")):
        opcoes.append(palavra[:-3] + "ao")  # leões -> leão
    if palavra.endswith(("ais", "eis", "ois", "uis")):
        opcoes.append(palavra[:-2] + "l")  # azuis -> azul
    if palavra.endswith("eis"):
        opcoes.append(palavra[:-3] + "il")  # fósseis -> fóssil
    if palavra.endswith("is"):
        opcoes.append(palavra[:-1] + "l")  # fuzis -> fuzil
    return opcoes


def eh_plural(palavra: str, dicionario: set[str]) -> bool:
    """Plural é a palavra em -s cujo singular também está no dicionário."""
    return any(s in dicionario and s != palavra for s in singulares(palavra))


def conjugar(radical: str, fim: str, conjugacao: str) -> set[str]:
    """Junta radical e terminação, com os acertos de grafia mais comuns."""
    formas = {radical + fim}
    if conjugacao == "ar" and fim[0] == "e":
        if radical.endswith("c"):  # ficar -> fiquei (e alçar -> alcei, que fica igual)
            formas.add(radical[:-1] + "qu" + fim)
        if radical.endswith("g"):  # pagar -> paguei
            formas = {radical + "u" + fim}
    if conjugacao == "ar" and radical.endswith("e") and fim in ("o", "a", "as", "am", "e", "es", "em"):
        formas.add(radical + "i" + fim)  # passear -> passeio
    if conjugacao in ("er", "ir") and fim[0] in "ao":
        if radical.endswith("g"):  # fugir -> fujo
            formas = {radical[:-1] + "j" + fim}
        elif radical.endswith("gu"):  # seguir -> sigo (só o gu)
            formas = {radical[:-1] + fim}
        elif radical.endswith(("a", "o", "u")):  # cair -> caio
            formas.add(radical + "i" + fim)
    return formas


def formas_verbais(dicionario: set[str]) -> set[str]:
    """Conjuga, pelas regras regulares, todo infinitivo do dicionário."""
    formas = set(IRREGULARES)
    for infinitivo in dicionario:
        if len(infinitivo) < 4 and infinitivo not in VERBOS_CURTOS:
            continue
        conjugacao = infinitivo[-2:]
        if conjugacao in TERMINACOES:
            for fim in TERMINACOES[conjugacao].split():
                formas |= conjugar(infinitivo[:-2], fim, conjugacao)
    return formas


def eh_verbo_conjugado(palavra: str, verbais: set[str], dicionario: set[str]) -> bool:
    if palavra.endswith(("amo", "emo", "imo")) and palavra + "s" in verbais:
        return True  # "amamo", pedaço de "amamo-lo" que o dicionário lista
    if palavra not in verbais:
        return False
    # "livro" parece "eu livro", mas tem plural (livros): é substantivo.
    return not (palavra.endswith("o") and palavra + "s" in dicionario)


def main(caminho: str) -> None:
    respostas = {
        letras.replace(",", "")
        for letras, _ in RESPOSTA.findall((PROLOG / "palavras.pl").read_text(encoding="utf-8"))
    }

    todas = [linha.strip() for linha in Path(caminho).read_text(encoding="utf-8").splitlines()]
    dicionario = {sem_acento(p) for p in todas if p and p.islower()}
    verbais = formas_verbais(dicionario)

    grupos: dict[str, list[str]] = {}
    for palavra in todas:
        if SO_LETRAS.match(palavra):
            grupos.setdefault(sem_acento(palavra), []).append(palavra)

    plurais = conjugados = 0
    linhas = []
    for letras, grafias in sorted(grupos.items()):
        if letras in respostas:
            continue
        if eh_plural(letras, dicionario):
            plurais += 1
        elif eh_verbo_conjugado(letras, verbais, dicionario):
            conjugados += 1
        else:
            linhas.append(f'aceita([{",".join(letras)}], "{escolher_grafia(grafias)}").')

    with open(PROLOG / "aceitas.pl", "w", encoding="utf-8", newline="\n") as saida:
        saida.write(CABECALHO + "\n".join(linhas) + "\n")
    print(f"{len(linhas)} palavras aceitas gravadas em {PROLOG / 'aceitas.pl'}")
    print(f"fora: {plurais} plurais e {conjugados} verbos conjugados")


if __name__ == "__main__":
    main(sys.argv[1])
