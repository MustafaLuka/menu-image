# ============================================================
#  Menu Image Matcher - local backend (no install needed)
#  Serves the web app + the local image library on 127.0.0.1
#  ASCII-only on purpose: Windows PowerShell reads .ps1 as ANSI.
# ============================================================
param([switch]$NoBrowser, [int]$Port = 8770)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $root 'images_dir.txt'

# ---- image library folder ----
# Default: an "images" folder next to the app. Drop your big .zip (or loose
# images) in there. An optional images_dir.txt can point somewhere else.
$imagesDir = $null
if (Test-Path $cfgPath) { $imagesDir = (Get-Content $cfgPath -Raw -Encoding UTF8).Trim() }
if (-not $imagesDir -or -not (Test-Path $imagesDir)) { $imagesDir = Join-Path $root 'images' }
New-Item -ItemType Directory -Force -Path $imagesDir | Out-Null
# folder where Gemini-generated images are saved (also part of the library)
$genDir = Join-Path $imagesDir '_generated'

# ---- image index: loose files on disk + images INSIDE .zip (read directly, no extraction) ----
# Big libraries (e.g. a 13 GB zip with 10k images) are served straight from the
# archive, so nothing is ever unpacked to disk.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:files = @()
$script:zipHandles = @{}

# STABLE ids: each image keeps the same id across re-indexing (so ids saved by the
# browser stay valid even after new images are imported). Index is keyed by a stable
# key (disk path / zip entry path), never by array position.
$script:idMap  = @{}   # stableKey -> id
$script:byId   = @{}   # id -> descriptor
$script:nextId = 0
function Assign-Id($d, $key){
  if ($script:idMap.ContainsKey($key)) { $d.Id = $script:idMap[$key] }
  else { $d.Id = $script:nextId; $script:idMap[$key] = $script:nextId; $script:nextId++ }
  $script:byId[$d.Id] = $d
}
function Refresh-Files {
  $list = New-Object System.Collections.Generic.List[object]
  # loose images sitting directly on disk
  Get-ChildItem -LiteralPath $imagesDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '^\.(jpg|jpeg|png)$' } |
    ForEach-Object {
      $d=[pscustomobject]@{ Name=$_.Name; Source='disk'; Path=$_.FullName; Zip=$null; Entry=$null; Id=$null }
      Assign-Id $d ('disk|'+$_.FullName); [void]$list.Add($d)
    }
  # images inside any .zip (each zip opened once and kept open for fast reads)
  Get-ChildItem -LiteralPath $imagesDir -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue |
    ForEach-Object {
      $zp = $_.FullName
      try {
        if (-not $script:zipHandles.ContainsKey($zp)) { $script:zipHandles[$zp] = [System.IO.Compression.ZipFile]::OpenRead($zp) }
        foreach ($e in $script:zipHandles[$zp].Entries) {
          if ($e.Name -match '\.(jpg|jpeg|png)$') {
            $d=[pscustomobject]@{ Name=$e.Name; Source='zip'; Path=$null; Zip=$zp; Entry=$e.FullName; Id=$null }
            Assign-Id $d ('zip|'+$zp+'|'+$e.FullName); [void]$list.Add($d)
          }
        }
      } catch { Write-Host ("Could not read zip {0}: {1}" -f $_.Name, $_.Exception.Message) -ForegroundColor Red }
    }
  $script:files = $list.ToArray()
}

function Get-FileBytes($f){
  if ($f.Source -eq 'disk') { return [System.IO.File]::ReadAllBytes($f.Path) }
  $entry = $script:zipHandles[$f.Zip].GetEntry($f.Entry)
  $s = $entry.Open(); $ms = New-Object System.IO.MemoryStream
  $s.CopyTo($ms); $s.Close()
  $bytes = $ms.ToArray(); $ms.Dispose()
  return $bytes
}
function Img-Mime($name){
  switch -regex ($name) { '\.png$' {'image/png'} '\.jpe?g$' {'image/jpeg'} default {'application/octet-stream'} }
}

