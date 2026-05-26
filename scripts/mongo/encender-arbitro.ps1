# encender-arbitro.ps1 — Espera a que el Arbitro (mongo-arb-0) vuelva Ready
. "$PSScriptRoot\_lib.ps1"
Encender-Pod "Arbitro" "mongo-arb-0"
