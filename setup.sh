#!/bin/bash
# my26-rag-stack setup script
# Fully local RAG stack: Qdrant + Ollama + sentence-transformers
# No Homebrew required. Works on macOS Apple Silicon and Linux (x86_64/arm64).
#
# Usage:
#   ./setup.sh                          # local Qdrant (default)
#   ./setup.sh --remote-db 192.168.x.x # remote Qdrant on home server
#   ./setup.sh --vault ~/path/to/vault  # set Obsidian vault path
#   ./setup.sh --skip-ollama            # skip Ollama install (already installed)
#   ./setup.sh --skip-models            # skip model pulls
#   ./setup.sh --install-dir ~/bin      # where to install the rag tool (default: ~/.local/bin)

set -e

# ── Detect OS and arch ────────────────────────────────────────────────────────
OS=$(uname -s)   # Darwin or Linux
ARCH=$(uname -m) # arm64 / aarch64 / x86_64

case "$OS" in
  Darwin)
    if [[ "$ARCH" != "arm64" ]]; then
      echo "❌ macOS requires Apple Silicon (arm64). Got: $ARCH"
      exit 1
    fi
    PLATFORM="macos"
    SHELL_RC="$HOME/.zshrc"
    ;;
  Linux)
    case "$ARCH" in
      x86_64)  PLATFORM="linux-x86_64" ;;
      aarch64) PLATFORM="linux-arm64" ;;
      arm64)   PLATFORM="linux-arm64"; ARCH="aarch64" ;;
      *) echo "❌ Unsupported Linux architecture: $ARCH"; exit 1 ;;
    esac
    SHELL_RC="$HOME/.bashrc"
    ;;
  *) echo "❌ Unsupported OS: $OS"; exit 1 ;;
esac

# ── Defaults ──────────────────────────────────────────────────────────────────
QDRANT_MODE="local"
QDRANT_REMOTE_HOST=""
QDRANT_PORT="6333"
OBSIDIAN_VAULT=""
SKIP_OLLAMA=false
SKIP_MODELS=false
INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/rag"
OLLAMA_VERSION="v0.30.8"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --remote-db)   QDRANT_MODE="remote"; QDRANT_REMOTE_HOST="$2"; shift 2 ;;
    --qdrant-port) QDRANT_PORT="$2"; shift 2 ;;
    --vault)       OBSIDIAN_VAULT="$2"; shift 2 ;;
    --skip-ollama) SKIP_OLLAMA=true; shift ;;
    --skip-models) SKIP_MODELS=true; shift ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ "$QDRANT_MODE" == "remote" ]]; then
  QDRANT_URL="http://$QDRANT_REMOTE_HOST:$QDRANT_PORT"
else
  QDRANT_URL="http://localhost:$QDRANT_PORT"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         my26-rag-stack  setup            ║"
echo "╠══════════════════════════════════════════╣"
echo "║  OS:        $OS ($ARCH)"
echo "║  Qdrant:    $QDRANT_URL"
echo "║  Install:   $INSTALL_DIR"
echo "║  Vault:     ${OBSIDIAN_VAULT:-"(not set — edit config later)"}"
echo "╚══════════════════════════════════════════╝"
echo ""

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# ── Python check ──────────────────────────────────────────────────────────────
echo "▶ Checking Python..."
if ! command -v python3 &>/dev/null; then
  echo "❌ python3 not found."
  if [[ "$OS" == "Linux" ]]; then
    echo "   Install with: sudo apt install python3 python3-pip  (Debian/Ubuntu)"
    echo "             or: sudo dnf install python3              (Fedora/RHEL)"
  else
    echo "   Install from https://www.python.org/downloads/"
  fi
  exit 1
fi
PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
if python3 -c "import sys; exit(0 if sys.version_info >= (3,10) else 1)"; then
  echo "  ✅ Python $PYTHON_VER"
else
  echo "  ❌ Python 3.10+ required, got $PYTHON_VER"
  exit 1
fi

# ── Python dependencies ───────────────────────────────────────────────────────
echo ""
echo "▶ Installing Python dependencies..."
pip install -q qdrant-client ollama sentence-transformers \
               beautifulsoup4 playwright pypdf python-docx
