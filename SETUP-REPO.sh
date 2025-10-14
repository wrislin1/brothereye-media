#!/bin/bash
# Brother Eye Media Stack - Repository Setup Script
# This script initializes the entire repository structure
# Run this once to set up a new clone or fresh repo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
REPO_NAME="brother-eye-media-stack"
DEFAULT_BRANCH="main"

# Banner
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Brother Eye Media Stack${NC}"
echo -e "${CYAN}   Repository Setup & Initialization${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Check if we're in a git repository already
if [ -d .git ]; then
    echo -e "${YELLOW}⚠ Warning: This directory is already a git repository${NC}"
    echo ""
    read -p "Continue anyway? This will NOT reinitialize git. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Cancelled by user${NC}"
        exit 0
    fi
    GIT_EXISTS=true
else
    GIT_EXISTS=false
fi

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
echo ""

MISSING_DEPS=()

if ! command -v git &> /dev/null; then
    MISSING_DEPS+=("git")
fi

if ! command -v gpg &> /dev/null; then
    MISSING_DEPS+=("gnupg")
fi

if ! command -v git-crypt &> /dev/null; then
    MISSING_DEPS+=("git-crypt")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}✗ Missing required packages: ${MISSING_DEPS[*]}${NC}"
    echo ""
    echo -e "${YELLOW}Install with:${NC}"
    echo -e "  apt update && apt install -y ${MISSING_DEPS[*]}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"
echo ""

DIRECTORIES=(
    "docs"
    "proxmox"
    "lxc"
    "docker/compose"
    "docker/configs/caddy"
    "scripts"
    "secrets/wireguard"
    "config"
    "cache"
    "logs"
)

for dir in "${DIRECTORIES[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo -e "${GREEN}✓${NC} Created: ${dir}/"
    else
        echo -e "${BLUE}↪${NC} Exists:  ${dir}/"
    fi
done

echo ""

# Create .gitkeep files in empty directories
echo -e "${YELLOW}Creating placeholder files...${NC}"
echo ""

GITKEEP_DIRS=(
    "docs"
    "config"
    "cache"
    "logs"
    "secrets/wireguard"
    "docker/configs/caddy"
)

for dir in "${GITKEEP_DIRS[@]}"; do
    if [ ! -f "$dir/.gitkeep" ]; then
        touch "$dir/.gitkeep"
        echo -e "${GREEN}✓${NC} Created: ${dir}/.gitkeep"
    fi
done

echo ""

# Create README files for important directories
echo -e "${YELLOW}Creating directory README files...${NC}"
echo ""

# secrets/README.md
cat > secrets/README.md << 'EOF'
# Secrets Directory

This directory contains encrypted sensitive files managed by git-crypt.

## What Goes Here

- `wireguard/` - WireGuard VPN configuration files
- `.env.production` - Production environment variables with real credentials
- `*.key` - Private keys
- `*.pem` - SSL/TLS certificates

## Encryption

All files in this directory are automatically encrypted by git-crypt when committed.
See `GPG-SETUP.md` in the repository root for setup instructions.

## Security Notes

- Files are encrypted in the repository
- Decrypted locally only when repository is unlocked
- Never commit sensitive data outside this directory
- Always verify files are encrypted: `git-crypt status`
EOF
echo -e "${GREEN}✓${NC} Created: secrets/README.md"

# config/README.md
cat > config/README.md << 'EOF'
# Config Directory

This directory is for Docker container persistent configurations.

## Purpose

When Docker containers run, they store their configurations, databases, and metadata here:

- `jellyfin/` - Jellyfin library database, metadata, images
- `sonarr/` - Sonarr database and settings
- `radarr/` - Radarr database and settings
- `prowlarr/` - Prowlarr indexer configurations
- `nzbget/` - NZBGet queue and settings
- `bazarr/` - Bazarr subtitle database
- `jellyseerr/` - Jellyseerr request database
- `caddy/` - Caddy certificates and config

## Important

- This directory is in `.gitignore` (not tracked by git)
- Contains sensitive data (API keys, database passwords)
- Backup this directory regularly
- Size can grow large (Jellyfin metadata, images)

## Backup

Use the backup script:
```bash
cd /opt/media-stack
../scripts/backup-configs.sh
```
EOF
echo -e "${GREEN}✓${NC} Created: config/README.md"

echo ""

# Initialize git if not already initialized
if [ "$GIT_EXISTS" = false ]; then
    echo -e "${YELLOW}Initializing git repository...${NC}"
    echo ""
    
    git init
    git branch -M $DEFAULT_BRANCH
    
    # Set recommended git configs
    git config core.autocrlf false
    git config core.eol lf
    git config pull.rebase false
    
    echo -e "${GREEN}✓ Git repository initialized${NC}"
    echo ""
else
    echo -e "${BLUE}↪ Git repository already initialized${NC}"
    echo ""
fi

# Setup git-crypt
echo -e "${YELLOW}Setting up git-crypt encryption...${NC}"
echo ""

if [ -d .git/git-crypt ]; then
    echo -e "${BLUE}↪ git-crypt already initialized${NC}"
    echo ""
