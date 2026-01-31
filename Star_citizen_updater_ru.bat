@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: Настройки
set "LAUNCHER_DIR=%~dp0"
set "GITHUB_REPO=n1ghter/StarCitizenRu"
set "GITHUB_RAW=https://raw.githubusercontent.com/%GITHUB_REPO%/master"
set "TEMP_DIR=%LAUNCHER_DIR%temp_debug"
set "CONFIG_FILE=%LAUNCHER_DIR%sc_ru_config.cfg"

:: Переменные конфигурации
set "LAUNCHER_PATH="
set "LIVE_REPO="
set "LIVE_VERSION="
set "LIVE_PATH="
set "PTU_REPO="
set "PTU_VERSION="
set "PTU_PATH="

cls
call :DrawHeader

:: Загрузка конфигурации или настройка путей
call :LoadOrSetupConfig

:: Проверка пути лаунчера после загрузки конфигурации
if "!LAUNCHER_PATH!"=="" (
    echo.
    echo Путь к RSI Launcher не настроен
    echo Выберите папку с RSI Launcher.exe
    :SelectLauncherAfterLoad
    call :SelectFolder "Выберите папку с RSI Launcher.exe" LAUNCHER_PATH

    if not "!LAUNCHER_PATH!"=="" (
        if not exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
            echo ✗ RSI Launcher.exe не найден в выбранной папке
            echo.
            set /p "RETRY=Выбрать другую папку? (Y/N): "
            if /i "!RETRY!"=="Y" (
                goto :SelectLauncherAfterLoad
            ) else (
                set "LAUNCHER_PATH="
            )
        ) else (
            echo ✓ RSI Launcher найден: !LAUNCHER_PATH!
            call :SaveConfig
        )
    ) else (
        echo Папка не выбрана
        set /p "RETRY=Попробовать ещё раз? (Y/N): "
        if /i "!RETRY!"=="Y" (
            goto :SelectLauncherAfterLoad
        )
    )
)

:: Устанавливаем флаг что пути загружены
set "PATHS_LOADED=1"

:: Файлы версий
if not "!LIVE_PATH!"=="" (
    set "LIVE_VERSION_FILE=!LIVE_PATH!\data\Localization\korean_(south_korea)\global.ini"
)

if not "!PTU_PATH!"=="" (
    set "PTU_VERSION_FILE=!PTU_PATH!\data\Localization\korean_(south_korea)\global.ini"
)

:: Создание временной директории
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

:RestartDiagnostics
:: Обновляем пути к файлам версий после возможной перенастройки
if not "!LIVE_PATH!"=="" (
    set "LIVE_VERSION_FILE=!LIVE_PATH!\data\Localization\korean_(south_korea)\global.ini"
)

if not "!PTU_PATH!"=="" (
    set "PTU_VERSION_FILE=!PTU_PATH!\data\Localization\korean_(south_korea)\global.ini"
)

:: Проверка наличия версий
echo.
echo [1/4] Проверка установленных версий...
call :ShowProgress "Сканирование папок..." 50

set "LIVE_FOUND=false"
set "PTU_FOUND=false"
set "LIVE_VERSION=не найдена"
set "PTU_VERSION=не найдена"

if not "!LIVE_PATH!"=="" (
    set "LIVE_FOUND=true"
    if exist "!LIVE_VERSION_FILE!" (
        call :GetVersionFromFile "!LIVE_VERSION_FILE!" LIVE_VERSION
    )
)

if not "!PTU_PATH!"=="" (
    set "PTU_FOUND=true"
    if exist "!PTU_VERSION_FILE!" (
        call :GetVersionFromFile "!PTU_VERSION_FILE!" PTU_VERSION
    )
)

call :ShowProgress "Версии определены" 100
echo.

if "!LIVE_FOUND!"=="false" if "!PTU_FOUND!"=="false" (
    echo ОШИБКА: Ни LIVE ни PTU версии не найдены
    echo Настроенные пути:
    if not "!LIVE_PATH!"=="" echo   LIVE: !LIVE_PATH!
    if not "!PTU_PATH!"=="" echo   PTU:  !PTU_PATH!
    echo.
    echo Запустите скрипт заново для настройки путей
    pause
    exit /b 1
)

:: Получение версии с GitHub
echo [2/4] Проверка обновлений на GitHub...
call :ShowProgress "Подключение к GitHub..." 40

:: Скачивание информации о релизах с GitHub
powershell -NoProfile -Command "try { $response = Invoke-WebRequest -Uri 'https://github.com/n1ghter/StarCitizenRu/releases/latest' -UseBasicParsing; $content = $response.Content; $version = 'не найдена'; if($content -match 'global\.ini\s+([\d\.]+\s+v\d+)') { $version = $matches[1] }; \"VERSION:$version\" | Out-File -FilePath '%TEMP_DIR%\github_version.txt' -Encoding UTF8; $content | Select-String -Pattern 'global\.ini' | Select-Object -First 5 | Out-File -FilePath '%TEMP_DIR%\github_debug.txt' -Encoding UTF8 } catch { 'VERSION:не найдена' | Out-File -FilePath '%TEMP_DIR%\github_version.txt' -Encoding UTF8; $_.Exception.Message | Out-File -FilePath '%TEMP_DIR%\github_debug.txt' -Encoding UTF8 }" >nul 2>&1

