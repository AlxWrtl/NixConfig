"""Bouchon de fetch.py pour checks/veille.nix : sortie fixe, marquée par $STUB_TAG."""

import os
import sys

print(f"# Candidats stub {os.environ.get('STUB_TAG', '')}, fenêtre {sys.argv[1]} h\n")
print("## Hacker News (1 éléments)\n- Good | 9pts 2com | https://good.example/a")