# ---- Gemini image generation (one image per item, saved into _generated) ----
function Gemini-Generate($key,$model,$promptText,$itemName){
  if (-not $model) { $model = 'gemini-2.5-flash-image-preview' }
  $url = "https://generativelanguage.googleapis.com/v1beta/models/$model`:generateContent?key=$key"
  $payload = @{
    contents = @(@{ parts = @(@{ text = $promptText }) })
    generationConfig = @{ responseModalities = @('TEXT','IMAGE') }
  } | ConvertTo-Json -Depth 10
  $resp = Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 180
  $parts = $resp.candidates[0].content.parts
  foreach ($p in $parts) {
    $inline = $null
    if ($p.PSObject.Properties.Name -contains 'inlineData')  { $inline = $p.inlineData }
    elseif ($p.PSObject.Properties.Name -contains 'inline_data') { $inline = $p.inline_data }
    if ($inline -and $inline.data) {
      $imgBytes = [Convert]::FromBase64String($inline.data)
      $mt = "$($inline.mimeType)$($inline.mime_type)"
      $ext = if ($mt -match 'jpe?g') { '.jpg' } else { '.png' }
      $safe = ($itemName -replace '[\\/:*?"<>|]', ' ').Trim()
      if (-not $safe) { $safe = 'image' }
      New-Item -ItemType Directory -Force -Path $genDir | Out-Null
      [System.IO.File]::WriteAllBytes((Join-Path $genDir ($safe + $ext)), $imgBytes)
      return @{ ok=$true; file=($safe + $ext) }
    }
  }
  return @{ ok=$false; error='no image in response (try a different model or check quota)' }
}

$mime = @{
  '.html'='text/html; charset=utf-8'; '.js'='application/javascript; charset=utf-8';
  '.css'='text/css; charset=utf-8'; '.json'='application/json; charset=utf-8';
  '.svg'='image/svg+xml'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.png'='image/png';
  '.webmanifest'='application/manifest+json'; '.ico'='image/x-icon'
}

function Send-Bytes($ctx,$bytes,$type,$status=200){
  $ctx.Response.StatusCode = $status
  $ctx.Response.ContentType = $type
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.KeepAlive = $false
  $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
  $ctx.Response.OutputStream.Flush()
  $ctx.Response.Close()
}
function Send-Text($ctx,$text,$type='text/plain; charset=utf-8',$status=200){
  Send-Bytes $ctx ([System.Text.Encoding]::UTF8.GetBytes($text)) $type $status
}

# try the chosen port first, then fall back to others if the OS reserved it
$listener = $null
foreach ($p in @($Port,8771,8780,8782,8800,8888,8900,9090,9091,8123)) {
  try {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://127.0.0.1:$p/")
    try { $l.Prefixes.Add("http://localhost:$p/") } catch {}
    $l.Start()
    $listener = $l; $Port = $p; break
  } catch { try { $l.Close() } catch {} }
}
if (-not $listener) {
  Write-Host "Could not bind any port (8770-9091 all busy/reserved)." -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}
$rootFull = [System.IO.Path]::GetFullPath($root)
Write-Host "Indexing image library (reading zip directory)..." -ForegroundColor Cyan
Refresh-Files
Write-Host ""
Write-Host ("Server running at  http://127.0.0.1:{0}/" -f $Port) -ForegroundColor Green
Write-Host ("Image library: {0}  ({1} images)" -f $imagesDir, $script:files.Count) -ForegroundColor Green
if ($script:files.Count -eq 0) {
  Write-Host ("TIP: drop your images (or one big .zip) into:  {0}" -f $imagesDir) -ForegroundColor Yellow
}
Write-Host "Close this window to stop the server."
Write-Host ""
if (-not $NoBrowser) { Start-Process "http://127.0.0.1:$Port/" }

