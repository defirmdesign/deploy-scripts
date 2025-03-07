#!/bin/bash

KEY_PATH="$HOME/.ssh/" # Default "$HOME/.ssh/"
SSH_CONFIG="$HOME/.ssh/config" # Default "$HOME/.ssh/config"

read -r -p "What repository are you cloning? (Friendly name): " PROJECT_NAME
PROJECT_NAME="git_${PROJECT_NAME,,}"
KEY_FILE="${KEY_PATH%/}/$PROJECT_NAME"

# Check if the key file exists
if [ -f "$KEY_FILE" ]; then
    echo "SSH key already exists at '$KEY_FILE'."
    read -r -p "Do you want to overwrite this key? (y/N): " OVERWRITE
    if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
        echo "Exiting without overwriting the key."
        exit 1
    fi
    
    echo "Overwriting existing SSH key..."
    rm -f "$KEY_FILE" "${KEY_FILE}.pub"
fi


# Remove existing SSH config entries for this key
if [ -f "$SSH_CONFIG" ]; then
    if grep -q "IdentityFile $KEY_FILE" "$SSH_CONFIG"; then
        echo "Removing existing SSH config entries for $KEY_FILE..."

        TEMP_CONFIG=$(mktemp)
        awk -v key="$KEY_FILE" '
        /IdentityFile/ && index($2, key) {
            skip_next = 0
            in_block = 1
            next
        }
        /^Host / && in_block {
            in_block = 0
            skip_next = 1
            next
        }
        skip_next {
            skip_next = 0
            next
        }
        { print }
        ' "$SSH_CONFIG" > "$TEMP_CONFIG"
        mv "$TEMP_CONFIG" "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
    fi
fi

ssh-keygen -t ed25519 -C "deploy-key-${HOSTNAME,,}" -f "$KEY_FILE" -N "" > /dev/null
echo "SSH key generated at $KEY_FILE"

echo -e "\nAdd this public key to your GitHub repo as a Deploy Key: \n"
cat "${KEY_FILE}.pub"
echo -e "\nGo to: GitHub Repo → Settings → Deploy Keys → Add Key\n"

read -r -p "Paste your GitHub repo SSH URL (e.g., git@github.com:user/repo.git): " GIT_REPO

if [[ ! "$GIT_REPO" =~ ^git@([a-zA-Z0-9.-]+):([a-zA-Z0-9._-]+)/([a-zA-Z0-9._-]+)(\.git)?$ ]]; then
    echo "Invalid Git SSH URL. Expected format: git@github.com:user/repo.git"
    exit 1
fi

# Extract the Host from the git repo URL and build a new host and git repo URL
HOST=$(echo "$GIT_REPO" | sed -E 's/git@([^:]+):.*/\1/')
NEW_HOST="${PROJECT_NAME}.${HOST}"
GIT_REPO="${GIT_REPO/git@$HOST:/git@$NEW_HOST:}"

if ! grep -q "IdentityFile $KEY_FILE" "$SSH_CONFIG"; then
    echo -e "Host $NEW_HOST\n  HostName $HOST\n  IdentityFile $KEY_FILE\n  IdentitiesOnly yes" >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
fi

echo -e "\nCloning repo..."
CLONE_OUTPUT=$(git clone "$GIT_REPO" 2>&1)
CLONE_EXIT_CODE=$?

if [ $CLONE_EXIT_CODE -ne 0 ]; then
    echo -e "\n$CLONE_OUTPUT"
    echo -e "\nGit clone failed with exit code $CLONE_EXIT_CODE (error response above)"
    exit 1
fi

echo -e "\nDone! Repo cloned successfully."