if %errorlevel% neq 0 (
    echo ОШИБКА: Не удалось получить информацию о версии с GitHub
    echo Проверьте подключение к интернету
    pause
    exit /b 1
)

call :ShowProgress "Получение версии..." 100

:: Читаем версию из временного файла
set "GITHUB_VERSION=не найдена"
for /f "tokens=1,2 delims=:" %%a in ('type "%TEMP_DIR%\github_version.txt" 2^>nul') do (
    if "%%a"=="VERSION" set "GITHUB_VERSION=%%b"
)

if "!GITHUB_VERSION!"=="не найдена" (
    echo.
    echo ОШИБКА: Не удалось определить версию на GitHub
    echo Возможно, изменился формат страницы
    pause
    exit /b 1
)

:: Завершаем этап получения версии
call :CompleteProgress "Получение версии..."

:: Показываем найденную версию
call :RedrawScreen
echo ✓ Последняя версия на GitHub: !GITHUB_VERSION!
echo.

:: Устанавливаем флаг что таблица статуса готова
set "STATUS_TABLE_READY=1"

:: Проверка необходимости обновления
set "CHOICE_AVAILABLE=false"
set "SELECTED_VERSION="
set "SELECTED_PATH="

if "!LIVE_FOUND!"=="true" (
    if "!LIVE_VERSION!"=="не найдена" (
        set "CHOICE_AVAILABLE=true"
    ) else (
        if not "!LIVE_VERSION!"=="!GITHUB_VERSION!" (
            set "CHOICE_AVAILABLE=true"
        )
    )
)

if "!PTU_FOUND!"=="true" (
    if "!PTU_VERSION!"=="не найдена" (
        set "CHOICE_AVAILABLE=true"
    ) else (
        if not "!PTU_VERSION!"=="!GITHUB_VERSION!" (
            set "CHOICE_AVAILABLE=true"
        )
    )
)

:: Если все версии актуальны - сразу запускаем лаунчер
if "!CHOICE_AVAILABLE!"=="false" (
    call :RedrawScreen
    echo [4/4] Все версии актуальны!
    echo.
    echo ✓ Обновление не требуется
    echo Запуск лаунчера через 3 секунды...
    timeout /t 3 /nobreak >nul
    goto :LaunchGame
)

:: Меню выбора версии для обновления
call :RedrawScreen
echo [4/4] Выбор версии для обновления:
echo.

if "!LIVE_FOUND!"=="true" (
    if "!LIVE_VERSION!"=="не найдена" (
        echo  1 - Установить LIVE локализацию версии !GITHUB_VERSION!
    ) else (
        if not "!LIVE_VERSION!"=="!GITHUB_VERSION!" (
            echo  1 - Обновить LIVE, текущая: !LIVE_VERSION! → !GITHUB_VERSION!
        )
    )
)

if "!PTU_FOUND!"=="true" (
    if "!PTU_VERSION!"=="не найдена" (
        echo  2 - Установить PTU локализацию версии !GITHUB_VERSION!
    ) else (
        if not "!PTU_VERSION!"=="!GITHUB_VERSION!" (
            echo  2 - Обновить PTU, текущая: !PTU_VERSION! → !GITHUB_VERSION!
        )
    )
)

echo  3 - Настроить пути заново
echo  0 - Выход без обновления
echo.
set /p "CHOICE=Выберите вариант (0-3): "

if "!CHOICE!"=="1" if "!LIVE_FOUND!"=="true" (
    if "!LIVE_VERSION!"=="не найдена" (
        set "SELECTED_VERSION=LIVE"
        set "SELECTED_PATH=!LIVE_PATH!"
        set "TARGET_VERSION=!GITHUB_VERSION!"
    ) else (
        if not "!LIVE_VERSION!"=="!GITHUB_VERSION!" (
            set "SELECTED_VERSION=LIVE"
            set "SELECTED_PATH=!LIVE_PATH!"
            set "TARGET_VERSION=!GITHUB_VERSION!"
        )
    )
)

if "!CHOICE!"=="2" if "!PTU_FOUND!"=="true" (
    if "!PTU_VERSION!"=="не найдена" (
        set "SELECTED_VERSION=PTU"
        set "SELECTED_PATH=!PTU_PATH!"
        set "TARGET_VERSION=!GITHUB_VERSION!"
    ) else (
        if not "!PTU_VERSION!"=="!GITHUB_VERSION!" (
            set "SELECTED_VERSION=PTU"
            set "SELECTED_PATH=!PTU_PATH!"
            set "TARGET_VERSION=!GITHUB_VERSION!"
        )
    )
)

if "!CHOICE!"=="3" (
    call :SetupConfig
    :: После настройки путей возвращаемся к началу диагностики
    goto :RestartDiagnostics
)

if "!CHOICE!"=="0" (
    echo Выход без обновления
    goto :LaunchGame
)

