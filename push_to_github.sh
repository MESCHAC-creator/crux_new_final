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

# Verify and repair Gradle wrapper jar if needed to prevent ClassNotFoundException: org.gradle.wrapper.GradleWrapperMain
echo -e "${CYAN}Verifying Gradle Wrapper JAR...${NC}"
JAR_PATH="android/gradle/wrapper/gradle-wrapper.jar"
DOWNLOAD_URL="https://raw.githubusercontent.com/gradle/gradle/v8.11.1/gradle/wrapper/gradle-wrapper.jar"

needs_download=false
if [ ! -f "$JAR_PATH" ]; then
    echo -e "${YELLOW}[WARNING] Gradle wrapper JAR is missing.${NC}"
    needs_download=true
elif ! unzip -t "$JAR_PATH" &>/dev/null; then
    echo -e "${YELLOW}[WARNING] Gradle wrapper JAR is corrupted.${NC}"
    needs_download=true
fi

if [ "$needs_download" = true ]; then
    echo -e "${CYAN}Downloading a fresh, uncorrupted Gradle wrapper JAR...${NC}"
    mkdir -p "$(dirname "$JAR_PATH")"
    if command -v curl &>/dev/null; then
        curl -L -o "$JAR_PATH" "$DOWNLOAD_URL"
    elif command -v wget &>/dev/null; then
        wget -O "$JAR_PATH" "$DOWNLOAD_URL"
    else
        echo -e "${RED}[ERROR] Neither curl nor wget is available. Cannot download Gradle wrapper JAR.${NC}"
    fi
    if [ -f "$JAR_PATH" ] && unzip -t "$JAR_PATH" &>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Gradle wrapper JAR downloaded and verified successfully.${NC}"
    else
        echo -e "${RED}[ERROR] Failed to download or verify Gradle wrapper JAR. Please download it manually from: $DOWNLOAD_URL${NC}"
    fi
else
    echo -e "${GREEN}[INFO] Gradle wrapper JAR is present and valid.${NC}"
fi

# Prevent Git binary corruption by removing gradle-wrapper.jar from cache and re-adding it with correct binary attribute
if [ -f "android/gradle/wrapper/gradle-wrapper.jar" ]; then
    git rm --cached android/gradle/wrapper/gradle-wrapper.jar 2>/dev/null
fi
git add .
# Force add gradle-wrapper.jar to guarantee it is pushed to GitHub and not ignored by global patterns
if [ -f "android/gradle/wrapper/gradle-wrapper.jar" ]; then
    git add -f android/gradle/wrapper/gradle-wrapper.jar
fi

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
