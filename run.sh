#!/usr/bin/env bash
# ==============================================================================
# Boilerplate d'installation - Environnement de dev Debian WSL
# Installe et configure : Zsh, Oh My Zsh, Powerlevel10k (précision 0.0001s),
# plugins Zsh, Vim, wslview, uv (Python), fnm + Node LTS, GitHub CLI & SSH.
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

# ==============================================================================
# 0. Paramètres du profil (Git & SSH)
# ==============================================================================
info "Configuration du profil Git et SSH"
read -rp "Nom Git (ex: Timothée Vannier) : " GIT_NAME
read -rp "Email Git / SSH (ex: moi@exemple.com) : " GIT_EMAIL
read -rp "Nom de la clé SSH sur GitHub [Debian-WSL] : " SSH_KEY_TITLE
SSH_KEY_TITLE="${SSH_KEY_TITLE:-Debian-WSL}"

# ==============================================================================
# 1. Mise à jour Debian & paquets système
# ==============================================================================
info "Mise à jour du système et installation des paquets de base..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  git curl wget zsh fzf unzip build-essential vim ca-certificates gnupg

success "Paquets de base installés."

# ==============================================================================
# 2. Configuration de Vim (~/.vimrc)
# ==============================================================================
info "Configuration de Vim (~/.vimrc)..."
cat << 'EOF' > "$HOME/.vimrc"
set nocompatible
syntax on
filetype plugin indent on

" Affichage
set number
set relativenumber
set cursorline
set showcmd
set wildmenu
set termguicolors
colorscheme desert

" Indentation (4 espaces)
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set smartindent

" Recherche
set ignorecase
set smartcase
set incsearch
set hlsearch

" Confort
set mouse=a
set encoding=utf-8
set backspace=indent,eol,start
EOF
success "Vim configuré."

# ==============================================================================
# 3. Passerelle navigateur Windows (wslview)
# ==============================================================================
if [ -x /mnt/c/Windows/explorer.exe ]; then
  info "Création du wrapper /usr/local/bin/wslview pour WSL..."
  sudo tee /usr/local/bin/wslview > /dev/null << 'EOF'
#!/bin/sh
/mnt/c/Windows/explorer.exe "$1" >/dev/null 2>&1 || true
EOF
  sudo chmod +x /usr/local/bin/wslview
  success "wslview installé."
else
  warn "/mnt/c/Windows/explorer.exe introuvable : création de wslview ignorée."
fi

# ==============================================================================
# 4. Oh My Zsh, Powerlevel10k et plugins Zsh
# ==============================================================================
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  info "Installation de Oh My Zsh..."
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  success "Oh My Zsh est déjà installé."
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_or_update() {
  local repo="$1"
  local dest="$2"
  local extra_args="${3:-}"
  if [ ! -d "$dest" ]; then
    # shellcheck disable=SC2086
    git clone $extra_args "$repo" "$dest"
  else
    git -C "$dest" pull --ff-only || true
  fi
}

info "Installation de Powerlevel10k et des plugins Zsh..."
clone_or_update "https://github.com/romkatv/powerlevel10k.git" "$ZSH_CUSTOM/themes/powerlevel10k" "--depth=1"
clone_or_update "https://github.com/zsh-users/zsh-autosuggestions" "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_or_update "https://github.com/joshskidmore/zsh-fzf-history-search" "$ZSH_CUSTOM/plugins/zsh-fzf-history-search"
clone_or_update "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# Configuration de ~/.zshrc
info "Mise à jour de ~/.zshrc..."
ZSHRC="$HOME/.zshrc"

# Thème Powerlevel10k
if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

# Plugins (zsh-syntax-highlighting impérativement en dernier)
awk '
  /^plugins=\(/ {
    print "plugins=("
    print "  git"
    print "  zsh-autosuggestions"
    print "  zsh-fzf-history-search"
    print "  zsh-syntax-highlighting"
    print ")"
    in_plugins = ($0 !~ /\)/)
    next
  }
  in_plugins {
    if ($0 ~ /\)/) in_plugins = 0
    next
  }
  { print }
' "$ZSHRC" > "${ZSHRC}.tmp" && mv "${ZSHRC}.tmp" "$ZSHRC"

# Ajout du bloc personnalisé (idempotent)
if ! grep -q "# >>> wsl-boilerplate >>>" "$ZSHRC"; then
  cat << 'EOF' >> "$ZSHRC"

# >>> wsl-boilerplate >>>
export BROWSER=wslview
export PATH="$HOME/.local/bin:$PATH"

