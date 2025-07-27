#!/bin/bash

# Habilitar "modo estricto" para capturar errores y evitar que el script continúe si hay fallos
set -e

# Función para mostrar ayuda
mostrar_ayuda() {
    echo "Uso: $0 [FECHA]"
    echo "FECHA: Fecha en formato AAAA-MM-DD (opcional, por defecto usa la fecha actual)"
    echo "Ejemplo: $0 2025-01-15"
    echo "Si no se proporciona fecha, se usará: $(date +"%Y-%m-%d")"
}

# Verificar si se solicita ayuda
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    mostrar_ayuda
    exit 0
fi

# Obtener la fecha: usar parámetro si se proporciona, sino usar fecha actual
if [ $# -eq 1 ]; then
    FECHA="$1"
    # Validar formato de fecha
    if ! [[ $FECHA =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Error: Formato de fecha inválido. Use AAAA-MM-DD"
        mostrar_ayuda
        exit 1
    fi
    # Verificar que la fecha sea válida
    if ! date -d "$FECHA" >/dev/null 2>&1; then
        echo "Error: Fecha inválida: $FECHA"
        exit 1
    fi
    echo "Usando fecha especificada: $FECHA"
else
    FECHA=$(date +"%Y-%m-%d")
    echo "Usando fecha actual: $FECHA"
fi

# Definir el nombre del directorio con el nuevo formato
DIRECTORIO="${FECHA}-Catalogos_Acervos"

# Definir las URLs de los archivos de respaldo con la fecha
URL1="https://acervos.inpi.gob.mx/respaldos/koha_${FECHA//-/}.sql.gz"
URL2="https://acervos.inpi.gob.mx/respaldos/fototeca_${FECHA//-/}.sql.gz"
URL3="https://acervos.inpi.gob.mx/respaldos/dspace_${FECHA//-/}.sql.gz"

echo "Los respaldos se guardarán en la carpeta: $DIRECTORIO"
echo "URLs a descargar:"
echo "  - $URL1"
echo "  - $URL2"
echo "  - $URL3"

# Crear el directorio de respaldo si no existe
mkdir -p "$DIRECTORIO"

# Función para verificar si una URL existe y es accesible
verificar_url() {
    local URL="$1"
    echo "Verificando acceso a: $URL"
    
    # Usar curl para verificar el código de respuesta HTTP
    local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
        -H "Referer: https://acervos.inpi.gob.mx/" \
        "$URL")
    
    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "✓ URL accesible (HTTP $HTTP_CODE)"
        return 0
    else
        echo "✗ Error al acceder a la URL (HTTP $HTTP_CODE)"
        
        # Información adicional según el código de error
        case $HTTP_CODE in
            403) echo "  Motivo: Acceso prohibido (403 Forbidden)" ;;
            404) echo "  Motivo: Archivo no encontrado (404 Not Found)" ;;
            500) echo "  Motivo: Error interno del servidor (500)" ;;
            *) echo "  Motivo: Error HTTP $HTTP_CODE" ;;
        esac
        return 1
    fi
}

# Función para descargar un archivo y guardarlo en la carpeta correspondiente
descargar_archivo() {
    local URL="$1"
    local ARCHIVO=$(basename "$URL")

    echo "Descargando $ARCHIVO..."
    
    # Primero verificar si la URL es accesible
    if ! verificar_url "$URL"; then
        echo "Error: No se puede acceder a $URL"
        return 1
    fi
    
    # Descargar el archivo con curl usando headers que simulan un navegador
    # y mostrando progreso
    if curl -L \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
        -H "Accept-Language: es-ES,es;q=0.8,en-US;q=0.5,en;q=0.3" \
        -H "Accept-Encoding: gzip, deflate, br" \
        -H "Referer: https://acervos.inpi.gob.mx/" \
        -H "DNT: 1" \
        -H "Connection: keep-alive" \
        -H "Upgrade-Insecure-Requests: 1" \
        --progress-bar \
        --connect-timeout 30 \
        --max-time 3600 \
        -o "$DIRECTORIO/$ARCHIVO" \
        "$URL"; then
        echo "✓ $ARCHIVO descargado correctamente."
        
        # Verificar que el archivo se descargó y no está vacío
        if [ -s "$DIRECTORIO/$ARCHIVO" ]; then
            echo "✓ Archivo verificado (tamaño: $(du -h "$DIRECTORIO/$ARCHIVO" | cut -f1))"
        else
            echo "✗ Warning: El archivo descargado está vacío o no se creó correctamente"
            return 1
        fi
    else
        echo "✗ Error al descargar $ARCHIVO"
        return 1
    fi
}

# Variables para el control de errores
ERRORES=0
ARCHIVOS_DESCARGADOS=0

# Array con las URLs para iterar
URLS=("$URL1" "$URL2" "$URL3")

# Descargar cada archivo de respaldo con manejo de errores
for URL in "${URLS[@]}"; do
    echo "=================================================="
    if descargar_archivo "$URL"; then
        ((ARCHIVOS_DESCARGADOS++))
    else
        ((ERRORES++))
        echo "⚠️  Continuando con el siguiente archivo..."
    fi
done

echo "=================================================="
echo "Resumen de descargas:"
echo "Archivos descargados exitosamente: $ARCHIVOS_DESCARGADOS"
echo "Errores encontrados: $ERRORES"

# Solo proceder con la compresión si se descargó al menos un archivo
if [ $ARCHIVOS_DESCARGADOS -gt 0 ]; then
    # Verificar que zip esté instalado
    if ! command -v zip &> /dev/null; then
        echo "Error: zip no está instalado. Instalando..."
        # En sistemas Debian/Ubuntu
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zip
        # En sistemas Red Hat/CentOS/Fedora
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y zip
        elif command -v yum &> /dev/null; then
            sudo yum install -y zip
        else
            echo "No se pudo instalar zip automáticamente. Por favor instálelo manualmente."
            exit 1
        fi
    fi
    
    # Comprimir la carpeta en un archivo ZIP con el mismo nombre
    echo "Comprimiendo la carpeta en un archivo ZIP..."
    if zip -r "${DIRECTORIO}.zip" "$DIRECTORIO"; then
        echo "✓ Archivo ZIP creado: ${DIRECTORIO}.zip"
        
        # Eliminar la carpeta una vez que ha sido comprimida
        echo "Eliminando la carpeta temporal: $DIRECTORIO"
        rm -rf "$DIRECTORIO"
        
        # Mostrar mensaje de finalización
        echo "✓ Proceso completado. Se ha generado el archivo: ${DIRECTORIO}.zip"
        echo "Tamaño del archivo final: $(du -h "${DIRECTORIO}.zip" | cut -f1)"
    else
        echo "✗ Error al crear el archivo ZIP"
        exit 1
    fi
else
    echo "✗ No se pudo descargar ningún archivo. Verifique las URLs y la conectividad."
    echo "Posibles causas:"
    echo "  1. Los archivos para la fecha $FECHA no existen en el servidor"
    echo "  2. El servidor está bloqueando las descargas automáticas"
    echo "  3. Problemas de conectividad de red"
    echo "  4. El servidor requiere autenticación"
    # No eliminar la carpeta para poder inspeccionar qué pasó
    exit 1
fi

# Mostrar estadísticas finales
if [ $ERRORES -gt 0 ]; then
    echo "⚠️  Advertencia: Se completó el proceso pero hubo $ERRORES error(es)."
    exit 2
else
    echo "✓ Todos los archivos se descargaron exitosamente."
fi