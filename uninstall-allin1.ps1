param(
    [string]$PluginName,
    [int]$Branch # 1 = luatools, 2 = steamtools-collection
)

$Host.UI.RawUI.WindowTitle = "Luatools Uninstaller | .gg/luatools"
$defaultPluginName = "luatools"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
$ProgressPreference = 'SilentlyContinue'


#### Logging ####
function Log {
    param ([string]$Type, [string]$Message, [boolean]$NoNewline = $false)
    $Type = $Type.ToUpper()
    switch ($Type) {
        "OK"    { $fg = "Green" }
        "INFO"  { $fg = "Cyan" }
        "ERR"   { $fg = "Red" }
        "WARN"  { $fg = "Yellow" }
        "LOG"   { $fg = "Magenta" }
        "AUX"   { $fg = "DarkGray" }
        default { $fg = "White" }
    }
    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor Cyan -NoNewline
    Write-Host "[$Type] $Message" -ForegroundColor $fg -NoNewline:$NoNewline
}

function Sep   { Write-Host ("=" * 63) -ForegroundColor Cyan }
function Blank { Write-Host "" }


#### Locate Steam ####
function Get-SteamPath {
    $entries = @(
        @{ Path = "HKCU:\Software\Valve\Steam";                     Key = "SteamPath"   },
        @{ Path = "HKLM:\SOFTWARE\Valve\Steam";                     Key = "InstallPath" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam";         Key = "InstallPath" }
    )
    foreach ($e in $entries) {
        if (Test-Path $e.Path) {
            $val = (Get-ItemProperty -Path $e.Path -Name $e.Key -ErrorAction SilentlyContinue).($e.Key)
            if ($val -and (Test-Path $val)) { return $val }
        }
    }
    return $null
}

$steam = Get-SteamPath
if (-not $steam) {
    Log "ERR" "Steam not found. Is Steam installed?"
    Blank; Read-Host "Press Enter to exit"
    exit 1
}


#### Resolve plugin name ####
$name = $defaultPluginName
if ($PluginName) { $name = $PluginName }
if ($br -eq 2 -or $Branch -eq 2) { $name = "steamtools-collection" }
$upperName = $name.Substring(0,1).ToUpper() + $name.Substring(1).ToLower()


#### Detection ####
function Test-PluginInstalled {
    $possibleDirs = @(
        (Join-Path $steam "millennium\plugins"),
        (Join-Path $steam "plugins"),
        (Join-Path $steam ".millennium\plugins")
    )
    foreach ($dir in $possibleDirs) {
        if (Test-Path $dir) {
            foreach ($p in Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue) {
                $jp = Join-Path $p.FullName "plugin.json"
                if (Test-Path $jp) {
                    $j = Get-Content $jp -Raw | ConvertFrom-Json
                    if ($j.name -eq $name) { return $true }
                }
            }
        }
    }
    return $false
}

function Test-SteamtoolsInstalled {
    $hasDll = (@("dwmapi.dll","xinput1_4.dll") | Where-Object { Test-Path (Join-Path $steam $_) }).Count -gt 0
    return ($hasDll -or (Test-Path "C:\Program Files\SteamTools"))
}

function Test-MillenniumInstalled {
    return (@("millennium.dll","python311.dll") | Where-Object { Test-Path (Join-Path $steam $_) }).Count -gt 0
}

function Get-LuaFileCount {
    $p = Join-Path $steam "config\stplug-in"
    if (-not (Test-Path $p)) { return 0 }
    return @(Get-ChildItem -Path $p -Filter "*.lua" -ErrorAction SilentlyContinue).Count
}


#### Uninstall functions ####
function Uninstall-Plugin {
    Blank; Sep; Log "INFO" "Uninstalling plugin: $name"; Sep; Blank

    $possibleDirs = @(
        (Join-Path $steam "millennium\plugins"),
        (Join-Path $steam "plugins"),
        (Join-Path $steam ".millennium\plugins")
    )

    $pluginPath = $null
    $foundDir = $false

    foreach ($dir in $possibleDirs) {
        if (Test-Path $dir) {
            $foundDir = $true
            foreach ($p in Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue) {
                $jp = Join-Path $p.FullName "plugin.json"
                if (Test-Path $jp) {
                    $j = Get-Content $jp -Raw | ConvertFrom-Json
                    if ($j.name -eq $name) { 
                        $pluginPath = $p.FullName
                        break 
                    }
                }
            }
        }
        if ($pluginPath) { break }
    }

    if (-not $foundDir) {
        Log "WARN" "Plugins directory not found."
        return
    }

    if ($pluginPath) {
        Log "LOG" "Removing: $pluginPath"
        Remove-Item $pluginPath -Recurse -Force
        Log "OK" "$upperName folder removed"
    } else {
        Log "WARN" "Plugin folder for '$name' not found — already uninstalled?"
    }

    $configPaths = @(
        (Join-Path $steam "millennium\ext\config.json"),
        (Join-Path $steam "ext\config.json"),
        (Join-Path $steam ".millennium\ext\config.json")
    )
    
    foreach ($configPath in $configPaths) {
        if (Test-Path $configPath) {
            $config = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json
            if ($config.plugins -and $config.plugins.enabledPlugins) {
                $before = @($config.plugins.enabledPlugins)
                $after  = $before | Where-Object { $_ -ne $name }
                if ($before.Count -ne $after.Count) {
                    $config.plugins.enabledPlugins = $after
                    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
                    Log "OK" "Removed '$name' from enabled plugins list"
                }
            }
        }
    }

    Log "OK" "$upperName uninstalled"
}

function Uninstall-Steamtools([bool]$RemoveLuas) {
    Blank; Sep; Log "INFO" "Uninstalling SteamTools"; Sep; Blank

    $stDlls          = @("dwmapi.dll","xinput1_4.dll")
    $foundDlls       = $stDlls | Where-Object { Test-Path (Join-Path $steam $_) }
    $stAppDir        = "C:\Program Files\SteamTools"
    $stAppExists     = Test-Path $stAppDir
    $stplugPath      = Join-Path $steam "config\stplug-in"
    $luaFiles        = @()
    if (Test-Path $stplugPath) { $luaFiles = @(Get-ChildItem -Path $stplugPath -Filter "*.lua" -ErrorAction SilentlyContinue) }
    $stRegKey        = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SteamTools"
    $stRegExists     = Test-Path $stRegKey
    $startMenuDir    = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\SteamTools"
    $startMenuExists = Test-Path $startMenuDir

    if ($foundDlls.Count -eq 0 -and -not $stAppExists) { Log "INFO" "SteamTools does not appear to be installed."; return }

    Log "WARN" "Killing Steam and SteamTools..."
    Get-Process -Name "steam","SteamTools" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    foreach ($f in $foundDlls) {
        $t = Join-Path $steam $f
        try   { Remove-Item -Path $t -Force -ErrorAction Stop; Log "OK" "Removed: $f" }
        catch { Log "ERR" "Could not remove $f — try running as Administrator" }
    }

    if ($RemoveLuas) {
        foreach ($lua in $luaFiles) {
            try   { Remove-Item -Path $lua.FullName -Force -ErrorAction Stop; Log "OK" "Removed: $($lua.Name)" }
            catch { Log "ERR" "Could not remove $($lua.Name)" }
        }
    }

    if ($stAppExists) {
        try   { Remove-Item -Path $stAppDir -Recurse -Force -ErrorAction Stop; Log "OK" "Removed: $stAppDir" }
        catch { Log "ERR" "Could not remove $stAppDir — try running as Administrator" }
    }

    if ($stRegExists) {
        try   { Remove-Item -Path $stRegKey -Recurse -Force -ErrorAction Stop; Log "OK" "Registry entry removed" }
        catch { Log "ERR" "Could not remove registry entry" }
    }

    if ($startMenuExists) {
        try   { Remove-Item -Path $startMenuDir -Recurse -Force -ErrorAction Stop; Log "OK" "Start Menu folder removed" }
        catch { Log "ERR" "Could not remove Start Menu folder" }
    }

    Log "OK" "SteamTools uninstalled"
}

function Uninstall-Millennium([bool]$KeepPlugins) {
    Blank; Sep; Log "INFO" "Uninstalling Millennium"; Sep; Blank

    $milFiles  = @("millennium.dll","python311.dll","python311.zip")
    $milDirs   = @("ext","plugins","millennium","pkg", ".millennium")
    $foundFiles = $milFiles | Where-Object { Test-Path (Join-Path $steam $_) }
    $foundDirs  = $milDirs  | Where-Object { Test-Path (Join-Path $steam $_) }

    if ($foundFiles.Count -eq 0 -and $foundDirs.Count -eq 0) { Log "INFO" "Millennium does not appear to be installed."; return }

    Log "WARN" "Killing Steam..."
    Get-Process -Name "steam" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    foreach ($f in $foundFiles) {
        $t = Join-Path $steam $f
        try   { Remove-Item -Path $t -Force -ErrorAction Stop; Log "OK" "Removed: $f" }
        catch { Log "ERR" "Could not remove $f — try running as Administrator" }
    }

    foreach ($d in $foundDirs) {
        if (($d -eq "plugins" -or $d -eq "millennium\plugins" -or $d -eq ".millennium\plugins") -and $KeepPlugins) { 
            Log "AUX" "Skipping plugins folder"
            continue 
        }
        $t = Join-Path $steam $d
        if (Test-Path $t) {
            try   { Remove-Item -Path $t -Recurse -Force -ErrorAction Stop; Log "OK" "Removed: $d\" }
            catch { Log "ERR" "Could not remove $d\ — try running as Administrator" }
        }
    }

    Log "OK" "Millennium uninstalled"
}

function Restart-Steam {
    $exe = Join-Path $steam "steam.exe"
    if (Test-Path $exe) { Start-Process -FilePath $exe; Log "OK" "Steam started" }
    else                { Log "ERR" "steam.exe not found" }
}


#### Toggle menu ####
$luaCount = Get-LuaFileCount

# State
$doPlugin     = Test-PluginInstalled
$doSteamtools = Test-SteamtoolsInstalled
$doMillennium = Test-MillenniumInstalled
$doLuas       = $false
$doKeepPlugins = $false

function Write-Menu {
    Clear-Host
    Sep
    Write-Host "  Potatools Uninstaller  |  .gg/potatools" -ForegroundColor Cyan
    Sep
    Blank

    function Checkbox([bool]$on) { if ($on) { return "[X]" } else { return "[ ]" } }
    function Status([bool]$found) { if ($found) { return "[installed]" } else { return "[not found]" } }

    Write-Host "  WHAT TO UNINSTALL:" -ForegroundColor DarkGray
    Write-Host "  1  $(Checkbox $doPlugin)    " -ForegroundColor Cyan -NoNewline
    Write-Host "Plugin ($name)   " -NoNewline
    Write-Host (Status (Test-PluginInstalled)) -ForegroundColor DarkGray

    Write-Host "  2  $(Checkbox $doSteamtools) " -ForegroundColor Cyan -NoNewline
    Write-Host "SteamTools       " -NoNewline
    Write-Host (Status (Test-SteamtoolsInstalled)) -ForegroundColor DarkGray

    Write-Host "  3  $(Checkbox $doMillennium) " -ForegroundColor Cyan -NoNewline
    Write-Host "Millennium       " -NoNewline
    Write-Host (Status (Test-MillenniumInstalled)) -ForegroundColor DarkGray

    Blank
    Write-Host "  OPTIONS:" -ForegroundColor DarkGray

    $luaLabel = if ($luaCount -gt 0) { "($luaCount file(s) found)" } else { "(none found)" }
    $luaColor = if ($luaCount -gt 0) { "DarkGray" } else { "DarkGray" }
    Write-Host "  4  $(Checkbox $doLuas)    " -ForegroundColor Cyan -NoNewline
    Write-Host "Remove SteamTools Lua files  " -NoNewline
    Write-Host $luaLabel -ForegroundColor DarkGray

    Write-Host "  5  $(Checkbox $doKeepPlugins) " -ForegroundColor Cyan -NoNewline
    Write-Host "Keep Millennium plugins folder"

    Blank
    Write-Host "  R" -ForegroundColor Green -NoNewline; Write-Host "  Run"
    Write-Host "  Q" -ForegroundColor DarkGray -NoNewline; Write-Host "  Quit"
    Blank
}

while ($true) {
    Write-Menu
    $key = Read-Host "Toggle option or run"

    switch ($key.Trim().ToUpper()) {
        "1" { $doPlugin     = -not $doPlugin }
        "2" { $doSteamtools = -not $doSteamtools }
        "3" { $doMillennium = -not $doMillennium }
        "4" { $doLuas       = -not $doLuas }
        "5" { $doKeepPlugins = -not $doKeepPlugins }
        "Q" { exit 0 }
        "R" {
            if (-not $doPlugin -and -not $doSteamtools -and -not $doMillennium) {
                Clear-Host
                Log "WARN" "Nothing selected to uninstall."
                Blank
                Read-Host "Press Enter to go back"
                break
            }

            Clear-Host
            Sep
            Write-Host "  Running uninstaller..." -ForegroundColor Cyan
            Sep

            if ($doPlugin)     { Uninstall-Plugin }
            if ($doSteamtools) { Uninstall-Steamtools -RemoveLuas $doLuas }
            if ($doMillennium) { Uninstall-Millennium -KeepPlugins $doKeepPlugins }

            Blank
            $restart = Read-Host "Restart Steam? (y/n)"
            if ($restart.Trim() -ieq "y") { Restart-Steam }

            Blank; Sep
            Write-Host "  Done!" -ForegroundColor Green
            Sep; Blank
            Read-Host "Press Enter to exit"
            exit 0
        }
    }
}
