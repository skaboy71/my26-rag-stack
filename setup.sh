#!/bin/bash
# my26-rag-stack setup script
# Fully local RAG stack: Qdrant + Ollama + sentence-transformers
# No Homebrew required. Works on macOS Apple Silicon (M1/M2/M3/M4).
#
# Usage:
#   ./setup.sh                          # local Qdrant (default)
#   ./setup.sh --remote-db 192.168.1.30 # remote Qdrant on home server
#   ./setup.sh --vault ~/path/to/vault  # set Obsidian vault path
#   ./setup.sh --skip-ollama            # skip Ollama install (already installed)
#   ./setup.sh --skip-models            # skip model pulls
#   ./setup.sh --install-dir ~/bin      # where to install the rag tool (default: ~/.local/bin)

set -e

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

ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
  echo "❌ This script targets Apple Silicon (arm64). Got: $ARCH"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         my26-rag-stack  setup            ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Qdrant:    $QDRANT_URL"
echo "║  Install:   $INSTALL_DIR"
echo "║  Vault:     ${OBSIDIAN_VAULT:-"(not set — edit config later)"}"
echo "╚══════════════════════════════════════════╝"
echo ""

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# ── Python check ──────────────────────────────────────────────────────────────
echo "▶ Checking Python..."
if ! command -v python3 &>/dev/null; then
  echo "❌ python3 not found. Install from https://www.python.org/downloads/"
  exit 1
fi
PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  ✅ Python $PYTHON_VER"

# ── Python dependencies ───────────────────────────────────────────────────────
echo ""
echo "▶ Installing Python dependencies..."
pip install -q qdrant-client ollama sentence-transformers \
               beautifulsoup4 playwright pypdf python-docx
echo "  ✅ Python packages installed"

echo ""
echo "▶ Installing Playwright browser..."
python3 -m playwright install chromium --quiet
echo "  ✅ Chromium installed"

# ── Qdrant (local mode only) ──────────────────────────────────────────────────
if [[ "$QDRANT_MODE" == "local" ]]; then
  echo ""
  echo "▶ Installing Qdrant (native arm64 binary)..."
  if command -v qdrant &>/dev/null || [[ -f "$INSTALL_DIR/qdrant" ]]; then
    echo "  ✅ Qdrant already installed"
  else
    QDRANT_RELEASE=$(curl -s https://api.github.com/repos/qdrant/qdrant/releases/latest \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
    QDRANT_URL_DL="https://github.com/qdrant/qdrant/releases/download/${QDRANT_RELEASE}/qdrant-aarch64-apple-darwin.tar.gz"
    echo "  Downloading Qdrant $QDRANT_RELEASE..."
    curl -sL "$QDRANT_URL_DL" | tar xz -C "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/qdrant"
    echo "  ✅ Qdrant installed to $INSTALL_DIR/qdrant"
  fi

  # launchd plist for Qdrant
  QDRANT_DATA="$HOME/.local/share/qdrant"
  mkdir -p "$QDRANT_DATA"
  PLIST="$HOME/Library/LaunchAgents/com.local.qdrant.plist"
  if [[ ! -f "$PLIST" ]]; then
    cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.qdrant</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/qdrant</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>QDRANT__STORAGE__STORAGE_PATH</key>
    <string>$QDRANT_DATA</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/qdrant.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/qdrant.log</string>
</dict>
</plist>
PLIST_EOF
    launchctl load "$PLIST"
    echo "  ✅ Qdrant launchd service installed (autostart on login)"
  else
    echo "  ✅ Qdrant launchd service already configured"
  fi
fi

# ── Ollama ────────────────────────────────────────────────────────────────────
if [[ "$SKIP_OLLAMA" == false ]]; then
  echo ""
  echo "▶ Installing Ollama..."
  if command -v ollama &>/dev/null; then
    echo "  ✅ Ollama already installed ($(ollama --version 2>/dev/null | head -1))"
  else
    echo "  Downloading Ollama $OLLAMA_VERSION..."
    OLLAMA_TGZ="https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-darwin.tgz"
    curl -sL "$OLLAMA_TGZ" -o /tmp/ollama.tgz
    tar xz -C "$INSTALL_DIR" -f /tmp/ollama.tgz
    rm /tmp/ollama.tgz
    chmod +x "$INSTALL_DIR/ollama"
    echo "  ✅ Ollama installed to $INSTALL_DIR/ollama"

    # launchd plist for Ollama
    PLIST="$HOME/Library/LaunchAgents/com.local.ollama.plist"
    cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.ollama</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/ollama</string>
    <string>serve</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OLLAMA_FLASH_ATTENTION</key>
    <string>1</string>
    <key>OLLAMA_KV_CACHE_TYPE</key>
    <string>q8_0</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/ollama.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/ollama.log</string>
</dict>
</plist>
PLIST_EOF
    launchctl load "$PLIST"
    echo "  ✅ Ollama launchd service installed"
    sleep 3
  fi
fi

# ── Models ────────────────────────────────────────────────────────────────────
if [[ "$SKIP_MODELS" == false ]]; then
  echo ""
  echo "▶ Pulling models (this will take a while)..."
  echo "  Pulling qwen3-embedding:8b (~5GB)..."
  ollama pull qwen3-embedding:8b
  echo "  ✅ qwen3-embedding:8b ready"
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
  "embed_batch_size": 32,
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
  echo "⚠️  Add this to your ~/.zshrc:"
  echo "   export PATH=\"$INSTALL_DIR:\$PATH\""
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
