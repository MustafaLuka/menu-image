# ============================================================
#  Add the deduped "NEW 1" batch to the cloud library staging.
#  Reads the list of relative paths (under images/NEW 1/) to keep,
#  compresses each to <= TargetKB JPEG (same approach as
#  add-to-library.ps1 / compress-library.ps1), assigns sequential
#  ids continuing from the current max in cloud_images/index.json,
#  writes to cloud_images/img/<id>.jpg, and appends {id,name,file}
#  entries. Does NOT upload to R2 - local staging only.
# ============================================================
param(
  [string]$ListFile = "C:\ME\menu-matcher\_dedup_work\keep_list_relpaths.txt",
  [string]$SourceRoot = "C:\ME\menu-matcher\images\NEW 1",
  [string]$OutDir = "C:\ME\menu-matcher\cloud_images",
  [int]$TargetKB = 300
)
$ErrorActionPreference = 'Stop'
$idxPath = Join-Path $OutDir 'index.json'
$imgDir  = Join-Path $OutDir 'img'
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
$target  = $TargetKB * 1024
$jpegEnc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }

# GDI+ (System.Drawing) can't decode webp/some formats - fall back to WPF's BitmapDecoder
# (backed by WIC, which has broader codec support), re-encode to JPEG bytes, then hand that
# to System.Drawing so the rest of the pipeline (resize/quality loop) stays unified.
function Load-AnyImage([byte[]]$bytes) {
  $ms = New-Object System.IO.MemoryStream(,$bytes)
  try {
    return [System.Drawing.Image]::FromStream($ms)
  } catch {
    $ms.Position = 0
    $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create($ms, [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $frame = $decoder.Frames[0]
    $enc = New-Object System.Windows.Media.Imaging.JpegBitmapEncoder
    $enc.QualityLevel = 95
    $enc.Frames.Add($frame)
    $tmp = New-Object System.IO.MemoryStream
    $enc.Save($tmp)
    $tmp.Position = 0
    return [System.Drawing.Image]::FromStream($tmp)
  }
}

function Encode-Jpeg($image, [int]$q) {
  $eps = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $eps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$q)
  $o = New-Object System.IO.MemoryStream
  $image.Save($o, $jpegEnc, $eps)
  $b = $o.ToArray(); $o.Dispose()
  return ,$b
}

function Compress-Bytes([byte[]]$bytes) {
  $img = Load-AnyImage $bytes
  try {
    $w = $img.Width; $h = $img.Height; $scale = 1.0; $out = $null
    for ($att = 0; $att -lt 6; $att++) {
      $cw = [Math]::Max(1, [int]($w * $scale)); $ch = [Math]::Max(1, [int]($h * $scale))
      $bmp = New-Object System.Drawing.Bitmap($cw, $ch)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.Clear([System.Drawing.Color]::White)
      $g.DrawImage($img, 0, 0, $cw, $ch)
      $g.Dispose()
      $best = $null
      foreach ($q in 90,80,70,60,50,40) {
        $b = Encode-Jpeg $bmp $q
        if ($b.Length -le $target) { $best = $b; break }
      }
      if (-not $best) { $best = Encode-Jpeg $bmp 40 }
      $bmp.Dispose()
      $out = $best
      if ($out.Length -le $target) { break }
      $scale *= 0.8
    }
    return ,$out
  } finally { $img.Dispose() }
}

# load existing index (source of truth for next id)
if (-not (Test-Path -LiteralPath $idxPath)) { Write-Host "index.json not found in $OutDir" -ForegroundColor Red; exit 1 }
$existing = [System.IO.File]::ReadAllText($idxPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$nextId = (($existing | Measure-Object id -Maximum).Maximum) + 1
Write-Host ("Starting id: {0}" -f $nextId)

$lines = Get-Content -LiteralPath $ListFile -Encoding UTF8
Write-Host ("Processing {0} images..." -f $lines.Count)

$newEntries = New-Object System.Collections.ArrayList
$added = 0; $skipped = 0
foreach ($rel in $lines) {
  if ([string]::IsNullOrWhiteSpace($rel)) { continue }
  $src = Join-Path $SourceRoot $rel
  if (-not (Test-Path -LiteralPath $src)) { Write-Host ("  MISSING: {0}" -f $rel) -ForegroundColor DarkYellow; $skipped++; continue }
  try {
    $bytes = [System.IO.File]::ReadAllBytes($src)
    $compressed = Compress-Bytes $bytes
    [System.IO.File]::WriteAllBytes((Join-Path $imgDir "$nextId.jpg"), $compressed)
    $baseName = Split-Path -Leaf $rel
    [void]$newEntries.Add([pscustomobject]@{ id = $nextId; name = $baseName; file = "img/$nextId.jpg" })
    $nextId++; $added++
    if ($added % 250 -eq 0) { Write-Host ("  {0} / {1} ..." -f $added, $lines.Count) }
  } catch {
    Write-Host ("  skip {0}: {1}" -f $rel, $_.Exception.Message) -ForegroundColor DarkYellow
    $skipped++
  }
}

# write new entries to a side file for review, and merge into index.json
$newEntriesPath = "C:\ME\menu-matcher\_dedup_work\new_index_entries.json"
[System.IO.File]::WriteAllText($newEntriesPath, (ConvertTo-Json $newEntries.ToArray() -Compress), (New-Object System.Text.UTF8Encoding($false)))

$merged = New-Object System.Collections.ArrayList
foreach ($e in $existing) { [void]$merged.Add([pscustomobject]@{ id = $e.id; name = $e.name; file = $e.file }) }
foreach ($e in $newEntries) { [void]$merged.Add($e) }
[System.IO.File]::WriteAllText($idxPath, (ConvertTo-Json $merged.ToArray() -Compress), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("DONE. Added {0} images (skipped {1}). Library now has {2} total entries." -f $added, $skipped, $merged.Count) -ForegroundColor Green