if "!SELECTED_VERSION!"=="" (
    echo ОШИБКА: Неверный выбор!
    pause
    goto :LaunchGame
)

echo.
echo Скачивание локализации версии !TARGET_VERSION!...
call :ShowProgress "Загрузка архива..." 30

powershell -NoProfile -Command "try { Invoke-WebRequest -Uri 'https://github.com/%GITHUB_REPO%/archive/refs/heads/master.zip' -OutFile '%TEMP_DIR%\localization.zip' -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1

if %errorlevel% neq 0 (
    echo ОШИБКА: Не удалось скачать локализацию
    pause
    goto :LaunchGame
)

call :ShowProgress "Распаковка архива..." 60

powershell -NoProfile -Command "try { Expand-Archive -Path '%TEMP_DIR%\localization.zip' -DestinationPath '%TEMP_DIR%\extracted' -Force; exit 0 } catch { exit 1 }" >nul 2>&1

if %errorlevel% neq 0 (
    echo ОШИБКА: Не удалось распаковать архив
    pause
    goto :LaunchGame
)

call :ShowProgress "Установка файлов..." 85

set "SOURCE_DATA=%TEMP_DIR%\extracted\StarCitizenRu-master\data"
if not exist "%SOURCE_DATA%" (
    echo ОШИБКА: Папка data не найдена в архиве
    pause
    goto :LaunchGame
)

xcopy "%SOURCE_DATA%\*" "!SELECTED_PATH!\data\" /E /Y /Q >nul 2>&1

call :ShowProgress "Настройка локализации..." 90

:: Настраиваем user.cfg для локализации только для выбранной версии
echo.
echo === Настройка файла user.cfg ===

:: Определяем путь к user.cfg в зависимости от выбранной версии
if "!SELECTED_VERSION!"=="LIVE" (
    set "USER_CFG_PATH=!LIVE_PATH!\user.cfg"
    echo Версия: LIVE
    echo Путь к папке: !LIVE_PATH!
) else if "!SELECTED_VERSION!"=="PTU" (
    set "USER_CFG_PATH=!PTU_PATH!\user.cfg"
    echo Версия: PTU  
    echo Путь к папке: !PTU_PATH!
) else (
    echo ✗ ОШИБКА: Неизвестная версия !SELECTED_VERSION!
    goto :SkipUserCfg
)

:: Вызываем функцию создания бэкапа
call :BackupUserCfg "!USER_CFG_PATH!"
set "backup_result=!errorlevel!"

if !backup_result! equ 0 (
    echo Файл найден и бэкап создан, обновляем параметры...
    call :UpdateUserCfg "!USER_CFG_PATH!"
    if !errorlevel! equ 0 (
        echo ✓ Настройка user.cfg завершена успешно
    ) else (
        echo ✗ Ошибка при обновлении user.cfg
    )
) else if !backup_result! equ 2 (
    echo Файл не найден, создаем новый...
    call :CreateUserCfg "!USER_CFG_PATH!"
    if !errorlevel! equ 0 (
        echo ✓ Создание user.cfg завершено успешно
    ) else (
        echo ✗ Ошибка при создании user.cfg
    )
) else (
    echo ✗ Ошибка при создании бэкапа, пропускаем настройку
    goto :SkipUserCfg
)

:SkipUserCfg
echo === Завершение настройки user.cfg ===
echo.

:: Обновляем статус версий для корректного отображения таблицы
call :RefreshVersionStatus

call :ShowProgress "Завершение..." 100

:: Обновляем информацию о установленной версии в конфигурации
if "!SELECTED_VERSION!"=="LIVE" (
    set "LIVE_REPO=https://github.com/%GITHUB_REPO%"
    :: Используем реальную версию из файла, а не TARGET_VERSION
    if "!LIVE_VERSION!"=="не найдена" (
        set "LIVE_VERSION=!TARGET_VERSION!"
    )
)
if "!SELECTED_VERSION!"=="PTU" (
    set "PTU_REPO=https://github.com/%GITHUB_REPO%"
    :: Используем реальную версию из файла, а не TARGET_VERSION
    if "!PTU_VERSION!"=="не найдена" (
        set "PTU_VERSION=!TARGET_VERSION!"
    )
)

:: Сохраняем обновлённую конфигурацию
call :SaveConfig

:: Завершаем последний этап прогресса
if defined PREV_PROGRESS_MSG (
    call :CompleteProgress "!PREV_PROGRESS_MSG!"
)

:: Финальная перерисовка экрана с обновленными данными
call :RedrawScreen

echo ✓ Локализация !SELECTED_VERSION! успешно обновлена до версии !TARGET_VERSION!
echo.

:LaunchGame
:: Очистка временных файлов
rmdir /s /q "%TEMP_DIR%" 2>nul


echo Запуск RSI Launcher...
if not "!LAUNCHER_PATH!"=="" (
    if exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
        echo ✓ Запускаю лаунчер из: !LAUNCHER_PATH!
        powershell -Command "Start-Process -FilePath '!LAUNCHER_PATH!\RSI Launcher.exe'"
        timeout /t 1 /nobreak >nul
        exit
    )
)

