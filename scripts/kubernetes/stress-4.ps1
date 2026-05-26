# stress-4.ps1 — Genera carga ligera para que el HPA escale ~4 replicas
. "$PSScriptRoot\_lib.ps1"
Set-Stress-Level -Loaders 2 -Etiqueta "Nivel LIGERO" -ObjetivoReplicas 4
