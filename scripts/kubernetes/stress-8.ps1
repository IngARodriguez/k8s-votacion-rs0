# stress-8.ps1 — Genera carga media para que el HPA escale ~8 replicas
. "$PSScriptRoot\_lib.ps1"
Set-Stress-Level -Loaders 5 -Etiqueta "Nivel MEDIO" -ObjetivoReplicas 8
