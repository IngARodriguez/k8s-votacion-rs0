# stop-stress.ps1 — Detiene toda la carga (escala loader a 0 y elimina el Deployment)
. "$PSScriptRoot\_lib.ps1"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DETENIENDO CARGA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$exists = kubectl get deployment stress-loader -o name 2>$null
if (-not $exists) {
    Write-Host "  (no hay deployment stress-loader desplegado)" -ForegroundColor Yellow
    return
}

Write-Host "  Eliminando deployment stress-loader..." -ForegroundColor Yellow
kubectl delete deployment stress-loader | Out-Null
Write-Host "  OK carga detenida" -ForegroundColor Green
Write-Host ""
Write-Host "  El HPA escalara la app DE VUELTA a 2 replicas en ~2 minutos" -ForegroundColor DarkGray
Write-Host "  (stabilizationWindow de scaleDown = 120s)" -ForegroundColor DarkGray
Write-Host ""
