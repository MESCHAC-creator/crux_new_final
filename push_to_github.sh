#!/bin/bash

# ==============================================================================
#  CRUX - AUTOMATIC GITHUB PUSH & SYNC SCRIPT
# ==============================================================================
# This script automates the process of staging, committing, and pushing your
# recent updates to GitHub, ensuring CI/CD compatibility.
# ==============================================================================

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== CRUX Git Sync Utility ===${NC}\n"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}[ERROR] Git is not installed.${NC}"
    exit 1
fi

# Show current status
echo -e "${CYAN}[1/4] Scanning local workspace changes...${NC}"
git status --short

# Ask for a custom commit message
echo -e "\n${CYAN}[2/4] Preparing Commit Message...${NC}"
DEFAULT_MSG="update: fix LiveKit connection, add social login methods, and fix Gradle wrapper"
read -p "Enter commit message [Press Enter for default]: " user_msg
COMMIT_MSG=${user_msg:-$DEFAULT_MSG}

# Stage all changes
echo -e "\n${CYAN}[3/4] Staging files...${NC}"
git add .

# FIX: Force add gradle-wrapper.jar to ensure it exists in the repo for CI (Codemagic/GitHub Actions)
echo -e "${YELLOW}Ensuring Gradle Wrapper is included...${NC}"
if [ -f "android/gradle/wrapper/gradle-wrapper.jar" ]; then
    git add -f android/gradle/wrapper/gradle-wrapper.jar
    git add -f android/gradlew
    git add -f android/gradlew.bat
    echo -e "${GREEN}Gradle Wrapper files force-added.${NC}"
else
    echo -e "${RED}[WARNING] android/gradle/wrapper/gradle-wrapper.jar not found locally!${NC}"
fi

# Commit changes
echo -e "${CYAN}Committing changes...${NC}"
git commit -m "$COMMIT_MSG"

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
    git checkout -b main
    CURRENT_BRANCH="main"
fi

# Push changes
echo -e "\n${CYAN}[4/4] Pushing changes to GitHub ($CURRENT_BRANCH)...${NC}"
git push -u origin "$CURRENT_BRANCH"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}🎉 SUCCESS: Your CRUX project has been pushed!${NC}"
    echo -e "${GREEN}====================================================${NC}"
else
    echo -e "\n${RED}❌ ERROR: Failed to push to GitHub.${NC}"
    exit 1
fi
