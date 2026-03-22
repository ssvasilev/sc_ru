@echo off
color 0B
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1

for /f %%e in ('echo prompt $E^| cmd') do set "ESC=%%e"


::Настройка цветов статусов
set "CLR_RESET=%ESC%[0m"
set "CLR_GREEN=%ESC%[92m"
set "CLR_YELLOW=%ESC%[93m"
set "CLR_RED=%ESC%[91m"
set "CLR_CYAN=%ESC%[96m"
set "CLR_GRAY=%ESC%[90m"
set "CLR_DEFAULT=%CLR_CYAN%"



:: =========================================================
:: STAR - Script To Apply Russian.
:: Скрипт для установки русской локализации в Star citizen.
:: Автор: ssvasilev (Demoneo)
:: Репозиторий: https://github.com/ssvasilev/STAR
::
:: Скрипт сейчас использует файл локализации из репозитория: n1ghter/StarCitizenRu
:: При необходимости может  быть использован произвольный источник локализации в Github.
::
:: Скрипт используется для обновления версий LIVE и PTU. Поиск обновлений выполняется по тегам в репозитории GitHub:
::   LIVE -> tag вида X.Y.Z-vNN
::   PTU  -> tag вида X.Y.Z-vNN-ptu
::
:: После скачивания архива проверяется его содержимое.
:: Если оно не подходит для выбранной версии, будут скачаны и проверены предыдущие версии архива.
:: =========================================================

:: -----------------------------
:: Настройки
:: -----------------------------
set "SCRIPT_DIR=%~dp0"
set "GITHUB_AUTHOR=n1ghter"
set "GITHUB_REPO=StarCitizenRu"
set "TEMP_DIR=%TEMP%\star_updater"
set "CONFIG_FILE=%SCRIPT_DIR%star_config.cfg"

:: -----------------------------
:: Конфигурация
:: -----------------------------
set "LAUNCHER_PATH="
set "LIVE_REPO="
set "LIVE_VERSION="
set "LIVE_PATH="
set "PTU_REPO="
set "PTU_VERSION="
set "PTU_PATH="

:: -----------------------------
:: Состояние конфигурации / поиска
:: CONFIGURED = путь настроен и валиден
:: FOUND      = потенциальная папка была обнаружена поиском
:: -----------------------------
set "LIVE_CONFIGURED=false"
set "PTU_CONFIGURED=false"

set "LIVE_FOUND=false"
set "PTU_FOUND=false"

set "LIVE_BUILD_TYPE=не найден"
set "PTU_BUILD_TYPE=не найден"

set "LIVE_VERSION_DIGITS=не найдена"
set "PTU_VERSION_DIGITS=не найдена"

set "LIVE_TYPE_MISMATCH=false"
set "PTU_TYPE_MISMATCH=false"

set "LIVE_STATUS=нет данных"
set "PTU_STATUS=нет данных"

set "INSTALL_LIVE_NEEDED=false"
set "INSTALL_PTU_NEEDED=false"
set "CURRENT_INSTALL="

set "INSTALL_LIVE_RESULT=не проверялась"
set "INSTALL_PTU_RESULT=не проверялась"

:: -----------------------------
:: GitHub статус и кандидаты
:: -----------------------------
set "GITHUB_OK=false"

set "LIVE_CAND_COUNT=0"
set "PTU_CAND_COUNT=0"

set "LIVE_CURRENT_INDEX=1"
set "PTU_CURRENT_INDEX=1"

set "LATEST_LIVE_VERSION=не найдена"
set "LATEST_LIVE_TAG="
set "LATEST_PTU_VERSION=не найдена"
set "LATEST_PTU_TAG="

set "LAST_REJECTED_LIVE_TAG="
set "LAST_REJECTED_PTU_TAG="

set "STATUS_TABLE_READY="
set "PATHS_LOADED="

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" >nul 2>&1

:: -----------------------------
:: Автообнаружение рядом со скриптом
:: -----------------------------
if exist "%SCRIPT_DIR%RSI Launcher.exe" (
    set "LAUNCHER_PATH=%SCRIPT_DIR%"
    set "LAUNCHER_AUTO_DETECTED=1"
)

if exist "%SCRIPT_DIR%StarCitizen_Launcher.exe" (
    if exist "%SCRIPT_DIR%Bin64\StarCitizen.exe" (
        set "LIVE_PATH=%SCRIPT_DIR%"
        set "LIVE_AUTO_DETECTED=1"
    )
)

call :RenderScreen

call :LoadOrSetupConfig

if "!LAUNCHER_PATH!"=="" (
    echo.
    echo Путь к RSI Launcher не настроен.
    echo.
    :SelectLauncherAfterLoad
    call :SelectFolder "Выберите папку с RSI Launcher.exe" LAUNCHER_PATH

    if not "!LAUNCHER_PATH!"=="" (
        if not exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
            echo ✗ RSI Launcher.exe не найден в выбранной папке
            echo.
            set /p "RETRY=Выбрать другую папку? (Y/N): "
            if /i "!RETRY!"=="Y" goto :SelectLauncherAfterLoad
            set "LAUNCHER_PATH="
        ) else (
            echo ✓ RSI Launcher найден: !LAUNCHER_PATH!
            call :SaveConfig
        )
    ) else (
        echo Папка не выбрана
        set /p "RETRY=Попробовать ещё раз? (Y/N): "
        if /i "!RETRY!"=="Y" goto :SelectLauncherAfterLoad
    )
)

if defined LAUNCHER_AUTO_DETECTED (
    call :SaveConfig
    set "LAUNCHER_AUTO_DETECTED="
)

if defined LIVE_AUTO_DETECTED (
    call :SaveConfig
    set "LIVE_AUTO_DETECTED="
)

set "PATHS_LOADED=1"

:RestartDiagnostics
call :RenderScreen

:: =========================================================
:: [1/4] Проверка установленных версий
:: =========================================================
echo Проверка установленных версий...
call :ShowProgress "Сканирование папок..." 35

call :RefreshVersionStatus

call :ShowProgress "Локальные версии определены" 100
echo.

if "!LIVE_CONFIGURED!"=="false" if "!PTU_CONFIGURED!"=="false" (
    echo ОШИБКА: Не настроена ни одна папка игры ^(LIVE/PTU^)
    echo.
    set /p "RECONFIRM=Настроить пути заново сейчас? (Y/N): "
    if /i "!RECONFIRM!"=="Y" goto :SetupConfig
    pause
    exit /b 1
)

:: =========================================================
:: [2/4] Проверка релизов на GitHub по тегам
:: =========================================================
echo Проверка обновлений на GitHub...
call :ShowProgress "Подключение к GitHub..." 40

call :GetGithubVersionsByTags

if "!GITHUB_OK!"=="false" (
    echo ⚠️ Не удалось получить данные о релизах GitHub
    echo.
) else (
    call :ShowProgress "Версии определены" 100
    if not "!LATEST_LIVE_VERSION!"=="не найдена" (
        echo ✓ LIVE по тегу: !LATEST_LIVE_VERSION! ^(тег: !LATEST_LIVE_TAG!^)
    ) else (
        echo ⚠️ LIVE-тег среди последних релизов не найден
    )
    if not "!LATEST_PTU_VERSION!"=="не найдена" (
        echo ✓ PTU по тегу:  !LATEST_PTU_VERSION! ^(тег: !LATEST_PTU_TAG!^)
    ) else (
        echo ⚠️ PTU-тег среди последних релизов не найден
    )
    echo.
)

