#!/bin/bash

# Ensure local Homebrew binaries are in the PATH
export PATH="/opt/homebrew/bin:$PATH"

echo "=== Ollama Tailscale Server Manager ==="

# 1. Check if Tailscale CLI tool exists
if ! command -v tailscale &> /dev/null; then
    echo "❌ Error: Tailscale binary not found. Run 'brew install tailscale' first."
    exit 1
fi

# 2. Conflict Prevention: Check if another Ollama instance is blocking the port
if lsof -Pi :11434 -sTCP:LISTEN -t >/dev/null ; then
    echo "⚠️  Warning: Something is already listening on port 11434."
    echo "Attempting to clear the port so this optimized script can take over..."
    brew services stop ollama 2>/dev/null
    killall ollama 2>/dev/null
    sleep 1
fi

# 3. Try to get the Tailscale IP. If it fails, authenticate.
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | tr -d '[:space:]')

if [ -z "$TAILSCALE_IP" ] || [[ "$TAILSCALE_IP" == *"Error"* ]] || [[ "$TAILSCALE_IP" == *"no current"* ]]; then
    echo "🔑 Tailscale is not logged in or active."
    echo "Launching Tailscale login portal..."
    echo "--------------------------------------------------------"
    sudo tailscale up
    echo "--------------------------------------------------------"
    
    sleep 2
    TAILSCALE_IP=$(tailscale ip -4 | tr -d '[:space:]')
fi

if [ -z "$TAILSCALE_IP" ] || [[ "$TAILSCALE_IP" == *"Error"* ]] || [[ "$TAILSCALE_IP" == *"no current"* ]]; then
    echo "❌ Error: Could not retrieve a valid Tailscale IP."
    exit 1
fi

# 4. Grab local Wi-Fi IP as a convenient backup address
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null)

# 5. Print Unified Network Dashboard
echo ""
echo "🌐 SERVER NETWORK INFRASTRUCTURE ACTIVE"
echo "--------------------------------------------------------"
echo "🔒 SECURE REMOTE IP (Use this on your other computers via Tailscale):"
echo "   👉 http://${TAILSCALE_IP}:11434"
echo ""
if [ ! -z "$LOCAL_IP" ]; then
echo "🏠 LOCAL WI-FI IP (Use for devices on the same home router):"
echo "   👉 http://${LOCAL_IP}:11434"
echo ""
fi
echo "💻 LOCALHOST (Use if coding directly on this M3 Pro):"
echo "   👉 http://localhost:11434"
echo "--------------------------------------------------------"
echo "Paste the appropriate URL directly into your remote IDE configs."
echo "Press Ctrl+C in this window to stop the server safely."
echo ""

# 6. Inject elite multi-threading and caching optimizations
export OLLAMA_HOST="0.0.0.0"
export OLLAMA_FLASH_ATTENTION="1"
export OLLAMA_KV_CACHE_TYPE="q8_0"
export OLLAMA_NUM_PARALLEL="2"  # Crucial for IDEs: handles Chat + Autocomplete at the same time

echo "🚀 Starting optimized Homebrew Ollama service natively..."
exec /opt/homebrew/opt/ollama/bin/ollama serve