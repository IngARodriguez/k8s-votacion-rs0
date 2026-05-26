# apagar-nodo2.ps1 — Apaga el Nodo 2 (mongo-1) PERSISTENTEMENTE
# Queda apagado hasta que ejecutes .\encender-nodo2.ps1
. "$PSScriptRoot\_lib.ps1"
Stop-PortForward -Pod "mongo-1"
Write-Host "  Puente Compass de Nodo 2 cerrado (localhost:27018)" -ForegroundColor DarkGray
Apagar-Pod-Persistente "Nodo 2" "mongo-1"
