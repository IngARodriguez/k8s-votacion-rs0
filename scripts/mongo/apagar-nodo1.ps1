# apagar-nodo1.ps1 — Apaga el Nodo 1 (mongo-0) PERSISTENTEMENTE
# Queda apagado hasta que ejecutes .\encender-nodo1.ps1
. "$PSScriptRoot\_lib.ps1"
Stop-PortForward -Pod "mongo-0"
Write-Host "  Puente Compass de Nodo 1 cerrado (localhost:27017)" -ForegroundColor DarkGray
Apagar-Pod-Persistente "Nodo 1" "mongo-0"
