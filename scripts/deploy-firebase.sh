#!/bin/bash
# Script de despliegue de Firebase
# Uso: ./scripts/deploy-firebase.sh

echo "=== Desplegando Firestore (reglas + índices) ==="
firebase deploy --only firestore

echo ""
echo "=== Desplegando Storage (reglas) ==="
firebase deploy --only storage

echo ""
echo "=== Desplegando Cloud Functions ==="
firebase deploy --only functions

echo ""
echo "=== Despliegue completado ==="
echo "Recuerda ejecutar el script de inicialización de datos:"
echo "  export GOOGLE_APPLICATION_CREDENTIALS=ruta/a/service-account.json"
echo "  node functions/init-firebase-data.js"