else
    # Check if user has GPG key
    echo "Do you want to use GPG keys for encryption or a symmetric key file?"
    echo ""
    echo "  1) GPG Key (recommended - more secure, per-user access)"
    echo "  2) Symmetric Key File (simpler - one shared key)"
    echo "  3) Skip for now (you can set up later)"
    echo ""
    read -p "Choice [1]: " CRYPT_CHOICE
    CRYPT_CHOICE=${CRYPT_CHOICE:-1}
    echo ""
    
    case $CRYPT_CHOICE in
        1)
            # GPG key method
            echo -e "${CYAN}Using GPG key method${NC}"
            echo ""
            
            # List available GPG keys
            echo "Available GPG keys:"
            gpg --list-secret-keys --keyid-format=long
            echo ""
            
            if ! gpg --list-secret-keys | grep -q "sec"; then
                echo -e "${YELLOW}⚠ No GPG keys found${NC}"
                echo ""
                echo "Generate a GPG key first:"
                echo "  See GPG-SETUP.md for detailed instructions"
                echo "  Or run: gpg --full-generate-key"
                echo ""
                echo -e "${BLUE}Skipping git-crypt setup for now${NC}"
            else
                read -p "Enter your GPG Key ID (or press Enter to skip): " GPG_KEY
                echo ""
                
                if [ -n "$GPG_KEY" ]; then
                    # Initialize git-crypt with GPG key
                    git-crypt init
                    git-crypt add-gpg-user "$GPG_KEY"
                    
                    echo -e "${GREEN}✓ git-crypt initialized with GPG key: $GPG_KEY${NC}"
                    echo ""
                    echo -e "${YELLOW}Important:${NC} Backup your GPG keys!"
                    echo "  gpg --armor --export $GPG_KEY > brother-eye-gpg-public.asc"
                    echo "  gpg --armor --export-secret-keys $GPG_KEY > brother-eye-gpg-private.asc"
                    echo ""
                else
                    echo -e "${BLUE}Skipping git-crypt setup${NC}"
                fi
            fi
            ;;
        2)
            # Symmetric key method
            echo -e "${CYAN}Using symmetric key file method${NC}"
            echo ""
            
            git-crypt init
            git-crypt export-key git-crypt.key
            
            echo -e "${GREEN}✓ git-crypt initialized with symmetric key${NC}"
            echo ""
            echo -e "${YELLOW}Important:${NC} Backup the key file!"
            echo "  File: git-crypt.key"
            echo "  Store in password manager or encrypted USB"
            echo "  To unlock on another machine: git-crypt unlock git-crypt.key"
            echo ""
            ;;
        3)
            echo -e "${BLUE}Skipping git-crypt setup${NC}"
            echo "You can initialize it later with:"
            echo "  git-crypt init"
            echo "  git-crypt add-gpg-user YOUR_GPG_KEY_ID"
            echo ""
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            ;;
    esac
fi

# Create initial commit if new repo
if [ "$GIT_EXISTS" = false ]; then
    echo -e "${YELLOW}Creating initial commit...${NC}"
    echo ""
    
    # Stage files
    git add .gitignore .gitattributes GPG-SETUP.md SETUP-REPO.sh
    git add docs/ secrets/ config/ docker/ proxmox/ lxc/ scripts/
    
    # Commit
    git commit -m "Initial commit: Repository structure and security setup"
    
    echo -e "${GREEN}✓ Initial commit created${NC}"
    echo ""
fi

# Optionally set up GitHub remote
echo -e "${YELLOW}GitHub Remote Setup${NC}"
echo ""
read -p "Do you want to add a GitHub remote? (y/N): " -n 1 -r
echo
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter your GitHub username: " GH_USER
    read -p "Enter repository name [$REPO_NAME]: " GH_REPO
    GH_REPO=${GH_REPO:-$REPO_NAME}
    
    echo ""
    echo "GitHub remote will be:"
    echo "  git@github.com:${GH_USER}/${GH_REPO}.git"
    echo ""
    
    read -p "Add this remote? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if git remote | grep -q "^origin$"; then
            echo -e "${YELLOW}⚠ Remote 'origin' already exists${NC}"
            git remote -v
            echo ""
            read -p "Replace existing remote? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git remote remove origin
                git remote add origin "git@github.com:${GH_USER}/${GH_REPO}.git"
                echo -e "${GREEN}✓ Remote 'origin' updated${NC}"
            fi
        else
            git remote add origin "git@github.com:${GH_USER}/${GH_REPO}.git"
            echo -e "${GREEN}✓ Remote 'origin' added${NC}"
        fi
        echo ""
        
        # Offer to push
        read -p "Push to GitHub now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${YELLOW}Pushing to GitHub...${NC}"
            git push -u origin $DEFAULT_BRANCH
            echo ""
            echo -e "${GREEN}✓ Pushed to GitHub${NC}"
        fi
    fi
fi

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo -e "${YELLOW}Repository Structure:${NC}"
tree -L 2 -a --dirsfirst 2>/dev/null || ls -la
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. ${CYAN}Review and customize .env.example:${NC}"
echo "   nano docker/.env.example"
echo ""
echo "2. ${CYAN}Copy to production and fill in secrets:${NC}"
echo "   cp docker/.env.example docker/.env.production"
echo "   nano docker/.env.production"
echo ""
echo "3. ${CYAN}Verify git-crypt is working:${NC}"
echo "   git-crypt status"
echo ""
echo "4. ${CYAN}Continue adding the deployment scripts${NC}"
echo "   (The remaining files from the generation process)"
echo ""
echo -e "${YELLOW}Documentation:${NC}"
echo "  • GPG-SETUP.md - Encryption setup guide"
echo "  • secrets/README.md - Secrets directory info"
echo "  • config/README.md - Config directory info"
echo ""
echo -e "${GREEN}Happy deploying! 🚀${NC}"
echo ""
