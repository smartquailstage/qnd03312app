#!/bin/bash

# Salir inmediatamente si ocurre un error
set -e

echo "=== Configuración Avanzada de Proyecto Django ERP / Analítica ==="

# 1. Solicitar el nombre del proyecto dinámicamente
read -p "Introduce el nombre del proyecto Django: " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: El nombre del proyecto no puede estar vacío."
    exit 1
fi

# 2. Solicitar el nombre de la app inicial dinámicamente
read -p "Introduce el nombre de la aplicación inicial (ej. sba, sbl, sbm, core): " APP_NAME

if [ -z "$APP_NAME" ]; then
    echo "Error: El nombre de la aplicación no puede estar vacío."
    exit 1
fi

# Definir dinámicamente el archivo de dependencias (pk) según la app
if [ "$APP_NAME" = "sba" ] || [ "$APP_NAME" = "sbl" ] || [ "$APP_NAME" = "sbm" ]; then
    if [ -f "pks/${APP_NAME}.txt" ]; then
        REQ_FILE="pks/${APP_NAME}.txt"
        echo "--> Usando el archivo de dependencias específico: $REQ_FILE"
    else
        REQ_FILE="pk.txt"
        echo "--> [Aviso] No existe 'pks/${APP_NAME}.txt'. Usando el predeterminado: $REQ_FILE"
    fi
else
    REQ_FILE="pk.txt"
    echo "--> Usando el archivo de dependencias predeterminado: $REQ_FILE"
fi

# Seleccionar dinámicamente el set de templates de settings según la app
if [ "$APP_NAME" = "sba" ] || [ "$APP_NAME" = "sbl" ] || [ "$APP_NAME" = "sbm" ]; then
    if [ -d "settings/${APP_NAME}" ]; then
        BASE_TEMPLATE="settings/${APP_NAME}/base.txt"
        LOCAL_TEMPLATE="settings/${APP_NAME}/local.txt"
        PROD_TEMPLATE="settings/${APP_NAME}/prod.txt"
        echo "--> Usando plantillas de settings específicas para: $APP_NAME"
    else
        BASE_TEMPLATE="settings/base.txt"
        LOCAL_TEMPLATE="settings/local.txt"
        PROD_TEMPLATE="settings/prod.txt"
        echo "--> [Aviso] No existe el directorio 'settings/${APP_NAME}'. Usando plantillas predeterminadas."
    fi
else
    BASE_TEMPLATE="settings/base.txt"
    LOCAL_TEMPLATE="settings/local.txt"
    PROD_TEMPLATE="settings/prod.txt"
    echo "--> Usando plantillas de settings predeterminadas"
fi

# Verificar archivos requeridos de plantillas de configuración y dependencias
for f in "$REQ_FILE" "$BASE_TEMPLATE" "$LOCAL_TEMPLATE" "$PROD_TEMPLATE"; do
    if [ ! -f "$f" ]; then
        echo "Error: No se encuentra el archivo requerido '$f' en el directorio actual."
        exit 1
    fi
done

echo "--> Creando entorno virtual con Python 3.12 usando 'uv'..."
uv venv --python 3.12

echo "--> Activando el entorno virtual..."
source .venv/bin/activate

echo "--> Asegurando la instalación de Django y dependencias desde '$REQ_FILE'..."
uv pip install "Django>=5.1,<5.2"
if [ -f "$REQ_FILE" ] && [ -s "$REQ_FILE" ]; then
    uv pip install -r "$REQ_FILE"
fi

echo "--> Creando el proyecto Django: $PROJECT_NAME..."
django-admin startproject "$PROJECT_NAME"

echo "--> Configurando la carpeta 'settings' modular..."
cd "$PROJECT_NAME"

# Crear la carpeta settings y eliminar el settings.py antiguo de la raíz del módulo
mkdir -p "$PROJECT_NAME/settings"
rm -f "$PROJECT_NAME/settings.py"

# Dejar el __init__.py completamente vacío dentro de settings/
touch "$PROJECT_NAME/settings/__init__.py"

# Copiar las plantillas a sus respectivos archivos dentro de settings/
cp "../$BASE_TEMPLATE" "$PROJECT_NAME/settings/base.py"
cp "../$LOCAL_TEMPLATE" "$PROJECT_NAME/settings/local.py"
cp "../$PROD_TEMPLATE" "$PROJECT_NAME/settings/prod.py"

echo "--> Creando la aplicación Django: $APP_NAME..."
python manage.py startapp "$APP_NAME"

# Lógica de reemplazo si la app es sba, sbl o sbm buscando en la ruta raíz apps/
if [[ "$APP_NAME" =~ ^(sba|sbl|sbm)$ ]] && [ -d "../apps/$APP_NAME" ]; then
    echo "--> Reemplazando la carpeta de la app '$APP_NAME' con la estructura externa de 'apps/$APP_NAME'..."
    rm -rf "$APP_NAME"
    cp -r "../apps/$APP_NAME" "$APP_NAME"
elif [[ "$APP_NAME" =~ ^(sba|sbl|sbm)$ ]]; then
    echo "--> Nota: Se seleccionó '$APP_NAME' pero no se encontró la ruta externa '../apps/$APP_NAME'. Se mantiene la generada por Django."
fi

# Reemplazar urls.py del proyecto si existe un archivo personalizado en urls/{APP_NAME}/urls.py
URLS_TEMPLATE="../urls/${APP_NAME}/urls.py"
if [[ "$APP_NAME" =~ ^(sba|sbl|sbm)$ ]] && [ -f "$URLS_TEMPLATE" ]; then
    echo "--> Reemplazando 'urls.py' del proyecto con la plantilla específica para '$APP_NAME'..."
    cp "$URLS_TEMPLATE" "$PROJECT_NAME/urls.py"
elif [[ "$APP_NAME" =~ ^(sba|sbl|sbm)$ ]]; then
    echo "--> [Aviso] No se encontró el archivo '$URLS_TEMPLATE'. Se mantiene el urls.py predeterminado de Django."
fi

cd ..

echo "--> Generando archivo .env básico..."
cat << EOF > .env
PROJECT_NAME=$PROJECT_NAME
SECRET_KEY=$(python -c 'import django.core.management.utils; print(django.core.management.utils.get_random_secret_key())')
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
EOF

echo "=== ¡Proyecto '$PROJECT_NAME' y app '$APP_NAME' configurados con éxito! ==="
echo "Para correr el servidor de desarrollo, ejecuta:"
echo "  source .venv/bin/activate"
echo "  cd $PROJECT_NAME"
echo "  export DJANGO_SETTINGS_MODULE=$PROJECT_NAME.settings.local"
echo "  python manage.py migrate"
echo "  python manage.py runserver"