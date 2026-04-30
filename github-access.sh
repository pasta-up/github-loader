#!/usr/bin/env bash
set -e

echo "=== Github SSH/Deploy Key Bootstrapper ==="


# --
# dependencies
# --
echo "[1/6] Installing dependencies..."
sudo apt update
sudo apt install -y git curl gh openssh-client

# --
# exising key?
# --
SSH_DIR="$HOME/.ssh"
ED25519_KEY="$SSH_DIR/id_ed25519"
RSA_KEY="$SSH_DIR/id_rsa"
KEY_PATH=""

echo "[2/6] Checking for existing RSA key..."

if [ -f "$ED25519_KEY" ] || [ -f "${ED25519_KEY}.pub" ]; then
    echo "Found existing ED25519 key."
    KEY_PATH="$ED25519_KEY"
elif [ -f "$RSA_KEY" ] || [ -f "${RSA_KEY}.pub" ]; then
    echo "Found existing RSA key (fallback)."
    KEY_PATH="$RSA_KEY"
fi

# --
# replace/generate key
# --
if [ -n "$KEY_PATH" ]; then
    echo "Using key: $KEY_PATH"
    read -p "Do you want to replace it? (y/n): " replace

    if [[ "$replace" == "y" ]]; then
        rm -f "$KEY_PATH" "${KEY_PATH}.pub"
        KEY_PATH=""
    fi
fi

if [ -z "$KEY_PATH" ]; then
    default_email="${USER}@${HOSTNAME}"

    echo "[3/6] Creating new SSH key..."
    read -p "Enter email for SSH key [${default_email}]: " email
    email="${email:-$default_email}"

    read -p "Preferred key type? (ed25519/rsa) [default: ed25519]: " keytype
    keytype=${keytype:-ed25519}

    if [[ "$keytype" == "rsa" ]]; then
        KEY_PATH="$RSA_KEY"
        ssh-keygen -t rsa -b 4096 -C "$email" -f "$KEY_PATH" -N ""
    else
        KEY_PATH="$ED25519_KEY"
        ssh-keygen -t ed25519 -C "$email" -f "$KEY_PATH" -N ""
    fi
fi

PUBKEY="$KEY_PATH.pub"

# --
# auth to github
# --
echo "[4/6] GitHub authentication..."

if ! gh auth status >/dev/null 2>&1; then
    gh auth login
fi

# --
# target
# --
echo "[5/6] Target selection:"
echo "  - Repo: https://github.com/org/repo"
echo "  - Account: account"
read -p "Enter target: " target

# --
# actions
# --
echo "[6/6] Processing..."
PUBKEY_CONTENT=$(cat "$PUBKEY")

if [[ "$target" == "account" ]]; then
    echo "Adding SSH key to GitHub account..."

    gh api user/keys \
        --method POST \
        -f title="$(hostname)-$(date +%Y%m%d-%H%M%S)" \
        -f key="$PUBKEY_CONTENT"

    echo "Done: added to account."

else
    if [[ "$target" =~ github\.com[:/]+([^/]+)/([^/.]+) ]]; then
        OWNER="${BASH_REMATCH[1]}"
        REPO="${BASH_REMATCH[2]}"

        echo "Repo detected: $OWNER/$REPO"

        read -p "Read-only deploy key? (y/n): " readonly
        if [[ "$readonly" == "y" ]]; then
          RO="true"
        else
          RO="false"
        fi

        gh api "repos/$OWNER/$REPO/keys" \
          --method POST \
          -H "Accept: application/vnd.github+json" \
          -f title="$(hostname)-deploy-key" \
          -f key="$PUBKEY_CONTENT" \
          -f read_only="$RO"

        echo "Done: deploy key added."
          else
        echo "Invalid input (must be repo URL or 'account')"
        exit 1
    fi
fi

echo "All complete."