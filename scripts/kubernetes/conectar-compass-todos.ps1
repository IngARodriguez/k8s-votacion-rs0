# conectar-compass-todos.ps1 — Expone los 3 nodos del replica set en 27017/27018/27019
# para conectarse a Compass como cliente real del RS (no directConnection).
#
# Uso:
#   .\conectar-compass-todos.ps1
#
# En Compass:
#   URI: mongodb://localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0
#
# Importante: en este modo Compass conecta al RS completo y elige automaticamente
# el PRIMARY. Util para mostrar el rol de cada nodo en la pestana "Performance" -> "ReplicaSet".
#
# Para terminar: Ctrl+C en esta ventana (mata los 3 procesos hijos automaticamente).

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PUENTE COMPLETO PARA COMPASS (rs0)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  mongo-0 -> localhost:27017" -ForegroundColor Yellow
Write-Host "  mongo-1 -> localhost:27018" -ForegroundColor Yellow
Write-Host "  mongo-2 -> localhost:27019" -ForegroundColor Yellow
Write-Host ""
Write-Host "  URI para Compass:" -ForegroundColor Green
Write-Host "    mongodb://localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0" -ForegroundColor White
Write-Host ""
Write-Host "  Si Compass falla por nombres DNS internos, usa modo directo (1 nodo):" -ForegroundColor DarkGray
Write-Host "    mongodb://localhost:27017/?directConnection=true" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  (Ctrl+C aqui termina los 3 puentes)" -ForegroundColor DarkGray
Write-Host ""

$jobs = @()
try {
    $jobs += Start-Process kubectl -ArgumentList "port-forward","mongo-0","27017:27017" -PassThru -NoNewWindow
    $jobs += Start-Process kubectl -ArgumentList "port-forward","mongo-1","27018:27017" -PassThru -NoNewWindow
    $jobs += Start-Process kubectl -ArgumentList "port-forward","mongo-2","27019:27017" -PassThru -NoNewWindow
    Write-Host "  Puentes activos. Esperando... (Ctrl+C para salir)" -ForegroundColor Green
    while ($true) { Start-Sleep -Seconds 5 }
} finally {
    Write-Host ""
    Write-Host "  Cerrando puentes..." -ForegroundColor Yellow
    foreach ($p in $jobs) {
        if ($p -and -not $p.HasExited) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    Write-Host "  OK" -ForegroundColor Green
}
