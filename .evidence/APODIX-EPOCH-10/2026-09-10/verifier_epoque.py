#!/usr/bin/env python3
"""Verifier une epoque d'Apodix SANS notre depot, SANS notre outillage, SANS aucune cle.

CE QUE CE FICHIER EXISTE POUR RENDRE POSSIBLE. Le registre d'Apodix porte des faits ; toutes
les 24 h leurs empreintes sont reunies dans un arbre de Merkle dont la racine est ecrite sur
Ethereum. Ce script tient dans un fichier, ne depend que de Python, et refait le calcul de
bout en bout contre un noeud Ethereum public que le lecteur choisit lui-meme : il n'a besoin ni
de nous croire sur parole, ni de nous demander quoi que ce soit.

CE QU'IL ETABLIT, ET RIEN DE PLUS :
  1. la racine recalculee depuis le manifeste est celle qui est ECRITE SUR ETHEREUM ;
  2. le fait demande est bien une feuille de cet arbre, par sa preuve d'inclusion.
CE QU'IL N'ETABLIT PAS, et qu'aucun arbre de Merkle ne peut etablir : que le fait dit vrai.
Un fait d'Apodix atteste qu'une preuve STARK a ete acceptee par un verifieur on-chain ; ce
script ne verifie pas cette preuve, il verifie l'INCLUSION du fait dans une epoque scellee.
Les deux questions sont distinctes et il ne faut pas que la seconde ait l'air de repondre a
la premiere.

TROIS ISSUES, jamais confondues :
  0  tout ce qui a ete demande est verifie
  1  verdict NEGATIF : la racine differe, ou la preuve ne tient pas, ou le fait est absent
  2  INDETERMINE : le noeud Ethereum n'a pas repondu. Ne pas pouvoir regarder n'est pas
     « rien a signaler », et ce script ne rendra jamais 0 dans ce cas.

AUCUNE DEPENDANCE : keccak256 est implemente DANS ce fichier, avec le seul interprete (un tiers n'a besoin que de ce script et du manifeste).
Si `pycryptodome` ou `pysha3` sont installes ils sont preferes pour la vitesse, et un test
verifie que les deux chemins concordent. `hashlib.sha3_256` n'est JAMAIS utilise : SHA3 et
keccak different d'un octet de bourrage, donc de tous leurs condensats.

USAGE
  python3 verifier_epoque.py --manifeste epoch-0006.json \\
      [--fact 0x190776b9…] \\
      [--rpc https://ethereum-sepolia-rpc.publicnode.com] \\
      [--contrat 0x48421a2e448cb2E3fA66af2E047F86ee755cFB14]
"""

import argparse
import json
import sys
import urllib.request

# --- keccak256, SANS AUCUNE DEPENDANCE -----------------------------------------------------
# Ce fichier SEUL suffit : il s'execute avec le seul interprete Python. Demander `pip install` a quelqu'un qui verifie nos ancrages serait lui
# demander une deuxieme confiance, envers une dependance qu'il n'a pas choisie. Si
# `pycryptodome` ou `pysha3` sont la, ils sont preferes pour la vitesse (environ 40 fois plus
# rapides sur un arbre de 41 feuilles), et un test verifie que les deux chemins donnent le
# meme resultat. `hashlib.sha3_256` n'est jamais utilise : SHA3 et keccak different d'un octet
# de bourrage, ce qui suffit a rendre tous les condensats differents.
# UN SEUL FICHIER : un verificateur qui promet « aucune dependance » et importe un module
# voisin ment par omission. keccak256 est donc ECRIT ICI.
_RC = (
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
)
_ROT = (
    (0, 36, 3, 41, 18), (1, 44, 10, 45, 2), (62, 6, 43, 15, 61),
    (28, 55, 25, 21, 56), (27, 20, 39, 8, 14),
)
_MASK = (1 << 64) - 1


def _rotl(x: int, n: int) -> int:
    return ((x << n) | (x >> (64 - n))) & _MASK


