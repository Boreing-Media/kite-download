@echo off
rem Takeoff for Windows. Download this file from https://boreing-media.github.io/kite-download/ and double-click it.
rem It asks GitHub's API for the newest Takeoff-Windows.zip and GitHub's own SHA-256 of that upload (not a value
rem kept in this file or this repo), downloads the zip, refuses it if the SHA-256 differs, unzips it and runs
rem "Make this PC reachable". There is no "irm | iex": the PowerShell part below is copied to a temp .ps1 and run
rem with -File. Check only (download + verify, unzip and install nothing):  Install-Takeoff.cmd check
setlocal
set "KITE_PS1=%TEMP%\Install-Takeoff-%RANDOM%%RANDOM%.ps1"
more +16 "%~f0" > "%KITE_PS1%"
set "KITE_ARG="
if /i "%~1"=="check" set "KITE_ARG=-CheckOnly"
powershell -NoProfile -ExecutionPolicy Bypass -File "%KITE_PS1%" %KITE_ARG%
set "KITE_RC=%ERRORLEVEL%"
del "%KITE_PS1%" >nul 2>&1
if /i not "%~1"=="check" pause
exit /b %KITE_RC%
# ---- PowerShell part (everything below this line is written to a temp .ps1) ----
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
$repo = 'Boreing-Media/kite-download'
$name = 'Takeoff-Windows.zip'
function Fail([string]$m) { Write-Host ''; Write-Host $m -ForegroundColor Red; Write-Host 'Nothing was installed. Tell Sam.'; exit 1 }
if ($CheckOnly) { $root = Join-Path $env:TEMP ('TakeoffCheck-' + [guid]::NewGuid().ToString('N')) }
else { $root = Join-Path $env:LOCALAPPDATA 'Kite\download' }
$zip = Join-Path $root $name

# 1. Which file, and GitHub's SHA-256 of it. GitHub computes this digest itself when the file is uploaded.
Write-Host 'Asking GitHub for the newest Takeoff and its fingerprint...'
$wc = New-Object Net.WebClient
$wc.Headers.Add('User-Agent', 'Takeoff-installer')
$wc.Headers.Add('Accept', 'application/vnd.github+json')
try { $rel = $wc.DownloadString("https://api.github.com/repos/$repo/releases/latest") | ConvertFrom-Json }
catch { Fail ('Could not ask GitHub: ' + $_.Exception.Message) }
$asset = @($rel.assets | Where-Object { $_.name -eq $name })[0]
if (-not $asset) { Fail ("The newest release (" + $rel.tag_name + ") has no $name.") }
if (-not ("" + $asset.digest -match '^sha256:([0-9a-f]{64})$')) { Fail "GitHub did not give a SHA-256 for $name." }
$want = $Matches[1]
$url = "" + $asset.browser_download_url
if (-not $url.StartsWith("https://github.com/$repo/releases/download/")) { Fail "Unexpected download address: $url" }

# 2. Download and check.
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
New-Item -ItemType Directory -Path $root | Out-Null
Write-Host ("Downloading Takeoff " + $rel.tag_name + '...')
$dl = New-Object Net.WebClient
$dl.Headers.Add('User-Agent', 'Takeoff-installer')
try { $dl.DownloadFile($url, $zip) } catch { Remove-Item $root -Recurse -Force; Fail ('Download failed: ' + $_.Exception.Message) }
$fs = [IO.File]::OpenRead($zip)
try { $got = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) } finally { $fs.Close() }
if ($got -ne $want) {
  Remove-Item $root -Recurse -Force
  Fail "The download does not match GitHub's fingerprint (expected $want, got $got)."
}
Write-Host "Download checked: SHA-256 $got matches GitHub."
if ($CheckOnly) {
  Remove-Item $root -Recurse -Force
  Write-Host ('CHECK OK: ' + $rel.tag_name + ' ' + $got + ' (check only: nothing unzipped or installed)')
  exit 0
}

# 3. Unzip and set up.
Write-Host 'Unzipping...'
if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) { Expand-Archive -LiteralPath $zip -DestinationPath $root -Force }
else { $sh = New-Object -ComObject Shell.Application; $sh.Namespace($root).CopyHere($sh.Namespace($zip).Items(), 0x14) }
$cmd = Join-Path $root 'Takeoff-Windows\Make this PC reachable.cmd'
$old = Join-Path $root 'Kite-Windows\Make this PC reachable.cmd'
for ($i = 0; $i -lt 50 -and -not (Test-Path $cmd) -and -not (Test-Path $old); $i++) { Start-Sleep -Milliseconds 200 }
if (-not (Test-Path $cmd) -and (Test-Path $old)) { $cmd = $old }
if (-not (Test-Path $cmd)) { Fail "Unzip failed: $cmd is missing." }
Write-Host 'Setting up Takeoff. Choose a password, then click Yes.'
Start-Process -FilePath $cmd -WorkingDirectory (Split-Path $cmd) -Wait -NoNewWindow
