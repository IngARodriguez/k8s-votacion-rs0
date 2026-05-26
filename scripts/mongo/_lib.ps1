# _lib.ps1 — Funciones comunes para los scripts apagar/encender/estado.
# No se ejecuta directamente. Los otros scripts hacen: . $PSScriptRoot\_lib.ps1

# Mapeo pod -> etiqueta corta (neutral, el rol se obtiene en vivo del RS)
$global:NODOS = [ordered]@{
    "mongo-0"     = "Nodo 1"
    "mongo-1"     = "Nodo 2"
    "mongo-2"     = "Nodo 3"
    "mongo-arb-0" = "Arbitro"
}

# Puertos locales fijos para port-forward de cada nodo (solo nodos de datos)
$global:PUERTOS = @{
    "mongo-0" = 27017
    "mongo-1" = 27018
    "mongo-2" = 27019
}

# Carpeta donde guardamos los PIDs de los port-forward para poder matarlos despues
$global:PIDDIR = Join-Path $PSScriptRoot ".pf"
if (-not (Test-Path $global:PIDDIR)) { New-Item -ItemType Directory -Path $global:PIDDIR -Force | Out-Null }

function Start-PortForward {
    param([string]$Pod, [int]$LocalPort)
    Stop-PortForward -Pod $Pod
    $proc = Start-Process kubectl `
        -ArgumentList "port-forward","$Pod","$($LocalPort):27017" `
        -PassThru -WindowStyle Hidden
    Set-Content -Path (Join-Path $global:PIDDIR "$Pod.pid") -Value $proc.Id -Encoding ASCII
    Start-Sleep -Milliseconds 1500
    return $proc.Id
}

function Stop-PortForward {
    param([string]$Pod)
    $pidFile = Join-Path $global:PIDDIR "$Pod.pid"
    if (Test-Path $pidFile) {
        $procId = (Get-Content $pidFile -Raw).Trim()
        if ($procId) {
            try { Stop-Process -Id ([int]$procId) -Force -ErrorAction SilentlyContinue } catch {}
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
}

function Mostrar-URI-Compass {
    param([string]$Pod, [int]$LocalPort, [string]$Etiqueta)
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host "  CONEXION COMPASS para $Etiqueta" -ForegroundColor Green
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  URI:" -ForegroundColor Yellow
    Write-Host "    mongodb://localhost:$LocalPort/?directConnection=true" -ForegroundColor White
    Write-Host ""
    Write-Host "  Base de datos: test_db" -ForegroundColor Gray
    Write-Host "  Coleccion:     votos" -ForegroundColor Gray
    Write-Host "  Pod:           $Pod  ->  localhost:$LocalPort" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  El puente queda corriendo en segundo plano hasta que apagues el nodo." -ForegroundColor DarkGray
    Write-Host ""
}

function Apagar-Pod {
    # Apagado SIMPLE (sin marker) — kubelet lo reinicia en segundos.
    # Lo usa solo el arbitro (no necesita persistencia).
    param([string]$Etiqueta, [string]$Pod)
    Write-Host ""
    Write-Host "  Apagando $Etiqueta  [pod: $Pod]" -ForegroundColor Yellow
    kubectl exec $Pod -- mongosh --quiet --eval "try { db.adminCommand({shutdown:1, force:true}) } catch(e) {}" 2>$null | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "  X  $Etiqueta APAGADO" -ForegroundColor Red
}

function Encender-Pod {
    param([string]$Etiqueta, [string]$Pod)
    Write-Host ""
    Write-Host "  Esperando a que $Etiqueta  [pod: $Pod] vuelva Ready..." -ForegroundColor Yellow
    kubectl wait --for=condition=ready pod/$Pod --timeout=120s | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK $Etiqueta ENCENDIDO" -ForegroundColor Green
    } else {
        Write-Host "  X  Timeout esperando $Etiqueta" -ForegroundColor Red
    }
}

# --- Apagado PERSISTENTE para nodos de datos ---------------------------------
# Crea el marker file en el PVC. El container, al reiniciarse, ve el marker
# y entra en bucle de sleep (Ready=False) hasta que el marker se borre.

function Apagar-Pod-Persistente {
    param([string]$Etiqueta, [string]$Pod)
    Write-Host ""
    Write-Host "  Apagando $Etiqueta  [pod: $Pod] de forma PERSISTENTE" -ForegroundColor Yellow
    # 1. Crear marker en el volumen persistente
    kubectl exec $Pod -- sh -c "touch /data/db/.k8s-shutdown" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Aviso: no se pudo crear el marker (pod tal vez ya esta apagado)" -ForegroundColor DarkYellow
    }
    # 2. Apagar mongod (el container se reinicia, ve el marker, queda dormido)
    kubectl exec $Pod -- mongosh --quiet --eval "try { db.adminCommand({shutdown:1, force:true}) } catch(e) {}" 2>$null | Out-Null
    Start-Sleep -Seconds 3
    Write-Host "  X  $Etiqueta APAGADO (quedara apagado hasta que lo enciendas)" -ForegroundColor Red
}

