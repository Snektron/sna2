#!/usr/bin/env python3
import sys
import graph_tool as gt
import graph_tool.inference
import graph_tool.draw
import numpy as np

path = sys.argv[1]
g = gt.load_graph_from_csv(path, directed=False, csv_options={'delimiter': '\t'})
name = g.vp["name"]

print("vertices:", g.num_vertices())
print("edges:", g.num_edges())

# print("Fetching blockmodel")
# state = gt.inference.minimize_blockmodel_dl(g, deg_corr = True)

# levels = state.get_levels()
# for s in levels:
#     print(s)

print("Drawing")
# state.draw(output="out.pdf")


pos = gt.draw.sfdp_layout(g)
gt.draw.graph_draw(g, pos=pos, output="graph-draw-sfdp.pdf")