:: Попробуем найти лаунчер в текущей папке
if exist "%LAUNCHER_DIR%RSI Launcher.exe" (
    echo ✓ Запускаю лаунчер из текущей папки...
    powershell -Command "Start-Process -FilePath '%LAUNCHER_DIR%RSI Launcher.exe'"
    timeout /t 1 /nobreak >nul
    exit
) else (
    echo ОШИБКА: RSI Launcher.exe не найден
    echo Настройте путь к лаунчеру в конфигурации
    pause
    exit /b 1
)

:: ============================================
:: ФУНКЦИИ
:: ============================================

:: Функция проверки валидности папки игры
:ValidateGameFolder
set "game_path=%~1"
set "game_type=%~2"
set "is_valid=0"

echo.
echo Проверяю папку !game_type!...

:: 1. Проверка существования папки
if not exist "!game_path!\" (
    echo ✗ Папка не существует: !game_path!
    set "is_valid=1"
    goto :ValidationEnd
)

:: 2. Проверка обязательной папки
if not exist "!game_path!\Bin64\" (
    echo ✗ Отсутствует обязательная папка: Bin64
    set "is_valid=1"
    goto :ValidationEnd
)

:: 3. Проверка обязательного файла
if not exist "!game_path!\StarCitizen_Launcher.exe" (
    echo ✗ Отсутствует обязательный файл: StarCitizen_Launcher.exe
    set "is_valid=1"
    goto :ValidationEnd
)

:: 4. Проверка файла локализации
if not exist "!game_path!\data\Localization\korean_(south_korea)\global.ini" (
    echo ⚠ Внимание: Файл локализации не найден
    echo Это может быть новая установка игры
)

echo ✓ Папка существует
echo ✓ Найден StarCitizen_Launcher.exe
echo ✓ Найдена папка Bin64

:ValidationEnd
if !is_valid! equ 0 (
    echo ✓ Папка !game_type! прошла проверку
) else (
    echo ✗ Папка !game_type! не прошла проверку
)
exit /b !is_valid!

:: Функция загрузки конфигурации или настройки
:LoadOrSetupConfig
if exist "%CONFIG_FILE%" (
    echo Загружаю сохранённую конфигурацию...
    for /f "tokens=1,* delims==" %%a in ('type "%CONFIG_FILE%" 2^>nul') do (
        if "%%a"=="LAUNCHER_PATH" set "LAUNCHER_PATH=%%b"
        if "%%a"=="LIVE_REPO" set "LIVE_REPO=%%b"
        if "%%a"=="LIVE_VERSION" set "LIVE_VERSION=%%b"
        if "%%a"=="LIVE_PATH" set "LIVE_PATH=%%b"
        if "%%a"=="PTU_REPO" set "PTU_REPO=%%b"
        if "%%a"=="PTU_VERSION" set "PTU_VERSION=%%b"
        if "%%a"=="PTU_PATH" set "PTU_PATH=%%b"
    )

    echo Настроенные пути:
    if not "!LAUNCHER_PATH!"=="" echo   Лаунчер: !LAUNCHER_PATH!
    if not "!LIVE_PATH!"=="" echo   LIVE: !LIVE_PATH!
    if not "!PTU_PATH!"=="" echo   PTU:  !PTU_PATH!
    echo.

    :: Проверяем, существуют ли папки
    if not "!LIVE_PATH!"=="" (
        call :ValidateGameFolder "!LIVE_PATH!" "LIVE"
        if !ERRORLEVEL! neq 0 (
            set "LIVE_PATH="
        )
    )

    if not "!PTU_PATH!"=="" (
        call :ValidateGameFolder "!PTU_PATH!" "PTU"
        if !ERRORLEVEL! neq 0 (
            set "PTU_PATH="
        )
    )

    :: Проверяем лаунчер
    if not "!LAUNCHER_PATH!"=="" (
        if not exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
            echo ⚠ Лаунчер не найден по указанному пути
            set "LAUNCHER_PATH="
        )
    )

    :: Если все основные пути есть и лаунчер настроен, продолжаем
    if not "!LIVE_PATH!"=="" if not "!LAUNCHER_PATH!"=="" goto :eof
    if not "!PTU_PATH!"=="" if not "!LAUNCHER_PATH!"=="" goto :eof

    echo.
    echo Необходимо настроить пути заново
) else (
    echo Конфигурационный файл не найден
    echo Запуск первоначальной настройки...
)

:: Первоначальная настройка
:SetupConfig
cls
echo.
echo ════════════════════════════════════════
echo    Первоначальная настройка путей
echo ════════════════════════════════════════
echo.

:: Настройка пути к лаунчеру (всегда спрашиваем при перенастройке)
echo [1/4] Настройка пути к RSI Launcher
echo.
:SelectLauncherFolder
call :SelectFolder "Выберите папку с RSI Launcher.exe" LAUNCHER_PATH

