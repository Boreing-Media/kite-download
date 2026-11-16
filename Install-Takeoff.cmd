@echo off
rem Takeoff for Windows. Download this file from https://boreing-media.github.io/kite-download/ and double-click it.
rem It asks GitHub's API for the newest Takeoff-Windows.zip, GitHub's own SHA-256 of it, and its signature file
rem Takeoff-Windows.zip.sig. It installs ONLY when the zip matches GitHub's SHA-256 AND carries a P-256 signature by
rem Takeoff's own update key: the public key is written in this file, never fetched. Anything else and the download
rem is deleted, nothing is unzipped and nothing is run. There is no "irm | iex": the PowerShell part below is copied
rem to a temp .ps1 and run with -File.
rem   Install-Takeoff.cmd check                    download + verify only: nothing unzipped, installed or started
rem   Install-Takeoff.cmd verify ZIP SIG [SHA256]  verify local files only (tests): nothing unzipped or started
setlocal
if not "%~1"=="" if /i not "%~1"=="check" if /i not "%~1"=="verify" goto usage
set "KITE_PS1=%TEMP%\Install-Takeoff-%RANDOM%%RANDOM%.ps1"
more +37 "%~f0" > "%KITE_PS1%"
set "KITE_PS=powershell -NoProfile -ExecutionPolicy Bypass -File"
if /i "%~1"=="check" goto check
if /i "%~1"=="verify" goto verify
%KITE_PS% "%KITE_PS1%"
set "KITE_RC=%ERRORLEVEL%"
del "%KITE_PS1%" >nul 2>&1
pause
exit /b %KITE_RC%
:usage
echo Install-Takeoff.cmd: double-click it to install, or: Install-Takeoff.cmd check ^| verify ZIP SIG [SHA256]
exit /b 2
:check
%KITE_PS% "%KITE_PS1%" -CheckOnly
goto done
:verify
if not "%~4"=="" goto verifysha
%KITE_PS% "%KITE_PS1%" -VerifyOnly -ZipFile "%~2" -SigFile "%~3"
goto done
:verifysha
%KITE_PS% "%KITE_PS1%" -VerifyOnly -ZipFile "%~2" -SigFile "%~3" -Sha256 "%~4"
:done
set "KITE_RC=%ERRORLEVEL%"
del "%KITE_PS1%" >nul 2>&1
exit /b %KITE_RC%
# ---- PowerShell part (everything below this line is written to a temp .ps1) ----
param([switch]$CheckOnly, [switch]$VerifyOnly, [string]$ZipFile = '', [string]$SigFile = '', [string]$Sha256 = '')
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
$repo = 'Boreing-Media/kite-download'
$name = 'Takeoff-Windows.zip'
$signame = 'Takeoff-Windows.zip.sig'

# TAKEOFF'S UPDATE KEYS, written here and never fetched (16 Nov 2026, audit risk #3: before this, a first install
# trusted GitHub alone). The same Secure Enclave keys every Takeoff host trusts for its own updates (kite repo:
# mac/signing/update-key-p256.pub = BAKED_P256_KEYS in crates/kite-hostd/src/update.rs): P-256, SEC1 uncompressed, hex.
# The zip is installed only when its "signature_p256" (ECDSA P-256 over SHA-256 of the zip's exact bytes, r||s, hex:
# what the hosts' self-updater checks) is good for one of these. The old Ed25519 key is NOT accepted here: Windows
# PowerShell has no Ed25519, and that key is being retired (a plain file, the reason for audit risk #2).
# A key in $RevokedP256 is never trusted, whatever $TrustedP256 says. kite's mac/public-release.sh refuses to publish
# while this list trusts a key the hosts do not, and ./release refuses a zip these keys do not verify.
$TrustedP256 = @(
  '0487ef23fda4a4abf1700f6423d033d8d60415036520562a89aa6dc71675392cee1d890dd30f5d1f1c77c9dd383877c1841e6641b4836219cf968ab734f30062ec'
)
$RevokedP256 = @(
  '04b40e8a42cc0172750c3780f52f09b1e9375d5052b28f6194852c0f78ea90ac3d257f21257df0f16529c612a8930ec6209c73a058e209dfa5f1b2296e319cf916'
)

$root = ''
function Fail([string]$m) { Write-Host ''; Write-Host $m -ForegroundColor Red; Write-Host 'Nothing was installed. Tell Sam.'; exit 1 }
function Drop { if ($script:root -and (Test-Path -LiteralPath $script:root)) { Remove-Item -LiteralPath $script:root -Recurse -Force } }
# Any failed check: the download (zip and signature) is deleted first, then the reason, loudly.
function Refuse([string]$m) {
  try { Drop } catch {}
  if ($script:root -and (Test-Path -LiteralPath $script:root)) { Fail ("REFUSED: $m Could not delete the download at " + $script:root + ': delete it.') }
  Fail "REFUSED: $m The download was deleted."
}