def _keccak_f1600(a: list) -> None:
    """Permutation en place sur l'etat 5x5 de mots de 64 bits, 24 tours."""
    for rnd in range(24):
        # theta
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rotl(c[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                a[x][y] ^= d[x]
        # rho et pi
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rotl(a[x][y], _ROT[x][y])
        # chi
        for x in range(5):
            for y in range(5):
                a[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y] & _MASK)
        # iota
        a[0][0] ^= _RC[rnd]


def _keccak_pur(donnees: bytes) -> bytes:
    """Le condensat keccak256 (256 bits) de `donnees`. Rate 136 octets, bourrage 0x01 / 0x80."""
    rate = 136
    a = [[0] * 5 for _ in range(5)]
    m = bytearray(donnees)
    # Bourrage keccak d'origine : 0x01, des zeros, puis 0x80 sur le dernier octet du bloc.
    m.append(0x01)
    while len(m) % rate != 0:
        m.append(0x00)
    m[-1] ^= 0x80
    for debut in range(0, len(m), rate):
        bloc = m[debut:debut + rate]
        for i in range(rate // 8):
            mot = int.from_bytes(bloc[i * 8:(i + 1) * 8], "little")
            a[i % 5][i // 5] ^= mot
        _keccak_f1600(a)
    sortie = bytearray()
    while len(sortie) < 32:
        for i in range(rate // 8):
            if len(sortie) >= 32:
                break
            sortie += a[i % 5][i // 5].to_bytes(8, "little")
        if len(sortie) < 32:  # pragma: no cover - jamais atteint pour 256 bits
            _keccak_f1600(a)
    return bytes(sortie[:32])


_MOTEUR = "python pur"
try:
    from Crypto.Hash import keccak as _keccak_lib  # pycryptodome

    def k256(b: bytes) -> bytes:
        h = _keccak_lib.new(digest_bits=256)
        h.update(b)
        return h.digest()

    _MOTEUR = "pycryptodome"
except ImportError:
    try:
        import sha3 as _sha3  # pysha3

        def k256(b: bytes) -> bytes:
            return _sha3.keccak_256(b).digest()

        _MOTEUR = "pysha3"
    except ImportError:
        k256 = _keccak_pur

VERT, NEGATIF, INDETERMINE = 0, 1, 2


def felt_vers_bytes32(x: str) -> bytes:
    """Un fact_hash d'Apodix est un felt (< 2^252) ecrit en hex minuscule sans zero de tete."""
    n = int(x, 16)
    if n >= 1 << 252:
        raise ValueError(f"hors felt252 : {x}")
    return n.to_bytes(32, "big")


def feuille(fact: str) -> bytes:
    """Feuille OpenZeppelin StandardMerkleTree pour l'encodage ["bytes32"] :
    keccak256(keccak256(abi.encode(v))). Pour un unique bytes32, `abi.encode` EST les 32 octets."""
    return k256(k256(felt_vers_bytes32(fact)))


def paire(a: bytes, b: bytes) -> bytes:
    """Les paires sont TRIEES avant hachage : la racine ne depend pas de l'ordre des freres."""
    return k256(a + b) if a < b else k256(b + a)


def racine(feuilles: list) -> bytes:
    """L'arbre d'OpenZeppelin, a l'identique. Le piege est ici et il vaut d'etre ecrit : les
    feuilles ne sont PAS appariees de proche en proche dans leur ordre. Elles sont placees a
    la FIN d'un tableau de 2n-1 cases, en ordre INVERSE, puis chaque case i recoit le hachage
    de ses enfants 2i+1 et 2i+2. Une reimplementation naive par paires successives donne une
    autre racine, ce qui a ete constate en ecrivant ce fichier."""
    n = len(feuilles)
    if n == 0:
        raise ValueError("aucune feuille")
    if n == 1:
        return feuilles[0]
    arbre = [None] * (2 * n - 1)
    for i, f in enumerate(feuilles):
        arbre[len(arbre) - 1 - i] = f
    for i in range(len(arbre) - 1 - n, -1, -1):
        arbre[i] = paire(arbre[2 * i + 1], arbre[2 * i + 2])
    return arbre[0]


def preuve_tient(feuille_: bytes, preuve: list, racine_attendue: bytes) -> bool:
    """Une preuve d'inclusion est une remontee : on rehache la feuille avec chaque frere."""
    cur = feuille_
    for frere in preuve:
        cur = paire(cur, bytes.fromhex(frere[2:]))
    return cur == racine_attendue


def selecteur(signature: str) -> str:
    return "0x" + k256(signature.encode()).hex()[:8]


def racine_on_chain(rpc: str, contrat: str, epoch_id: int):
    """`epoch(uint64)` rend un tuple (bytes32 factsRoot, uint32 factsCount, uint64 apxBlockMax,
    uint64 anchoredAt, uint64 l1Block). On lit les deux premiers mots de 32 octets."""
    data = selecteur("epoch(uint64)") + f"{epoch_id:064x}"
    corps = {"jsonrpc": "2.0", "id": 1, "method": "eth_call",
             "params": [{"to": contrat, "data": data}, "latest"]}
    # `User-Agent` explicite : plusieurs noeuds publics repondent 403 a un client qui n'en
    # envoie pas ; sans cet en-tete le script rendrait INDETERMINE a chaque appel.
    req = urllib.request.Request(rpc, data=json.dumps(corps).encode(),
                                 headers={"content-type": "application/json",
                                          "user-agent": "apodix-verifier-epoque/1"})
    rep = json.load(urllib.request.urlopen(req, timeout=60))
    if "result" not in rep:
        raise RuntimeError(rep.get("error", {}).get("message", "reponse sans resultat"))
    brut = rep["result"][2:]
    return bytes.fromhex(brut[0:64]), int(brut[64:128], 16)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Verifier une epoque d'Apodix sans cle et sans notre depot.")
    ap.add_argument("--manifeste", required=True, help="anchors/epoch-NNNN.json, publie avec l'epoque")
    ap.add_argument("--fact", help="fact_hash dont on veut la preuve d'inclusion (facultatif)")
    ap.add_argument("--rpc", default="https://ethereum-sepolia-rpc.publicnode.com",
                    help="noeud Ethereum de VOTRE choix (defaut : un public)")
    ap.add_argument("--contrat", default="0x48421a2e448cb2E3fA66af2E047F86ee755cFB14",
                    help="contrat d'ancrage sur Ethereum Sepolia")
    ap.add_argument("--sans-chaine", action="store_true",
                    help="recalcule la racine locale seulement ; ne PROUVE rien contre la chaine")
    a = ap.parse_args(argv)

    print(f"(keccak256 : {_MOTEUR})")
    m = json.load(open(a.manifeste))
    faits = m["leaves"]
    feuilles = sorted(feuille(f) for f in faits)
    r_local = racine(feuilles)
    print(f"epoque {m['epoch_id']} : {len(faits)} faits, racine recalculee 0x{r_local.hex()}")

    if f"0x{r_local.hex()}" != m["root"]:
        print(f"NEGATIF : le manifeste annonce {m['root']}, le recalcul donne 0x{r_local.hex()}",
              file=sys.stderr)
        return NEGATIF
    print("  racine du manifeste : conforme au recalcul")

    if a.sans_chaine:
        print("  chaine : NON CONSULTEE (--sans-chaine) ; rien n'est etabli contre Ethereum")
    else:
        try:
            r_chaine, n_chaine = racine_on_chain(a.rpc, a.contrat, int(m["epoch_id"]))
        except Exception as e:  # noqa: BLE001 - toute panne de lecture est INDETERMINE
            print(f"INDETERMINE : le noeud n'a pas repondu ({e}). Ce n'est PAS une verification "
                  "reussie ; reessayez, ou choisissez un autre noeud.", file=sys.stderr)
            return INDETERMINE
        if r_chaine != r_local:
            print(f"NEGATIF : la chaine porte 0x{r_chaine.hex()} pour l'epoque {m['epoch_id']}",
                  file=sys.stderr)
            return NEGATIF
        print(f"  racine ON-CHAIN : identique ({n_chaine} faits annonces par le contrat)")
        if n_chaine != len(faits):
            print(f"NEGATIF : le contrat annonce {n_chaine} faits, le manifeste en porte {len(faits)}",
                  file=sys.stderr)
            return NEGATIF

    if a.fact:
        # DEUX ECRITURES DU MEME NOMBRE, et la comparaison litterale les separait. Un `fact_hash`
        # est un FELT : le manifeste le stocke sous sa forme canonique, sans zero de tete
        # (`0x388779f8…`, 63 chiffres ici), tandis que la plupart des explorateurs, des
        # bibliotheques et des recus le rendent PADDE a 64 (`0x0388779f8…`) : coller la forme
        # paddee d'un fait qui est dans l'epoque recevait « n'est pas dans cette epoque ».
        #
        # C'EST LE PIRE DEFAUT POSSIBLE POUR CET OUTIL. Un faux negatif ici ne fait pas douter
        # d'un ancrage douteux : il fait RENONCER quelqu'un qui avait raison, et il le fait avec
        # l'autorite d'un verificateur cense ne rien prendre pour argent comptant. Entre un
        # verdict d'absence et une difference d'ecriture, la charge de la preuve est sur nous.
        #
        # La normalisation ne perd RIEN : les deux ecritures designent le meme entier, et c'est
        # l'entier qui entre dans la feuille. Elle ne rend pas l'outil laxiste pour autant : une
        # valeur qui n'est pas ce felt-la reste refusee, et une abreviation (une ellipse « … »)
        # reste refusee : jamais d'ellipse en entree.
        def _canon(x: str) -> str:
            return hex(int(x, 16))

        cle = _canon(a.fact)
        preuves = {_canon(k): v for k, v in (m.get("proofs") or {}).items()}
        preuve = preuves.get(cle)
        if preuve is None:
            print(f"NEGATIF : {a.fact} n'est pas dans cette epoque (aucune preuve au manifeste ; "
                  f"forme canonique cherchee : {cle})", file=sys.stderr)
            return NEGATIF
        if not preuve_tient(feuille(cle), preuve, r_local):
            print(f"NEGATIF : la preuve de {cle} ne remonte pas a la racine", file=sys.stderr)
            return NEGATIF
        print(f"  inclusion de {cle} : preuve de {len(preuve)} niveaux, VERIFIEE")

    print("VERT : tout ce qui a ete demande est verifie. Rappel : ceci etablit l'INCLUSION du "
          "fait dans une epoque scellee, pas la validite de la preuve STARK qu'il atteste.")
    return VERT


if __name__ == "__main__":
    raise SystemExit(main())
