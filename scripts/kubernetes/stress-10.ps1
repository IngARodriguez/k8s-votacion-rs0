# stress-10.ps1 — Carga maxima para que el HPA escale al techo (10 replicas)
. "$PSScriptRoot\_lib.ps1"
Set-Stress-Level -Loaders 10 -Etiqueta "Nivel MAXIMO" -ObjetivoReplicas 10