:: =========================================================
:: [3/4] Расчёт статусов
:: =========================================================
call :RecalculateStatuses
set "STATUS_TABLE_READY=1"
call :RenderScreen

:: =========================================================
:: [4/4] Определение необходимости установки
:: =========================================================
call :DetermineInstallNeeds

if "!GITHUB_OK!"=="false" (
    echo Не удалось получить данные об обновлениях
    echo.
    call :ShowFinalReport
    echo Запуск лаунчера через 3 секунды...
    timeout /t 3 /nobreak >nul
    goto :LaunchGame
)

if "!INSTALL_LIVE_NEEDED!"=="false" if "!INSTALL_PTU_NEEDED!"=="false" (
    echo Все версии актуальны!
    echo.
    echo ✓ Обновление не требуется
    echo Запуск лаунчера через 3 секунды...
    timeout /t 3 /nobreak >nul
    goto :LaunchGame
)

echo  Запуск автоматической установки...
echo.

if "!INSTALL_LIVE_NEEDED!"=="true" (
    set "CURRENT_INSTALL=LIVE"
    goto :PrepareSelectedArchive
)

if "!INSTALL_PTU_NEEDED!"=="true" (
    set "CURRENT_INSTALL=PTU"
    goto :PrepareSelectedArchive
)

goto :LaunchGame

:: =========================================================
:: Установка выбранной ветки
:: =========================================================
:PrepareSelectedArchive
call :LoadCurrentBranchContext
if errorlevel 1 goto :ContinueAutoInstall

call :CheckCurrentBranchAlreadyUpToDate "!CURRENT_INSTALL!"
if "!BRANCH_ALREADY_SATISFIED!"=="true" (
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=актуальна, скачивание не требуется"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=актуальна, скачивание не требуется"
    goto :ContinueAutoInstall
)

if "!TARGET_TAG!"=="" (
    echo.
    echo ОШИБКА: Не удалось определить подходящий тег для !CURRENT_INSTALL!.
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=ошибка выбора тега"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=ошибка выбора тега"
    goto :ContinueAutoInstall
)

echo.
echo Подготовка архива !CURRENT_INSTALL! версии !TARGET_VERSION!...
call :ShowProgress "Скачивание архива..." 25

call :DownloadAndExtractArchive "!TARGET_TAG!"
if errorlevel 1 (
    echo ОШИБКА: Не удалось скачать или распаковать архив релиза.
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=ошибка скачивания/распаковки"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=ошибка скачивания/распаковки"
    goto :ContinueAutoInstall
)

if "!EXTRACTED_ROOT!"=="" (
    echo ОШИБКА: Не удалось определить распакованную папку архива.
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=ошибка структуры архива"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=ошибка структуры архива"
    goto :ContinueAutoInstall
)

set "ARCHIVE_GLOBAL_INI=!EXTRACTED_ROOT!\data\Localization\korean_(south_korea)\global.ini"
if not exist "!ARCHIVE_GLOBAL_INI!" (
    echo ОШИБКА: Файл global.ini не найден в распакованном архиве.
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=global.ini не найден"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=global.ini не найден"
    goto :ContinueAutoInstall
)

call :ShowProgress "Проверка содержимого архива..." 50

set "ARCHIVE_BUILD_TYPE=не найден"
set "ARCHIVE_VERSION=не найдена"
set "ARCHIVE_VERSION_DIGITS=не найдена"

call :GetBuildTypeFromFile "!ARCHIVE_GLOBAL_INI!" ARCHIVE_BUILD_TYPE
call :GetVersionFromFile "!ARCHIVE_GLOBAL_INI!" ARCHIVE_VERSION
call :ExtractVersionDigits "!ARCHIVE_VERSION!" ARCHIVE_VERSION_DIGITS

if "!ARCHIVE_BUILD_TYPE!"=="не найден" (
    echo ОШИБКА: Не удалось определить тип сборки в архиве.
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=тип сборки не определён"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=тип сборки не определён"
    goto :ContinueAutoInstall
)

if /i not "!ARCHIVE_BUILD_TYPE!"=="!CURRENT_INSTALL!" (
    echo.
    echo ⚠️ ВНИМАНИЕ: В архиве находится сборка типа !ARCHIVE_BUILD_TYPE!
    echo    Выбранная папка: !CURRENT_INSTALL!
    echo    Установка отменена.
    echo.
    call :MarkCurrentTagRejected "!CURRENT_INSTALL!" "!TARGET_TAG!"
    call :OfferNextCandidate "!CURRENT_INSTALL!"
    if errorlevel 2 goto :NoMoreCandidates
    goto :PrepareSelectedArchive
)

if not "!ARCHIVE_VERSION_DIGITS!"=="!TARGET_VERSION!" (
    echo.
    echo ⚠️ ВНИМАНИЕ: Версия в архиве не совпадает с ожидаемой по тегу.
    echo    Ожидалась: !TARGET_VERSION!
    echo    В архиве:  !ARCHIVE_VERSION_DIGITS!
    echo    Установка отменена.
    echo.
    call :MarkCurrentTagRejected "!CURRENT_INSTALL!" "!TARGET_TAG!"
    call :OfferNextCandidate "!CURRENT_INSTALL!"
    if errorlevel 2 goto :NoMoreCandidates
    goto :PrepareSelectedArchive
)

echo ✓ Архив подтверждён: !ARCHIVE_BUILD_TYPE! !ARCHIVE_VERSION_DIGITS!
echo.

set "SOURCE_DATA=!EXTRACTED_ROOT!\data"
if not exist "!SOURCE_DATA!" (
    echo ОШИБКА: В архиве отсутствует папка data
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=в архиве нет data"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=в архиве нет data"
    goto :ContinueAutoInstall
)

call :ShowProgress "Копирование файлов..." 75
xcopy "!SOURCE_DATA!\*" "!SELECTED_PATH!\data\" /E /Y /I /Q >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать файлы локализации.
    if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=ошибка копирования"
    if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=ошибка копирования"
    goto :ContinueAutoInstall
)

call :ShowProgress "Настройка user.cfg..." 90

if "!CURRENT_INSTALL!"=="LIVE" (
    set "USER_CFG_PATH=!LIVE_PATH!\user.cfg"
) else (
    set "USER_CFG_PATH=!PTU_PATH!\user.cfg"
)

call :BackupUserCfg "!USER_CFG_PATH!"
set "backup_result=!errorlevel!"

if "!backup_result!"=="0" (
    call :UpdateUserCfg "!USER_CFG_PATH!"
) else if "!backup_result!"=="2" (
    call :CreateUserCfg "!USER_CFG_PATH!"
) else (
    echo ⚠️ Не удалось создать резервную копию user.cfg. Настройка user.cfg пропущена.
)

call :RefreshVersionStatus
call :RecalculateStatuses

