# Script de despliegue de Firebase
# Ejecutar cuando tengas el nuevo proyecto configurado y firebase use ya ejecutado
# Uso: .\scripts\deploy-firebase.ps1

Write-Host "=== Desplegando Firestore (reglas + indices) ===" -ForegroundColor Cyan
firebase deploy --only firestore

Write-Host "`n=== Desplegando Storage (reglas) ===" -ForegroundColor Cyan
firebase deploy --only storage

Write-Host "`n=== Desplegando Cloud Functions ===" -ForegroundColor Cyan
firebase deploy --only functions

Write-Host "`n=== Despliegue completado ===" -ForegroundColor Green
Write-Host "Recuerda ejecutar el script de inicializacion de datos:" -ForegroundColor Yellow
Write-Host "  `$env:GOOGLE_APPLICATION_CREDENTIALS = 'ruta\a\service-account.json'" -ForegroundColor Yellow
Write-Host "  node functions/init-firebase-data.js" -ForegroundColor Yellow
