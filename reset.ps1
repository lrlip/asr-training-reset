<#
.SYNOPSIS
  reset.ps1 - give this laptop a fresh copy of one or every session of the AI Orchestrator training
  and set it up, on Windows.

.DESCRIPTION
  1. Asks which sessions to reset, which is also the confirmation; -Session skips the question and
     -Force the confirmation
  2. Per session: stops the processes that use its folder, removes the folder, clones the
     repository again from GitHub and runs its setup.ps1. When the folder stays locked, it stops
     every Node.js, Bun, Python, uv and VS Code process, also those of the other sessions, and
     tries again

  The sessions go on the desktop, next to this launcher, or in C:\training when the desktop cannot
  be written to. Never inside this launcher: the session setups refuse to run inside another git
  repository. -TrainingFolder picks another folder. Works in Windows PowerShell 5.1 and
  PowerShell 7. Deliberately pure ASCII, so 5.1 parses it without a BOM. reset.cmd next to this
  file starts it with the execution policy bypassed.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\reset.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\reset.ps1 -Session 2
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\reset.ps1 -TrainingFolder D:\training -Force
#>
[CmdletBinding()]
param(
    [string]$TrainingFolder = '',
    # Session numbers or names, such as 1, asr-session-2, "1,2" or all. Empty asks, or with -Force takes all.
    [string[]]$Session = @(),
    [switch]$Force
)

# No global $ErrorActionPreference = 'Stop': Windows PowerShell 5.1 turns the progress a native
# command writes to stderr into a terminating error under Stop. Every native call checks
# $LASTEXITCODE instead.

