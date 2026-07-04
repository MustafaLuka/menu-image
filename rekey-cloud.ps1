# ============================================================
#  Re-key cloud_images to ASCII names (img/<id>.jpg) for reliable
#  cloud serving. Original names stay in index.json (name field).
#  Fast: just moves the already-compressed files (no re-compress).
# ============================================================
param([string]$OutDir="")
$ErrorActionPreference='Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $OutDir){ $OutDir = Join-Path $root 'cloud_images' }
$idxPath = Join-Path $OutDir 'index.json'
if(-not (Test-Path -LiteralPath $idxPath)){ Write-Host "index.json not found in $OutDir" -ForegroundColor Red; exit 1 }

$arr = [System.IO.File]::ReadAllText($idxPath,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
$imgDir = Join-Path $OutDir 'img'
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null

$new = New-Object System.Collections.ArrayList
$i = 0; $moved = 0; $missing = 0
foreach($e in $arr){
  $src = Join-Path $OutDir ($e.file -replace '/','\')
  $dstRel = "img/$i.jpg"
  $dst = Join-Path $imgDir "$i.jpg"
  if(Test-Path -LiteralPath $src){ Move-Item -LiteralPath $src -Destination $dst -Force; $moved++ }
  elseif(Test-Path -LiteralPath $dst){ }  # already moved (re-run)
  else { $missing++ }
  [void]$new.Add([pscustomobject]@{ id=$i; name=$e.name; file=$dstRel })
  $i++
  if($i % 1000 -eq 0){ Write-Host ("  {0} ..." -f $i) }
}
[System.IO.File]::WriteAllText($idxPath, (ConvertTo-Json $new.ToArray() -Compress), (New-Object System.Text.UTF8Encoding($false)))

# remove the now-empty original folders (keep img/ and index.json)
Get-ChildItem -LiteralPath $OutDir -Directory | Where-Object { $_.Name -ne 'img' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ("DONE. {0} files re-keyed to img/<id>.jpg  (missing: {1}). index.json updated (names kept)." -f $moved, $missing) -ForegroundColor Green
