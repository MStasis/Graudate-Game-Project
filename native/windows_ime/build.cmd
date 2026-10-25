@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1
cd /d "%~dp0"
if not exist generated\gdextension_interface.h (
 if not exist generated mkdir generated
 pushd generated
 ..\..\..\runtime\godot\Godot_v4.7.2-stable_win64_console.exe --headless --dump-gdextension-interface
 if errorlevel 1 exit /b 1
 popd
)
if not exist build mkdir build
cl /nologo /std:c++17 /utf-8 /W4 /O2 /MT /EHsc /LD windows_ime.cpp /Fobuild\windows_ime.obj /link /OUT:..\..\game\native\windows_ime\windows_ime.dll /IMPLIB:build\windows_ime.lib
exit /b %errorlevel%