function Get-HexBytes([string]$h) {
  if (-not $h -or $h -notmatch '^(?:[0-9a-fA-F]{2})+\z') { return $null }
  $b = New-Object byte[] ($h.Length / 2)
  for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($h.Substring(2 * $i, 2), 16) }
  return ,$b
}

# Is $sig (r||s, 64 bytes) a good ECDSA P-256 signature by $keyHex over the SHA-256 digest $hash (32 bytes)?
# .NET 4.7+ (every Windows 10/11): ECParameters. Older .NET: the same key as a CNG public blob ("ECS1", X, Y).
function Test-P256Signature([string]$keyHex, [byte[]]$hash, [byte[]]$sig) {
  $k = Get-HexBytes $keyHex
  if ($null -eq $k -or $k.Length -ne 65 -or $k[0] -ne 4 -or $hash.Length -ne 32 -or $sig.Length -ne 64) { return $false }
  $x = New-Object byte[] 32; $y = New-Object byte[] 32
  [Array]::Copy($k, 1, $x, 0, 32); [Array]::Copy($k, 33, $y, 0, 32)
  $ec = $null
  try {
    if ('System.Security.Cryptography.ECParameters' -as [type]) {
      $q = New-Object System.Security.Cryptography.ECPoint
      $q.X = $x; $q.Y = $y
      $p = New-Object System.Security.Cryptography.ECParameters
      $p.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
      $p.Q = $q
      $ec = [System.Security.Cryptography.ECDsa]::Create()
      $ec.ImportParameters($p)
    } else {
      $blob = New-Object byte[] 72
      [Array]::Copy([byte[]](0x45, 0x43, 0x53, 0x31, 0x20, 0, 0, 0), 0, $blob, 0, 8)
      [Array]::Copy($x, 0, $blob, 8, 32); [Array]::Copy($y, 0, $blob, 40, 32)
      $cng = [System.Security.Cryptography.CngKey]::Import($blob, [System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
      $ec = New-Object System.Security.Cryptography.ECDsaCng -ArgumentList (,$cng)
    }
    return [bool]$ec.VerifyHash($hash, $sig)
  } catch { return $false } finally { if ($null -ne $ec) { $ec.Dispose() } }
}

# THE CHECK, before anything is unzipped or run. $zip and $sigPath sit in $root, a folder made for this run alone.
# $want: GitHub's SHA-256 of the zip ('' only in verify mode without one). The zip is read ONCE: the same SHA-256
# digest is compared with GitHub's and is what the P-256 signature must cover.
function Confirm-Takeoff([string]$zip, [string]$sigPath, [string]$want) {
  $fs = [IO.File]::OpenRead($zip)
  try { $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($fs) } finally { $fs.Close() }
  $got = -join ($hash | ForEach-Object { $_.ToString('x2') })
  if ($want) {
    if ($got -ne $want.ToLowerInvariant()) { Refuse "The zip does not match GitHub's fingerprint (expected $want, got $got)." }
    Write-Host "SHA-256 $got matches GitHub."
  }
  if (-not (Test-Path -LiteralPath $sigPath -PathType Leaf)) { Refuse "There is no signature file ($signame) for this zip." }
  if ((Get-Item -LiteralPath $sigPath).Length -gt 4096) { Refuse 'The signature file is too big to be one.' }
  $s = $null
  try { $s = [IO.File]::ReadAllText($sigPath) | ConvertFrom-Json } catch { $s = $null }
  if ($s -isnot [Management.Automation.PSCustomObject]) { Refuse 'The signature file is not readable.' }
  $sigHex = '' + $s.signature_p256
  if (-not $sigHex) {
    if ($s.signature) { Refuse "This zip is signed only with Takeoff's OLD key (Ed25519), which this installer no longer accepts (an older release)." }
    Refuse 'This zip carries no Takeoff signature.'
  }
  $sig = Get-HexBytes $sigHex
  if ($null -eq $sig -or $sig.Length -ne 64) { Refuse 'The P-256 signature is not 64 bytes of hex.' }
  foreach ($k in $RevokedP256) {
    if (Test-P256Signature $k $hash $sig) { Refuse ('This zip is signed by a REVOKED Takeoff key (' + $k.Substring(0, 16) + '...).') }
  }
  foreach ($k in $TrustedP256) {
    if ($RevokedP256 -contains $k) { continue }
    if (Test-P256Signature $k $hash $sig) {
      Write-Host ("Signature checked: signed by Takeoff's key " + $k.Substring(0, 16) + '...')
      return $got
    }
  }
  Refuse "This zip is not signed by Takeoff's key."
}

# VERIFY MODE (tests): a local zip and signature file, copied into a fresh folder and checked exactly as a download is.
if ($VerifyOnly) {
  if (-not $ZipFile -or -not (Test-Path -LiteralPath $ZipFile -PathType Leaf)) { Fail "verify: there is no zip at '$ZipFile'." }
  if ($Sha256 -and $Sha256 -notmatch '^[0-9a-fA-F]{64}\z') { Fail 'verify: the SHA-256 given is not 64 hex digits.' }
  $root = Join-Path $env:TEMP ('TakeoffVerify-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $root | Out-Null
  $zip = Join-Path $root $name
  $sigPath = Join-Path $root $signame
  Copy-Item -LiteralPath $ZipFile -Destination $zip
  if ($SigFile -and (Test-Path -LiteralPath $SigFile -PathType Leaf)) { Copy-Item -LiteralPath $SigFile -Destination $sigPath }
  $got = Confirm-Takeoff $zip $sigPath $Sha256
  Drop
  Write-Host ('VERIFY OK: ' + $got + ' (verify only: nothing unzipped, installed or started)')
  exit 0
}

# A test run sets TAKEOFF_NO_INSTALL: it can only ever stop an install, never start one.
if (-not $CheckOnly -and $env:TAKEOFF_NO_INSTALL) { Fail 'TAKEOFF_NO_INSTALL is set (a test run): nothing downloaded or installed.' }
if ($CheckOnly) { $root = Join-Path $env:TEMP ('TakeoffCheck-' + [guid]::NewGuid().ToString('N')) }
else { $root = Join-Path $env:LOCALAPPDATA 'Kite\download' }
$zip = Join-Path $root $name
$sigPath = Join-Path $root $signame

# 1. Which files, and GitHub's SHA-256 of the zip. GitHub computes this digest itself when the file is uploaded.
Write-Host 'Asking GitHub for the newest Takeoff, its fingerprint and its signature...'
$wc = New-Object Net.WebClient
$wc.Headers.Add('User-Agent', 'Takeoff-installer')
$wc.Headers.Add('Accept', 'application/vnd.github+json')
try { $rel = $wc.DownloadString("https://api.github.com/repos/$repo/releases/latest") | ConvertFrom-Json }
catch { Fail ('Could not ask GitHub: ' + $_.Exception.Message) }
$asset = @($rel.assets | Where-Object { $_.name -eq $name })[0]
if (-not $asset) { Fail ("The newest release (" + $rel.tag_name + ") has no $name.") }
$sigAsset = @($rel.assets | Where-Object { $_.name -eq $signame })[0]
if (-not $sigAsset) { Fail ("REFUSED: the newest release (" + $rel.tag_name + ") has no signature file ($signame), so it was not signed with Takeoff's key. Nothing was downloaded.") }
if (-not ("" + $asset.digest -match '^sha256:([0-9a-f]{64})$')) { Fail "GitHub did not give a SHA-256 for $name." }
$want = $Matches[1]
$url = "" + $asset.browser_download_url
$sigUrl = "" + $sigAsset.browser_download_url
foreach ($u in @($url, $sigUrl)) {
  if (-not $u.StartsWith("https://github.com/$repo/releases/download/")) { Fail "Unexpected download address: $u" }
}

# 2. Download both, then check: GitHub's SHA-256 AND Takeoff's signature, before anything is unzipped.
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
New-Item -ItemType Directory -Path $root | Out-Null
Write-Host ("Downloading Takeoff " + $rel.tag_name + '...')
$dl = New-Object Net.WebClient
$dl.Headers.Add('User-Agent', 'Takeoff-installer')
try { $dl.DownloadFile($sigUrl, $sigPath); $dl.DownloadFile($url, $zip) }
catch { Drop; Fail ('Download failed: ' + $_.Exception.Message) }
$got = Confirm-Takeoff $zip $sigPath $want
Write-Host 'Download checked: GitHub fingerprint and Takeoff signature both good.'
if ($CheckOnly) {
  Drop
  Write-Host ('CHECK OK: ' + $rel.tag_name + ' ' + $got + ' (check only: nothing unzipped or installed)')
  exit 0
}

# 3. Unzip and set up (only ever reached after Confirm-Takeoff).
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