if "!CURRENT_INSTALL!"=="LIVE" (
    set "LIVE_REPO=https://github.com/%GITHUB_AUTHOR%/%GITHUB_REPO%"
    set "INSTALL_LIVE_RESULT=успешно обновлена до !ARCHIVE_VERSION_DIGITS!"
) else (
    set "PTU_REPO=https://github.com/%GITHUB_AUTHOR%/%GITHUB_REPO%"
    set "INSTALL_PTU_RESULT=успешно обновлена до !ARCHIVE_VERSION_DIGITS!"
)

set "LAST_REJECTED_LIVE_TAG="
set "LAST_REJECTED_PTU_TAG="

call :SaveConfig
call :RecalculateStatuses
call :CompleteProgress "Завершение..."
call :RenderScreen
echo ✓ Локализация !CURRENT_INSTALL! успешно установлена / обновлена до версии !ARCHIVE_VERSION_DIGITS!
echo.
goto :ContinueAutoInstall

:NoMoreCandidates
if /i "!CURRENT_INSTALL!"=="LIVE" set "INSTALL_LIVE_RESULT=подходящих тегов больше нет"
if /i "!CURRENT_INSTALL!"=="PTU" set "INSTALL_PTU_RESULT=подходящих тегов больше нет"
goto :ContinueAutoInstall

:ContinueAutoInstall
if "!CURRENT_INSTALL!"=="LIVE" (
    set "INSTALL_LIVE_NEEDED=false"
    if "!INSTALL_PTU_NEEDED!"=="true" (
        set "CURRENT_INSTALL=PTU"
        goto :PrepareSelectedArchive
    )
)

if "!CURRENT_INSTALL!"=="PTU" (
    set "INSTALL_PTU_NEEDED=false"
)

call :RefreshVersionStatus
call :RecalculateStatuses
call :RenderScreen
call :ShowFinalReport

echo Запуск лаунчера через 3 секунды...
timeout /t 3 /nobreak >nul
goto :LaunchGame

:: =========================================================
:: Запуск лаунчера
:: =========================================================
:LaunchGame
echo.
echo Запуск RSI Launcher...

if not "!LAUNCHER_PATH!"=="" (
    if exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
        echo ✓ Запускаю лаунчер из: !LAUNCHER_PATH!
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '!LAUNCHER_PATH!\RSI Launcher.exe'" >nul 2>&1
        exit /b 0
    )
)

if exist "%SCRIPT_DIR%RSI Launcher.exe" (
    echo ✓ Запускаю лаунчер из текущей папки...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%SCRIPT_DIR%RSI Launcher.exe'" >nul 2>&1
    exit /b 0
)

echo ОШИБКА: RSI Launcher.exe не найден
echo Настройте путь к лаунчеру в конфигурации
pause
exit /b 1

:: =========================================================
:: UI
:: =========================================================
:RenderScreen
cls
call :DrawHeader
call :DrawPaths
if defined STATUS_TABLE_READY call :DrawStatusTable
goto :eof

:DrawHeader
echo.
echo ════════════════════════════════════════════════════════
echo STAR - Script To Apply Russian.
echo Скрипт для установки русской локализации в Star citizen.
echo ════════════════════════════════════════════════════════
echo.
goto :eof

:DrawPaths
if defined PATHS_LOADED (
    echo Настроенные пути:
    if not "!LAUNCHER_PATH!"=="" echo   Лаунчер: !LAUNCHER_PATH!
    if "!LIVE_CONFIGURED!"=="true" if not "!LIVE_PATH!"=="" echo   LIVE:    !LIVE_PATH!
    if "!PTU_CONFIGURED!"=="true" if not "!PTU_PATH!"=="" echo   PTU:     !PTU_PATH!
    echo.
)
goto :eof

:DrawStatusTable
echo  Статус локализации:
echo.
echo  +-----------------------------------------------------------------------------------+
echo  ^| Ветка ^| Установлена            ^| GitHub по тегу       ^| Статус                    ^|
echo  +-----------------------------------------------------------------------------------+
call :PrintStatusRow "LIVE" "!LIVE_VERSION!" "!LATEST_LIVE_VERSION!" "!LIVE_STATUS!"
call :PrintStatusRow "PTU" "!PTU_VERSION!" "!LATEST_PTU_VERSION!" "!PTU_STATUS!"
echo  +-----------------------------------------------------------------------------------+
echo.
goto :eof

:PrintStatusRow
set "ROW_BRANCH=%~1"
set "ROW_INSTALLED=%~2"
set "ROW_GITHUB=%~3"
set "ROW_STATUS=%~4"

call :GetStatusColor "!ROW_STATUS!" STATUS_COLOR
call :GetVersionColor "!ROW_BRANCH!" VERSION_COLOR

call :MakeCell "!ROW_BRANCH!" 5  C1
call :MakeCell "!ROW_INSTALLED!" 22 C2_RAW
call :MakeCell "!ROW_GITHUB!" 20 C3
call :BuildStatusCell "!ROW_STATUS!" C4_RAW

set "C2=!VERSION_COLOR!!C2_RAW!!CLR_RESET!!CLR_DEFAULT!"
set "C4=!STATUS_COLOR!!C4_RAW!!CLR_RESET!!CLR_DEFAULT!"

echo  ^| !C1! ^| !C2! ^| !C3! ^| !C4! ^|
goto :eof

:BuildStatusCell
set "raw_status=%~1"
set "return_var=%~2"
set "cell_text=%raw_status%"

if /i "%raw_status%"=="актуальна" set "cell_text=✅ актуальна             "
if /i "%raw_status%"=="устарела" set "cell_text=⚠️ устарела              "
if /i "%raw_status%"=="не установлена" set "cell_text=📥 не установлена        "
if /i "%raw_status%"=="неверный тип" set "cell_text=❌ неверный тип          "
if /i "%raw_status%"=="нет данных GitHub" set "cell_text=🌐 нет данных GitHub     "
if /i "%raw_status%"=="папка не настроена" set "cell_text=📁 папка не настроена    "

set "%return_var%=%cell_text%"
goto :eof

:GetStatusColor
set "raw_status=%~1"
set "return_var=%~2"
set "status_color=%CLR_DEFAULT%"

if /i "%raw_status%"=="актуальна" set "status_color=%CLR_GREEN%"
if /i "%raw_status%"=="устарела" set "status_color=%CLR_YELLOW%"
if /i "%raw_status%"=="не установлена" set "status_color=%CLR_CYAN%"
if /i "%raw_status%"=="неверный тип" set "status_color=%CLR_RED%"
if /i "%raw_status%"=="нет данных GitHub" set "status_color=%CLR_RED%"
if /i "%raw_status%"=="папка не настроена" set "status_color=%CLR_GRAY%"

set "%return_var%=%status_color%"
goto :eof

:GetVersionColor
set "branch=%~1"
set "return_var=%~2"
set "version_color=%CLR_DEFAULT%"

if /i "%branch%"=="LIVE" (
    if /i "!LIVE_STATUS!"=="актуальна" set "version_color=%CLR_GREEN%"
    if /i "!LIVE_STATUS!"=="устарела" set "version_color=%CLR_YELLOW%"
    if /i "!LIVE_STATUS!"=="неверный тип" set "version_color=%CLR_RED%"
    if /i "!LIVE_STATUS!"=="не установлена" set "version_color=%CLR_CYAN%"
    if /i "!LIVE_STATUS!"=="папка не настроена" set "version_color=%CLR_GRAY%"
    if /i "!LIVE_STATUS!"=="нет данных GitHub" set "version_color=%CLR_DEFAULT%"
    goto :GetVersionColorDone
)