echo "  ✅ Python packages installed"

echo ""
echo "▶ Installing Playwright browser..."
if [[ "$OS" == "Linux" ]]; then
  # Install system deps for Chromium on Linux (requires sudo)
  echo "  Installing Chromium system dependencies (needs sudo)..."
  python3 -m playwright install-deps chromium 2>/dev/null || \
    echo "  ⚠️  Could not install system deps automatically. If Chromium fails, run:"
    echo "      sudo python3 -m playwright install-deps chromium"
fi
python3 -m playwright install chromium --quiet
echo "  ✅ Chromium installed"

# ── Qdrant (local mode only) ──────────────────────────────────────────────────
if [[ "$QDRANT_MODE" == "local" ]]; then
  echo ""
  echo "▶ Installing Qdrant..."
  if command -v qdrant &>/dev/null || [[ -f "$INSTALL_DIR/qdrant" ]]; then
    echo "  ✅ Qdrant already installed"
  else
    QDRANT_RELEASE=$(curl -sf https://api.github.com/repos/qdrant/qdrant/releases/latest \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")

    case "$PLATFORM" in
      macos)         QDRANT_TARBALL="qdrant-aarch64-apple-darwin.tar.gz" ;;
      linux-x86_64)  QDRANT_TARBALL="qdrant-x86_64-unknown-linux-musl.tar.gz" ;;
      linux-arm64)   QDRANT_TARBALL="qdrant-aarch64-unknown-linux-musl.tar.gz" ;;
    esac

    QDRANT_DL="https://github.com/qdrant/qdrant/releases/download/${QDRANT_RELEASE}/${QDRANT_TARBALL}"
    echo "  Downloading Qdrant $QDRANT_RELEASE..."
    curl -sL "$QDRANT_DL" | tar xz -C "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/qdrant"
    echo "  ✅ Qdrant installed to $INSTALL_DIR/qdrant"
  fi

  QDRANT_DATA="$HOME/.local/share/qdrant"
  mkdir -p "$QDRANT_DATA"

  if [[ "$OS" == "Darwin" ]]; then
    # launchd service (macOS)
    PLIST="$HOME/Library/LaunchAgents/com.local.qdrant.plist"
    if [[ ! -f "$PLIST" ]]; then
      cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.qdrant</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/qdrant</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>QDRANT__STORAGE__STORAGE_PATH</key>
    <string>$QDRANT_DATA</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/qdrant.log</string>
  <key>StandardErrorPath</key><string>/tmp/qdrant.log</string>
</dict>
</plist>
PLIST_EOF
      launchctl load "$PLIST"
      echo "  ✅ Qdrant launchd service installed"
    else
      echo "  ✅ Qdrant launchd service already configured"
    fi

  else
    # systemd user service (Linux)
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/qdrant.service" << UNIT_EOF
[Unit]
Description=Qdrant vector database
After=network.target

[Service]
ExecStart=$INSTALL_DIR/qdrant
Environment=QDRANT__STORAGE__STORAGE_PATH=$QDRANT_DATA
Restart=on-failure
StandardOutput=append:/tmp/qdrant.log
StandardError=append:/tmp/qdrant.log

[Install]
WantedBy=default.target
UNIT_EOF
    systemctl --user daemon-reload
    systemctl --user enable --now qdrant
    echo "  ✅ Qdrant systemd user service installed (autostart on login)"
  fi
fi