# Applique la précision 0.0001s sur Powerlevel10k après p10k configure
p10k-precision() {
  if [ -f "$HOME/.p10k.zsh" ]; then
    sed -i 's/POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=.*/POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=0/' "$HOME/.p10k.zsh"
    sed -i 's/POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=.*/POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=4/' "$HOME/.p10k.zsh"
    source "$HOME/.p10k.zsh"
    echo "Précision Powerlevel10k réglée sur 0.0001s."
  else
    echo "~/.p10k.zsh introuvable. Lance d'abord 'p10k configure'."
  fi
}
# <<< wsl-boilerplate <<<
EOF
fi

# Si ~/.p10k.zsh existe déjà (ex: ré-exécution du script), on applique directement la précision
if [ -f "$HOME/.p10k.zsh" ]; then
  sed -i 's/POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=.*/POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=0/' "$HOME/.p10k.zsh"
  sed -i 's/POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=.*/POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=4/' "$HOME/.p10k.zsh"
fi

# Définir Zsh comme shell par défaut
if [ "$(basename "$SHELL")" != "zsh" ]; then
  info "Passage de Zsh en shell par défaut..."
  sudo chsh -s "$(which zsh)" "$USER"
fi
success "Oh My Zsh, Powerlevel10k et plugins configurés."

# ==============================================================================
# 5. uv (Gestionnaire Python)
# ==============================================================================
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
  info "Installation de uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  success "uv est déjà installé."
fi

# ==============================================================================
# 6. fnm + Node.js LTS & npm
# ==============================================================================
FNM_DIR="$HOME/.local/share/fnm"
if [ ! -d "$FNM_DIR" ] && ! command -v fnm >/dev/null 2>&1; then
  info "Installation de fnm..."
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

if ! grep -q 'fnm env' "$ZSHRC"; then
  cat << 'EOF' >> "$ZSHRC"

# fnm (Node.js)
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell zsh)"
EOF
fi

export PATH="$FNM_DIR:$PATH"
eval "$(fnm env --shell bash)"
info "Installation de Node.js LTS via fnm..."
fnm install --lts
fnm default lts-latest
success "Node $(node -v) et npm $(npm -v) installés."

# ==============================================================================
# 7. GitHub CLI (gh)
# ==============================================================================
if ! command -v gh >/dev/null 2>&1; then
  info "Installation de GitHub CLI (gh)..."
  sudo mkdir -p -m 755 /etc/apt/keyrings
  out=$(mktemp)
  wget -nv -O "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  rm -f "$out"
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update
  sudo apt install -y gh
else
  success "GitHub CLI est déjà installé."
fi

# ==============================================================================
# 8. Configuration Git & Clé SSH Ed25519
# ==============================================================================
info "Configuration de Git..."
[ -n "$GIT_NAME" ]  && git config --global user.name "$GIT_NAME"
[ -n "$GIT_EMAIL" ] && git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main

SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  info "Génération de la clé SSH Ed25519..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "${GIT_EMAIL:-$USER@wsl}" -f "$SSH_KEY"
else
  success "Clé SSH $SSH_KEY déjà existante."
fi

# ==============================================================================
# 9. Connexion GitHub CLI en SSH
# ==============================================================================
gh config set git_protocol ssh
echo ""
read -rp "Se connecter à GitHub CLI maintenant et uploader la clé SSH ? [O/n] : " DO_GH_AUTH
DO_GH_AUTH="${DO_GH_AUTH:-O}"

if [[ "$DO_GH_AUTH" =~ ^[OoYy]$ ]]; then
  export BROWSER=wslview
  gh auth login -h github.com -p ssh -s admin:public_key -w
  if ! gh ssh-key list | grep -qF "$(cut -d' ' -f2 "${SSH_KEY}.pub")"; then
    gh ssh-key add "${SSH_KEY}.pub" --title "$SSH_KEY_TITLE"
  fi
  success "GitHub CLI authentifié en SSH et clé ajoutée."
fi

# ==============================================================================
# Fin & dernières étapes manuelles
# ==============================================================================
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN} Installation terminée !${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "Étapes finales :"
echo -e "  1. Vérifie que la police ${YELLOW}MesloLGS NF${NC} est active dans Windows Terminal."
echo -e "  2. Lance Zsh maintenant avec : ${BLUE}exec zsh${NC}"
echo -e "  3. Termine l'assistant ${BLUE}p10k configure${NC}, puis exécute : ${BLUE}p10k-precision${NC}"
echo -e "     (pour activer l'affichage du temps d'exécution à 0.0001s)."
