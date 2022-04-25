#!/usr/bin/env python3
import sys

with open(sys.argv[1]) as edges_file:
    def map_edge(edge):
        [src, dst] = edge[:-1].split('\t')
        return (int(src), int(dst))

    edges = list(map(map_edge, edges_file))

with open(sys.argv[2]) as users_file:
    users = list(map(lambda user: user[:-1], users_file))

def map_edge_to_user(edge):
    (src, dst) = edge
    return (users[src], users[dst])

for (src, dst) in edges:
    src_user = users[src]
    dst_user = users[dst]
    print(f'{src_user}\t{dst_user}')