if not "!LAUNCHER_PATH!"=="" (
    if not exist "!LAUNCHER_PATH!\RSI Launcher.exe" (
        echo ✗ RSI Launcher.exe не найден в выбранной папке
        echo.
        set /p "RETRY=Выбрать другую папку? (Y/N): "
        if /i "!RETRY!"=="Y" (
            goto :SelectLauncherFolder
        ) else (
            set "LAUNCHER_PATH="
        )
    ) else (
        echo ✓ RSI Launcher найден: !LAUNCHER_PATH!
    )
) else (
    echo Папка не выбрана
    set /p "RETRY=Попробовать ещё раз? (Y/N): "
    if /i "!RETRY!"=="Y" (
        goto :SelectLauncherFolder
    )
)

:: Автоматический поиск игры
echo.
echo [2/4] Поиск установленных версий игры
echo Автоматический поиск установленных версий...
call :FindStandardPaths

:: Настройка LIVE
echo.
echo [3/4] Настройка папки LIVE
if "!LIVE_FOUND!"=="true" (
    echo.
    echo ✓ Найдена потенциальная папка LIVE: !LIVE_PATH!
    call :ValidateGameFolder "!LIVE_PATH!" "LIVE"
    if !ERRORLEVEL! equ 0 (
        set /p "USE_FOUND=Использовать этот путь? (Y/N): "
        if /i not "!USE_FOUND!"=="Y" (
            set "LIVE_FOUND=false"
            set "LIVE_PATH="
        )
    ) else (
        set "LIVE_FOUND=false"
        set "LIVE_PATH="
    )
)

if "!LIVE_FOUND!"=="false" (
    echo.
    :SelectLiveFolder
    call :SelectFolder "Выберите папку LIVE игры (путь до папки LIVE, должен содержать StarCitizen_Launcher.exe)" LIVE_PATH

    if not "!LIVE_PATH!"=="" (
        call :ValidateGameFolder "!LIVE_PATH!" "LIVE"
        if !ERRORLEVEL! neq 0 (
            echo.
            set /p "RETRY=Выбрать другую папку? (Y/N): "
            if /i "!RETRY!"=="Y" (
                goto :SelectLiveFolder
            ) else (
                set "LIVE_PATH="
            )
        )
    )
)

:: Настройка PTU (опционально)
echo.
echo [4/4] Настройка PTU (опционально)
if "!PTU_FOUND!"=="true" (
    echo.
    echo ✓ Найдена потенциальная папка PTU: !PTU_PATH!
    call :ValidateGameFolder "!PTU_PATH!" "PTU"
    if !ERRORLEVEL! equ 0 (
        set /p "USE_FOUND=Использовать этот путь? (Y/N): "
        if /i not "!USE_FOUND!"=="Y" (
            set "PTU_FOUND=false"
            set "PTU_PATH="
        )
    ) else (
        set "PTU_FOUND=false"
        set "PTU_PATH="
    )
)

if "!PTU_FOUND!"=="false" (
    echo.
    set /p "ASK_PTU=Настроить папку PTU? (Y/N): "
    if /i "!ASK_PTU!"=="Y" (
        :SelectPTUFolder
        call :SelectFolder "Выберите папку PTU игры (путь до папки PTU, должен содержать StarCitizen_Launcher.exe)" PTU_PATH

        if not "!PTU_PATH!"=="" (
            call :ValidateGameFolder "!PTU_PATH!" "PTU"
            if !ERRORLEVEL! neq 0 (
                echo.
                set /p "RETRY=Выбрать другую папку? (Y/N): "
                if /i "!RETRY!"=="Y" (
                    goto :SelectPTUFolder
                ) else (
                    set "PTU_PATH="
                )
            )
        )
    )
)

if "!LIVE_PATH!"=="" if "!PTU_PATH!"=="" (
    echo ОШИБКА: Не настроено ни одной папки игры
    pause
    exit /b 1
)

if "!LAUNCHER_PATH!"=="" (
    echo ПРЕДУПРЕЖДЕНИЕ: Путь к лаунчеру не настроен
    echo Лаунчер нужно будет запускать вручную
)

call :SaveConfig
echo.
echo ✓ Конфигурация сохранена в: %CONFIG_FILE%
timeout /t 2 /nobreak >nul
goto :eof

:: Функция сохранения конфигурации
:SaveConfig
echo Сохранение конфигурации...
(
    echo //Конфигурационный файл скрипта русификации Starcitizen
    echo LAUNCHER_PATH=!LAUNCHER_PATH!
    echo LIVE_REPO=!LIVE_REPO!
    echo LIVE_VERSION=!LIVE_VERSION!
    echo LIVE_PATH=!LIVE_PATH!
    echo PTU_REPO=!PTU_REPO!
    echo PTU_VERSION=!PTU_VERSION!
    echo PTU_PATH=!PTU_PATH!
) > "%CONFIG_FILE%"
goto :eof

:: Функция поиска стандартных путей
:FindStandardPaths
set "LIVE_FOUND=false"
set "PTU_FOUND=false"

:: Список возможных дисков для поиска
set DISKS=C D E F G H I J K L M N O P Q R S T U V W X Y Z

