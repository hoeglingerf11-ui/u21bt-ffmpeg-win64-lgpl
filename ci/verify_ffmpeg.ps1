param([Parameter(Mandatory=$true)][string]$ArtifactRoot)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ArtifactRoot).Path
$runtimeZip = Join-Path $root 'ffmpeg-win64-lgpl-shared-u21bt.zip'
$sourceZip = Join-Path $root 'ffmpeg-win64-lgpl-source-build-u21bt.zip'
if (!(Test-Path -LiteralPath $runtimeZip) -or !(Test-Path -LiteralPath $sourceZip)) { throw 'Runtime or corresponding source/build archive is missing.' }
$unpack = Join-Path $root 'runtime-unpacked'
$source = Join-Path $root 'source-unpacked'
Expand-Archive -LiteralPath $runtimeZip -DestinationPath $unpack -Force
Expand-Archive -LiteralPath $sourceZip -DestinationPath $source -Force
$runtime = Join-Path $unpack 'bin'
$ffmpeg = Join-Path $runtime 'ffmpeg.exe'
$ffprobe = Join-Path $runtime 'ffprobe.exe'
if (!(Test-Path -LiteralPath $ffmpeg) -or !(Test-Path -LiteralPath $ffprobe)) { throw 'Runtime archive is missing ffmpeg.exe or ffprobe.exe.' }

# Resolve each PE import either inside the package or through the Windows system loader.
$importsFile = Get-ChildItem -LiteralPath $source -Filter 'pe-imports.json' -Recurse | Select-Object -First 1
if (!$importsFile) { throw 'Source package has no PE import inventory.' }
$inventory = Get-Content -LiteralPath $importsFile.FullName -Raw | ConvertFrom-Json
$packaged = @{}; Get-ChildItem -LiteralPath $runtime -File | ForEach-Object { $packaged[$_.Name.ToLowerInvariant()] = $true }
$unresolved = @()
foreach ($file in $inventory.files) {
  foreach ($dll in $file.imports) {
    $name = ([string]$dll).ToLowerInvariant()
    if ($packaged.ContainsKey($name) -or $name.StartsWith('api-ms-win-') -or $name.StartsWith('ext-ms-win-')) { continue }
    if (!(Test-Path -LiteralPath (Join-Path "$env:SystemRoot\System32" $name))) { $unresolved += "$($file.file) -> $name" }
  }
}
if ($unresolved.Count) { throw "Unresolved non-system PE imports: $($unresolved -join '; ')" }

$build = (& $ffmpeg -hide_banner -buildconf 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg -buildconf failed.' }
if ($build -match '--enable-gpl|--enable-nonfree|--enable-libx264') { throw 'GPL/nonfree/x264 build flag detected.' }
$encoders = (& $ffmpeg -hide_banner -encoders 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg -encoders failed.' }
foreach ($encoder in @('ffv1','h264_mf','aac')) { if ($encoders -notmatch "\b$([regex]::Escape($encoder))\b") { throw "Required encoder missing: $encoder" } }
$filters = (& $ffmpeg -hide_banner -filters 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg -filters failed.' }
$requiredFilters = @('fps','split','scale','crop','overlay','zoompan','setsar','format','trim','settb','setpts','concat','xfade','atrim','asetpts','adelay','afade','volume','amix','apad','sidechaincompress','alimiter','aresample','anull','asplit')
foreach ($filter in $requiredFilters) { if ($filters -notmatch "\b$([regex]::Escape($filter))\b") { throw "Required filter missing: $filter" } }

$scene = Join-Path $root 'scene-test.mkv'
$movie = Join-Path $root 'movie-test.mp4'
& $ffmpeg -hide_banner -v error -xerror -nostdin -f lavfi -i 'testsrc2=size=320x180:rate=25:duration=2' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=2' -c:v ffv1 -level 3 -coder 1 -context 1 -g 1 -slicecrc 1 -pix_fmt yuv444p -c:a pcm_s16le -y $scene
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $scene)) { throw 'FFV1 intermediate encode failed.' }
& $ffmpeg -hide_banner -v error -xerror -nostdin -i $scene -f null NUL
if ($LASTEXITCODE -ne 0) { throw 'FFV1 intermediate decode failed.' }

$graph = '[0:v][1:v]xfade=transition=fade:duration=0.25:offset=0.75,format=yuv420p[v];[2:a]anull[a]'
& $ffmpeg -hide_banner -v error -xerror -nostdin -i $scene -f lavfi -i 'testsrc=size=320x180:rate=25:duration=1' -i $scene -filter_complex $graph -map '[v]' -map '[a]' -frames:v 44 -t 1.76 -c:v h264_mf -hw_encoding 0 -rate_control quality -quality 100 -scenario archive -b:v 2M -g 50 -bf 0 -c:a aac -b:a 128k -ar 48000 -movflags +faststart -y $movie
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $movie)) { throw 'Media Foundation H.264/AAC MP4 encode failed.' }
& $ffmpeg -hide_banner -v error -xerror -nostdin -i $movie -f null NUL
if ($LASTEXITCODE -ne 0) { throw 'Full MP4 decode check failed.' }
$probe = (& $ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,sample_rate,channels -of json $movie | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'ffprobe metadata check failed.' }
$meta = $probe | ConvertFrom-Json
$video = $meta.streams | Where-Object { $_.codec_name -eq 'h264' } | Select-Object -First 1
$audio = $meta.streams | Where-Object { $_.codec_name -eq 'aac' } | Select-Object -First 1
if (!$video -or !$audio) { throw 'Expected H.264 video and AAC audio streams were not found.' }
if ($video.width -ne 320 -or $video.height -ne 180) { throw 'Unexpected MP4 video dimensions.' }
if ([int]$audio.sample_rate -ne 48000 -or [int]$audio.channels -ne 1) { throw 'Unexpected MP4 audio format.' }
$duration = [double]$meta.format.duration
if ($duration -lt 1.70 -or $duration -gt 1.80) { throw "Unexpected MP4 duration: $duration seconds." }
$report = [ordered]@{
  status = 'PASS'
  test = 'synthetic FFV1 intermediate; Media Foundation H.264/AAC MP4; full decode'
  unresolved_pe_imports = @()
  verified_encoders = @('ffv1','h264_mf','aac')
  verified_filters = $requiredFilters
  ffv1_intermediate_sha256 = (Get-FileHash -LiteralPath $scene -Algorithm SHA256).Hash.ToLowerInvariant()
  mp4_full_decode = 'PASS'
  mp4_duration_seconds = $duration
  streams = $meta.streams
  format = $meta.format
  buildconf = $build.Trim()
  mp4_sha256 = (Get-FileHash -LiteralPath $movie -Algorithm SHA256).Hash.ToLowerInvariant()
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'windows-smoke-report.json' -Encoding utf8
