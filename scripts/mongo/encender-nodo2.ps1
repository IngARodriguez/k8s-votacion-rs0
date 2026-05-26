# encender-nodo2.ps1 — Enciende el Nodo 2 (mongo-1) y abre puente Compass en :27018
. "$PSScriptRoot\_lib.ps1"
Encender-Pod-Persistente "Nodo 2" "mongo-1"
if ($LASTEXITCODE -eq 0) {
    $port = $global:PUERTOS["mongo-1"]
    Start-PortForward -Pod "mongo-1" -LocalPort $port | Out-Null
    Mostrar-URI-Compass -Pod "mongo-1" -LocalPort $port -Etiqueta "Nodo 2"
}