:: Поиск LIVE
for %%D in (!DISKS!) do (
    set "test_path1=%%D:\Roberts Space Industries\StarCitizen\LIVE"
    set "test_path2=%%D:\Program Files\Roberts Space Industries\StarCitizen\LIVE"
    set "test_path3=%%D:\Program Files (x86)\Roberts Space Industries\StarCitizen\LIVE"
    set "test_path4=%%D:\Games\StarCitizen\LIVE"
    set "test_path5=%%D:\StarCitizen\LIVE"

    for %%P in ("!test_path1!" "!test_path2!" "!test_path3!" "!test_path4!" "!test_path5!") do (
        if exist %%~P\StarCitizen_Launcher.exe (
            if "!LIVE_FOUND!"=="false" (
                set "LIVE_PATH=%%~P"
                set "LIVE_FOUND=true"
            )
        )
    )
)

:: Поиск PTU
for %%D in (!DISKS!) do (
    set "test_path1=%%D:\Roberts Space Industries\StarCitizen\PTU"
    set "test_path2=%%D:\Program Files\Roberts Space Industries\StarCitizen\PTU"
    set "test_path3=%%D:\Program Files (x86)\Roberts Space Industries\StarCitizen\PTU"
    set "test_path4=%%D:\Games\StarCitizen\PTU"
    set "test_path5=%%D:\StarCitizen\PTU"

    for %%P in ("!test_path1!" "!test_path2!" "!test_path3!" "!test_path4!" "!test_path5!") do (
        if exist %%~P\StarCitizen_Launcher.exe (
            if "!PTU_FOUND!"=="false" (
                set "PTU_PATH=%%~P"
                set "PTU_FOUND=true"
            )
        )
    )
)
goto :eof

:: Функция выбора папки через PowerShell
:SelectFolder
set "description=%~1"
set "varname=%~2"

echo.
echo %description%
echo.

set "psScript=Add-Type -AssemblyName System.Windows.Forms; $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog; $folderBrowser.Description = '%description%'; $folderBrowser.RootFolder = 'MyComputer'; $folderBrowser.ShowNewFolderButton = $false; $result = $folderBrowser.ShowDialog(); if($result -eq 'OK') { Write-Output $folderBrowser.SelectedPath } else { Write-Output '' }"

for /f "delims=" %%F in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "!psScript!"') do set "SELECTED_PATH=%%F"

if "!SELECTED_PATH!"=="" (
    echo Папка не выбрана
    set "!varname!="
    exit /b 1
) else (
    echo Выбрана папка: !SELECTED_PATH!
    set "!varname!=!SELECTED_PATH!"
    exit /b 0
)


:: Функция отображения прогресса
:ShowProgress
set "message=%~1"
set "percent=%~2"

:: Перерисовываем экран
call :RedrawScreen

:: Отображаем текущий прогресс
set "bar="
set /a "filled=%percent%/5"
set /a "empty=20-filled"

for /l %%i in (1,1,%filled%) do set "bar=!bar!█"
for /l %%i in (1,1,%empty%) do set "bar=!bar!░"

echo !message! [!bar!] !percent!%%

:: Сохраняем сообщение для возможного завершения
set "PREV_PROGRESS_MSG=!message!"

timeout /t 1 /nobreak >nul
goto :eof

:: Функция завершения предыдущего этапа
:CompleteProgress
set "prev_message=%~1"
set "complete_bar=████████████████████"

:: Перерисовываем экран
call :RedrawScreen

echo !prev_message! [!complete_bar!] 100%%
echo.
goto :eof

:: Функция извлечения версии из файла global.ini
:GetVersionFromFile
set "file_path=%~1"
set "return_var=%~2"
set "version=не найдена"

if not exist "%file_path%" (
    set "%return_var%=не найдена"
    goto :eof
)

:: Ищем строку Frontend_PU_Version и извлекаем версию в формате "LIVE x.x.x vxx"
for /f "usebackq delims=" %%a in (`findstr /c:"Frontend_PU_Version" "%file_path%" 2^>nul`) do (
    set "line=%%a"
    :: Используем PowerShell для извлечения версии из строки
    for /f "delims=" %%b in ('powershell -NoProfile -Command "if('!line!' -match 'LIVE\s+([\d\.]+\s+v\d+)') { $matches[1] } else { 'не найдена' }"') do (
        set "version=%%b"
    )
)

set "%return_var%=%version%"
goto :eof

:: Функция создания бэкапа user.cfg
:BackupUserCfg
set "user_cfg_path=%~1"

echo Проверка файла user.cfg...
echo Путь: %user_cfg_path%

if exist "%user_cfg_path%" (
    echo ✓ Найден файл user.cfg
    echo Создание резервной копии...
    
    copy "%user_cfg_path%" "%user_cfg_path%.bak" >nul 2>&1
    if !errorlevel! equ 0 (
        echo ✓ Резервная копия создана: user.cfg.bak
        exit /b 0
    ) else (
        echo ✗ Не удалось создать резервную копию
        exit /b 1
    )
) else (
    echo ⚠ Файл user.cfg не найден
    exit /b 2
)

goto :eof

:: Функция обновления существующего user.cfg
:UpdateUserCfg
set "user_cfg_path=%~1"
set "backup_path=%user_cfg_path%.bak"
set "new_path=%user_cfg_path%.new"

