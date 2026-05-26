# encender-nodo3.ps1 — Enciende el Nodo 3 (mongo-2) y abre puente Compass en :27019
. "$PSScriptRoot\_lib.ps1"
Encender-Pod-Persistente "Nodo 3" "mongo-2"
if ($LASTEXITCODE -eq 0) {
    $port = $global:PUERTOS["mongo-2"]
    Start-PortForward -Pod "mongo-2" -LocalPort $port | Out-Null
    Mostrar-URI-Compass -Pod "mongo-2" -LocalPort $port -Etiqueta "Nodo 3"
}