if /i "%branch%"=="PTU" (
    if /i "!PTU_STATUS!"=="актуальна" set "version_color=%CLR_GREEN%"
    if /i "!PTU_STATUS!"=="устарела" set "version_color=%CLR_YELLOW%"
    if /i "!PTU_STATUS!"=="неверный тип" set "version_color=%CLR_RED%"
    if /i "!PTU_STATUS!"=="не установлена" set "version_color=%CLR_CYAN%"
    if /i "!PTU_STATUS!"=="папка не настроена" set "version_color=%CLR_GRAY%"
    if /i "!PTU_STATUS!"=="нет данных GitHub" set "version_color=%CLR_DEFAULT%"
)

:GetVersionColorDone
set "%return_var%=%version_color%"
goto :eof

:MakeCell
setlocal EnableDelayedExpansion
set "text=%~1"
if not defined text set "text=-"
set "text=!text!                                                            "
set "text=!text:~0,%~2!"
endlocal & set "%~3=%text%"
goto :eof

:ShowProgress
set "message=%~1"
set "percent=%~2"
set "bar="
set /a "filled=%percent%/5"
set /a "empty=20-filled"

for /l %%i in (1,1,%filled%) do set "bar=!bar!█"
for /l %%i in (1,1,%empty%) do set "bar=!bar!░"

call :RenderScreen
echo !message! [!bar!] !percent!%%
goto :eof

:CompleteProgress
set "message=%~1"
call :RenderScreen
echo !message! [████████████████████] 100%%
echo.
goto :eof

:ShowFinalReport
echo Результат установки:
echo   LIVE: !INSTALL_LIVE_RESULT!
echo   PTU : !INSTALL_PTU_RESULT!
echo.

if "!GITHUB_OK!"=="false" (
    echo ⚠️ Не удалось получить данные об обновлениях с GitHub.
    echo.
    goto :eof
)

if /i "!INSTALL_LIVE_RESULT!"=="подходящих тегов больше нет" (
    echo ⚠️ LIVE не была обновлена: подходящие теги закончились.
)
if /i "!INSTALL_PTU_RESULT!"=="подходящих тегов больше нет" (
    echo ⚠️ PTU не была обновлена: подходящие теги закончились.
)
if /i "!INSTALL_LIVE_RESULT!"=="ошибка выбора тега" (
    echo ⚠️ LIVE не была обновлена: не удалось определить тег.
)
if /i "!INSTALL_PTU_RESULT!"=="ошибка выбора тега" (
    echo ⚠️ PTU не была обновлена: не удалось определить тег.
)

echo.
echo Все возможные действия завершены.
goto :eof

:: =========================================================
:: Конфиг / настройка путей
:: =========================================================
:LoadOrSetupConfig
if exist "%CONFIG_FILE%" (
    echo Загружаю сохранённую конфигурацию...

    for /f "usebackq delims=" %%L in ("%CONFIG_FILE%") do (
        set "cfg_line=%%L"
        if defined cfg_line (
            if not "!cfg_line:~0,2!"=="//" (
                for /f "tokens=1,* delims==" %%a in ("!cfg_line!") do (
                    if "%%a"=="LAUNCHER_PATH" set "LAUNCHER_PATH=%%b"
                    if "%%a"=="LIVE_REPO" set "LIVE_REPO=%%b"
                    if "%%a"=="LIVE_VERSION" set "LIVE_VERSION=%%b"
                    if "%%a"=="LIVE_PATH" set "LIVE_PATH=%%b"
                    if "%%a"=="PTU_REPO" set "PTU_REPO=%%b"
                    if "%%a"=="PTU_VERSION" set "PTU_VERSION=%%b"
                    if "%%a"=="PTU_PATH" set "PTU_PATH=%%b"
                )
            )
        )
    )

    echo Настроенные пути:
    if not "!LAUNCHER_PATH!"=="" echo   Лаунчер: !LAUNCHER_PATH!
    if not "!LIVE_PATH!"=="" echo   LIVE: !LIVE_PATH!
    if not "!PTU_PATH!"=="" echo   PTU:  !PTU_PATH!
    echo.

    set "LIVE_CONFIGURED=false"
    set "PTU_CONFIGURED=false"
    set "BROKEN_CONFIG=false"

    if not "!LIVE_PATH!"=="" (
        call :ValidateGameFolder "!LIVE_PATH!" "LIVE"
        if errorlevel 1 (
            echo ⚠ Папка LIVE недоступна по сохранённому пути
            set "LIVE_PATH="
            set "BROKEN_CONFIG=true"
        ) else (
            set "LIVE_CONFIGURED=true"
        )
    )

    if not "!PTU_PATH!"=="" (
        call :ValidateGameFolder "!PTU_PATH!" "PTU"
        if errorlevel 1 (
            echo ⚠ Папка PTU недоступна по сохранённому пути
            set "PTU_PATH="
            set "BROKEN_CONFIG=true"
        ) else (
            set "PTU_CONFIGURED=true"
        )
    )

    if not "!LAUNCHER_PATH!"=="" (
        if not exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
            echo ⚠ Лаунчер не найден по указанному пути
            set "LAUNCHER_PATH="
            set "BROKEN_CONFIG=true"
        )
    )

    if "!LIVE_CONFIGURED!"=="true" goto :eof
    if "!PTU_CONFIGURED!"=="true" goto :eof

    echo.
    if "!BROKEN_CONFIG!"=="true" (
        echo Сохранённые пути стали невалидны.
        set /p "RECONFIGURE_NOW=Настроить пути заново сейчас? (Y/N): "
        if /i "!RECONFIGURE_NOW!"=="Y" goto :SetupConfig
        goto :eof
    ) else (
        echo Необходимо настроить пути заново.
        goto :SetupConfig
    )
) else (
    echo Конфигурационный файл не найден.
    echo Запуск первоначальной настройки...
)

:SetupConfig
cls
echo.
echo ════════════════════════════════════════
echo    Первоначальная настройка путей
echo ════════════════════════════════════════
echo.

echo Настройка пути к RSI Launcher
echo.

if not "!LAUNCHER_PATH!"=="" (
    if not defined LAUNCHER_AUTO_DETECTED (
        echo ✓ Текущий путь к лаунчеру: !LAUNCHER_PATH!
        set /p "RECONFIGURE_LAUNCHER=Переустановить путь к лаунчеру? (Y/N): "
        if /i not "!RECONFIGURE_LAUNCHER!"=="Y" goto :SkipLauncherSetup
    ) else (
        goto :SkipLauncherSetup
    )
)

:SelectLauncherFolder
call :SelectFolder "Выберите папку с RSI Launcher.exe" LAUNCHER_PATH
if not "!LAUNCHER_PATH!"=="" (
    if not exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
        echo ✗ RSI Launcher.exe не найден в выбранной папке
        set /p "RETRY=Выбрать другую папку? (Y/N): "
        if /i "!RETRY!"=="Y" goto :SelectLauncherFolder
        set "LAUNCHER_PATH="
    ) else (
        echo ✓ RSI Launcher найден: !LAUNCHER_PATH!
    )
) else (
    echo Папка не выбрана
)

