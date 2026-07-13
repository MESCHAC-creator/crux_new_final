@echo off
:: ==============================================================================
::  CRUX - AUTOMATIC GITHUB PUSH & SYNC SCRIPT (WINDOWS COMMAND PROMPT)
:: ==============================================================================
:: This script automates staging, committing, and pushing your CRUX changes 
:: to the target branch: claude/kind-babbage-vqDxq
:: ==============================================================================

chcp 65001 > nul
title CRUX Git Sync Utility (Windows)

echo.
echo     ██████╗██████╗ ██╗   ██╗██╗  ██╗
echo    ██╔═════██╔═══██╗██║   ██║╚██╗██╔╝
echo    ██║     ██████╔╝██║   ██║ ╚███╔╝ 
echo    ██║     ██╔══██╗██║   ██║ ██╔██╗ 
echo    ╚██████╗██║  ██║╚██████╔╝██╔╝ ██╗
echo     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝
echo.
echo ===================================================
echo   CRUX Git Sync Utility for Windows
echo ===================================================
echo.

:: Vérifier si Git est installé
where git >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Git n'est pas installe sur votre systeme ou n'est pas dans votre PATH.
    echo Veuillez installer Git pour Windows et reessayer.
    pause
    exit /b 1
)

:: Vérifier si le dossier .git existe
if not exist ".git" (
    echo [INFO] Le depot Git n'est pas initialise dans ce dossier.
    set /p "init_git=Voulez-vous l'initialiser maintenant ? (o/n) : "
    if /i "%init_git%"=="o" (
        git init
        echo [SUCCESS] Depot Git initialise.
    ) else (
        echo [ABORT] Un depot Git est requis pour pousser vers GitHub.
        pause
        exit /b 1
    )
)

:: Vérifier l'URL distante
git remote get-url origin >nul 2>nul
if %errorlevel% neq 0 (
    echo [WARNING] Aucun depot distant 'origin' detecte.
    set /p "remote_input=Entrez l'URL de votre depot GitHub (ex: https://github.com/votre-user/votre-repo.git) : "
    if not "%remote_input%"=="" (
        git remote add origin %remote_input%
        echo [SUCCESS] Depot distant defini sur %remote_input%
    ) else (
        echo [ABORT] L'URL du depot distant est obligatoire pour continuer.
        pause
        exit /b 1
    )
)

echo [1/4] Analyse des changements locaux...
echo ---------------------------------------------------
git status --short
echo ---------------------------------------------------
echo.

echo [2/4] Preparation du message de commit...
set "DEFAULT_MSG=update: Nettoyage authentification unique Google et correction Gradle sous Windows"
set /p "user_msg=Entrez le message de commit [Entree pour la valeur par defaut] : "
if "%user_msg%"=="" (
    set "COMMIT_MSG=%DEFAULT_MSG%"
) else (
    set "COMMIT_MSG=%user_msg%"
)

echo.
echo [3/4] Indexation des fichiers...

:: Verify and repair Gradle wrapper jar if needed to prevent ClassNotFoundException: org.gradle.wrapper.GradleWrapperMain
echo Verifying Gradle Wrapper JAR...
set "JAR_PATH=android\gradle\wrapper\gradle-wrapper.jar"
set "DOWNLOAD_URL=https://raw.githubusercontent.com/gradle/gradle/v8.11.1/gradle/wrapper/gradle-wrapper.jar"

set "needs_download=0"
if not exist "%JAR_PATH%" (
    echo [WARNING] Gradle wrapper JAR is missing.
    set "needs_download=1"
) else (
    powershell -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead('%JAR_PATH%'); $zip.Dispose(); exit 0 } catch { exit 1 }" >nul 2>&1
    if errorlevel 1 (
        echo [WARNING] Gradle wrapper JAR is corrupted.
        set "needs_download=1"
    )
)

if "%needs_download%"=="1" (
    echo Downloading a fresh, uncorrupted Gradle wrapper JAR...
    if not exist "android\gradle\wrapper" mkdir "android\gradle\wrapper"
    powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('%DOWNLOAD_URL%', '%JAR_PATH%')" >nul 2>&1
    if exist "%JAR_PATH%" (
        powershell -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead('%JAR_PATH%'); $zip.Dispose(); exit 0 } catch { exit 1 }" >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] Downloaded jar is invalid.
        ) else (
            echo [SUCCESS] Gradle wrapper JAR downloaded and verified successfully.
        )
    ) else (
        echo [ERROR] Failed to download Gradle wrapper JAR.
    )
) else (
    echo [INFO] Gradle wrapper JAR is present and valid.
)

if exist "android\gradle\wrapper\gradle-wrapper.jar" (
    git rm --cached "android\gradle\wrapper\gradle-wrapper.jar" >nul 2>&1
)
git add .
if exist "android\gradle\wrapper\gradle-wrapper.jar" (
    git add -f "android\gradle\wrapper\gradle-wrapper.jar"
)

echo.
echo Committing des changements...
git commit -m "%COMMIT_MSG%"

:: Création ou switch vers la branche cible
echo.
echo Configuration de la branche : claude/kind-babbage-vqDxq
git checkout -b claude/kind-babbage-vqDxq 2>nul
if %errorlevel% neq 0 (
    git checkout claude/kind-babbage-vqDxq
)

echo.
echo [4/4] Push des changements vers GitHub sur la branche claude/kind-babbage-vqDxq...
echo Executing: git push -u origin claude/kind-babbage-vqDxq
git push -u origin claude/kind-babbage-vqDxq

if %errorlevel% equ 0 (
    echo.
    echo ====================================================
    echo   SUCCES : Votre projet CRUX a ete pousse sur GitHub !
    echo   Branche : claude/kind-babbage-vqDxq
    echo ====================================================
) else (
    echo.
    echo ====================================================
    echo   ERREUR : Impossible de pousser vers GitHub.
    echo   Veuillez verifier votre connexion internet, vos permissions,
    echo   ou vos identifiants GitHub puis reessayez.
    echo ====================================================
)

pause