while ($listener.IsListening) {
  $ctx = $null
  try {
    $ctx = $listener.GetContext()
    $path = $ctx.Request.Url.AbsolutePath
    if ($path -eq '/') { $path = '/index.html' }

    if ($path -eq '/api/images') {
      Refresh-Files
      $list = foreach ($d in $script:files) { [pscustomobject]@{ id=$d.Id; name=$d.Name } }
      $json = if ($script:files.Count -eq 0) { '[]' }
              elseif ($script:files.Count -eq 1) { '[' + (ConvertTo-Json $list[0] -Compress) + ']' }
              else { ConvertTo-Json $list -Compress }
      Send-Text $ctx $json 'application/json; charset=utf-8'
    }
    elseif ($path -eq '/api/file') {
      $id = -1
      [int]::TryParse($ctx.Request.QueryString['id'], [ref]$id) | Out-Null
      if ($script:byId.ContainsKey($id)) {
        $f = $script:byId[$id]
        Send-Bytes $ctx (Get-FileBytes $f) (Img-Mime $f.Name)
      } else { Send-Text $ctx 'not found' 'text/plain; charset=utf-8' 404 }
    }
    elseif ($path -eq '/api/generate' -and $ctx.Request.HttpMethod -eq 'POST') {
      $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
      $bodyText = $reader.ReadToEnd(); $reader.Close()
      $r = $null
      try {
        $req = $bodyText | ConvertFrom-Json
        $r = Gemini-Generate $req.key $req.model $req.prompt $req.item
      } catch {
        $msg = $_.Exception.Message
        if ($_.Exception.Response) {
          try { $sr=New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg = $sr.ReadToEnd(); $sr.Close() } catch {}
        }
        $r = @{ ok=$false; error=$msg }
      }
      Send-Text $ctx (ConvertTo-Json $r -Compress) 'application/json; charset=utf-8'
    }
    elseif ($path -eq '/api/save' -and $ctx.Request.HttpMethod -eq 'POST') {
      # save an imported image (e.g. downloaded from Gemini) into the library under the item name
      $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
      $bodyText = $reader.ReadToEnd(); $reader.Close()
      $r = $null
      try {
        $req = $bodyText | ConvertFrom-Json
        $ext = ([string]$req.ext).ToLower(); if ($ext -notmatch '^\.(jpg|jpeg|png|webp)$') { $ext = '.png' }
        $safe = ([string]$req.name -replace '[\\/:*?"<>|]', ' ').Trim(); if (-not $safe) { $safe = 'image' }
        $folder = if ($req.folder) { ([string]$req.folder) -replace '[^a-zA-Z0-9_]','' } else { '_added' }
        if (-not $folder) { $folder = '_added' }
        $outDir = Join-Path $imagesDir $folder
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $outDir ($safe + $ext)), [Convert]::FromBase64String($req.b64))
        $r = @{ ok=$true; file=($safe + $ext) }
      } catch { $r = @{ ok=$false; error=$_.Exception.Message } }
      Send-Text $ctx (ConvertTo-Json $r -Compress) 'application/json; charset=utf-8'
    }
    else {
      $rel  = $path.TrimStart('/')
      $full = [System.IO.Path]::GetFullPath((Join-Path $root $rel))
      if ($full.StartsWith($rootFull) -and (Test-Path -LiteralPath $full -PathType Leaf)) {
        $ext  = [System.IO.Path]::GetExtension($full).ToLower()
        $type = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
        Send-Bytes $ctx ([System.IO.File]::ReadAllBytes($full)) $type
      } else { Send-Text $ctx 'not found' 'text/plain; charset=utf-8' 404 }
    }
  } catch {
    if ($ctx) { try { Send-Text $ctx ("error: " + $_.Exception.Message) 'text/plain; charset=utf-8' 500 } catch {} }
  }
}
