$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'Apps/LumaStudioCross/build/windows/x64/runner/Release'
$output = Join-Path $root 'Deliverables/Release-0.5.0'
$stage = Join-Path $output 'LumaStudio-0.5.0-Windows-x64'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item "$build/*" $stage -Recurse -Force
# Flutter desktop needs the Visual C++ runtime. Bundle the official app-local
# redistributable DLLs so a clean Windows 10/11 installation can start the app.
$vs = & "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe" -latest -property installationPath
$crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC143.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (!$crt) { throw 'Official Visual C++ runtime not found; cannot produce a standalone package' }
Copy-Item "$($crt.FullName)/*.dll" $stage -Force
New-Item -ItemType Directory -Force -Path "$stage/ThirdParty" | Out-Null
Copy-Item "$root/Apps/LumaStudioCross/assets/licenses/*" "$stage/ThirdParty" -Force
Copy-Item "$root/Apps/LumaStudioCross/README.md" "$stage/README.md" -Force
$source = git -C $root rev-parse HEAD
@{version='0.5.0';platform='windows-x64';sourceCommit=$source;runtime='app-local Microsoft VC143 CRT';codeSigning='unsigned';selfTest='Artifacts/windows-release-self-test.json'} | ConvertTo-Json | Set-Content "$stage/BUILD.json" -Encoding utf8
Compress-Archive -Path $stage -DestinationPath "$output/LumaStudio-0.5.0-Windows-x64.zip" -Force
Get-FileHash "$output/LumaStudio-0.5.0-Windows-x64.zip" -Algorithm SHA256
