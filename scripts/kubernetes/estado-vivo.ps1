# estado-vivo.ps1 — Visualizador en tiempo real del autoescalado.
# Refresca cada 2s. Detener con Ctrl+C.

function Pintar {
    Clear-Host
    $now = Get-Date -Format "HH:mm:ss"
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ("  AUTOESCALADO EN VIVO   ({0})" -f $now) -ForegroundColor Cyan
    Write-Host "  (Ctrl+C para salir)" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan

    # --- HPA ---
    $hpaJson = kubectl get hpa voting-app-hpa -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($hpaJson) {
        $current = $hpaJson.status.currentReplicas
        $desired = $hpaJson.status.desiredReplicas
        $min = $hpaJson.spec.minReplicas
        $max = $hpaJson.spec.maxReplicas
        $cpuCur = "-"; $cpuTgt = "-"; $memCur = "-"; $memTgt = "-"
        foreach ($m in $hpaJson.status.currentMetrics) {
            if ($m.resource.name -eq "cpu")    { $cpuCur = "$($m.resource.current.averageUtilization)%" }
            if ($m.resource.name -eq "memory") { $memCur = "$($m.resource.current.averageUtilization)%" }
        }
        foreach ($m in $hpaJson.spec.metrics) {
            if ($m.resource.name -eq "cpu")    { $cpuTgt = "$($m.resource.target.averageUtilization)%" }
            if ($m.resource.name -eq "memory") { $memTgt = "$($m.resource.target.averageUtilization)%" }
        }

        Write-Host ""
        Write-Host "  HPA voting-app-hpa" -ForegroundColor White
        Write-Host ("    replicas actuales: {0}    deseadas: {1}    rango: {2}-{3}" -f $current,$desired,$min,$max) -ForegroundColor Gray
        Write-Host ("    CPU:    {0,-6} / objetivo {1}" -f $cpuCur, $cpuTgt) -ForegroundColor Gray
        Write-Host ("    Memoria:{0,-6} / objetivo {1}" -f $memCur, $memTgt) -ForegroundColor Gray

        # Mini-grafico de replicas
        Write-Host ""
        $bar = ""
        for ($i = 1; $i -le $max; $i++) {
            if ($i -le $current)      { $bar += "[#]" }
            elseif ($i -le $desired)  { $bar += "[.]" }
            else                       { $bar += "[ ]" }
        }
        $color = if ($current -ge 8) { "Red" } elseif ($current -ge 5) { "Yellow" } else { "Green" }
        Write-Host ("  Replicas: $bar  ($current/$max)") -ForegroundColor $color
    } else {
        Write-Host "  (HPA voting-app-hpa no encontrado)" -ForegroundColor Red
    }

    # --- Pods voting-app ---
    Write-Host ""
    Write-Host "  Pods voting-app:" -ForegroundColor White
    $pods = kubectl get pods -l app=voting-app --no-headers 2>$null
    if ($pods) {
        foreach ($line in $pods -split "`n") {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $cols = ($line -replace '\s+', ' ').Trim() -split ' '
            $name = $cols[0]; $ready = $cols[1]; $status = $cols[2]; $age = $cols[4]
            $color = if ($status -eq "Running" -and $ready -match '^[1-9]+/[1-9]+$') { "Green" } else { "Yellow" }
            Write-Host ("    {0,-32} {1,-6} {2,-12} {3}" -f $name, $ready, $status, $age) -ForegroundColor $color
        }
    }

    # --- Loaders ---
    Write-Host ""
    $loaderJson = kubectl get deployment stress-loader -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($loaderJson) {
        $lr = $loaderJson.status.replicas
        $lrReady = $loaderJson.status.readyReplicas
        Write-Host ("  Stress-loader: {0} pods (ready {1})" -f $lr, $lrReady) -ForegroundColor Magenta
    } else {
        Write-Host "  Stress-loader: (no desplegado - sin carga)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

while ($true) {
    try { Pintar } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Start-Sleep -Seconds 2
}