:SkipLauncherSetup

echo.
echo Поиск установленных версий игры
echo Автоматический поиск установленных версий...
call :FindStandardPaths

echo.
echo Настройка папки LIVE

if defined LIVE_AUTO_DETECTED (
    echo ✓ Папка LIVE автоматически обнаружена: !LIVE_PATH!
    set "LIVE_CONFIGURED=true"
    set "LIVE_AUTO_DETECTED="
    goto :SkipLiveSetup
)

if "!LIVE_FOUND!"=="true" (
    echo ✓ Найдена потенциальная папка LIVE: !LIVE_PATH!
    call :ValidateGameFolder "!LIVE_PATH!" "LIVE"
    if not errorlevel 1 (
        set /p "USE_FOUND=Использовать этот путь? (Y/N): "
        if /i not "!USE_FOUND!"=="Y" (
            set "LIVE_FOUND=false"
            set "LIVE_PATH="
            set "LIVE_CONFIGURED=false"
        ) else (
            set "LIVE_CONFIGURED=true"
        )
    ) else (
        set "LIVE_FOUND=false"
        set "LIVE_PATH="
        set "LIVE_CONFIGURED=false"
    )
)

if "!LIVE_FOUND!"=="false" (
    :SelectLiveFolder
    call :SelectFolder "Выберите папку LIVE игры" LIVE_PATH
    if not "!LIVE_PATH!"=="" (
        call :ValidateGameFolder "!LIVE_PATH!" "LIVE"
        if errorlevel 1 (
            set /p "RETRY=Выбрать другую папку? (Y/N): "
            if /i "!RETRY!"=="Y" goto :SelectLiveFolder
            set "LIVE_PATH="
            set "LIVE_CONFIGURED=false"
        ) else (
            set "LIVE_CONFIGURED=true"
        )
    )
)

:SkipLiveSetup

echo.
echo Настройка PTU (опционально)

if "!PTU_FOUND!"=="true" (
    echo ✓ Найдена потенциальная папка PTU: !PTU_PATH!
    call :ValidateGameFolder "!PTU_PATH!" "PTU"
    if not errorlevel 1 (
        set /p "USE_FOUND=Использовать этот путь? (Y/N): "
        if /i not "!USE_FOUND!"=="Y" (
            set "PTU_FOUND=false"
            set "PTU_PATH="
            set "PTU_CONFIGURED=false"
        ) else (
            set "PTU_CONFIGURED=true"
        )
    ) else (
        set "PTU_FOUND=false"
        set "PTU_PATH="
        set "PTU_CONFIGURED=false"
    )
)

if "!PTU_FOUND!"=="false" (
    set /p "ASK_PTU=Настроить папку PTU? (Y/N): "
    if /i "!ASK_PTU!"=="Y" (
        :SelectPTUFolder
        call :SelectFolder "Выберите папку PTU игры" PTU_PATH
        if not "!PTU_PATH!"=="" (
            call :ValidateGameFolder "!PTU_PATH!" "PTU"
            if errorlevel 1 (
                set /p "RETRY=Выбрать другую папку? (Y/N): "
                if /i "!RETRY!"=="Y" goto :SelectPTUFolder
                set "PTU_PATH="
                set "PTU_CONFIGURED=false"
            ) else (
                set "PTU_CONFIGURED=true"
            )
        )
    )
)

if "!LIVE_CONFIGURED!"=="false" if "!PTU_CONFIGURED!"=="false" (
    echo ОШИБКА: Не настроено ни одной папки игры
    pause
    exit /b 1
)

call :SaveConfig
echo.
echo ✓ Конфигурация сохранена: %CONFIG_FILE%
timeout /t 2 /nobreak >nul
goto :eof

:SaveConfig
(
    echo //Конфигурационный файл скрипта русификации StarCitizen
    echo LAUNCHER_PATH=!LAUNCHER_PATH!
    echo LIVE_REPO=!LIVE_REPO!
    echo LIVE_VERSION=!LIVE_VERSION!
    echo LIVE_PATH=!LIVE_PATH!
    echo PTU_REPO=!PTU_REPO!
    echo PTU_VERSION=!PTU_VERSION!
    echo PTU_PATH=!PTU_PATH!
) > "%CONFIG_FILE%"
goto :eof

:ValidateGameFolder
set "game_path=%~1"
set "game_type=%~2"
set "is_valid=0"

if "%game_path%"=="" exit /b 1

echo.
echo Проверяю папку !game_type!...

if not exist "!game_path!\" (
    echo ✗ Папка не существует: !game_path!
    set "is_valid=1"
    goto :ValidateGameFolderEnd
)

if not exist "!game_path!\Bin64\" (
    echo ✗ Отсутствует обязательная папка: Bin64
    set "is_valid=1"
    goto :ValidateGameFolderEnd
)

if not exist "!game_path!\StarCitizen_Launcher.exe" (
    echo ✗ Отсутствует обязательный файл: StarCitizen_Launcher.exe
    set "is_valid=1"
    goto :ValidateGameFolderEnd
)

if not exist "!game_path!\data\Localization\korean_(south_korea)\global.ini" (
    echo ⚠ Файл локализации пока не найден ^(это допустимо для новой установки^)
)

echo ✓ Найден StarCitizen_Launcher.exe
echo ✓ Найдена папка Bin64

:ValidateGameFolderEnd
if !is_valid! equ 0 (
    echo ✓ Папка !game_type! прошла проверку
) else (
    echo ✗ Папка !game_type! не прошла проверку
)
exit /b !is_valid!

:FindStandardPaths
set "LIVE_FOUND=false"
set "PTU_FOUND=false"

set DISKS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z

for %%D in (!DISKS!) do (
    set "test_path1=%%D:\Roberts Space Industries\StarCitizen\LIVE"
    set "test_path2=%%D:\Program Files\Roberts Space Industries\StarCitizen\LIVE"
    set "test_path3=%%D:\Program Files (x86)\Roberts Space Industries\StarCitizen\LIVE"
    set "test_path4=%%D:\Games\StarCitizen\LIVE"
    set "test_path5=%%D:\StarCitizen\LIVE"

    for %%P in ("!test_path1!" "!test_path2!" "!test_path3!" "!test_path4!" "!test_path5!") do (
        if exist "%%~P\StarCitizen_Launcher.exe" (
            if "!LIVE_FOUND!"=="false" (
                set "LIVE_PATH=%%~P"
                set "LIVE_FOUND=true"
            )
        )
    )
)

for %%D in (!DISKS!) do (
    set "test_path1=%%D:\Roberts Space Industries\StarCitizen\PTU"
    set "test_path2=%%D:\Program Files\Roberts Space Industries\StarCitizen\PTU"
    set "test_path3=%%D:\Program Files (x86)\Roberts Space Industries\StarCitizen\PTU"
    set "test_path4=%%D:\Games\StarCitizen\PTU"
    set "test_path5=%%D:\StarCitizen\PTU"

    for %%P in ("!test_path1!" "!test_path2!" "!test_path3!" "!test_path4!" "!test_path5!") do (
        if exist "%%~P\StarCitizen_Launcher.exe" (
            if "!PTU_FOUND!"=="false" (
                set "PTU_PATH=%%~P"
                set "PTU_FOUND=true"
            )
        )
    )
)
goto :eof

