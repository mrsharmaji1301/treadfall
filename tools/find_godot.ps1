# Finds the Godot 4 editor exe on this PC and prints its full path.
# Order: remembered path, a running Godot, PATH, usual folders, every drive,
# and only if all that fails a file picker. Writes nothing outside the project.
$ErrorActionPreference = 'SilentlyContinue'
$memo = Join-Path $PSScriptRoot '..\_preview\godot_path.txt'

function Test-Godot($path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $name = [IO.Path]::GetFileName($path)
    if ($name -notlike 'Godot*.exe') { return $false }
    # Version from the file name (Godot_v4.7.2-...) or from the file details.
    if ($name -match 'v(\d+)\.') { return ([int]$Matches[1] -ge 4) }
    $v = (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
    if ($v -match '^(\d+)\.') { return ([int]$Matches[1] -ge 4) }
    return $true
}

function Pick($list) {
    $good = @($list | Where-Object { Test-Godot $_ } | Select-Object -Unique)
    if ($good.Count -eq 0) { return $null }
    # Best first: version 4.7, then the console build (it prints results).
    $ranked = $good | Sort-Object `
        @{ Expression = { if ($_ -match '4\.7') { 0 } else { 1 } } }, `
        @{ Expression = { if ($_ -match 'console') { 0 } else { 1 } } }, `
        @{ Expression = { $_ }; Descending = $true }
    return @($ranked)[0]
}

function Done($path) {
    Set-Content -LiteralPath $memo -Value $path -Encoding ASCII
    Write-Output $path
    exit 0
}

# 1. The path found last time.
if (Test-Path -LiteralPath $memo) {
    $old = (Get-Content -LiteralPath $memo -TotalCount 1).Trim()
    if (Test-Godot $old) { Done $old }
}

# 2. A Godot that is running right now.
$hit = Pick @(Get-Process | Where-Object { $_.ProcessName -like 'Godot*' } | ForEach-Object { $_.Path })
if ($hit) { Done $hit }

# 3. On the PATH.
$hit = Pick @(Get-Command 'godot*.exe' -CommandType Application | ForEach-Object { $_.Source })
if ($hit) { Done $hit }

# 4. The usual places, a few folders deep.
$spots = @(
    "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\scoop", "$env:LOCALAPPDATA\Programs", "$env:ProgramFiles", "${env:ProgramFiles(x86)}",
    "$env:OneDrive\Desktop", "$env:ChocolateyInstall"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$found = @()
foreach ($s in $spots) {
    $found += Get-ChildItem -LiteralPath $s -Filter 'Godot*.exe' -File -Recurse -Depth 4 | ForEach-Object { $_.FullName }
}
$hit = Pick $found
if ($hit) { Done $hit }

# 5. Every fixed drive, whole disk (this can take a minute or two).
[Console]::Error.WriteLine('Searching all drives for Godot, please wait...')
$found = @()
$drives = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName }
# The project's own drive first.
$mine = [IO.Path]::GetPathRoot($PSScriptRoot)
$drives = @($mine) + @($drives | Where-Object { $_ -ne $mine })
foreach ($d in $drives) {
    $out = cmd /c "dir /b /s /a-d `"$($d)Godot*.exe`" 2>nul"
    if ($out) { $found += @($out) }
    $hit = Pick $found
    if ($hit) { Done $hit }
}

# 6. Last resort: ask with a file picker.
Add-Type -AssemblyName System.Windows.Forms
$dlg = New-Object System.Windows.Forms.OpenFileDialog
$dlg.Title = 'Select your Godot 4 .exe'
$dlg.Filter = 'Godot (Godot*.exe)|Godot*.exe|Programs (*.exe)|*.exe'
if ($dlg.ShowDialog() -eq 'OK' -and (Test-Path -LiteralPath $dlg.FileName)) { Done $dlg.FileName }
exit 1
