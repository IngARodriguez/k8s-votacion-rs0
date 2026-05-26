# Sistema de Votación Electrónica sobre Kubernetes con MongoDB rs0

App web de votación (Node.js + Express + MongoDB) desplegada en **Kubernetes** (Minikube) con un **MongoDB replica set rs0** real de 3 nodos + 1 árbitro, **autoescalado horizontal** de la app (HPA), y scripts de PowerShell para operar el cluster y demostrar tolerancia a fallos.

---

## Tabla de contenidos

1. [Arquitectura](#1-arquitectura)
2. [Prerrequisitos](#2-prerrequisitos)
3. [Setup desde cero](#3-setup-desde-cero)
4. [Manifiestos Kubernetes](#4-manifiestos-kubernetes-explicados)
5. [Operar el cluster con los scripts](#5-operar-el-cluster-con-los-scripts)
6. [Visualizar los datos con MongoDB Compass](#6-visualizar-los-datos-con-mongodb-compass)
7. [Pruebas de estrés y autoescalado](#7-pruebas-de-estrés-y-autoescalado)
8. [Guion de demostración](#8-guion-de-demostración)
9. [Limpieza](#9-limpieza)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Arquitectura

```
                                ┌──────────────────────────────┐
                                │  Usuario (navegador)         │
                                └──────────────┬───────────────┘
                                               │ HTTP
                                               ▼
                                ┌──────────────────────────────┐
                                │  Service voting-app-svc      │
                                │  (NodePort 30080)            │
                                └──────────────┬───────────────┘
                                               │
                       ┌───────────────────────┴───────────────────────┐
                       ▼                                               ▼
            ┌──────────────────┐                              ┌──────────────────┐
            │  voting-app pod  │   ... (2 a 10 réplicas)      │  voting-app pod  │
            │  Node.js + Express                              │  Node.js + Express│
            └─────────┬────────┘                              └─────────┬────────┘
                      │                                                 │
                      │  HPA (CPU 50% / Mem 70%) ajusta replicas        │
                      │  Deployment.voting-app                          │
                      │                                                 │
                      └───────────────────────┬─────────────────────────┘
                                              │ mongodb://...?replicaSet=rs0
                                              ▼
                              ┌────────────────────────────────┐
                              │  Service mongo-svc (headless)  │
                              └───┬──────────────┬─────────────┘
                                  │              │
              ┌───────────────────┼──────────────┼───────────────────┐
              ▼                   ▼              ▼                   ▼
       ┌────────────┐      ┌────────────┐  ┌────────────┐      ┌──────────────┐
       │  mongo-0   │      │  mongo-1   │  │  mongo-2   │      │ mongo-arb-0  │
       │  PRIMARY   │◀────▶│ SECONDARY  │  │ SECONDARY  │      │  ARBITER     │
       │  prio=10   │      │  prio=1    │  │  prio=1    │      │  (vota)      │
       └─────┬──────┘      └─────┬──────┘  └─────┬──────┘      └──────────────┘
             │                   │               │
        PVC 1Gi             PVC 1Gi          PVC 1Gi               PVC 256Mi
```

### Componentes

| Recurso K8s | Nombre | Función |
|---|---|---|
| `Deployment` | `voting-app` | App Node.js, 2 réplicas iniciales |
| `Service` (NodePort) | `voting-app-svc` | Expone la app en el puerto 30080 |
| `HorizontalPodAutoscaler` | `voting-app-hpa` | Escala la app 2→10 réplicas según CPU/Memoria |
| `StatefulSet` | `mongo` | 3 nodos de datos con replica set `rs0` |
| `StatefulSet` | `mongo-arb` | 1 árbitro del replica set |
| `Service` (headless) | `mongo-svc` | DNS estable: `mongo-0.mongo-svc`, `mongo-1...` |
| `Service` (headless) | `mongo-arb-svc` | DNS estable: `mongo-arb-0.mongo-arb-svc` |
| `Job` | `mongo-init-rs` | Ejecuta `rs.initiate(...)` una sola vez |
| `PVC` (×4) | `mongo-data-mongo-*` | Almacenamiento persistente de cada nodo |

### ¿Por qué replica set rs0?

Es una réplica del setup local descrito en el repo [mongo-replica-rs0](https://github.com/IngARodriguez/mongo-replica-rs0), pero en lugar de 4 procesos `mongod` en tu máquina, son 4 pods en Kubernetes que sobreviven a reinicios y se autocoordinan.

- **`mongo-0`** tiene `priority: 10` → siempre que esté arriba será el PRIMARY
- **`mongo-1`, `mongo-2`** tienen `priority: 1` → SECONDARY normalmente, pero pueden ser elegidos PRIMARY si `mongo-0` cae
- **`mongo-arb-0`** es ARBITER → no guarda datos, solo vota en elecciones (necesario para mantener mayoría con número par de nodos votantes)

---

## 2. Prerrequisitos

| Herramienta | Versión mínima | Uso |
|---|---|---|
| **Windows 10/11** | — | Sistema operativo de referencia |
| **PowerShell** | 5.1+ | Ejecutar los scripts |
| **Docker Desktop** | 20+ | Driver de Minikube **y** build de la imagen de la app |
| **kubectl** | 1.28+ | Cliente de Kubernetes |
| **Minikube** | 1.30+ | Cluster local de Kubernetes |
| **Git** | 2.x | Clonar el repo |
| **MongoDB Compass** | latest | Opcional: visualizar datos |

### Instalar con winget (recomendado)

```powershell
winget install Docker.DockerDesktop
winget install Kubernetes.kubectl
winget install Kubernetes.minikube
winget install Git.Git
winget install MongoDB.Compass.Full
```

> Después de instalar Docker Desktop hay que **abrirlo y esperar** a que arranque el daemon (icono verde en bandeja).

### Habilitar ejecución de scripts en PowerShell

Solo la primera vez:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## 3. Setup desde cero

### Paso 1 — Clonar el repo

```powershell
git clone https://github.com/IngARodriguez/k8s-votacion-rs0.git
cd k8s-votacion-rs0
```

### Paso 2 — Arrancar Minikube

Asegúrate de que **Docker Desktop esté corriendo** antes de este paso.

```powershell
minikube start --driver=docker
```

Esto descarga ~520 MB la primera vez (imagen base del nodo) y demora 2–5 min. Al terminar verás:

```
✅ Done! kubectl is now configured to use "minikube" cluster
```

Verifica:

```powershell
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   1m    v1.35.1
```

### Paso 3 — Habilitar metrics-server (necesario para el HPA)

```powershell
minikube addons enable metrics-server
```

Sin este addon el HPA se queda en `cpu: <unknown>/50%` y no escala.

### Paso 4 — Construir la imagen de la app dentro de Minikube

Minikube usa **su propio daemon de Docker**, así que apuntamos nuestro `docker` allí y compilamos:

```powershell
# Apuntar docker al daemon de Minikube (solo en esta terminal)
& minikube docker-env --shell powershell | Out-String | Invoke-Expression

# Construir la imagen
docker build -t voting-app:latest .
```

Esto crea la imagen `voting-app:latest` **dentro del cluster**, así Kubernetes puede usarla con `imagePullPolicy: IfNotPresent` (sin necesidad de un registry externo).

### Paso 5 — Desplegar MongoDB (replica set + árbitro)

```powershell
kubectl apply -f k8s/mongo.yaml
kubectl apply -f k8s/mongo-arbiter.yaml
```

Espera a que los 4 pods estén `Ready`:

```powershell
kubectl wait --for=condition=ready pod/mongo-0 pod/mongo-1 pod/mongo-2 pod/mongo-arb-0 --timeout=300s
```

> La primera vez `mongo:7` pesa ~700 MB → puede tomar 1–2 min.

### Paso 6 — Inicializar el replica set (rs.initiate)

```powershell
kubectl apply -f k8s/mongo-init-job.yaml
kubectl wait --for=condition=complete job/mongo-init-rs --timeout=180s
kubectl logs job/mongo-init-rs
```

Verás:

```
PRIMARY elegido en mongo-0
mongo-0.mongo-svc.default.svc.cluster.local:27017 PRIMARY
mongo-1.mongo-svc.default.svc.cluster.local:27017 SECONDARY
mongo-2.mongo-svc.default.svc.cluster.local:27017 SECONDARY
mongo-arb-0.mongo-arb-svc.default.svc.cluster.local:27017 ARBITER
```

### Paso 7 — Desplegar la app + HPA

```powershell
kubectl apply -f k8s/voting-app.yaml
kubectl apply -f k8s/hpa.yaml
kubectl rollout status deployment/voting-app
```

### Paso 8 — Abrir la app en el navegador

```powershell
minikube service voting-app-svc --url
```

Esto abre un túnel y te da una URL tipo `http://127.0.0.1:5XXXX`. **Mantén esa ventana abierta** mientras uses la app.

- Página principal: la URL devuelta
- Admin: `<URL>/admin.html` — usuario: `admin` / clave: `registraduria2026`

---

## 4. Manifiestos Kubernetes explicados

Todos están en `k8s/`. Cada uno con su rol específico:

### `k8s/mongo.yaml` — Replica set rs0

- **StatefulSet de 3 réplicas** (`mongo-0`, `mongo-1`, `mongo-2`)
- **Headless Service** `mongo-svc` (`clusterIP: None`) → genera DNS estable por pod
- Cada pod arranca con `mongod --replSet rs0`
- **PVC por pod**: 1 GiB cada uno
- **Wrapper especial en el `command`**:
  ```sh
  while [ -f /data/db/.k8s-shutdown ]; do sleep 5; done
  exec mongod --bind_ip_all --replSet rs0 --port 27017
  ```
  Esto permite a los scripts apagar un nodo de forma **persistente** (ver sección 5).

### `k8s/mongo-arbiter.yaml` — Árbitro

- StatefulSet aparte de 1 réplica
- Mismo binario `mongod --replSet rs0` pero rol diferente (lo asigna `rs.initiate`)
- PVC pequeño (256 MiB) porque solo guarda metadatos de elección

### `k8s/mongo-init-job.yaml` — Inicialización del RS

Job que solo se ejecuta una vez. Lanza un pod efímero que:
1. Espera a que los 4 mongods respondan a `ping`
2. Verifica si ya hay un RS configurado (si sí, sale OK)
3. Ejecuta `rs.initiate({...})` definiendo prioridades y rol del árbitro
4. Espera la elección del PRIMARY
5. Imprime el estado final del RS

### `k8s/voting-app.yaml` — App de votación

- **Deployment** de 2 réplicas (estado base, el HPA lo ajusta)
- Variables de entorno:
  - `MODO=replica`
  - `MONGO_URL=mongodb://mongo-0.mongo-svc.default.svc.cluster.local:27017,mongo-1...,mongo-2.../?replicaSet=rs0`
  - `DB_NAME=test_db`
- **Resources**: `requests.cpu=100m` → el HPA calcula porcentajes contra este valor
- **Probes**: `readiness` y `liveness` apuntan a `/` (puerto 3000)
- **Service NodePort 30080** → expuesto al host vía `minikube service`

### `k8s/hpa.yaml` — Autoescalado

```yaml
minReplicas: 2
maxReplicas: 10
metrics:
  - cpu     target 50%
  - memory  target 70%
behavior:
  scaleUp:   stabilizationWindow 15s
  scaleDown: stabilizationWindow 120s
```

- **Scale-up rápido** (15 s) para reaccionar al pico
- **Scale-down lento** (2 min) para evitar oscilaciones

---

## 5. Operar el cluster con los scripts

Hay **dos carpetas separadas** de scripts según el dominio:

```
scripts/
├── mongo/       ← operaciones sobre el replica set (apagar/encender nodos, ver estado)
└── kubernetes/  ← operaciones sobre el autoescalado de la app (stress, visor en vivo)
```

### 5.1 Scripts de Mongo (`scripts/mongo/`)

```
estado.ps1            Vista unificada del cluster (pods + roles RS + HPA)

apagar-nodo1.ps1      Apaga mongo-0 PERSISTENTEMENTE  + cierra puerto Compass
apagar-nodo2.ps1      Apaga mongo-1 PERSISTENTEMENTE  + cierra puerto Compass
apagar-nodo3.ps1      Apaga mongo-2 PERSISTENTEMENTE  + cierra puerto Compass
apagar-arbitro.ps1    Apaga mongo-arb-0 (NO persistente — kubelet lo restaura)

encender-nodo1.ps1    Enciende mongo-0  + abre puente Compass en :27017
encender-nodo2.ps1    Enciende mongo-1  + abre puente Compass en :27018
encender-nodo3.ps1    Enciende mongo-2  + abre puente Compass en :27019
encender-arbitro.ps1  Espera a que mongo-arb-0 vuelva Ready
```

#### Cómo funciona el apagado "persistente"

A diferencia de Kubernetes (que normalmente reinicia los contenedores caídos), nuestros scripts usan el **marker file** del wrapper de `mongo.yaml`:

1. `apagar-nodoN.ps1`:
   - `kubectl exec mongo-X -- sh -c "touch /data/db/.k8s-shutdown"` → crea el archivo marca en el PVC
   - `kubectl exec mongo-X -- mongosh ...shutdown` → mongod sale
   - kubelet reinicia el container → ve el marker → entra en `while sleep 5` → readiness probe falla → **pod queda en estado NotReady de forma indefinida**
2. `encender-nodoN.ps1`:
   - `kubectl exec mongo-X -- sh -c "rm -f /data/db/.k8s-shutdown"` → borra el marker
   - El bucle del wrapper sale (máx 5 s después) → `exec mongod` → pod se pone Ready
   - El script luego abre `kubectl port-forward` automáticamente para Compass

Como el marker vive en el PVC, **sobrevive a reinicios del pod** → el "apagado" es realmente persistente.

#### Ejemplo: `estado.ps1`

```
============================================================
  CLUSTER MONGO (rs0)
============================================================

  Nodo      Pod           K8s        Rol en RS    Health   Restarts
  ----------------------------------------------------------------------
* Nodo 1    mongo-0       Ready      PRIMARY      1        0
o Nodo 2    mongo-1       Ready      SECONDARY    1        0
X Nodo 3    mongo-2       NotReady   -            -        1     ← apagado por script
o Arbitro   mongo-arb-0   Ready      ARBITER      1        0

  Leyenda:  * PRIMARY    o SECONDARY/ARBITER    X APAGADO    ! UNREACHABLE
```

### 5.2 Scripts de Kubernetes (`scripts/kubernetes/`)

```
estado-vivo.ps1                Visor en tiempo real (refresca cada 2 s)
                               Muestra HPA, métricas CPU/Mem y barra de réplicas

stress-4.ps1                   Lanza carga LIGERA  → HPA escala ~4 réplicas
stress-8.ps1                   Lanza carga MEDIA   → HPA escala ~8 réplicas
stress-10.ps1                  Lanza carga MÁXIMA  → HPA llega a 10
stop-stress.ps1                Detiene los generadores de carga

stress-loader.yaml             Deployment de busybox que martilla el Service

conectar-compass.ps1           Puerto-forward de mongo-0 → :27017
                               + URI directConnection para Compass
conectar-compass-todos.ps1     Puerto-forward de mongo-0,1,2 → :27017,18,19
                               + URI con replicaSet=rs0
```

### 5.3 Uso típico

```powershell
cd scripts\mongo
.\estado.ps1                  # ver estado
.\apagar-nodo2.ps1            # tumbar el SECONDARY
.\estado.ps1                  # mongo-1 aparece X NotReady
.\encender-nodo2.ps1          # restaurar (abre Compass auto)
```

---

## 6. Visualizar los datos con MongoDB Compass

Las opciones de conexión:

### Opción A — Auto, al encender un nodo

```powershell
cd scripts\mongo
.\encender-nodo1.ps1
```

El script muestra la URI lista:

```
URI: mongodb://localhost:27017/?directConnection=true
```

Pégala en Compass → Connect.

| Script | Nodo conectado | URI |
|---|---|---|
| `encender-nodo1.ps1` | mongo-0 (PRIMARY normalmente) | `mongodb://localhost:27017/?directConnection=true` |
| `encender-nodo2.ps1` | mongo-1 (SECONDARY) | `mongodb://localhost:27018/?directConnection=true` |
| `encender-nodo3.ps1` | mongo-2 (SECONDARY) | `mongodb://localhost:27019/?directConnection=true` |

Al **apagar** el nodo, el script cierra automáticamente el puente → Compass pierde la conexión (mostrando visualmente que el nodo está caído).

### Opción B — Conexión manual a un nodo cualquiera

```powershell
cd scripts\kubernetes
.\conectar-compass.ps1
```

### Opción C — Conexión al RS completo (3 puertos a la vez)

```powershell
cd scripts\kubernetes
.\conectar-compass-todos.ps1
```

URI: `mongodb://localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0`

En este modo Compass detecta el rol de cada nodo y muestra el panel **Performance → ReplicaSet** con los 4 miembros y su estado en vivo.

### Datos a observar

- Base de datos: **`test_db`**
- Colección: **`votos`**

Cada documento que veas en `votos` es un voto enviado vía `POST /votos` desde la app.

### Dónde viven físicamente los datos

```
(Dentro de la VM de Minikube)
/tmp/hostpath-provisioner/default/
  ├── mongo-data-mongo-0/      ← 1 GiB, PRIMARY
  ├── mongo-data-mongo-1/      ← 1 GiB, SECONDARY (réplica idéntica)
  ├── mongo-data-mongo-2/      ← 1 GiB, SECONDARY (réplica idéntica)
  └── mongo-data-mongo-arb-0/  ← 256 MiB, solo metadatos del arbiter
```

Cada voto se guarda en **3 lugares físicos** → esa es la replicación en acción.

---

## 7. Pruebas de estrés y autoescalado

Usa **dos terminales** lado a lado:

**Terminal A — visor en vivo**:

```powershell
cd scripts\kubernetes
.\estado-vivo.ps1
```

Salida tipo:

```
============================================================
  AUTOESCALADO EN VIVO   (18:42:13)
============================================================

  HPA voting-app-hpa
    replicas actuales: 2    deseadas: 2    rango: 2-10
    CPU:    3%     / objetivo 50%
    Memoria:39%    / objetivo 70%

  Replicas: [#][#][ ][ ][ ][ ][ ][ ][ ][ ]  (2/10)

  Pods voting-app:
    voting-app-6d88799686-aaaaa  1/1   Running   30m
    voting-app-6d88799686-bbbbb  1/1   Running   30m

  Stress-loader: (no desplegado - sin carga)
```

**Terminal B — lanzar carga**:

```powershell
cd scripts\kubernetes

.\stress-4.ps1    # ~4 réplicas (15-30 s después)
.\stress-8.ps1    # ~7-9 réplicas
.\stress-10.ps1   # techo de 10
.\stop-stress.ps1 # detener (vuelve a 2 en ~2 min)
```

En la terminal A verás:

- La barra `[#][#][ ]...` ir llenándose con `#`
- CPU subir de 3% a 100%+
- Pods nuevos aparecer con edad `5s`, `15s`, etc.

### Tiempos importantes del HPA

| Acción | Tiempo |
|---|---|
| Detección de carga (metrics-server) | ~15 s |
| Decisión de scale-up | inmediato (`stabilizationWindow: 15s`) |
| Pod nuevo Ready | ~5–10 s |
| Decisión de scale-down | 2 min de espera (`stabilizationWindow: 120s`) |

El scale-down lento es **intencional**: evita "flapping" si la carga oscila.

---

## 8. Guion de demostración

Flujo recomendado para una presentación de 10–15 minutos:

### A. Mostrar el cluster en pie (1 min)

```powershell
cd scripts\mongo
.\estado.ps1
```

Resaltar:
- 4 nodos Mongo, todos Ready, con sus roles (PRIMARY/SECONDARY/ARBITER)
- 2 réplicas de la app
- HPA con CPU al ~3%

### B. Demo de replicación (3 min)

1. Abrir 3 ventanas de Compass:

   ```powershell
   .\encender-nodo1.ps1   # :27017 PRIMARY
   .\encender-nodo2.ps1   # :27018 SECONDARY
   .\encender-nodo3.ps1   # :27019 SECONDARY
   ```

2. En la app web (URL del `minikube service`), votar.

3. Refrescar la colección `test_db > votos` en las 3 ventanas de Compass:
   → **el mismo documento aparece en los 3 nodos**

### C. Demo de tolerancia a fallos (3 min)

```powershell
.\estado.ps1                  # mongo-0 es PRIMARY
.\apagar-nodo1.ps1            # tumbamos el PRIMARY
.\estado.ps1                  # mongo-0 X NotReady, mongo-1 es ahora PRIMARY
```

- En Compass: la ventana del :27017 muestra "connection lost"
- Insertar un voto desde la app → **sigue funcionando** (el nuevo PRIMARY recibe la escritura)

```powershell
.\encender-nodo1.ps1          # devolvemos mongo-0
.\estado.ps1                  # mongo-0 vuelve a ser PRIMARY (priority 10)
```

### D. Demo de autoescalado (3 min)

Terminal A:
```powershell
cd scripts\kubernetes
.\estado-vivo.ps1
```

Terminal B:
```powershell
.\stress-4.ps1
# esperar 30 s, ver subir a ~4 réplicas
.\stress-10.ps1
# esperar 30-60 s, ver llegar a 10
.\stop-stress.ps1
# ver bajar a 2 (después de 2 min)
```

### E. Cierre

```powershell
.\estado.ps1                  # todo verde, sistema vuelve al baseline
```

---

## 9. Limpieza

### Borrar solo los recursos de la app (sin tocar el cluster)

```powershell
kubectl delete -f k8s/hpa.yaml
kubectl delete -f k8s/voting-app.yaml
kubectl delete -f k8s/mongo-init-job.yaml
kubectl delete -f k8s/mongo-arbiter.yaml
kubectl delete -f k8s/mongo.yaml
kubectl delete pvc -l app=mongo
kubectl delete pvc -l app=mongo-arb
```

### Detener Minikube (conserva el cluster)

```powershell
minikube stop
```

### Borrar el cluster por completo

```powershell
minikube delete
```

---

## 10. Troubleshooting

### `minikube start` se queda colgado descargando

Es la imagen base (~520 MB). Normal la primera vez. Verifica con:

```powershell
docker ps    # debe aparecer un container llamado "minikube"
```

### HPA muestra `cpu: <unknown>/50%`

Falta el metrics-server. Habilítalo:

```powershell
minikube addons enable metrics-server
# Esperar 30-60 s a que arranque
kubectl top pods   # debe devolver valores, no error
```

### Los pods de mongo no se ponen Ready

Pueden estar descargando `mongo:7` (700 MB). Mira:

```powershell
kubectl describe pod mongo-0   # busca eventos "Pulling image"
```

### `kubectl port-forward` falla con "connection refused"

El pod destino no tiene mongod escuchando. Comprueba:

```powershell
kubectl get pods                          # ¿el pod está Ready?
kubectl logs mongo-0 --tail=20            # ¿mongod arrancó?
```

Si el pod está en bucle de sleep por el marker file, ejecuta `encender-nodoX.ps1` para limpiarlo.

### El visor en vivo (`estado-vivo.ps1`) no muestra HPA

```powershell
kubectl get hpa             # ¿existe voting-app-hpa?
kubectl apply -f k8s/hpa.yaml
```

### Cambié algo en `mongo.yaml` pero el pod no toma el cambio

Los StatefulSets hacen rolling-update. Para forzar:

```powershell
kubectl apply -f k8s/mongo.yaml
kubectl rollout restart statefulset mongo
kubectl rollout status statefulset mongo
```

### Quiero ver los logs en vivo de la app

```powershell
kubectl logs -f deployment/voting-app
```

### Quiero entrar a una shell dentro de un pod

```powershell
kubectl exec -it mongo-0 -- bash
kubectl exec -it voting-app-XXXX -- sh
```

---

## Estructura del repositorio

```
voting-app/
├── Dockerfile               # imagen Node.js (used by docker build)
├── package.json
├── server.js                # API Express + driver mongodb (lee MODO/MONGO_URL de env)
├── index.html               # página de votación
├── admin.html               # panel admin (admin / registraduria2026)
├── styles.css
├── icons/
│
├── k8s/                     # Manifiestos Kubernetes
│   ├── mongo.yaml             StatefulSet 3 réplicas + Service headless
│   ├── mongo-arbiter.yaml     StatefulSet 1 réplica (arbiter)
│   ├── mongo-init-job.yaml    Job rs.initiate(...)
│   ├── voting-app.yaml        Deployment + Service NodePort
│   └── hpa.yaml               HorizontalPodAutoscaler
│
└── scripts/                 # Operación del cluster
    ├── mongo/               # Apagar/encender nodos Mongo + estado
    │   ├── _lib.ps1
    │   ├── estado.ps1
    │   ├── apagar-nodo[1-3].ps1   + apagar-arbitro.ps1
    │   └── encender-nodo[1-3].ps1 + encender-arbitro.ps1
    │
    └── kubernetes/          # Stress + visor + Compass
        ├── _lib.ps1
        ├── stress-loader.yaml
        ├── stress-[4|8|10].ps1
        ├── stop-stress.ps1
        ├── estado-vivo.ps1
        ├── conectar-compass.ps1
        └── conectar-compass-todos.ps1
```

---

## Créditos

- App original de votación: Simulacion pagina de votacion / Materia: Sistemas Distribuidos UNIMAYOR [IngARodriguez/votacion_page_mongo_shell](https://github.com/IngARodriguez/votacion_page_mongo_shell)
- Replica set local de referencia: [IngARodriguez/mongo-replica-rs0](https://github.com/IngARodriguez/mongo-replica-rs0)
- Adaptación a Kubernetes + scripts de operación: este repo
