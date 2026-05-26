# estado.ps1 — Estado del cluster (mongo + RS + app + HPA)
# Uso: .\estado.ps1

. "$PSScriptRoot\_lib.ps1"

Estado-Cluster
Estado-App
Write-Host ""