:SelectFolder
set "description=%~1"
set "varname=%~2"
set "SELECTED_PATH="

echo.
echo %description%
echo.

set "psScript=Add-Type -AssemblyName System.Windows.Forms; $dlg = New-Object System.Windows.Forms.FolderBrowserDialog; $dlg.Description = '%description%'; $dlg.RootFolder = 'MyComputer'; $dlg.ShowNewFolderButton = $false; if($dlg.ShowDialog() -eq 'OK'){ $dlg.SelectedPath }"
for /f "delims=" %%F in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "!psScript!"') do set "SELECTED_PATH=%%F"

if "!SELECTED_PATH!"=="" (
    set "!varname!="
    exit /b 1
) else (
    echo Выбрана папка: !SELECTED_PATH!
    set "!varname!=!SELECTED_PATH!"
    exit /b 0
)

:: =========================================================
:: Версии / статусы
:: =========================================================
:RefreshVersionStatus
set "LIVE_BUILD_TYPE=не найден"
set "PTU_BUILD_TYPE=не найден"

set "LIVE_VERSION=не найдена"
set "PTU_VERSION=не найдена"

set "LIVE_VERSION_DIGITS=не найдена"
set "PTU_VERSION_DIGITS=не найдена"

set "LIVE_TYPE_MISMATCH=false"
set "PTU_TYPE_MISMATCH=false"

if not "!LIVE_PATH!"=="" (
    set "LIVE_CONFIGURED=true"
    set "LIVE_VERSION_FILE=!LIVE_PATH!\data\Localization\korean_(south_korea)\global.ini"
    if exist "!LIVE_VERSION_FILE!" (
        call :GetVersionFromFile "!LIVE_VERSION_FILE!" LIVE_VERSION
        call :GetBuildTypeFromFile "!LIVE_VERSION_FILE!" LIVE_BUILD_TYPE
        call :ExtractVersionDigits "!LIVE_VERSION!" LIVE_VERSION_DIGITS
        if /i not "!LIVE_BUILD_TYPE!"=="LIVE" set "LIVE_TYPE_MISMATCH=true"
    )
) else (
    set "LIVE_CONFIGURED=false"
)

if not "!PTU_PATH!"=="" (
    set "PTU_CONFIGURED=true"
    set "PTU_VERSION_FILE=!PTU_PATH!\data\Localization\korean_(south_korea)\global.ini"
    if exist "!PTU_VERSION_FILE!" (
        call :GetVersionFromFile "!PTU_VERSION_FILE!" PTU_VERSION
        call :GetBuildTypeFromFile "!PTU_VERSION_FILE!" PTU_BUILD_TYPE
        call :ExtractVersionDigits "!PTU_VERSION!" PTU_VERSION_DIGITS
        if /i not "!PTU_BUILD_TYPE!"=="PTU" set "PTU_TYPE_MISMATCH=true"
    )
) else (
    set "PTU_CONFIGURED=false"
)
goto :eof

:RecalculateStatuses
if "!LIVE_CONFIGURED!"=="false" (
    set "LIVE_STATUS=папка не настроена"
) else if "!LIVE_VERSION!"=="не найдена" (
    if not "!LATEST_LIVE_VERSION!"=="не найдена" (
        set "LIVE_STATUS=не установлена"
    ) else (
        set "LIVE_STATUS=нет данных GitHub"
    )
) else if "!LIVE_TYPE_MISMATCH!"=="true" (
    set "LIVE_STATUS=неверный тип"
) else if "!LATEST_LIVE_VERSION!"=="не найдена" (
    set "LIVE_STATUS=нет данных GitHub"
) else if "!LIVE_VERSION_DIGITS!"=="!LATEST_LIVE_VERSION!" (
    set "LIVE_STATUS=актуальна"
) else (
    set "LIVE_STATUS=устарела"
)

if "!PTU_CONFIGURED!"=="false" (
    set "PTU_STATUS=папка не настроена"
) else if "!PTU_VERSION!"=="не найдена" (
    if not "!LATEST_PTU_VERSION!"=="не найдена" (
        set "PTU_STATUS=не установлена"
    ) else (
        set "PTU_STATUS=нет данных GitHub"
    )
) else if "!PTU_TYPE_MISMATCH!"=="true" (
    set "PTU_STATUS=неверный тип"
) else if "!LATEST_PTU_VERSION!"=="не найдена" (
    set "PTU_STATUS=нет данных GitHub"
) else if "!PTU_VERSION_DIGITS!"=="!LATEST_PTU_VERSION!" (
    set "PTU_STATUS=актуальна"
) else (
    set "PTU_STATUS=устарела"
)
goto :eof

:DetermineInstallNeeds
set "INSTALL_LIVE_NEEDED=false"
set "INSTALL_PTU_NEEDED=false"

if "!GITHUB_OK!"=="false" (
    if "!LIVE_CONFIGURED!"=="true" (
        set "INSTALL_LIVE_RESULT=не удалось проверить обновления"
    ) else (
        set "INSTALL_LIVE_RESULT=не настроена"
    )

    if "!PTU_CONFIGURED!"=="true" (
        set "INSTALL_PTU_RESULT=не удалось проверить обновления"
    ) else (
        set "INSTALL_PTU_RESULT=не настроена"
    )

    goto :eof
)

if "!LIVE_CONFIGURED!"=="true" (
    if "!LIVE_VERSION!"=="не найдена" set "INSTALL_LIVE_NEEDED=true"
    if "!LIVE_TYPE_MISMATCH!"=="true" set "INSTALL_LIVE_NEEDED=true"
    if "!LIVE_TYPE_MISMATCH!"=="false" (
        if not "!LATEST_LIVE_VERSION!"=="не найдена" (
            if not "!LIVE_VERSION_DIGITS!"=="!LATEST_LIVE_VERSION!" set "INSTALL_LIVE_NEEDED=true"
        )
    )
)

if "!PTU_CONFIGURED!"=="true" (
    if "!PTU_VERSION!"=="не найдена" set "INSTALL_PTU_NEEDED=true"
    if "!PTU_TYPE_MISMATCH!"=="true" set "INSTALL_PTU_NEEDED=true"
    if "!PTU_TYPE_MISMATCH!"=="false" (
        if not "!LATEST_PTU_VERSION!"=="не найдена" (
            if not "!PTU_VERSION_DIGITS!"=="!LATEST_PTU_VERSION!" set "INSTALL_PTU_NEEDED=true"
        )
    )
)

if "!LIVE_CONFIGURED!"=="true" (
    if "!INSTALL_LIVE_NEEDED!"=="true" (
        set "INSTALL_LIVE_RESULT=ожидает установки"
    ) else (
        set "INSTALL_LIVE_RESULT=актуальна"
    )
) else (
    set "INSTALL_LIVE_RESULT=не настроена"
)

if "!PTU_CONFIGURED!"=="true" (
    if "!INSTALL_PTU_NEEDED!"=="true" (
        set "INSTALL_PTU_RESULT=ожидает установки"
    ) else (
        set "INSTALL_PTU_RESULT=актуальна"
    )
) else (
    set "INSTALL_PTU_RESULT=не настроена"
)

goto :eof

