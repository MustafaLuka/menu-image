# ============================================================
#  Compress the whole image library to <= TargetKB JPEGs and
#  generate index.json — ready to upload to Cloudflare R2.
#  - Keeps ORIGINAL file names (never renamed to hashes).
#  - Keeps the folder/section structure (so same-named images
#    in different sections don't collide).
#  - NO de-duplication: every image is kept, even duplicates.
#  Reads loose images + images inside .zip. ASCII-only (Windows PS).
#
#  Usage:  powershell -ExecutionPolicy Bypass -File compress-library.ps1
#          (optional)  -InputDir <path>  -OutDir <path>  -TargetKB 300  -Max 0
# ============================================================
param([string]$InputDir="", [string]$OutDir="", [int]$TargetKB=300, [int]$Max=0)
$ErrorActionPreference='Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $InputDir){ $InputDir = Join-Path $root 'images' }
if(-not $OutDir){   $OutDir   = Join-Path $root 'cloud_images' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

$target  = $TargetKB*1024
$jpegEnc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }

function Encode-Jpeg($image,[int]$q){
  $eps=New-Object System.Drawing.Imaging.EncoderParameters(1)
  $eps.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[int64]$q)
  $o=New-Object System.IO.MemoryStream; $image.Save($o,$jpegEnc,$eps); $b=$o.ToArray(); $o.Dispose(); return ,$b
}
# compress to <= target: try quality steps, then shrink dimensions (never upscales)
function Compress-Bytes([byte[]]$bytes){
  $ms=New-Object System.IO.MemoryStream(,$bytes)
  $img=[System.Drawing.Image]::FromStream($ms)
  try{
    $w=$img.Width; $h=$img.Height; $scale=1.0; $out=$null
    for($att=0; $att -lt 6; $att++){
      $cw=[Math]::Max(1,[int]($w*$scale)); $ch=[Math]::Max(1,[int]($h*$scale))
      $bmp=New-Object System.Drawing.Bitmap($cw,$ch)
      $g=[System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.Clear([System.Drawing.Color]::White)
      $g.DrawImage($img,0,0,$cw,$ch); $g.Dispose()
      $best=$null
      foreach($q in 90,80,70,60,50,40){ $b=Encode-Jpeg $bmp $q; if($b.Length -le $target){ $best=$b; break } }
      if(-not $best){ $best=Encode-Jpeg $bmp 40 }
      $bmp.Dispose(); $out=$best
      if($out.Length -le $target){ break }
      $scale*=0.8
    }
    return ,$out
  } finally { $img.Dispose(); $ms.Dispose() }
}

$index=New-Object System.Collections.ArrayList
$script:id=0; $script:done=0
# save one image, keeping its name + folder path; only add a numeric suffix on a real file clash
function Add-Image($relPath,[byte[]]$bytes){
  try{
    $c=Compress-Bytes $bytes
    $origName=[System.IO.Path]::GetFileName($relPath)
    $base=[System.IO.Path]::GetFileNameWithoutExtension($relPath)
    $dir=[System.IO.Path]::GetDirectoryName($relPath)
    $dirPrefix=''; if($dir){ $dirPrefix=($dir -replace '\\','/') + '/' }
    $outRel=$dirPrefix + $base + '.jpg'
    $full=Join-Path $OutDir ($outRel -replace '/','\')
    if(Test-Path -LiteralPath $full){
      $i=2
      while($true){ $try=$dirPrefix + $base + " ($i).jpg"; $tf=Join-Path $OutDir ($try -replace '/','\'); if(-not(Test-Path -LiteralPath $tf)){ $outRel=$try; $full=$tf; break }; $i++ }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $full -Parent) | Out-Null
    [System.IO.File]::WriteAllBytes($full,$c)
    [void]$index.Add([pscustomobject]@{ id=$script:id; name=$origName; file=$outRel }); $script:id++
    $script:done++
    if($script:done % 200 -eq 0){ Write-Host ("  processed {0} ..." -f $script:done) }
  } catch { Write-Host ("  skip {0}: {1}" -f $relPath, $_.Exception.Message) -ForegroundColor DarkYellow }
}

Write-Host ("Input : {0}" -f $InputDir)
Write-Host ("Output: {0}  (each <= {1} KB, original names kept, no dedupe)" -f $OutDir, $TargetKB)
Write-Host "Compressing... (one-time, may take a few minutes)"

# loose images on disk (keep path relative to the images folder)
Get-ChildItem -LiteralPath $InputDir -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -match '^\.(jpg|jpeg|png)$' } | ForEach-Object {
    if($Max -gt 0 -and $script:done -ge $Max){ return }
    $rel=$_.FullName.Substring($InputDir.Length).TrimStart('\','/')
    Add-Image $rel ([System.IO.File]::ReadAllBytes($_.FullName))
  }
# images inside .zip files (keep the entry path)
Get-ChildItem -LiteralPath $InputDir -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object {
  $za=[System.IO.Compression.ZipFile]::OpenRead($_.FullName)
  try{
    foreach($e in $za.Entries){
      if($Max -gt 0 -and $script:done -ge $Max){ break }
      if($e.Name -match '\.(jpg|jpeg|png)$'){
        $s=$e.Open(); $mm=New-Object System.IO.MemoryStream; $s.CopyTo($mm); $s.Close()
        Add-Image ($e.FullName) $mm.ToArray(); $mm.Dispose()
      }
    }
  } finally { $za.Dispose() }
}

$json=ConvertTo-Json $index.ToArray() -Compress
[System.IO.File]::WriteAllText((Join-Path $OutDir 'index.json'), $json, (New-Object System.Text.UTF8Encoding($false)))

$outSize=(Get-ChildItem -LiteralPath $OutDir -File -Recurse | Measure-Object Length -Sum).Sum
Write-Host ""
Write-Host ("DONE. {0} images kept (original names, no dedupe)." -f $index.Count) -ForegroundColor Green
Write-Host ("Total size: {0:N0} MB in {1}" -f ($outSize/1MB), $OutDir) -ForegroundColor Green
Write-Host "index.json written. Upload the whole cloud_images folder to R2 (structure preserved)."
