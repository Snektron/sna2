#!/usr/bin/env python3
import sys
import graph_tool as gt
import graph_tool.centrality
import scipy.stats
import numpy as np

path = sys.argv[1]
g = gt.load_graph_from_csv(path, directed=False, csv_options={'delimiter': '\t'})
name = g.vp["name"]

print("vertices:", g.num_vertices())
print("edges:", g.num_edges())

def print_top(vprop):
    sorting = np.argsort(vprop.a)

    for i in sorting[:-21:-1]:
        v = g.vertex(i)
        print(name[v], vprop[v], i)
    return sorting

def invert(arr):
    result = np.zeros(arr.shape, dtype=np.uint64)
    for i, j in enumerate(arr):
        result[j] = i
    return result

print("== degree top ==")
degree = g.degree_property_map("total")
degree_rank = invert(print_top(degree))

print("== betweenness top ==")
betweenness, _ = gt.centrality.betweenness(g)
betweenness_rank = invert(print_top(betweenness))

print("== closeness top ==")
closeness = gt.centrality.closeness(g, harmonic=True)
closeness_rank = invert(print_top(closeness))

print("degree/closeness correlation:", scipy.stats.kendalltau(degree_rank, closeness_rank))
print("degree/betweenness correlation:", scipy.stats.kendalltau(degree_rank, betweenness_rank))
print("closeness/betweenness correlation:", scipy.stats.kendalltau(closeness_rank, betweenness_rank))
