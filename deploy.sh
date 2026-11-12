#!/usr/bin/env bash

# Salir inmediatamente si ocurre un error, si falta una variable o si falla un pipe
set -euo pipefail

# Colores para salida formateada en consola
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== SmartQuail Core: Auto-Setup de Proyecto Django ERP / Analítica ===${NC}"

# 0. Verificación de prerrequisitos de sistema
if ! command -v uv &> /dev/null; then
    echo -e "${RED}Error: 'uv' no está instalado. Instálalo ejecutando: curl -LsSf https://astral.sh/uv/install.sh | sh${NC}"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: 'git' no está instalado.${NC}"
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: La CLI de GitHub ('gh') no está instalada.${NC}"
    exit 1
fi

# 1. Configurar identidad de Git automáticamente si existen variables
if [ -n "${GIT_USER_NAME:-}" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

# 2. Autenticar GitHub CLI evitando colisiones con la variable GH_TOKEN activa
if [ -n "${GH_TOKEN:-}" ]; then
    TEMP_GH_TOKEN="$GH_TOKEN"
    unset GH_TOKEN
    echo "$TEMP_GH_TOKEN" | gh auth login --with-token
    export GH_TOKEN="$TEMP_GH_TOKEN"
    echo -e "${GREEN}✓ GitHub CLI autenticado correctamente.${NC}"
else
    echo -e "${YELLOW}⚠️ Aviso: La variable GH_TOKEN no está presente. Omitiendo login automático en GitHub.${NC}"
fi

# 3. Solicitar el nombre del proyecto dinámicamente o leerlo de variable de entorno
PROJECT_NAME="${PROJECT_NAME:-}"
if [ -z "$PROJECT_NAME" ]; then
    read -p "Introduce el nombre del proyecto Django (ej. core_analytics): " RAW_PROJECT_NAME
    PROJECT_NAME=$(echo "$RAW_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr '-' '_' | tr -cd '[:alnum:]_')
fi

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: El nombre del proyecto no puede estar vacío.${NC}"
    exit 1
fi

# 4. Solicitar el nombre de la app inicial
APP_NAME="${APP_NAME:-}"
if [ -z "$APP_NAME" ]; then
    read -p "Introduce la aplicación inicial (ej. sba, sbl, sbm, core): " RAW_APP_NAME
    APP_NAME=$(echo "$RAW_APP_NAME" | tr '[:upper:]' '[:lower:]' | tr '-' '_' | tr -cd '[:alnum:]_')
fi

if [ -z "$APP_NAME" ]; then
    echo -e "${RED}Error: El nombre de la aplicación no puede estar vacío.${NC}"
    exit 1
fi

GH_ORG="${GH_ORG:-smartquailstage}"
VISIBILITY_CHOICE="${REPO_VISIBILITY:-private}"
if [ "$VISIBILITY_CHOICE" = "public" ]; then
    REPO_FLAG="--public"
else
    REPO_FLAG="--private"
fi

# 5. Determinar archivo de dependencias (requirements)
REQ_FILE="pk.txt"
if [ -f "pks/${APP_NAME}.txt" ]; then
    REQ_FILE="pks/${APP_NAME}.txt"
    echo -e "${GREEN}--> Usando dependencias específicas: $REQ_FILE${NC}"
else
    echo -e "${YELLOW}--> Usando dependencias predeterminadas: $REQ_FILE${NC}"
fi

# 6. Determinar plantillas de settings
BASE_TEMPLATE="settings/base.txt"
LOCAL_TEMPLATE="settings/local.txt"
PROD_TEMPLATE="settings/prod.txt"

if [ -d "settings/${APP_NAME}" ]; then
    BASE_TEMPLATE="settings/${APP_NAME}/base.txt"
    LOCAL_TEMPLATE="settings/${APP_NAME}/local.txt"
    PROD_TEMPLATE="settings/${APP_NAME}/prod.txt"
    echo -e "${GREEN}--> Usando plantillas de settings específicas para: $APP_NAME${NC}"
fi

# Verificar la existencia física de las plantillas requeridas
for f in "$REQ_FILE" "$BASE_TEMPLATE" "$LOCAL_TEMPLATE" "$PROD_TEMPLATE"; do
    if [ ! -f "$f" ]; then
        echo -e "${RED}Error: No se encuentra el archivo requerido '$f'${NC}"
        exit 1
    fi
done

# 7. Creación e instalación del entorno virtual
echo -e "${BLUE}--> Creando entorno virtual con Python 3.12 usando 'uv'...${NC}"
uv venv .venv --python 3.12

# Activar venv según el sistema operativo
if [ -d ".venv/bin" ]; then
    source .venv/bin/activate
else
    source .venv/Scripts/activate
fi

echo -e "${BLUE}--> Instalando Django 5.1.x y dependencias...${NC}"
uv pip install "Django>=5.1,<5.2" gunicorn
if [ -s "$REQ_FILE" ]; then
    uv pip install -r "$REQ_FILE"
fi

# 8. Inicializar estructura del proyecto Django
echo -e "${BLUE}--> Inicializando proyecto Django: $PROJECT_NAME...${NC}"
django-admin startproject "$PROJECT_NAME" .

echo -e "${BLUE}--> Configurando estructura modular de Settings...${NC}"
mkdir -p "$PROJECT_NAME/settings"
rm -f "$PROJECT_NAME/settings.py"
touch "$PROJECT_NAME/settings/__init__.py"

# Copiar y reemplazar tokens dinámicos en los settings
sed -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" -e "s/{{APP_NAME}}/$APP_NAME/g" "$BASE_TEMPLATE" > "$PROJECT_NAME/settings/base.py"
sed -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" -e "s/{{APP_NAME}}/$APP_NAME/g" "$LOCAL_TEMPLATE" > "$PROJECT_NAME/settings/local.py"
sed -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" -e "s/{{APP_NAME}}/$APP_NAME/g" "$PROD_TEMPLATE" > "$PROJECT_NAME/settings/prod.py"

# 9. Gestión de la App inicial
echo -e "${BLUE}--> Creando la aplicación Django: $APP_NAME...${NC}"
python manage.py startapp "$APP_NAME"

if [ -d "apps/$APP_NAME" ]; then
    echo -e "${GREEN}--> Reemplazando app '$APP_NAME' con el módulo preconstruido en 'apps/$APP_NAME'...${NC}"
    rm -rf "$APP_NAME"
    cp -r "apps/$APP_NAME" "$APP_NAME"
fi

# 10. Reemplazar `urls.py` si existe plantilla personalizada
URLS_TEMPLATE="urls/${APP_NAME}/urls.py"
if [ -f "$URLS_TEMPLATE" ]; then
    echo -e "${GREEN}--> Inyectando 'urls.py' personalizado desde '$URLS_TEMPLATE'...${NC}"
    cp "$URLS_TEMPLATE" "$PROJECT_NAME/urls.py"
fi

# 11. Generar archivo `.env` completo y seguro
echo -e "${BLUE}--> Generando configuración de variables de entorno (.env)...${NC}"
NEW_SECRET=$(python -c 'import django.core.management.utils; print(django.core.management.utils.get_random_secret_key())')

cat << EOF > .env
# Configuración Global
PROJECT_NAME=$PROJECT_NAME
DJANGO_SETTINGS_MODULE=$PROJECT_NAME.settings.local
SECRET_KEY=$NEW_SECRET
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1,0.0.0.0

# Almacenamiento y Archivos
MEDIA_URL=/media/
STATIC_URL=/static/

# Configuración Base de Datos (Por defecto SQLite local)
DATABASE_URL=sqlite:///db.sqlite3

# Correo (Predeterminado para evitar errores en Gunicorn)
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=localhost
EMAIL_PORT=587
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
EMAIL_USE_TLS=True
EOF

# 12. Ajustar manage.py para apuntar por defecto a settings.local
sed -i "s/'$PROJECT_NAME.settings'/'$PROJECT_NAME.settings.local'/g" manage.py || true

# 13. Generación automática de GitHub Actions workflows optimizados con Gunicorn
echo -e "${BLUE}--> Generando workflows de CI/CD para GitHub Actions...${NC}"
mkdir -p .github/workflows

# A. Workflow de Pruebas unitarias con Gunicorn y Postgres
cat << EOF > .github/workflows/app_test.yaml
name: SmartQuail Django-app & Postgres Test ${PROJECT_NAME}

on:
  workflow_call:
  workflow_dispatch:

jobs:
  app_test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: .
    env:
      DJANGO_SECRET_KEY: test-key-not-good
      NAME_DB: ${PROJECT_NAME^^}_STDB
      PASSWORD_DB: Support1719@
      USER_DB: sqadmindb
      HOST_DB: smartquaildb
      PORT_DB: 5432 
      DB_IGNORE_SSL: "true"

    services:
      smartquaildb:
        image: postgres:16-alpine
        env: 
          POSTGRES_DB: ${PROJECT_NAME^^}_STDB
          POSTGRES_PASSWORD: Support1719@
          POSTGRES_USER: sqadmindb
          POSTGRES_HOST: smartquaildb
          POSTGRES_PORT: 5432 
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    strategy:
      max-parallel: 4
      matrix:
        python-version: ["3.11"]

    steps:
      - uses: actions/checkout@v3

      - name: Set up Python \${{ matrix.python-version }}
        uses: actions/setup-python@v3
        with:
          python-version: \${{ matrix.python-version }}

      - name: Install Dependencies
        run: |
          python3 -m pip install --upgrade pip
          if [ -f "pks/${APP_NAME}.txt" ]; then
            pip3 install -r pks/${APP_NAME}.txt
          elif [ -f "pk.txt" ]; then
            pip3 install -r pk.txt
          fi
          pip3 install gunicorn

      - name: Start Gunicorn server check
        run: |
          gunicorn ${PROJECT_NAME}.wsgi:application --bind 0.0.0.0:8000 --workers 2 &
          sleep 5

      - name: Run Tests with Django
        run: |
          python3 manage.py test --settings=${PROJECT_NAME}.settings.prod
EOF

# B. Workflow de Docker Build y Push
cat << EOF > .github/workflows/docker_build.yaml
name: SmartQuail Docker Build Apps ${PROJECT_NAME}

on:
  workflow_call:
  workflow_dispatch:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  app_test:
    uses: ${GH_ORG}/${PROJECT_NAME}/.github/workflows/app_test.yaml@main

  Docker_container_build:
    runs-on: ubuntu-latest
    needs: [app_test]
    env:
      DJANGO_SECRET_KEY: test-key-not-good

    steps:
      - name: Checkout code
        uses: actions/checkout@v3 

      - name: Login to Docker Hub
        uses: docker/login-action@v1
        with:
          username: \${{ secrets.DOCKER_HUB_USERNAME }}
          password: \${{ secrets.DOCKER_HUB_ACCESS_TOKEN }}

      - name: Build container image
        run: | 
          docker build -f Dockerfile \
              -t smartquail/${PROJECT_NAME}:latest \
              -t smartquail/${PROJECT_NAME}:\${GITHUB_SHA::2}-\${GITHUB_RUN_ID::2} \
              .

      - name: Push Image
        run: | 
          docker push smartquail/${PROJECT_NAME} --all-tags
EOF

# 14. Generación de .gitignore profesional
cat << 'EOF' > .gitignore
# Python / Entorno virtual
.venv/
venv/
ENV/
__pycache__/
*.py[cod]
*$py.class
*.so

# Bases de Datos y Almacenamiento Local
db.sqlite3
media/
staticfiles/

# Variables de entorno y secretos
.env
*.pem
*.p12

# Logs y Cache
*.log
.uwsgi_plugins/

# IDEs y Sistema
.vscode/
.idea/
*.swp
*.swo
.DS_Store
EOF

# 15. Inicialización de Git local y primer Commit
echo -e "${BLUE}--> Inicializando repositorio Git local...${NC}"
if [ ! -d ".git" ]; then
    git init -b main
else
    git branch -M main
fi

git add .
git commit -m "chore: scaffold project structure, gunicorn CI/CD workflows and gitignore" || true

# 16. Creación e integración remota con GitHub via CLI si está autenticado
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo -e "${BLUE}--> Creando repositorio en GitHub (${GH_ORG}/${PROJECT_NAME})...${NC}"
    gh repo create "${GH_ORG}/${PROJECT_NAME}" $REPO_FLAG --source=. --remote=origin --push || true
    
    if [ -n "${DOCKER_HUB_ACCESS_TOKEN:-}" ]; then
        echo -e "${BLUE}--> Inyectando secretos en GitHub Actions...${NC}"
        echo "${DOCKER_HUB_USERNAME:-smartquail}" | gh secret set DOCKER_HUB_USERNAME --repo "${GH_ORG}/${PROJECT_NAME}"
        echo "$DOCKER_HUB_ACCESS_TOKEN" | gh secret set DOCKER_HUB_ACCESS_TOKEN --repo "${GH_ORG}/${PROJECT_NAME}"
    fi
fi

echo -e "${GREEN}=== ¡Proyecto '$PROJECT_NAME' y módulo '$APP_NAME' creados y configurados exitosamente con Gunicorn! ===${NC}"
echo -e "Para levantar la instancia de desarrollo local ejecuta:"
echo -e "  ${YELLOW}source .venv/bin/activate${NC}"
echo -e "  ${YELLOW}python manage.py migrate${NC}"
echo -e "  ${YELLOW}python manage.py runserver 0.0.0.0:8000${NC}"