# ============================================================
#  Add NEW images to the cloud library (incremental — does NOT
#  re-process the whole library). Put the team's new images in
#  the "incoming" folder, then run this. It compresses them to
#  <= TargetKB, gives new ids, appends to index.json, and uploads
#  the new files + index.json to R2. ASCII-only.
#
#  Usage:  powershell -ExecutionPolicy Bypass -File add-to-library.ps1
#          (optional)  -IncomingDir <path>  -TargetKB 300  -NoUpload
# ============================================================
param([string]$IncomingDir="", [string]$OutDir="", [int]$TargetKB=300, [switch]$NoUpload)
$ErrorActionPreference='Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $IncomingDir){ $IncomingDir = Join-Path $root 'incoming' }
if(-not $OutDir){      $OutDir      = Join-Path $root 'cloud_images' }
$idxPath = Join-Path $OutDir 'index.json'
$imgDir  = Join-Path $OutDir 'img'
New-Item -ItemType Directory -Force -Path $IncomingDir | Out-Null
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
$target  = $TargetKB*1024
$jpegEnc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
function Encode-Jpeg($image,[int]$q){ $eps=New-Object System.Drawing.Imaging.EncoderParameters(1); $eps.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[int64]$q); $o=New-Object System.IO.MemoryStream; $image.Save($o,$jpegEnc,$eps); $b=$o.ToArray(); $o.Dispose(); return ,$b }
function Compress-Bytes([byte[]]$bytes){
  $ms=New-Object System.IO.MemoryStream(,$bytes); $img=[System.Drawing.Image]::FromStream($ms)
  try{
    $w=$img.Width; $h=$img.Height; $scale=1.0; $out=$null
    for($att=0;$att -lt 6;$att++){
      $cw=[Math]::Max(1,[int]($w*$scale)); $ch=[Math]::Max(1,[int]($h*$scale))
      $bmp=New-Object System.Drawing.Bitmap($cw,$ch); $g=[System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $g.Clear([System.Drawing.Color]::White); $g.DrawImage($img,0,0,$cw,$ch); $g.Dispose()
      $best=$null; foreach($q in 90,80,70,60,50,40){ $b=Encode-Jpeg $bmp $q; if($b.Length -le $target){ $best=$b; break } }
      if(-not $best){ $best=Encode-Jpeg $bmp 40 }
      $bmp.Dispose(); $out=$best; if($out.Length -le $target){ break }; $scale*=0.8
    }
    return ,$out
  } finally { $img.Dispose(); $ms.Dispose() }
}

# load existing index (source of truth for ids)
if(-not (Test-Path -LiteralPath $idxPath)){ Write-Host "index.json not found in $OutDir. Run compress-library + rekey first." -ForegroundColor Red; exit 1 }
$existing = [System.IO.File]::ReadAllText($idxPath,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
$list = New-Object System.Collections.ArrayList
foreach($e in $existing){ [void]$list.Add([pscustomobject]@{ id=$e.id; name=$e.name; file=$e.file }) }
$nextId = 0; if($list.Count){ $nextId = (($list | Measure-Object id -Maximum).Maximum + 1) }

# gather new images from incoming (loose + zips)
$new = New-Object System.Collections.ArrayList
Get-ChildItem -LiteralPath $IncomingDir -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -match '^\.(jpg|jpeg|png)$' } |
  ForEach-Object { [void]$new.Add(@{ name=$_.Name; bytes=[System.IO.File]::ReadAllBytes($_.FullName) }) }
Get-ChildItem -LiteralPath $IncomingDir -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object {
  $za=[System.IO.Compression.ZipFile]::OpenRead($_.FullName)
  try{ foreach($en in $za.Entries){ if($en.Name -match '\.(jpg|jpeg|png)$'){ $s=$en.Open(); $mm=New-Object System.IO.MemoryStream; $s.CopyTo($mm); $s.Close(); [void]$new.Add(@{ name=$en.Name; bytes=$mm.ToArray() }); $mm.Dispose() } } } finally { $za.Dispose() }
}

if($new.Count -eq 0){ Write-Host "No new images in $IncomingDir. Put the team's images there and re-run." -ForegroundColor Yellow; exit 0 }
Write-Host ("Found {0} new image(s). Compressing + adding (starting id {1})..." -f $new.Count, $nextId)

$added=0
foreach($n in $new){
  try{
    $c=Compress-Bytes $n.bytes
    [System.IO.File]::WriteAllBytes((Join-Path $imgDir "$nextId.jpg"), $c)
    [void]$list.Add([pscustomobject]@{ id=$nextId; name=$n.name; file="img/$nextId.jpg" })
    $nextId++; $added++
    if($added % 100 -eq 0){ Write-Host ("  {0} ..." -f $added) }
  } catch { Write-Host ("  skip {0}: {1}" -f $n.name, $_.Exception.Message) -ForegroundColor DarkYellow }
}
[System.IO.File]::WriteAllText($idxPath, (ConvertTo-Json $list.ToArray() -Compress), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("Added {0} images. Library now has {1} total." -f $added, $list.Count) -ForegroundColor Green

# archive the processed incoming files so they aren't added again
$done = Join-Path $root ("incoming_done_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $done | Out-Null
Get-ChildItem -LiteralPath $IncomingDir -Force | Move-Item -Destination $done -Force -ErrorAction SilentlyContinue

# upload new files + updated index.json to R2 (rclone skips already-uploaded ones)
if($NoUpload){ Write-Host "Skipped upload (-NoUpload)." -ForegroundColor Yellow; exit 0 }
Write-Host "Uploading new images + index.json to R2..."
& rclone copy "$OutDir" "r2:menu-images" --transfers=16 --progress
Write-Host "DONE. New images are live for the whole team." -ForegroundColor Green
