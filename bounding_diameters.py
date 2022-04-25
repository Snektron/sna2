#!/usr/bin/env python3

graph = {
    'A': ['C'],
    'B': ['C', 'E'],
    'C': ['A', 'B', 'D', 'F'],
    'D': ['C', 'F'],
    'E': ['B', 'F', 'G'],
    'F': ['C', 'D', 'E', 'J', 'H', 'L'],
    'G': ['E', 'J', 'I'],
    'H': ['F', 'K'],
    'I': ['G'],
    'J': ['F', 'G'],
    'K': ['H'],
    'L': ['F', 'M', 'N', 'P'],
    'M': ['L'],
    'N': ['L'],
    'P': ['L', 'N', 'Q', 'R'],
    'Q': ['P', 'S'],
    'R': ['P'],
    'S': ['Q', 'T'],
    'T': ['S'],
}

INF = 999999

latex_template = '''\\begin{{center}}
\\begin{{tikzpicture}}[node distance=2cm, label distance=0.01cm]
    \\node[{Fa}circle, draw, label=10:{Fu}, label=-10:{Fl}] (F) {{$F$}};
    \\node[{Ca}circle, draw, left of = F, label=10:{Cu}, label=-10:{Cl}] (C) {{$C$}};
    \\node[{Aa}circle, draw, below left of = C, label=10:{Au}, label=-10:{Al}] (A) {{$A$}};
    \\node[{Ba}circle, draw, above left of = C, label=10:{Bu}, label=-10:{Bl}] (B) {{$B$}};
    \\node[{Ea}circle, draw, right of = B, label=10:{Eu}, label=-10:{El}] (E) {{$E$}};
    \\node[{Da}circle, draw, below left of = F, label=10:{Du}, label=-10:{Dl}] (D) {{$D$}};
    \\node[{Ja}circle, draw, above right of = F, label=10:{Ju}, label=-10:{Jl}] (J) {{$J$}};
    \\node[{Ga}circle, draw, above right of = E, label=10:{Gu}, label=-10:{Gl}] (G) {{$G$}};
    \\node[{Ia}circle, draw, right of = G, label=10:{Iu}, label=-10:{Il}] (I) {{$I$}};
    \\node[{La}circle, draw, below right of = J, label=10:{Lu}, label=-10:{Ll}] (L) {{$L$}};
    \\node[{Ma}circle, draw, below right of = L, label=10:{Mu}, label=-10:{Ml}] (M) {{$M$}};
    \\node[{Na}circle, draw, above right of = L, label=10:{Nu}, label=-10:{Nl}] (N) {{$N$}};
    \\node[{Pa}circle, draw, right of = L, label=10:{Pu}, label=-10:{Pl}] (P) {{$P$}};
    \\node[{Qa}circle, draw, above right of = P, label=10:{Qu}, label=-10:{Ql}] (Q) {{$Q$}};
    \\node[{Sa}circle, draw, right of = Q, label=10:{Su}, label=-10:{Sl}] (S) {{$S$}};
    \\node[{Ta}circle, draw, below of = S, label=10:{Tu}, label=-10:{Tl}] (T) {{$T$}};
    \\node[{Ha}circle, draw, right of = D, label=10:{Hu}, label=-10:{Hl}] (H) {{$H$}};
    \\node[{Ka}circle, draw, right of = H, label=10:{Ku}, label=-10:{Kl}] (K) {{$K$}};
    \\node[{Ra}circle, draw, below right of = P, label=10:{Ru}, label=-10:{Rl}] (R) {{$R$}};

    \\path
        (C) edge (F) edge (B) edge (D) edge (A)
        (D) edge (F)
        (E) edge (B) edge (F) edge (G)
        (J) edge (F) edge (G)
        (G) edge (I)
        (F) edge (L) edge (H)
        (H) edge (K)
        (L) edge (M) edge (N) edge (P)
        (P) edge (N) edge (R) edge (Q)
        (S) edge (Q) edge (T);

    \\node[below = 0.8cm of A, anchor=west] {{$\\Delta_L = {d_l}$\\hspace{{1em}}$\\Delta_U = {d_u}$\\hspace{{1em}}${start}$ selected by {selection} and highest degree}};
\\end{{tikzpicture}}
\\end{{center}}
'''

def format_graph(e_l, e_u, v, W, U, d_l, d_u, i):
    args = {'d_l': d_l, 'd_u': d_u, 'start': v, 'selection': 'largest upper bound' if i % 2 == 0 else 'smallest lower bound'}
    for n in graph.keys():
        args[f'{n}u'] = e_u[n]
        args[f'{n}l'] = e_l[n]
        if n == v:
            args[f'{n}a'] = 'fill=white!50!blue, '
        elif n in U:
            args[f'{n}a'] = 'fill=white!50!red, '
        elif n not in W:
            args[f'{n}a'] = 'fill=white!50!gray, '
        else:
            args[f'{n}a'] = ''

    return latex_template.format(**args)

def eccentricity(start):
    Q = [start]
    d = {start: 0}

    while len(Q) > 0:
        v = Q.pop()
        for n in graph[v]:
            if n not in d.keys():
                d[n] = d[v] + 1
                Q.append(n)

    return max(d.values()), d

def select(W, e_l, e_u, i):
    v = None
    if i % 2 == 0:
        # Select highest from e_u
        u = -INF
        for w in W:
            if e_u[w] > u or (e_u[w] == u and len(graph[w]) > len(graph[v])):
                u = e_u[w]
                v = w
    else:
        # Select smallest from e_l
        l = INF
        for w in W:
            if e_l[w] < l or (e_l[w] == l and len(graph[w]) > len(graph[v])):
                l = e_l[w]
                v = w

    return v

def bounding_diameters():
    V = list(graph.keys())
    W = V.copy()

    e_l = {}
    e_u = {}
    e = {}

    for w in W:
        e_l[w] = -INF
        e_u[w] = INF

    delta_l = -INF
    delta_u = INF

    i = 0

    while delta_l != delta_u and len(W) > 0:
        v = select(W, e_l, e_u, i)
        print(f'Selected node {v}')
        e[v], dv = eccentricity(v)

        delta_l = max(delta_l, e[v])
        delta_u = min(delta_u, e[v] * 2)

        to_remove = set()
        for w in W:
            dvw = dv[w]
            e_l[w] = max(e_l[w], max(e[v] - dvw, dvw))
            e_u[w] = min(e_u[w], e[v] + dvw)
            if (e_u[w] <= delta_l and e_l[w] >= delta_u / 2) or e_l[w] == e_u[w]:
                to_remove.add(w)

        for w in to_remove:
            W.remove(w)
        print(W)

        print(format_graph(e_l, e_u, v, W, to_remove, delta_l, delta_u, i))
        print("------")
        i += 1

    return delta_l

print(bounding_diameters())
