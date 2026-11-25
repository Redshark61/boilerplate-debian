#!/usr/bin/env bash
# ==============================================================================
# Boilerplate Odoo & Migrations - Debian WSL
# Installe et configure :
#   - Dépendances système (compilation psycopg2, python-ldap, lxml, Pillow...)
#   - PostgreSQL + rôle superutilisateur local
#   - wkhtmltopdf 0.12.6.1-3 (Qt patché pour rapports PDF QWeb)
#   - Versions Python via uv + gestionnaire de venvs dans ~/.virtualenvs/
#   - Outils CLI OCA & migration (odoo-module-migrator, click-odoo-contrib,
#     git-aggregator, pre-commit, ruff, pgcli)
# ==============================================================================

set -euo pipefail

# --- Couleurs pour les logs ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "\n${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERREUR]${NC} $1" >&2; }

export PATH="$HOME/.local/bin:$PATH"

# ==============================================================================
# 0. Vérification des prérequis & paramètres
# ==============================================================================
if ! command -v uv >/dev/null 2>&1; then
  error "uv est introuvable. Lance d'abord setup-wsl-debian.sh ou installe uv."
  exit 1
fi

info "Configuration des versions Python à préinstaller avec uv"
read -rp "Versions Python (séparées par des espaces) [3.10 3.12] : " PYTHON_VERSIONS
PYTHON_VERSIONS="${PYTHON_VERSIONS:-3.10 3.12}"

# ==============================================================================
# 1. Bibliothèques système pour compiler les dépendances Odoo
# ==============================================================================
info "Installation des bibliothèques système Odoo..."
sudo apt update
sudo apt install -y \
  libpq-dev libxml2-dev libxslt1-dev libldap2-dev libsasl2-dev \
  libffi-dev libjpeg-dev zlib1g-dev libssl-dev liblcms2-dev \
  libwebp-dev pkg-config python3-dev

success "Bibliothèques système installées."

# ==============================================================================
# 2. PostgreSQL & rôle superutilisateur local
# ==============================================================================
info "Installation et configuration de PostgreSQL..."
sudo apt install -y postgresql postgresql-client

if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
  sudo systemctl enable --now postgresql
else
  sudo service postgresql start
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$USER'" | grep -q 1; then
  sudo -u postgres createuser -s "$USER"
  success "Rôle superutilisateur PostgreSQL '$USER' créé."
else
  success "Rôle PostgreSQL '$USER' déjà existant."
fi

# ==============================================================================
# 3. wkhtmltopdf (Qt patché - 0.12.6.1-3)
# ==============================================================================
if ! command -v wkhtmltopdf >/dev/null 2>&1; then
  info "Installation de wkhtmltopdf 0.12.6.1-3 (Qt patché)..."
  WK_DEB="wkhtmltox_0.12.6.1-3.bookworm_amd64.deb"
  WK_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/${WK_DEB}"
  TMP_DEB="/tmp/${WK_DEB}"

  wget -q --show-progress -O "$TMP_DEB" "$WK_URL"
  if sudo apt install -y "$TMP_DEB"; then
    success "wkhtmltopdf installé : $(wkhtmltopdf --version)"
  else
    warn "Impossible d'installer wkhtmltopdf via le .deb Bookworm (dépendance manquante sur cette version de Debian)."
  fi
  rm -f "$TMP_DEB"
else
  success "wkhtmltopdf déjà installé : $(wkhtmltopdf --version)"
fi

# ==============================================================================
# 4. Multi-versions Python (uv) & dossier centralisé ~/.virtualenvs/
# ==============================================================================
info "Installation des versions Python ($PYTHON_VERSIONS) via uv..."
# shellcheck disable=SC2086
uv python install $PYTHON_VERSIONS
success "Versions Python installées."

info "Configuration du dossier ~/.virtualenvs/ et des raccourcis Zsh..."
mkdir -p "$HOME/.virtualenvs"

ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"

if ! grep -q "# >>> odoo-boilerplate >>>" "$ZSHRC"; then
  cat << 'EOF' >> "$ZSHRC"

# >>> odoo-boilerplate >>>
export WORKON_HOME="$HOME/.virtualenvs"

# Crée et active un environnement Python dans ~/.virtualenvs/<nom>
# Usage : mkvenv odoo17 3.12
mkvenv() {
  local name="${1:-}"
  local pyver="${2:-3.12}"
  if [ -z "$name" ]; then
    echo "Usage : mkvenv <nom> [version_python, ex: 3.12]"
    return 1
  fi
  mkdir -p "$WORKON_HOME"
  uv venv --python "$pyver" "$WORKON_HOME/$name" && source "$WORKON_HOME/$name/bin/activate"
}

# Active un environnement existant (ou liste les environnements si aucun argument)
# Usage : workon odoo17
workon() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "Environnements disponibles dans $WORKON_HOME :"
    ls -1 "$WORKON_HOME" 2>/dev/null || echo "  (aucun)"
    return 0
  fi
  if [ -f "$WORKON_HOME/$name/bin/activate" ]; then
    source "$WORKON_HOME/$name/bin/activate"
  else
    echo "Environnement introuvable : $WORKON_HOME/$name" >&2
    return 1
  fi
}

# Supprime un environnement virtuel
# Usage : rmvenv odoo17
rmvenv() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "Usage : rmvenv <nom>"
    return 1
  fi
  if [ -d "$WORKON_HOME/$name" ]; then
    rm -rf "$WORKON_HOME/$name"
    echo "Environnement supprimé : $name"
  else
    echo "Environnement introuvable : $WORKON_HOME/$name" >&2
    return 1
  fi
}

# Autocomplétion Zsh pour workon et rmvenv
_workon_complete() {
  local -a envs
  envs=("$WORKON_HOME"/*(N/:t))
  _describe 'virtualenvs' envs
}
compdef _workon_complete workon rmvenv
# <<< odoo-boilerplate <<<
EOF
  success "Fonctions mkvenv / workon / rmvenv ajoutées à ~/.zshrc."
else
  success "Bloc odoo-boilerplate déjà présent dans ~/.zshrc."
fi

# ==============================================================================
# 5. Outils CLI OCA, qualité & migrations (via uv tool)
# ==============================================================================
info "Installation des outils CLI Odoo/OCA avec uv tool..."
TOOLS=(
  odoo-module-migrator
  click-odoo-contrib
  git-aggregator
  pre-commit
  ruff
  pgcli
)

for tool in "${TOOLS[@]}"; do
  info "Installation de $tool..."
  uv tool install "$tool" || uv tool upgrade "$tool"
done
success "Tous les outils CLI sont installés."

# ==============================================================================
# Fin
# ==============================================================================
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN} Environnement Odoo prêt !${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "Recharge Zsh avec : ${BLUE}source ~/.zshrc${NC}"
echo -e "Commandes disponibles pour tes environnements (~/.virtualenvs/) :"
echo -e "  ${BLUE}mkvenv odoo17 3.12${NC}  -> crée et active ~/.virtualenvs/odoo17"
echo -e "  ${BLUE}workon odoo17${NC}       -> active l'environnement (avec autocomplétion Tab)"
echo -e "  ${BLUE}workon${NC}              -> liste tous tes environnements"
echo -e "  ${BLUE}rmvenv odoo17${NC}       -> supprime un environnement"