:CheckCurrentBranchAlreadyUpToDate
set "branch=%~1"
set "BRANCH_ALREADY_SATISFIED=false"

if /i "%branch%"=="LIVE" (
    if "!LIVE_CONFIGURED!"=="true" (
        if /i "!LIVE_BUILD_TYPE!"=="LIVE" (
            if not "!TARGET_VERSION!"=="" (
                if "!LIVE_VERSION_DIGITS!"=="!TARGET_VERSION!" set "BRANCH_ALREADY_SATISFIED=true"
            )
        )
    )
    goto :eof
)

if /i "%branch%"=="PTU" (
    if "!PTU_CONFIGURED!"=="true" (
        if /i "!PTU_BUILD_TYPE!"=="PTU" (
            if not "!TARGET_VERSION!"=="" (
                if "!PTU_VERSION_DIGITS!"=="!TARGET_VERSION!" set "BRANCH_ALREADY_SATISFIED=true"
            )
        )
    )
)
goto :eof

:: =========================================================
:: GitHub / кандидаты
:: =========================================================
:GetGithubVersionsByTags
set "GITHUB_OK=false"

for /l %%N in (1,1,50) do (
    set "LIVE_CAND_VER_%%N="
    set "LIVE_CAND_TAG_%%N="
    set "PTU_CAND_VER_%%N="
    set "PTU_CAND_TAG_%%N="
)

set "LIVE_CAND_COUNT=0"
set "PTU_CAND_COUNT=0"
set "LIVE_CURRENT_INDEX=1"
set "PTU_CURRENT_INDEX=1"

for /f "usebackq tokens=1,2,3 delims=|" %%a in (`
powershell -NoProfile -ExecutionPolicy Bypass -Command "$o='%GITHUB_AUTHOR%';$r='%GITHUB_REPO%';$wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','SC-RU-Updater');try{$relsJson=$wc.DownloadString(('https://api.github.com/repos/{0}/{1}/releases?per_page=50' -f $o,$r));$rels=$relsJson|ConvertFrom-Json;foreach($rel in $rels){$tag=$rel.tag_name;if($tag -match '^(\d+\.\d+\.\d+)-(v\d+)$'){Write-Output ('LIVE|'+$matches[1]+' '+$matches[2]+'|'+$tag)}elseif($tag -match '^(\d+\.\d+\.\d+)-(v\d+)-ptu$'){Write-Output ('PTU|'+$matches[1]+' '+$matches[2]+'|'+$tag)}}}catch{}"
`) do (
    if "%%a"=="LIVE" (
        set /a LIVE_CAND_COUNT+=1
        set "LIVE_CAND_VER_!LIVE_CAND_COUNT!=%%b"
        set "LIVE_CAND_TAG_!LIVE_CAND_COUNT!=%%c"
    )
    if "%%a"=="PTU" (
        set /a PTU_CAND_COUNT+=1
        set "PTU_CAND_VER_!PTU_CAND_COUNT!=%%b"
        set "PTU_CAND_TAG_!PTU_CAND_COUNT!=%%c"
    )
)

call :SetCurrentGithubVersions

if !LIVE_CAND_COUNT! gtr 0 set "GITHUB_OK=true"
if !PTU_CAND_COUNT! gtr 0 set "GITHUB_OK=true"
goto :eof

:SetCurrentGithubVersions
set "LATEST_LIVE_VERSION=не найдена"
set "LATEST_LIVE_TAG="
set "LATEST_PTU_VERSION=не найдена"
set "LATEST_PTU_TAG="

if !LIVE_CAND_COUNT! geq !LIVE_CURRENT_INDEX! (
    call set "LATEST_LIVE_VERSION=%%LIVE_CAND_VER_!LIVE_CURRENT_INDEX!%%"
    call set "LATEST_LIVE_TAG=%%LIVE_CAND_TAG_!LIVE_CURRENT_INDEX!%%"
)

if !PTU_CAND_COUNT! geq !PTU_CURRENT_INDEX! (
    call set "LATEST_PTU_VERSION=%%PTU_CAND_VER_!PTU_CURRENT_INDEX!%%"
    call set "LATEST_PTU_TAG=%%PTU_CAND_TAG_!PTU_CURRENT_INDEX!%%"
)
goto :eof

:LoadCurrentBranchContext
set "TARGET_VERSION="
set "TARGET_TAG="
set "SELECTED_PATH="

if /i "!CURRENT_INSTALL!"=="LIVE" (
    call set "TARGET_VERSION=%%LIVE_CAND_VER_!LIVE_CURRENT_INDEX!%%"
    call set "TARGET_TAG=%%LIVE_CAND_TAG_!LIVE_CURRENT_INDEX!%%"
    set "SELECTED_PATH=!LIVE_PATH!"
    goto :LoadCurrentBranchContextDone
)

if /i "!CURRENT_INSTALL!"=="PTU" (
    call set "TARGET_VERSION=%%PTU_CAND_VER_!PTU_CURRENT_INDEX!%%"
    call set "TARGET_TAG=%%PTU_CAND_TAG_!PTU_CURRENT_INDEX!%%"
    set "SELECTED_PATH=!PTU_PATH!"
    goto :LoadCurrentBranchContextDone
)

exit /b 1

:LoadCurrentBranchContextDone
if "!TARGET_TAG!"=="" exit /b 1
exit /b 0

:MarkCurrentTagRejected
set "branch=%~1"
set "tag=%~2"

if /i "%branch%"=="LIVE" (
    set "LAST_REJECTED_LIVE_TAG=%tag%"
    goto :eof
)

if /i "%branch%"=="PTU" (
    set "LAST_REJECTED_PTU_TAG=%tag%"
)
goto :eof

:OfferNextCandidate
set "branch=%~1"
set "NEXT_VERSION="
set "NEXT_TAG="
set "FOUND=false"

if /i "%branch%"=="LIVE" (
    for /l %%I in (!LIVE_CURRENT_INDEX!,1,!LIVE_CAND_COUNT!) do (
        if "!FOUND!"=="false" (
            if not "%%I"=="!LIVE_CURRENT_INDEX!" (
                call set "CAND_VERSION=%%LIVE_CAND_VER_%%I%%"
                call set "CAND_TAG=%%LIVE_CAND_TAG_%%I%%"

                set "SKIP=false"
                if defined LAST_REJECTED_LIVE_TAG (
                    if /i "!CAND_TAG!"=="!LAST_REJECTED_LIVE_TAG!" set "SKIP=true"
                )

                if "!SKIP!"=="false" (
                    set "NEXT_VERSION=!CAND_VERSION!"
                    set "NEXT_TAG=!CAND_TAG!"
                    set "NEXT_INDEX=%%I"
                    set "FOUND=true"
                )
            )
        )
    )

    if "!FOUND!"=="false" (
        echo Других LIVE-кандидатов по списку тегов больше нет.
        exit /b 2
    )

    echo Автоматически пробую следующий LIVE тег: !NEXT_TAG! ^(!NEXT_VERSION!^)
    set /a LIVE_CURRENT_INDEX=!NEXT_INDEX!
    call :SetCurrentGithubVersions
    exit /b 0
)

