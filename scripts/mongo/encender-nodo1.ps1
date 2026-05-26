# encender-nodo1.ps1 — Enciende el Nodo 1 (mongo-0) y abre puente Compass en :27017
. "$PSScriptRoot\_lib.ps1"
Encender-Pod-Persistente "Nodo 1" "mongo-0"
if ($LASTEXITCODE -eq 0) {
    $port = $global:PUERTOS["mongo-0"]
    Start-PortForward -Pod "mongo-0" -LocalPort $port | Out-Null
    Mostrar-URI-Compass -Pod "mongo-0" -LocalPort $port -Etiqueta "Nodo 1"
}
