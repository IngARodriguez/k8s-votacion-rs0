# _lib.ps1 — Funciones comunes para los scripts de stress y visor.
# No se ejecuta directo.

$global:LOADER_YAML = Join-Path $PSScriptRoot "stress-loader.yaml"

function Ensure-Loader {
    # Aplica el Deployment del loader si no existe (idempotente).
    $exists = kubectl get deployment stress-loader -o name 2>$null
    if (-not $exists) {
        Write-Host "  Creando Deployment stress-loader (busybox que martilla la app)..." -ForegroundColor DarkGray
        kubectl apply -f $global:LOADER_YAML | Out-Null
    }
}

function Set-Stress-Level {
    param(
        [Parameter(Mandatory=$true)][int]$Loaders,
        [Parameter(Mandatory=$true)][string]$Etiqueta,
        [Parameter(Mandatory=$true)][int]$ObjetivoReplicas
    )
    Ensure-Loader
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  STRESS: $Etiqueta" -ForegroundColor Cyan
    Write-Host "  Loaders: $Loaders    Objetivo HPA: ~$ObjetivoReplicas replicas" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    kubectl scale deployment stress-loader --replicas=$Loaders | Out-Null
    Write-Host ""
    Write-Host "  OK Loader escalado a $Loaders pods" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Mira el autoescalado en vivo en otra terminal con:" -ForegroundColor Yellow
    Write-Host "    .\estado-vivo.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "  Para detener la carga:" -ForegroundColor Yellow
    Write-Host "    .\stop-stress.ps1" -ForegroundColor White
    Write-Host ""
}
