@echo off
rem Build the Easy Reps APK on Windows.
rem
rem Works around two Windows problems (see README, "Windows note"):
rem   - a Flutter SDK path with spaces breaks native-asset hooks, so the SDK is
rem     mapped to a drive letter for the build;
rem   - JDK 21+ may fail with "Unable to establish loopback connection", so its
rem     local socket folder is pointed at build\jtmp.
rem
rem Usage:  tools\build_apk.bat debug^|release [extra flutter build args]
rem   e.g.  tools\build_apk.bat release
rem         tools\build_apk.bat release --split-per-abi
rem
rem Uses dart_defines.json (Google Web OAuth client id) when it exists.

setlocal EnableExtensions EnableDelayedExpansion

set "DRIVE_LETTER=S:"

rem Capture the script folder now: SHIFT below also shifts %0.
set "scriptDir=%~dp0"

rem --- Arguments -----------------------------------------------------------
if /i "%~1"=="debug" (set "buildType=debug") else if /i "%~1"=="release" (set "buildType=release") else (
  echo Usage: %~nx0 debug^|release [extra flutter build args]
  echo   e.g. %~nx0 release --split-per-abi
  exit /b 2
)
shift
set "extraArgs="
:collectArgs
if "%~1"=="" goto :argsDone
set "extraArgs=!extraArgs! %1"
shift
goto :collectArgs
:argsDone

rem --- Locations -------------------------------------------------------------
pushd "%scriptDir%.." || exit /b 1
set "projectDir=%CD%"

rem Flutter SDK: FLUTTER_ROOT if set, otherwise the flutter on PATH.
set "flutterRoot=%FLUTTER_ROOT%"
if not defined flutterRoot (
  for /f "delims=" %%F in ('where flutter.bat 2^>nul') do if not defined flutterRoot set "flutterRoot=%%~dpF.."
)
if not defined flutterRoot (
  echo ERROR: Flutter not found. Add it to PATH or set FLUTTER_ROOT.
  popd
  exit /b 1
)
for %%I in ("%flutterRoot%") do set "flutterRoot=%%~fI"
if not exist "%flutterRoot%\bin\flutter.bat" (
  echo ERROR: No flutter.bat under "!flutterRoot!\bin".
  popd
  exit /b 1
)

rem --- Map the SDK to a drive letter if its path contains spaces -------------
set "flutterCmd=%flutterRoot%\bin\flutter.bat"
set "usedDrive="
set "mappedHere="
if not "%flutterRoot: =%"=="%flutterRoot%" (
  set "usedDrive=1"
  if exist "%DRIVE_LETTER%\bin\flutter.bat" (
    echo Using the existing %DRIVE_LETTER% mapping for the Flutter SDK.
  ) else (
    subst %DRIVE_LETTER% "!flutterRoot!"
    if errorlevel 1 (
      echo ERROR: Could not map %DRIVE_LETTER% to the Flutter SDK. Is %DRIVE_LETTER% already in use?
      popd
      exit /b 1
    )
    set "mappedHere=1"
    echo Mapped %DRIVE_LETTER% to "!flutterRoot!".
  )
  set "flutterCmd=%DRIVE_LETTER%\bin\flutter.bat"
)

rem --- JDK local socket folder (needs a path without spaces) ----------------
set "jdkTmp=%projectDir%\build\jtmp"
if not "%jdkTmp: =%"=="%jdkTmp%" set "jdkTmp=%SystemDrive%\tmp\easyreps-jdk"
if not exist "%jdkTmp%" mkdir "%jdkTmp%"
set "JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=%jdkTmp%"

rem --- Google client id ------------------------------------------------------
set "defineArgs="
if exist "dart_defines.json" (
  set "defineArgs=--dart-define-from-file=dart_defines.json"
) else (
  echo WARNING: dart_defines.json not found. Google Drive backup will be disabled in this build.
)

rem --- Build -----------------------------------------------------------------
rem Clear APKs of this type from earlier builds so the list below is current.
del /q "build\app\outputs\flutter-apk\*-%buildType%.apk" "build\app\outputs\flutter-apk\*-%buildType%.apk.sha1" 2>nul
echo.
echo Building %buildType% APK...
rem Run Flutter's batch files with delayed expansion off, as from a normal prompt.
setlocal DisableDelayedExpansion
call "%flutterCmd%" build apk --%buildType% %defineArgs% %extraArgs%
endlocal & set "buildResult=%ERRORLEVEL%"

rem --- Clean up ----------------------------------------------------------------
rem Building from the drive letter rewrites flutter.sdk in local.properties;
rem put the real SDK path back so Android Studio keeps working.
if defined usedDrive (
  set "REAL_SDK=%flutterRoot%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = 'android\local.properties'; if (Test-Path $f) { $v = 'flutter.sdk=' + $env:REAL_SDK.Replace('\', '\\'); (Get-Content $f) | ForEach-Object { if ($_ -like 'flutter.sdk=*') { $v } else { $_ } } | Set-Content $f }"
)
if defined mappedHere (
  subst %DRIVE_LETTER% /d
  echo Removed the %DRIVE_LETTER% mapping.
)

rem --- Result ------------------------------------------------------------------
echo.
if not "%buildResult%"=="0" (
  echo BUILD FAILED ^(exit code %buildResult%^).
  popd
  exit /b %buildResult%
)
echo Done. APK files:
for %%A in ("build\app\outputs\flutter-apk\*-%buildType%.apk") do echo   %projectDir%\build\app\outputs\flutter-apk\%%~nxA
popd
exit /b 0
