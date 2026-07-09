#!/bin/bash

# ==============================================================================
#  CRUX - AUTOMATIC GITHUB PUSH & SYNC SCRIPT
# ==============================================================================
# This script automates the process of staging, committing, and pushing your
# recent updates (including the transition to CRUX and elegant toasts) to GitHub.
# ==============================================================================

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print Header
echo -e "${CYAN}"
echo "    ██████╗██████╗ ██╗   ██╗██╗  ██╗"
echo "   ██╔═════██╔═══██╗██║   ██║╚██╗██╔╝"
echo "   ██║     ██████╔╝██║   ██║ ╚███╔╝ "
echo "   ██║     ██╔══██╗██║   ██║ ██╔██╗ "
echo "   ╚██████╗██║  ██║╚██████╔╝██╔╝ ██╗"
echo "    ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "${BLUE}=== CRUX Git Sync Utility ===${NC}\n"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}[ERROR] Git is not installed on this system. Please install Git and try again.${NC}"
    exit 1
fi

# Ensure we are in a Git repository
if [ ! -d ".git" ]; then
    echo -e "${YELLOW}[INFO] Git repository is not initialized in this directory.${NC}"
    read -p "Would you like to initialize a new Git repository here? (y/n): " init_git
    if [[ $init_git =~ ^[Yy]$ ]]; then
        git init
        echo -e "${GREEN}[SUCCESS] Git repository initialized.${NC}"
    else
        echo -e "${RED}[ABORT] Git repository is required to push to GitHub.${NC}"
        exit 1
    fi
fi

# Check for remote origin
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if [ -z "$REMOTE_URL" ]; then
    echo -e "${YELLOW}[WARNING] No remote 'origin' detected for this repository.${NC}"
    read -p "Enter your GitHub Repository URL (e.g., https://github.com/username/repo.git): " remote_input
    if [ ! -z "$remote_input" ]; then
        git remote add origin "$remote_input"
        echo -e "${GREEN}[SUCCESS] Remote 'origin' set to: $remote_input${NC}"
        REMOTE_URL="$remote_input"
    else
        echo -e "${RED}[ABORT] A remote URL is required to push changes.${NC}"
        exit 1
    fi
fi

# Show current status
echo -e "${CYAN}[1/4] Scanning local workspace changes...${NC}"
git status --short

# Ask for a custom commit message or generate one
echo -e "\n${CYAN}[2/4] Preparing Commit Message...${NC}"
DEFAULT_MSG="update: Transition brand to CRUX & integrate Elegant Framer Motion Toasts"
read -p "Enter commit message [Press Enter for default: '$DEFAULT_MSG']: " user_msg

COMMIT_MSG=${user_msg:-$DEFAULT_MSG}

# Stage all changes
echo -e "\n${CYAN}[3/4] Staging files...${NC}"
git add .

# Commit changes
echo -e "${CYAN}Committing changes...${NC}"
git commit -m "$COMMIT_MSG"

# Get current branch or set default to main
CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
    # If no branch is currently active (e.g. freshly initialized repo)
    git checkout -b main
    CURRENT_BRANCH="main"
fi

# Push changes
echo -e "\n${CYAN}[4/4] Pushing changes to GitHub ($CURRENT_BRANCH)...${NC}"
echo -e "${YELLOW}Executing: git push -u origin $CURRENT_BRANCH${NC}"
git push -u origin "$CURRENT_BRANCH"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}🎉 SUCCESS: Your CRUX project has been pushed to GitHub!${NC}"
    echo -e "${GREEN}====================================================${NC}"
else
    echo -e "\n${RED}====================================================${NC}"
    echo -e "${RED}❌ ERROR: Failed to push to GitHub.${NC}"
    echo -e "${RED}Please check your network connection, remote permissions,${NC}"
    echo -e "${RED}or credentials and try again.${NC}"
    echo -e "${RED}====================================================${NC}"
    exit 1
fi
