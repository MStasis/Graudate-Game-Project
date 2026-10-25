@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1
cd /d "%~dp0"
if not exist build mkdir build
cl /nologo /std:c++17 /utf-8 /W4 /O2 /MT /EHsc native_ime_tests.cpp /Fobuild\native_ime_tests.obj /Febuild\native_ime_tests.exe
if errorlevel 1 exit /b 1
build\native_ime_tests.exe
exit /b %errorlevel%