echo Обновление параметров в user.cfg...

:: Создаем новый файл, сначала добавляем наши параметры
echo g_language=korean_(south_korea)> "%new_path%"
echo g_languageAudio=english>> "%new_path%"

:: Читаем бэкап и добавляем все строки кроме g_language и g_languageAudio
for /f "usebackq delims=" %%a in ("%backup_path%") do (
    set "line=%%a"
    set "skip_line=false"
    
    :: Проверяем начинается ли строка с g_language
    echo !line! | findstr /i /b "g_language" >nul
    if !errorlevel! equ 0 set "skip_line=true"
    
    :: Проверяем начинается ли строка с g_languageAudio  
    echo !line! | findstr /i /b "g_languageAudio" >nul
    if !errorlevel! equ 0 set "skip_line=true"
    
    :: Добавляем строку если она не должна быть пропущена
    if "!skip_line!"=="false" (
        echo !line!>> "%new_path%"
    )
)

:: Заменяем оригинальный файл новым
move "%new_path%" "%user_cfg_path%" >nul 2>&1
if !errorlevel! equ 0 (
    echo ✓ Файл user.cfg успешно обновлен
    echo ✓ Параметры локализации настроены
    exit /b 0
) else (
    echo ✗ Ошибка при замене файла
    :: Восстанавливаем из бэкапа при ошибке
    copy "%backup_path%" "%user_cfg_path%" >nul 2>&1
    echo ✓ Файл восстановлен из резервной копии
    exit /b 1
)

goto :eof

:: Функция создания нового user.cfg
:CreateUserCfg
set "user_cfg_path=%~1"

echo Создание нового файла user.cfg...
echo Путь: %user_cfg_path%

:: Создаем новый файл с параметрами локализации
echo g_language=korean_(south_korea)> "%user_cfg_path%"
echo g_languageAudio=english>> "%user_cfg_path%"

:: Проверяем что файл создался
if exist "%user_cfg_path%" (
    echo ✓ Файл user.cfg создан успешно
    echo ✓ Параметры локализации настроены
    exit /b 0
) else (
    echo ✗ Ошибка при создании файла user.cfg
    echo Проверьте права доступа к папке
    exit /b 1
)

goto :eof

:: Функция отрисовки заголовка
:DrawHeader
echo.
echo ════════════════════════════════════════
echo    Star Citizen - Русская локализация
echo ════════════════════════════════════════
echo.
goto :eof

:: Функция отрисовки настроенных путей
:DrawPaths
if defined PATHS_LOADED (
    echo Настроенные пути:
    if not "!LAUNCHER_PATH!"=="" echo   Лаунчер: !LAUNCHER_PATH!
    if not "!LIVE_PATH!"=="" echo   LIVE:    !LIVE_PATH!
    if not "!PTU_PATH!"=="" echo   PTU:     !PTU_PATH!
    echo.
)
goto :eof

:: Функция отрисовки таблицы статуса
:DrawStatusTable
if defined STATUS_TABLE_READY (
    echo [3/4] Статус локализации:
    echo.
    echo  ╔═══════════════════════════════════════════════════════════════╗
    echo  ║ Версия │   Установлена   │   GitHub   │      Статус           ║
    echo  ╠═══════════════════════════════════════════════════════════════╣
    
    if "!LIVE_FOUND!"=="true" (
        if "!LIVE_VERSION!"=="не найдена" (
            echo  ║ LIVE   │ не установлена  │ !GITHUB_VERSION!  │   ✗ Не установлена    ║
        ) else (
            if "!LIVE_VERSION!"=="!GITHUB_VERSION!" (
                echo  ║ LIVE   │    !LIVE_VERSION!    │ !GITHUB_VERSION!  │   ✓ Актуальна         ║
            ) else (
                echo  ║ LIVE   │    !LIVE_VERSION!    │ !GITHUB_VERSION!  │ ✗ Устарела        ║
            )
        )
    ) else (
        echo  ║ LIVE   │    не найдена   │ !GITHUB_VERSION!  │   ✗ Не установлена    ║
    )
    
    if "!PTU_FOUND!"=="true" (
        if "!PTU_VERSION!"=="не найдена" (
            echo  ║ PTU    │ не установлена  │ !GITHUB_VERSION!  │   ✗ Не установлена    ║
        ) else (
            if "!PTU_VERSION!"=="!GITHUB_VERSION!" (
                echo  ║ PTU    │    !PTU_VERSION!    │ !GITHUB_VERSION!  │   ✓ Актуальна         ║
            ) else (
                echo  ║ PTU    │    !PTU_VERSION!    │ !GITHUB_VERSION!  │   ✗ Устарела          ║
            )
        )
    ) else (
        echo  ║ PTU    │    не найдена   │ !GITHUB_VERSION!  │   ✗ Не установлена    ║
    )
    
    echo  ╚═══════════════════════════════════════════════════════════════╝
    echo.
)
goto :eof

:: Функция полной перерисовки экрана
:RedrawScreen
cls
call :DrawHeader
call :DrawPaths
call :DrawStatusTable
goto :eof

