# conectar-compass.ps1 — Expone mongo-0 (PRIMARY) en localhost:27017
# para que MongoDB Compass pueda conectarse al cluster K8s.
#
# Uso:
#   .\conectar-compass.ps1
#
# En Compass:
#   1. Pega el URI:  mongodb://localhost:27017/?directConnection=true
#   2. Click Connect
#   3. Veras la DB "test_db" -> coleccion "votos"
#
# Para terminar el puente: Ctrl+C en esta ventana.

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PUENTE PARA MONGODB COMPASS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Reenviando mongo-0 (PRIMARY)  -> localhost:27017" -ForegroundColor Yellow
Write-Host ""
Write-Host "  URI para Compass:" -ForegroundColor Green
Write-Host "    mongodb://localhost:27017/?directConnection=true" -ForegroundColor White
Write-Host ""
Write-Host "  Base de datos: test_db" -ForegroundColor Gray
Write-Host "  Coleccion:     votos" -ForegroundColor Gray
Write-Host ""
Write-Host "  (Ctrl+C para terminar el puente)" -ForegroundColor DarkGray
Write-Host ""

kubectl port-forward mongo-0 27017:27017