# ── Ollama ────────────────────────────────────────────────────────────────────
if [[ "$SKIP_OLLAMA" == false ]]; then
  echo ""
  echo "▶ Installing Ollama..."
  if command -v ollama &>/dev/null; then
    echo "  ✅ Ollama already installed ($(ollama --version 2>/dev/null | head -1))"
  else
    if [[ "$OS" == "Linux" ]]; then
      # Official Ollama install script — handles CUDA/ROCm detection automatically
      echo "  Running official Ollama installer (detects CUDA/GPU automatically)..."
      curl -fsSL https://ollama.com/install.sh | sh
      echo "  ✅ Ollama installed"

      # Check if GPU was detected
      if command -v nvidia-smi &>/dev/null; then
        echo "  🎮 Nvidia GPU detected — Ollama will use CUDA acceleration"
      else
        echo "  ℹ️  No Nvidia GPU detected — running on CPU"
        echo "     If you have a GPU, install CUDA drivers first then re-run setup"
      fi

    else
      # macOS — download binary directly
      echo "  Downloading Ollama $OLLAMA_VERSION..."
      OLLAMA_TGZ="https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-darwin.tgz"
      curl -sL "$OLLAMA_TGZ" -o /tmp/ollama.tgz
      tar xz -C "$INSTALL_DIR" -f /tmp/ollama.tgz
      rm /tmp/ollama.tgz
      chmod +x "$INSTALL_DIR/ollama"

      PLIST="$HOME/Library/LaunchAgents/com.local.ollama.plist"
      cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.ollama</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/ollama</string>
    <string>serve</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OLLAMA_FLASH_ATTENTION</key><string>1</string>
    <key>OLLAMA_KV_CACHE_TYPE</key><string>q8_0</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/ollama.log</string>
  <key>StandardErrorPath</key><string>/tmp/ollama.log</string>
</dict>
</plist>
PLIST_EOF
      launchctl load "$PLIST"
      echo "  ✅ Ollama installed with launchd service"
      sleep 3
    fi
  fi
fi

# ── Models ────────────────────────────────────────────────────────────────────
if [[ "$SKIP_MODELS" == false ]]; then
  echo ""
  echo "▶ Pulling models..."
  # Give Ollama a moment to start if just installed
  sleep 2
  echo "  Pulling qwen3-embedding:8b (~5GB)..."
  ollama pull qwen3-embedding:8b
  echo "  ✅ qwen3-embedding:8b ready"

  if [[ "$OS" == "Linux" ]] && command -v nvidia-smi &>/dev/null; then
    # Check available VRAM — suggest 4b variant if tight
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    if [[ -n "$VRAM_MB" && "$VRAM_MB" -lt 7000 ]]; then
      echo "  ⚠️  GPU has ${VRAM_MB}MB VRAM — qwen3-embedding:8b needs ~5GB"
      echo "     If it fails to load, try: ollama pull qwen3-embedding:4b"
      echo "     Then update 'embedding_model' in $CONFIG_DIR/config.json"
    fi
  fi
fi

# ── rag tool ─────────────────────────────────────────────────────────────────
echo ""
echo "▶ Installing rag tool..."
cp "$(dirname "$0")/rag" "$INSTALL_DIR/rag"
chmod +x "$INSTALL_DIR/rag"
echo "  ✅ rag installed to $INSTALL_DIR/rag"

# ── Config ───────────────────────────────────────────────────────────────────
echo ""
echo "▶ Writing config..."
CONFIG_FILE="$CONFIG_DIR/config.json"
VAULT_PATH="${OBSIDIAN_VAULT:-"/path/to/your/obsidian/vault"}"

cat > "$CONFIG_FILE" << CONFIG_EOF
{
  "qdrant_url": "$QDRANT_URL",
  "ollama_url": "http://localhost:11434",
  "embedding_model": "qwen3-embedding:8b",
  "reranker_model": "BAAI/bge-reranker-v2-m3",
  "collections": ["files", "web", "pdfs", "code"],
  "default_top_k": 8,
  "embed_batch_size": 8,
  "persistent_sources": [],
  "web_sources": [],
  "obsidian_vaults": [
    {
      "name": "personal",
      "path": "$VAULT_PATH",
      "collection": "files"
    }
  ]
}
CONFIG_EOF
echo "  ✅ Config written to $CONFIG_FILE"

# ── PATH reminder ─────────────────────────────────────────────────────────────
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo ""
  echo "⚠️  Add this to your $SHELL_RC:"
  echo "   export PATH=\"$INSTALL_DIR:\$PATH\""
  echo "   Then run: source $SHELL_RC"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║            Setup complete! ✅            ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Run:  rag status"
echo ""
if [[ "$OBSIDIAN_VAULT" == "" ]]; then
  echo "  ⚠️  Set your Obsidian vault path in: $CONFIG_FILE"
  echo ""
fi