:: Функция обновления статуса версий после установки
:RefreshVersionStatus
:: Определяем пути к файлам версий и обновляем статус
if not "!LIVE_PATH!"=="" (
    set "LIVE_VERSION_FILE=!LIVE_PATH!\data\Localization\korean_(south_korea)\global.ini"
    if exist "!LIVE_VERSION_FILE!" (
        call :GetVersionFromFile "!LIVE_VERSION_FILE!" LIVE_VERSION
        set "LIVE_FOUND=true"
    ) else (
        set "LIVE_VERSION=не найдена"
        set "LIVE_FOUND=true"
    )
) else (
    set "LIVE_FOUND=false"
)

if not "!PTU_PATH!"=="" (
    set "PTU_VERSION_FILE=!PTU_PATH!\data\Localization\korean_(south_korea)\global.ini"
    if exist "!PTU_VERSION_FILE!" (
        call :GetVersionFromFile "!PTU_VERSION_FILE!" PTU_VERSION
        set "PTU_FOUND=true"
    ) else (
        set "PTU_VERSION=не найдена"
        set "PTU_FOUND=true"
    )
) else (
    set "PTU_FOUND=false"
)

goto :eof

:: Функция настройки user.cfg для локализации
:ConfigureUserCfg
set "game_path=%~1"
set "user_cfg_path=%game_path%\user.cfg"

echo.
echo === Настройка файла user.cfg ===
echo Версия: !SELECTED_VERSION!
echo Путь к игре: %game_path%
echo Путь к файлу: %user_cfg_path%

:: Проверяем что путь не пустой
if "%game_path%"=="" (
    echo ✗ ОШИБКА: Путь к игре пустой
    goto :eof
)

:: 1. Проверяем, существует ли файл
if exist "%user_cfg_path%" (
    echo ✓ Найден существующий файл user.cfg
    
    :: 1.1. Делаем бэкап файла для безопасности
    echo Создание резервной копии...
    copy "%user_cfg_path%" "%user_cfg_path%.bak" >nul 2>&1
    if !errorlevel! equ 0 (
        echo ✓ Резервная копия создана: user.cfg.bak
    ) else (
        echo ⚠ Не удалось создать резервную копию
    )
    
    :: 1.2. Открываем файл для редактирования
    echo Редактирование параметров локализации...
    set "temp_cfg=%game_path%\user_temp.cfg"
    set "lang_updated=false"
    set "audio_updated=false"
    
    :: 1.3. Находим и заменяем ТОЛЬКО указанные параметры
    for /f "usebackq delims=" %%a in ("%user_cfg_path%") do (
        set "line=%%a"
        set "line_processed=false"
        
        :: Проверяем g_language
        echo !line! | findstr /i /b "g_language=" >nul
        if !errorlevel! equ 0 (
            echo g_language=korean_(south_korea)>> "%temp_cfg%"
            set "lang_updated=true"
            set "line_processed=true"
        )
        
        :: Проверяем g_languageAudio
        if "!line_processed!"=="false" (
            echo !line! | findstr /i /b "g_languageAudio=" >nul
            if !errorlevel! equ 0 (
                echo g_languageAudio=english>> "%temp_cfg%"
                set "audio_updated=true"
                set "line_processed=true"
            )
        )
        
        :: 1.4. Остальные строки оставляем без изменений
        if "!line_processed!"=="false" (
            echo !line!>> "%temp_cfg%"
        )
    )
    
    :: Добавляем параметры если их не было в файле
    if "!lang_updated!"=="false" (
        echo g_language=korean_(south_korea)>> "%temp_cfg%"
        echo ✓ Добавлен параметр g_language
    ) else (
        echo ✓ Обновлен параметр g_language
    )
    
    if "!audio_updated!"=="false" (
        echo g_languageAudio=english>> "%temp_cfg%"
        echo ✓ Добавлен параметр g_languageAudio
    ) else (
        echo ✓ Обновлен параметр g_languageAudio
    )
    
    :: Заменяем оригинальный файл
    move "%temp_cfg%" "%user_cfg_path%" >nul 2>&1
    if !errorlevel! equ 0 (
        echo ✓ Файл user.cfg успешно обновлен
    ) else (
        echo ✗ Ошибка при сохранении файла
        :: Восстанавливаем из бэкапа при ошибке
        if exist "%user_cfg_path%.bak" (
            copy "%user_cfg_path%.bak" "%user_cfg_path%" >nul 2>&1
            echo ✓ Файл восстановлен из резервной копии
        )
    )
    
) else (
    :: 2.1. Если файла нет - создаём его с параметрами
    pause
    echo Файл user.cfg не найден
    echo Создание нового файла user.cfg...
    
    echo g_language=korean_(south_korea)> "%user_cfg_path%"
    echo g_languageAudio=english>> "%user_cfg_path%"
    
    if exist "%user_cfg_path%" (
        echo ✓ Файл user.cfg создан с параметрами локализации
    ) else (
        echo ✗ Ошибка при создании файла user.cfg
        echo Проверьте права доступа к папке: %game_path%
    )
)

echo === Завершение настройки user.cfg ===
echo.
goto :eof