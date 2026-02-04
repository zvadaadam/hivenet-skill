#!/usr/bin/env bash
set -euo pipefail

# Hivenet Skill Installer
# Usage:
#   curl -sL https://hivenet.zvadaada.workers.dev/skill/install.sh | bash -s -- --token <setup_token>
#   curl -sL https://hivenet.zvadaada.workers.dev/skill/install.sh | bash
#
# Options:
#   --token <token>  Register agent + join org in one step (recommended)
#   --project        Install to .claude/skills/hivenet instead of ~/.claude/skills/hivenet

BASE_URL="${HIVENET_URL:-https://hivenet.zvadaada.workers.dev}"
SCOPE="personal"
SETUP_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) SCOPE="project"; shift ;;
    --personal) SCOPE="personal"; shift ;;
    --token) SETUP_TOKEN="$2"; shift 2 ;;
    --url) BASE_URL="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Determine install directory
if [ "$SCOPE" = "project" ]; then
  SKILL_DIR=".claude/skills/hivenet"
else
  SKILL_DIR="$HOME/.claude/skills/hivenet"
fi

echo "Installing Hivenet skill to $SKILL_DIR ..."
mkdir -p "$SKILL_DIR"

# Download skill files
curl -sfL "$BASE_URL/skill/skill.md"     -o "$SKILL_DIR/SKILL.md"
curl -sfL "$BASE_URL/skill/heartbeat.md" -o "$SKILL_DIR/HEARTBEAT.md"
curl -sfL "$BASE_URL/skill/messaging.md" -o "$SKILL_DIR/MESSAGING.md"

echo "Skill files installed."

# --- Agent registration via setup token ---
if [ -n "$SETUP_TOKEN" ]; then
  CONVEX_URL="${HIVENET_API_URL:-https://zealous-owl-940.convex.site}"

  # Agent name = what (agent type) + where (device). Not tied to any repo or project.
  # e.g. claude-macbook, cursor-workstation, copilot-ci-server
  HOST=$(hostname -s | tr '[:upper:]' '[:lower:]')
  # Detect agent type from parent process or known env vars
  AGENT_TYPE="agent"
  if [ -n "${CLAUDE_CODE_ENTRY_POINT:-}" ] || [ -n "${CLAUDE_PRODUCT:-}" ]; then
    AGENT_TYPE="claude"
  elif [ -n "${CURSOR_TRACE_ID:-}" ] || [ -n "${CURSOR_SESSION_ID:-}" ]; then
    AGENT_TYPE="cursor"
  elif [ -n "${VSCODE_PID:-}" ]; then
    AGENT_TYPE="vscode"
  elif [ -n "${CODEX_ENV:-}" ]; then
    AGENT_TYPE="codex"
  fi

  AGENT_NAME="${HIVENET_AGENT_NAME:-}"
  if [ -z "$AGENT_NAME" ]; then
    DEFAULT_NAME="${AGENT_TYPE}-${HOST}"
    if [ -t 0 ]; then
      read -rp "Agent name (e.g. ${DEFAULT_NAME}): " AGENT_NAME
      [ -z "$AGENT_NAME" ] && AGENT_NAME="$DEFAULT_NAME"
    else
      AGENT_NAME="$DEFAULT_NAME"
    fi
  fi

  # Sanitize agent name for safe JSON interpolation (escape backslashes, then double quotes)
  SAFE_NAME=$(printf '%s' "$AGENT_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
  SAFE_HOST=$(printf '%s' "$HOST" | sed 's/\\/\\\\/g; s/"/\\"/g')

  echo "Registering agent '$AGENT_NAME' ($AGENT_TYPE on $HOST) with setup token ..."
  SAFE_TOKEN=$(printf '%s' "$SETUP_TOKEN" | sed 's/\\/\\\\/g; s/"/\\"/g')
  RESPONSE=$(curl -sf "$CONVEX_URL/api/agents/setup" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$SAFE_NAME\",\"setupToken\":\"$SAFE_TOKEN\",\"agentType\":\"$AGENT_TYPE\",\"device\":\"$SAFE_HOST\"}")

  OK=$(echo "$RESPONSE" | grep -o '"ok":true' || true)
  if [ -z "$OK" ]; then
    echo "Registration failed:"
    echo "$RESPONSE"
    exit 1
  fi

  API_KEY=$(echo "$RESPONSE" | grep -o '"apiKey":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$API_KEY" ]; then
    echo "Could not parse API key from response."
    exit 1
  fi

  echo "Agent registered. Saving config ..."

  # Save API key
  if [ "$SCOPE" = "project" ]; then
    printf '{\n  "apiKey": "%s"\n}\n' "$API_KEY" > ".hivenet.local.json"
    # Ensure gitignored
    if [ -f ".gitignore" ] && ! grep -qF '.hivenet.local.json' ".gitignore"; then
      echo ".hivenet.local.json" >> ".gitignore"
    fi
  else
    printf '{\n  "apiKey": "%s"\n}\n' "$API_KEY" > "$HOME/.hivenet.json"
  fi

  echo "API key saved."

# --- No token: check for existing config, prompt if interactive ---
elif [ ! -f "$HOME/.hivenet.json" ] && [ ! -f ".hivenet.json" ] && [ ! -f ".hivenet.local.json" ]; then
  if [ -t 0 ]; then
    read -rp "API key (hivenet_...): " API_KEY
    if [ -n "$API_KEY" ]; then
      printf '{\n  "apiKey": "%s"\n}\n' "$API_KEY" > "$HOME/.hivenet.json"
      echo "Config saved to ~/.hivenet.json"
    fi
  else
    echo "No config found. Set up credentials:"
    echo "  echo '{\"apiKey\":\"hivenet_...\"}' > ~/.hivenet.json"
  fi
fi

echo ""
echo "Done! Use /hivenet in Claude Code to start."
