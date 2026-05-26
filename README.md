# Sistema de Votación Electrónica — Registraduría Nacional

Aplicación web de votación con Node.js, Express y MongoDB (Atlas / Replica Set / Local).

---

## Arranque rápido

```bash
npm install
node server.js
```

Abrir en: `http://localhost:3000`  
Panel admin: `http://localhost:3000/admin.html` — usuario: `admin` / clave: `registraduria2026`

---

## Cambiar modo de conexión

Editar **una línea** en `server.js`:

```js
const MODO = 'atlas';    // MongoDB Atlas (nube)
const MODO = 'replica';  // Replica set local rs0 (27017-27019 + árbitro 27020)
const MODO = 'local';    // MongoDB nodo único local (27017)
```

---

## Reiniciar el servidor

```powershell
# PowerShell — matar puerto 3000 y reiniciar
$proc = (Get-NetTCPConnection -LocalPort 3000 -State Listen).OwningProcess
Stop-Process -Id $proc -Force
node server.js
```

```bash
# Git Bash
kill $(netstat -ano | grep :3000 | grep LISTEN | awk '{print $5}') 2>/dev/null
node server.js
```

---

## Configuracion de nodos de replicidad en
```bash
https://github.com/IngARodriguez/mongo-replica-rs0
```

## Modo Replica Set Local (rs0)

### Apagar nodos uno por uno

```bash
mongosh --port 27017 --eval "db.adminCommand({shutdown: 1})"
mongosh --port 27018 --eval "db.adminCommand({shutdown: 1})"
mongosh --port 27019 --eval "db.adminCommand({shutdown: 1})"
mongosh --port 27020 --eval "db.adminCommand({shutdown: 1})"
```

### Encender nodos uno por uno

```bash
mongod --config "C:\data\nodo1\mongod.cfg"
mongod --config "C:\data\nodo2\mongod.cfg"
mongod --config "C:\data\nodo3\mongod.cfg"
mongod --config "C:\data\arb\mongod.cfg"
```

## Estructura del proyecto

```
crud_page/
├── index.html               # Página de votación
├── admin.html               # Panel administrativo
├── server.js                # API Express + conexión MongoDB
├── icons/
│   └── fondos_oscuros.svg   # Logo Registraduría
├── package.json
└── .gitignore
```
