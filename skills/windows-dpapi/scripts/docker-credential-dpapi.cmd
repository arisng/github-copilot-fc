@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0docker-credential-dpapi-impl.ps1" %*
