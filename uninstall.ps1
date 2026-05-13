#Requires -Version 5.1
# SteamTools Uninstaller - discord.gg/luatools

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
$ProgressPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = "SteamTools Uninstaller | .gg/luatools"

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SteamTools Uninstaller - discord.gg/luatools" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# %% Locate Steam %%

function Get-SteamPath {
    $entries = @(
        @{ Path = "HKCU:\Software\Valve\Steam";                        Key = "SteamPath"   },
        @{ Path = "HKLM:\SOFTWARE\Valve\Steam";                        Key = "InstallPath" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam";            Key = "InstallPath" }
    )
    foreach ($e in $entries) {
        if (Test-Path $e.Path) {
            $val = (Get-ItemProperty -Path $e.Path -Name $e.Key -ErrorAction SilentlyContinue).($e.Key)
            if ($val -and (Test-Path $val)) { return $val }
        }
    }
    return $null
}

Write-Host "[*] Locating Steam..." -ForegroundColor Yellow
$steam = Get-SteamPath

if (-not $steam) {
    Write-Host "[ERR] Steam not found. Is Steam installed?" -ForegroundColor Red
    Write-Host "`nPress Enter to exit..."
    Read-Host
    exit 1
}

Write-Host "[OK] Steam found: $steam" -ForegroundColor Green
Write-Host ""

# %% Detect what's installed %%

$stDlls          = @("dwmapi.dll", "xinput1_4.dll")
$foundDlls       = $stDlls | Where-Object { Test-Path (Join-Path $steam $_) }
$stAppDir        = "C:\Program Files\SteamTools"
$stAppExists     = Test-Path $stAppDir
$stplugPath      = Join-Path $steam "config\stplug-in"
$luaFiles        = @()
if (Test-Path $stplugPath) {
    $luaFiles    = @(Get-ChildItem -Path $stplugPath -Filter "*.lua" -ErrorAction SilentlyContinue)
}
$stRegKey        = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SteamTools"
$stRegExists     = Test-Path $stRegKey
$startMenuDir    = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\SteamTools"
$startMenuExists = Test-Path $startMenuDir

if ($foundDlls.Count -eq 0 -and -not $stAppExists) {
    Write-Host "[INFO] SteamTools does not appear to be installed." -ForegroundColor Cyan
    Write-Host "`nPress Enter to exit..."
    Read-Host
    exit 0
}

Write-Host "[*] Detected SteamTools components:" -ForegroundColor Yellow
if ($foundDlls.Count -gt 0)  { $foundDlls | ForEach-Object { Write-Host "    [DLL]       $steam\$_" -ForegroundColor White } }
if ($stAppExists)             { Write-Host "    [APP]       $stAppDir" -ForegroundColor White }
if ($luaFiles.Count -gt 0)   { Write-Host "    [LUAS]      $($luaFiles.Count) file(s) in config\stplug-in" -ForegroundColor White }
if ($stRegExists)             { Write-Host "    [REGISTRY]  Uninstall entry" -ForegroundColor White }
if ($startMenuExists)         { Write-Host "    [STARTMENU] $startMenuDir" -ForegroundColor White }
Write-Host ""

# %% Ask about Lua files %%

$removeLuas = $false
if ($luaFiles.Count -gt 0) {
    $answer = Read-Host "Remove Lua files in config\stplug-in? (y/n)"
    $removeLuas = ($answer.Trim() -ieq "y")
    Write-Host ""
}

# %% Confirm %%

$confirm = Read-Host "Remove all SteamTools components listed above? (y/n)"
if ($confirm.Trim() -ine "y") {
    Write-Host "Aborted." -ForegroundColor Gray
    exit 0
}
Write-Host ""

# %% Kill processes %%

Write-Host "[*] Closing Steam and SteamTools..." -ForegroundColor Yellow
Get-Process -Name "steam", "SteamTools" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-Host "[OK] Processes closed." -ForegroundColor Green

# %% Remove DLLs from Steam dir %%

if ($foundDlls.Count -gt 0) {
    Write-Host "[*] Removing SteamTools DLLs..." -ForegroundColor Yellow
    foreach ($f in $foundDlls) {
        $target = Join-Path $steam $f
        try {
            Remove-Item -Path $target -Force -ErrorAction Stop
            Write-Host "[OK] Removed: $f" -ForegroundColor Green
        } catch {
            Write-Host "[ERR] Could not remove $f - $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "      Try running as Administrator." -ForegroundColor Yellow
        }
    }
}

# %% Remove Lua files %%

if ($removeLuas) {
    Write-Host "[*] Removing Lua files..." -ForegroundColor Yellow
    foreach ($lua in $luaFiles) {
        try {
            Remove-Item -Path $lua.FullName -Force -ErrorAction Stop
            Write-Host "[OK] Removed: $($lua.Name)" -ForegroundColor Green
        } catch {
            Write-Host "[ERR] Could not remove $($lua.Name) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# %% Remove SteamTools app directory %%

if ($stAppExists) {
    Write-Host "[*] Removing SteamTools app..." -ForegroundColor Yellow
    try {
        Remove-Item -Path $stAppDir -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $stAppDir" -ForegroundColor Green
    } catch {
        Write-Host "[ERR] Could not remove $stAppDir - $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "      Try running as Administrator." -ForegroundColor Yellow
    }
}

# %% Remove registry entry %%

if ($stRegExists) {
    Write-Host "[*] Removing registry entry..." -ForegroundColor Yellow
    try {
        Remove-Item -Path $stRegKey -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Registry entry removed." -ForegroundColor Green
    } catch {
        Write-Host "[ERR] Could not remove registry entry - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# %% Remove Start Menu shortcuts %%

if ($startMenuExists) {
    Write-Host "[*] Removing Start Menu shortcuts..." -ForegroundColor Yellow
    try {
        Remove-Item -Path $startMenuDir -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Start Menu folder removed." -ForegroundColor Green
    } catch {
        Write-Host "[ERR] Could not remove Start Menu folder - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# %% Restart Steam %%

Write-Host ""
$restart = Read-Host "Restart Steam? (y/n)"
if ($restart.Trim() -ieq "y") {
    $exe = Join-Path $steam "steam.exe"
    if (Test-Path $exe) {
        Start-Process -FilePath $exe
        Write-Host "[OK] Steam started." -ForegroundColor Green
    } else {
        Write-Host "[ERR] steam.exe not found." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Done! SteamTools has been fully uninstalled." -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Enter to exit..."
Read-Host
