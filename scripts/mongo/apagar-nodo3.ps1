# apagar-nodo3.ps1 — Apaga el Nodo 3 (mongo-2) PERSISTENTEMENTE
# Queda apagado hasta que ejecutes .\encender-nodo3.ps1
. "$PSScriptRoot\_lib.ps1"
Stop-PortForward -Pod "mongo-2"
Write-Host "  Puente Compass de Nodo 3 cerrado (localhost:27019)" -ForegroundColor DarkGray
Apagar-Pod-Persistente "Nodo 3" "mongo-2"