if /i "%branch%"=="PTU" (
    for /l %%I in (!PTU_CURRENT_INDEX!,1,!PTU_CAND_COUNT!) do (
        if "!FOUND!"=="false" (
            if not "%%I"=="!PTU_CURRENT_INDEX!" (
                call set "CAND_VERSION=%%PTU_CAND_VER_%%I%%"
                call set "CAND_TAG=%%PTU_CAND_TAG_%%I%%"

                set "SKIP=false"
                if defined LAST_REJECTED_PTU_TAG (
                    if /i "!CAND_TAG!"=="!LAST_REJECTED_PTU_TAG!" set "SKIP=true"
                )

                if "!SKIP!"=="false" (
                    set "NEXT_VERSION=!CAND_VERSION!"
                    set "NEXT_TAG=!CAND_TAG!"
                    set "NEXT_INDEX=%%I"
                    set "FOUND=true"
                )
            )
        )
    )

    if "!FOUND!"=="false" (
        echo Других PTU-кандидатов по списку тегов больше нет.
        exit /b 2
    )

    echo Автоматически пробую следующий PTU тег: !NEXT_TAG! ^(!NEXT_VERSION!^)
    set /a PTU_CURRENT_INDEX=!NEXT_INDEX!
    call :SetCurrentGithubVersions
    exit /b 0
)

exit /b 2

:: =========================================================
:: Файлы игры
:: =========================================================
:GetVersionFromFile
set "file_path=%~1"
set "return_var=%~2"
set "version=не найдена"

if not exist "%file_path%" (
    set "%return_var%=не найдена"
    goto :eof
)

for /f "usebackq delims=" %%b in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $content = Get-Content -LiteralPath '%file_path%' -Encoding UTF8 -Raw; if($content -match 'Установленная версия:\s+((?:LIVE|PTU)\s+[\d\.]+\s+v\d+)'){ $matches[1] } else { 'не найдена' } } catch { 'не найдена' }"`) do (
    set "version=%%b"
)

set "%return_var%=%version%"
goto :eof

:GetBuildTypeFromFile
set "file_path=%~1"
set "return_var=%~2"
set "build_type=не найден"

if not exist "%file_path%" (
    set "%return_var%=не найден"
    goto :eof
)

for /f "usebackq delims=" %%b in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $content = Get-Content -LiteralPath '%file_path%' -Encoding UTF8 -Raw; if($content -match 'Установленная версия:\s+(LIVE|PTU)\s+[\d\.]+\s+v\d+'){ $matches[1] } else { 'не найден' } } catch { 'не найден' }"`) do (
    set "build_type=%%b"
)

set "%return_var%=%build_type%"
goto :eof

:ExtractVersionDigits
set "full_version=%~1"
set "return_var=%~2"
set "version_digits=не найдена"

for /f "tokens=2,3" %%a in ("%full_version%") do (
    set "version_digits=%%a %%b"
)

set "%return_var%=!version_digits!"
goto :eof

:BackupUserCfg
set "user_cfg_path=%~1"

if "%user_cfg_path%"=="" (
    echo [DEBUG] BackupUserCfg: пустой путь
    exit /b 3
)

if not exist "%user_cfg_path%" (
    exit /b 2
)

copy /y "%user_cfg_path%" "%user_cfg_path%.bak" >nul 2>&1
if errorlevel 1 (
    echo [DEBUG] BackupUserCfg: не удалось создать backup: "%user_cfg_path%.bak"
    exit /b 1
)

exit /b 0

:UpdateUserCfg
set "user_cfg_path=%~1"
set "backup_path=%user_cfg_path%.bak"
set "new_path=%user_cfg_path%.new"

if "%user_cfg_path%"=="" (
    echo [DEBUG] UpdateUserCfg: пустой путь
    exit /b 1
)

if not exist "%backup_path%" (
    echo [DEBUG] UpdateUserCfg: backup не найден: "%backup_path%"
    exit /b 1
)

set "HAS_LANG=false"
set "HAS_AUDIO=false"

(
    rem файл создаётся заново
) > "%new_path%"

for /f "usebackq delims=" %%a in ("%backup_path%") do (
    set "line=%%a"
    set "skip_line=false"

    echo(%%a | findstr /i /b /c:"g_language=" >nul
    if not errorlevel 1 (
        >> "%new_path%" echo g_language=korean_(south_korea^)
        set "HAS_LANG=true"
        set "skip_line=true"
    )

    if "!skip_line!"=="false" (
        echo(%%a | findstr /i /b /c:"g_languageAudio=" >nul
        if not errorlevel 1 (
            >> "%new_path%" echo g_languageAudio=english
            set "HAS_AUDIO=true"
            set "skip_line=true"
        )
    )

    if "!skip_line!"=="false" (
        >> "%new_path%" echo(%%a
    )
)

if /i "!HAS_LANG!"=="false" (
    >> "%new_path%" echo g_language=korean_(south_korea^)
)

if /i "!HAS_AUDIO!"=="false" (
    >> "%new_path%" echo g_languageAudio=english
)

move /y "%new_path%" "%user_cfg_path%" >nul 2>&1
if errorlevel 1 (
    echo [DEBUG] UpdateUserCfg: move не удался, пытаюсь восстановить backup
    copy /y "%backup_path%" "%user_cfg_path%" >nul 2>&1
    del /q "%new_path%" >nul 2>&1
    exit /b 1
)

exit /b 0

:CreateUserCfg
set "user_cfg_path=%~1"

if "%user_cfg_path%"=="" (
    echo [DEBUG] CreateUserCfg: пустой путь
    exit /b 1
)

for %%D in ("%user_cfg_path%") do set "user_cfg_dir=%%~dpD"

if not exist "%user_cfg_dir%" (
    echo [DEBUG] CreateUserCfg: папка не существует: "%user_cfg_dir%"
    exit /b 1
)

(
    echo g_language=korean_(south_korea^)
    echo g_languageAudio=english
) > "%user_cfg_path%"

if exist "%user_cfg_path%" (
    echo [DEBUG] CreateUserCfg: файл создан: "%user_cfg_path%"
    exit /b 0
) else (
    echo [DEBUG] CreateUserCfg: файл не создан: "%user_cfg_path%"
    exit /b 1
)

:DownloadAndExtractArchive
set "req_tag=%~1"
set "EXTRACTED_ROOT="
if "%req_tag%"=="" exit /b 1

set "WORK_DIR=%TEMP_DIR%\work"
set "ZIP_FILE=%WORK_DIR%\release.zip"
set "EXTRACT_DIR=%WORK_DIR%\extracted"

if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%" >nul 2>&1
mkdir "%WORK_DIR%" >nul 2>&1

set "DOWNLOAD_URL=https://github.com/%GITHUB_AUTHOR%/%GITHUB_REPO%/archive/refs/tags/%req_tag%.zip"

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Headers @{ 'User-Agent'='SC-RU-Updater' } -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
if errorlevel 1 exit /b 1

call :ShowProgress "Распаковка архива..." 40
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force; exit 0 } catch { exit 1 }" >nul 2>&1
if errorlevel 1 exit /b 1

for /d %%D in ("%EXTRACT_DIR%\StarCitizenRu-*") do (
    if exist "%%~fD\data\Localization\korean_(south_korea)\global.ini" (
        set "EXTRACTED_ROOT=%%~fD"
    )
)

if "!EXTRACTED_ROOT!"=="" exit /b 1
exit /b 0