function Encender-Pod-Persistente {
    param([string]$Etiqueta, [string]$Pod)
    Write-Host ""
    Write-Host "  Encendiendo $Etiqueta  [pod: $Pod]" -ForegroundColor Yellow
    # 1. Borrar marker — el wrapper sale del sleep en max 5s y arranca mongod
    $intentos = 0
    while ($intentos -lt 20) {
        kubectl exec $Pod -- sh -c "rm -f /data/db/.k8s-shutdown" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 2
        $intentos++
    }
    if ($intentos -ge 20) {
        Write-Host "  X  No se pudo borrar el marker (pod no respondia)" -ForegroundColor Red
        return
    }
    # 2. Esperar Ready
    Write-Host "  Marker borrado. Esperando a que mongod arranque..." -ForegroundColor DarkGray
    kubectl wait --for=condition=ready pod/$Pod --timeout=120s | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK $Etiqueta ENCENDIDO" -ForegroundColor Green
    } else {
        Write-Host "  X  Timeout esperando $Etiqueta" -ForegroundColor Red
    }
}

function Estado-Cluster {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  CLUSTER MONGO (rs0)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # 1. Recoger estado K8s de cada pod
    $estadoPods = [ordered]@{}
    foreach ($entry in $global:NODOS.GetEnumerator()) {
        $pod = $entry.Key
        $info = kubectl get pod $pod -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $info) {
            $estadoPods[$pod] = @{ Existe=$false; Ready=$false; Phase="NoExiste"; Restarts=0 }
        } else {
            $estadoPods[$pod] = @{
                Existe = $true
                Ready = ($info.status.containerStatuses | Select-Object -First 1).ready
                Phase = $info.status.phase
                Restarts = ($info.status.containerStatuses | Select-Object -First 1).restartCount
            }
        }
    }

    # 2. Buscar un pod Ready para consultar rs.status (si ninguno esta Ready saltamos esa parte)
    $podConsulta = $null
    foreach ($p in $global:NODOS.Keys) {
        if ($p -ne "mongo-arb-0" -and $estadoPods[$p].Ready) { $podConsulta = $p; break }
    }
    if (-not $podConsulta) {
        foreach ($p in $global:NODOS.Keys) {
            if ($estadoPods[$p].Ready) { $podConsulta = $p; break }
        }
    }

    # 3. Recoger roles del RS (si hay algun pod Ready)
    $rolRS = @{}
    if ($podConsulta) {
        $js = 'try { rs.status().members.forEach(function(m){ print(m.name, m.stateStr, m.health) }) } catch(e) { print(ERROR, e.message) }'
        $out = & kubectl exec $podConsulta -- mongosh --quiet --eval $js 2>$null
        foreach ($line in $out) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = ($line -replace '\s+', ' ').Trim() -split ' '
            if ($parts.Count -ge 3) {
                $name = ($parts[0] -split '\.')[0]
                $rolRS[$name] = @{ State=$parts[1]; Health=$parts[2] }
            }
        }
    }

    # 4. Imprimir tabla unificada
    Write-Host ("  {0,-9} {1,-13} {2,-13} {3,-12} {4,-8} {5}" -f "Nodo","Pod","K8s","Rol en RS","Health","Restarts") -ForegroundColor Gray
    Write-Host ("  " + ("-" * 70)) -ForegroundColor DarkGray
    foreach ($entry in $global:NODOS.GetEnumerator()) {
        $pod = $entry.Key
        $label = $entry.Value
        $k = $estadoPods[$pod]
        $rs = $rolRS[$pod]

        if (-not $k.Existe) {
            $linea = ("  {0,-9} {1,-13} {2,-13} {3,-12} {4,-8} {5}" -f $label, $pod, "NoExiste", "-", "-", "-")
            Write-Host "X $linea" -ForegroundColor Red
            continue
        }

        $k8sLabel = if ($k.Ready) { "Ready" } else { "NotReady" }
        $rolStr = if ($k.Ready -and $rs) { $rs.State } else { "-" }
        $healthStr = if ($k.Ready -and $rs) { $rs.Health } else { "-" }
        $linea = ("  {0,-9} {1,-13} {2,-13} {3,-12} {4,-8} {5}" -f $label, $pod, $k8sLabel, $rolStr, $healthStr, $k.Restarts)

        # Color basado en el estado real combinado
        if (-not $k.Ready) {
            Write-Host "X $linea" -ForegroundColor Red
        } elseif ($rs -and $rs.Health -eq "0") {
            Write-Host "! $linea" -ForegroundColor Yellow
        } elseif ($rolStr -eq "PRIMARY") {
            Write-Host "* $linea" -ForegroundColor Green
        } elseif ($rolStr -eq "SECONDARY") {
            Write-Host "o $linea" -ForegroundColor Cyan
        } elseif ($rolStr -eq "ARBITER") {
            Write-Host "o $linea" -ForegroundColor Magenta
        } else {
            Write-Host "? $linea" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "  Leyenda:  * PRIMARY    o SECONDARY/ARBITER    X APAGADO    ! UNREACHABLE" -ForegroundColor DarkGray
}

function Estado-App {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  APP DE VOTACION + HPA" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    kubectl get deployment voting-app
    Write-Host ""
    kubectl get hpa voting-app-hpa
}