$script:Sessions = @(
    @{ Name = 'asr-session-1'; Repository = 'https://github.com/AlexDM0/asr-session-1.git' },
    @{ Name = 'asr-session-2'; Repository = 'https://github.com/AlexDM0/asr-session-2.git' }
)
# The last resort when a session folder stays locked; names without .exe.
$script:ProcessesToStop = @('node', 'bun', 'python', 'uv', 'Code')
# The reset buttons on the desktop: shortcut name and the file next to this script it starts.
$script:Shortcuts = @(
    @{ Name = 'Reset ASR session 1'; Target = 'reset1.cmd'; Description = 'Removes asr-session-1, clones it again and sets it up' },
    @{ Name = 'Reset ASR session 2'; Target = 'reset2.cmd'; Description = 'Removes asr-session-2, clones it again and sets it up' },
    @{ Name = 'Reset ASR all sessions'; Target = 'resetall.cmd'; Description = 'Removes every training session, clones them again and sets them up' }
)
# The single shortcut of an earlier version, which the three above replace.
$script:OldShortcutName = 'Reset ASR training'
$script:FallbackTrainingFolder = 'C:\training'
# The size of the reset window, in characters.
$script:WindowWidth = 100
$script:WindowHeight = 25
# AppLocker and WDAC run scripts from a user folder in ConstrainedLanguage, where .NET calls fail.
$script:IsFullLanguage = ($ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage')
$script:ResetExitCode = 0

# --- Output helpers ----------------------------------------------------------
# ASCII markers: the console font of Windows PowerShell 5.1 has no check mark glyph.
function Write-Bold($message) { Write-Host $message -ForegroundColor White }
function Write-Step($message) { Write-Host ''; Write-Host $message -ForegroundColor White }
function Write-Info($message) { Write-Host "- $message" -ForegroundColor Cyan }
function Write-Ok($message)   { Write-Host "+ $message" -ForegroundColor Green }
function Write-Warn($message) { Write-Host "! $message" -ForegroundColor Yellow }
function Write-ErrorMessage($message) { Write-Host "x $message" -ForegroundColor Red }

# --- Helpers -----------------------------------------------------------------
function Test-CommandExists($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# git only reads HTTPS_PROXY, not the Windows proxy settings, so copy those over. The session
# setups inherit it.
function Initialize-SystemProxy {
    if (-not $script:IsFullLanguage) { return }
    try {
        [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
        if ($env:HTTPS_PROXY -or $env:https_proxy) { return }
        $probeAddress = [uri]'https://github.com'
        $proxyAddress = [Net.WebRequest]::GetSystemWebProxy().GetProxy($probeAddress)
        if ($proxyAddress -and $proxyAddress.Host -ne $probeAddress.Host) {
            $env:HTTPS_PROXY = $proxyAddress.AbsoluteUri
            $env:HTTP_PROXY = $proxyAddress.AbsoluteUri
            Write-Info "Using the Windows proxy $($proxyAddress.AbsoluteUri)."
        }
    } catch { }
}

# The desktop Explorer shows, which OneDrive or a company policy may have moved away from
# %USERPROFILE%\Desktop. GetFolderPath is a .NET call, so locked-down PowerShell falls back.
function Get-DesktopFolder {
    $desktopFolder = $null
    if ($script:IsFullLanguage) {
        try { $desktopFolder = [Environment]::GetFolderPath('Desktop') } catch { }
    }
    if (-not $desktopFolder) { $desktopFolder = Join-Path $env:USERPROFILE 'Desktop' }
    return $desktopFolder
}

# Whether a file can be created in $folder, which also creates $folder when it is missing.
function Test-FolderIsWritable($folder) {
    if (-not $folder) { return $false }
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction SilentlyContinue | Out-Null
    $probeFile = Join-Path $folder 'reset-write-test.tmp'
    New-Item -ItemType File -Path $probeFile -Force -ErrorAction SilentlyContinue | Out-Null
    if (-not (Test-Path -LiteralPath $probeFile)) { return $false }
    Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
    return $true
}

# -TrainingFolder when given, else the desktop, else C:\training. Returns $null when none works.
function Resolve-TrainingFolder {
    if ($script:TrainingFolder) {
        if (Test-FolderIsWritable $script:TrainingFolder) { return $script:TrainingFolder }
        Write-ErrorMessage "Cannot write to $script:TrainingFolder."
        return $null
    }
    $desktopFolder = Get-DesktopFolder
    if (Test-FolderIsWritable $desktopFolder) { return $desktopFolder }
    Write-Warn "Cannot write to the desktop ($desktopFolder); using $script:FallbackTrainingFolder instead."
    if (Test-FolderIsWritable $script:FallbackTrainingFolder) { return $script:FallbackTrainingFolder }
    Write-ErrorMessage "Cannot write to $script:FallbackTrainingFolder either."
    return $null
}

# A double-click on a desktop shortcut is a reset button. Creates the shortcuts that are missing,
# brings older ones up to date and removes the single shortcut of an earlier version. A shortcut
# starts its .cmd in the classic console (conhost.exe) instead of Windows Terminal, because only
# that window can be made smaller.
function Install-DesktopShortcuts {
    if (-not $script:IsFullLanguage) { return }
    try {
        $desktopFolder = Get-DesktopFolder
        Remove-Item -LiteralPath (Join-Path $desktopFolder "$script:OldShortcutName.lnk") -Force -ErrorAction SilentlyContinue
        $consoleHost = Join-Path $env:SystemRoot 'System32\conhost.exe'
        $shell = New-Object -ComObject WScript.Shell
        foreach ($shortcutDefinition in $script:Shortcuts) {
            $shortcutPath = Join-Path $desktopFolder "$($shortcutDefinition.Name).lnk"
            $isNewShortcut = -not (Test-Path -LiteralPath $shortcutPath)
            $cmdFile = Join-Path $PSScriptRoot $shortcutDefinition.Target
            $targetPath = $cmdFile
            $arguments = ''
            if (Test-Path -LiteralPath $consoleHost) {
                $targetPath = $consoleHost
                # cmd.exe strips the outer pair of quotes, so a path with spaces keeps its own.
                $arguments = "cmd.exe /c `"`"$cmdFile`"`""
            }
            $shortcut = $shell.CreateShortcut($shortcutPath)
            if (-not $isNewShortcut -and $shortcut.TargetPath -ieq $targetPath -and $shortcut.Arguments -eq $arguments) { continue }
            $shortcut.TargetPath = $targetPath
            $shortcut.Arguments = $arguments
            $shortcut.WorkingDirectory = $PSScriptRoot
            $shortcut.IconLocation = "$env:SystemRoot\System32\cmd.exe,0"
            $shortcut.Description = $shortcutDefinition.Description
            $shortcut.Save()
            if ($isNewShortcut) {
                Write-Ok "Added the shortcut `"$($shortcutDefinition.Name)`" to the desktop."
            } else {
                Write-Ok "Updated the shortcut `"$($shortcutDefinition.Name)`" on the desktop."
            }
        }
    } catch {
        Write-Warn "Could not add the desktop shortcuts: $($_.Exception.Message)"
    }
}

# Makes the console window small, keeping its scrollback. Only the classic console can be resized;
# in Windows Terminal this does nothing.
function Set-SmallWindow {
    try {
        $rawUi = $Host.UI.RawUI
        $windowSize = $rawUi.WindowSize
        $windowSize.Width = $script:WindowWidth
        if ($rawUi.BufferSize.Width -lt $windowSize.Width) { $windowSize.Width = $rawUi.BufferSize.Width }
        $windowSize.Height = $script:WindowHeight
        $rawUi.WindowSize = $windowSize
    } catch { }
}

# Every process, from one snapshot, with its executable path and command line together in Text.
# Empty when Windows does not hand out the list.
function Get-ProcessSnapshot {
    $processSnapshot = @()
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)) {
        $processSnapshot += [pscustomobject]@{
            Id       = [int]$process.ProcessId
            ParentId = [int]$process.ParentProcessId
            Name     = [string]$process.Name
            Text     = "$($process.ExecutablePath) $($process.CommandLine)"
        }
    }
    return ,$processSnapshot
}

# This script and the windows that started it, which must keep running.
function Get-OwnProcessIds($processSnapshot) {
    $ownProcessIds = @($PID)
    $currentId = $PID
    for ($depth = 0; $depth -lt 16; $depth++) {
        $currentProcess = $processSnapshot | Where-Object { $_.Id -eq $currentId } | Select-Object -First 1
        if (-not $currentProcess -or $currentProcess.ParentId -le 0 -or $ownProcessIds -contains $currentProcess.ParentId) { break }
        $currentId = $currentProcess.ParentId
        $ownProcessIds += $currentId
    }
    return ,$ownProcessIds
}

# Stops the given processes and everything they started, such as the terminals and servers of a
# VS Code window, but never this script or the windows that started it. Returns how many it stopped.
function Stop-ProcessTree($processSnapshot, $processIds) {
    $treeIds = @($processIds)
    $addedIds = @($processIds)
    while ($addedIds.Count -gt 0) {
        $addedIds = @($processSnapshot | Where-Object { $addedIds -contains $_.ParentId -and $treeIds -notcontains $_.Id } | ForEach-Object { $_.Id })
        $treeIds += $addedIds
    }
    $ownProcessIds = Get-OwnProcessIds $processSnapshot
    $stopIds = @($treeIds | Where-Object { $ownProcessIds -notcontains $_ })
    foreach ($stopId in $stopIds) { Stop-Process -Id $stopId -Force -ErrorAction SilentlyContinue }
    if ($stopIds.Count -gt 0) { Start-Sleep -Seconds 2 }
    return $stopIds.Count
}

# Stops every process that runs from the session folder or names it on its command line, with
# everything it started: node, bun or python from the folder, VS Code opened on it. Windows does not
# tell which folder a terminal is in, so a terminal that was only opened there keeps running.
function Stop-SessionProcesses($sessionFolder) {
    $processSnapshot = Get-ProcessSnapshot
    # The folder with \ or / as separator, followed by a separator, a quote, a space or the end, so
    # asr-session-1 does not also match asr-session-10. -match ignores case, like Windows paths.
    $escapedFolder = ($sessionFolder.TrimEnd('\', '/') -replace '([\\.\[\]\(\)\{\}\^\$\|\?\*\+])', '\$1') -replace '\\\\', '[\\/]'
    $folderPattern = $escapedFolder + '([\\/"'' ]|$)'
    $matchingIds = @($processSnapshot | Where-Object { $_.Text -match $folderPattern } | ForEach-Object { $_.Id })
    $stoppedCount = Stop-ProcessTree $processSnapshot $matchingIds
    if ($stoppedCount -gt 0) {
        Write-Ok "Stopped $stoppedCount process(es) that used $sessionFolder."
    } else {
        Write-Ok "No running process uses $sessionFolder."
    }
}

# The last resort when the folder stays locked: every Node.js, Bun, Python, uv and VS Code process
# with everything it started, also those of the other sessions.
function Stop-TrainingProcesses {
    $processSnapshot = Get-ProcessSnapshot
    $processNames = @($script:ProcessesToStop | ForEach-Object { "$_.exe" })
    $matchingIds = @($processSnapshot | Where-Object { $processNames -contains $_.Name } | ForEach-Object { $_.Id })
    $stoppedCount = Stop-ProcessTree $processSnapshot $matchingIds
    Write-Warn "Stopped $stoppedCount Node.js, Bun, Python, uv and VS Code process(es), also those of other sessions."
}

# Turns -Session values like 1, asr-session-2, "1,2" or all into sessions. Returns $null for an unknown one.
function Get-SessionsFromNames($sessionNames) {
    $selectedSessions = @()
    foreach ($sessionName in @($sessionNames | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })) {
        if ($sessionName -ieq 'all') { return ,@($script:Sessions) }
        $matchingSession = $script:Sessions | Where-Object { $_.Name -ieq $sessionName -or $_.Name -ieq "asr-session-$sessionName" }
        if (-not $matchingSession) {
            Write-ErrorMessage "There is no session $sessionName. Choose from: $(($script:Sessions | ForEach-Object { $_.Name }) -join ', ')."
            return $null
        }
        if ($selectedSessions -notcontains $matchingSession) { $selectedSessions += $matchingSession }
    }
    return ,$selectedSessions
}

# Asks which sessions to reset; the answer is also the confirmation. Returns no sessions on Enter.
function Read-SessionChoice {
    Write-Host ''
    Write-Bold 'Which session do you want to reset? This deletes all work in it.'
    for ($sessionIndex = 0; $sessionIndex -lt $script:Sessions.Count; $sessionIndex++) {
        $sessionFolder = Join-Path $script:TrainingFolder $script:Sessions[$sessionIndex].Name
        Write-Host "  $($sessionIndex + 1)  $sessionFolder"
    }
    Write-Host '  A  all of them'
    while ($true) {
        $answer = (Read-Host 'Type 1, 2 or A and press Enter (only Enter: stop)').Trim()
        if (-not $answer) { return ,@() }
        if ($answer -ieq 'A') { return ,@($script:Sessions) }
        $chosenSessions = Get-SessionsFromNames @($answer)
        if ($chosenSessions) { return ,$chosenSessions }
    }
}

# Remove-Item in Windows PowerShell 5.1 fails on paths past 260 characters, which node_modules
# reaches; rmdir with the \\?\ prefix does not. Returns whether the folder is gone.
function Remove-SessionFolder($sessionFolder) {
    Remove-Item -LiteralPath $sessionFolder -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $sessionFolder) {
        & cmd.exe /d /c "rmdir /s /q `"\\?\$sessionFolder`"" 2>$null
    }
    return (-not (Test-Path -LiteralPath $sessionFolder))
}

# Returns whether the session was cloned and set up.
function Reset-Session($session) {
    $sessionFolder = Join-Path $script:TrainingFolder $session.Name
    Write-Step $session.Name

    if (Test-Path -LiteralPath $sessionFolder) {
        Stop-SessionProcesses $sessionFolder
        Write-Info "Removing $sessionFolder..."
        if (-not (Remove-SessionFolder $sessionFolder)) {
            Write-Warn "Something still uses $sessionFolder."
            Stop-TrainingProcesses
            if (-not (Remove-SessionFolder $sessionFolder)) {
                Write-ErrorMessage "Could not remove $sessionFolder. Close the terminals and Explorer windows in that folder, then press the reset button again."
                return $false
            }
        }
        Write-Ok "Removed $sessionFolder."
    }

    Write-Info "Cloning $($session.Repository)..."
    $global:LASTEXITCODE = 1
    & git clone --quiet $session.Repository $sessionFolder
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "Cloning $($session.Name) failed. Check your internet connection (or HTTPS_PROXY behind a proxy) and press the reset button again."
        return $false
    }
    Write-Ok "Cloned $($session.Name) into $sessionFolder."

    $setupScript = Join-Path $sessionFolder 'setup.ps1'
    if (-not (Test-Path -LiteralPath $setupScript)) {
        Write-ErrorMessage "$($session.Name) has no setup.ps1."
        return $false
    }
    Write-Info "Running the setup of $($session.Name)..."
    $global:LASTEXITCODE = 1
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "The setup of $($session.Name) did not finish. Read its messages above."
        return $false
    }
    Write-Ok "$($session.Name) is set up in $sessionFolder."
    return $true
}

function Invoke-Reset {
    Set-SmallWindow
    $resolvedFolder = Resolve-TrainingFolder
    if (-not $resolvedFolder) {
        Write-Info 'Pick a folder you can write to with -TrainingFolder, for example D:\training.'
        $script:ResetExitCode = 1; return
    }
    $script:TrainingFolder = $resolvedFolder
    Install-DesktopShortcuts

    # --- 1. Choice and confirmation ---------------------------------------------
    if ($Session.Count -gt 0) {
        $selectedSessions = Get-SessionsFromNames $Session
        if (-not $selectedSessions) { $script:ResetExitCode = 1; return }
    } elseif ($Force) {
        $selectedSessions = @($script:Sessions)
    } else {
        $selectedSessions = Read-SessionChoice
    }
    if ($selectedSessions.Count -eq 0) {
        Write-Info 'Nothing was changed.'
        return
    }
    $sessionNames = ($selectedSessions | ForEach-Object { $_.Name }) -join ' and '
    if ($Session.Count -gt 0 -and -not $Force) {
        Write-Host ''
        Write-Warn "This deletes $sessionNames in $script:TrainingFolder, with all work in them."
        $answer = Read-Host 'Type Y and press Enter to continue'
        if ($answer -notmatch '^\s*[yY]') {
            Write-Info 'Nothing was changed.'
            return
        }
    }
    Write-Bold "Resetting $sessionNames in $script:TrainingFolder"

    # --- 2. Checks --------------------------------------------------------------
    Write-Step 'Checks'
    if (-not (Test-CommandExists 'git')) {
        Write-ErrorMessage 'git was not found. Install it from https://git-scm.com and press the reset button again.'
        $script:ResetExitCode = 1; return
    }
    Write-Ok "$(& git --version) works."
    Initialize-SystemProxy

    # --- 3. Sessions -----------------------------------------------------------
    # Every session gets its turn, so one failing session does not block the other.
    $failedSessions = @()
    foreach ($selectedSession in $selectedSessions) {
        if (-not (Reset-Session $selectedSession)) { $failedSessions += $selectedSession.Name }
    }

    Write-Host ''
    if ($failedSessions.Count -gt 0) {
        Write-ErrorMessage "Not ready: $($failedSessions -join ', '). Read the messages above."
        $script:ResetExitCode = 1
    } else {
        Write-Ok "Ready in $($script:TrainingFolder): $sessionNames."
    }
}

if ($PSScriptRoot) {
    try {
        Invoke-Reset
    } catch {
        Write-ErrorMessage "Reset stopped unexpectedly: $($_.Exception.Message)"
        $script:ResetExitCode = 1
    }
} else {
    Write-ErrorMessage 'Run this script as a file: double-click reset.cmd.'
    $script:ResetExitCode = 1
}

# Only exit when run as a script: exit in a dot-sourced file would close the caller's shell.
if ($MyInvocation.InvocationName -ne '.') { exit $script:ResetExitCode }
