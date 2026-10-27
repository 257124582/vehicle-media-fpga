param()
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$build=Get-Content -LiteralPath (Join-Path $taskRoot 'build/td/result.json') -Raw | ConvertFrom-Json
if (-not $build.bit_generated -or -not $build.timing_passed) { throw 'Build/timing must pass before download' }
foreach ($source in $build.source_sha256.PSObject.Properties) {
    $actualHash=(Get-FileHash -LiteralPath (Join-Path $taskRoot $source.Name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $source.Value) { throw ('Source changed after build: '+$source.Name) }
}
$bit=Join-Path $taskRoot 'build/td/vehicle_media.bit'
$bitHash=(Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash.ToLowerInvariant()
$stage=Join-Path $env:TEMP ('hx4s20_sram_'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $stage
Copy-Item -LiteralPath $bit -Destination (Join-Path $stage 'vehicle_media.bit')
if ((Get-FileHash -LiteralPath (Join-Path $stage 'vehicle_media.bit') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $bitHash) { throw 'Staged bit mismatch' }
$stageForward=$stage.Replace('\','/')
$lines=@('set actual [string trim [read_device_id -total 1 -cable 0]]',
 'if {$actual ne "EG4S20BG256"} {error "Unexpected JTAG device: $actual"}',
 ('download -mode jtag -bit {'+$stageForward+'/vehicle_media.bit} -cable 0'),
 'puts {SRAM_DOWNLOAD_COMMAND_COMPLETED}','exit')
Set-Content -LiteralPath (Join-Path $stage 'download.tcl') -Value $lines -Encoding ascii
$stamp=[DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')
$evidence=Join-Path $taskRoot ('build/hardware/sram_download_'+$stamp+'.log')
$tdCommand=$env:TD_EXE
if (-not $tdCommand) {
    $found=Get-Command td_commands_prompt.exe -ErrorAction SilentlyContinue
    if ($found) { $tdCommand=$found.Source } else { $tdCommand='D:/TD/bin/td_commands_prompt.exe' }
}
if (-not (Test-Path -LiteralPath $tdCommand)) { throw 'Set TD_EXE to the installed td_commands_prompt.exe.' }
$null=New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'build/hardware')
$output=& $tdCommand ($stageForward+'/download.tcl') 2>&1
$output | Set-Content -LiteralPath $evidence -Encoding utf8
$output | Write-Output
if (-not ($output -match 'SRAM_DOWNLOAD_COMMAND_COMPLETED') -or ($output -match 'PRG-[0-9]+ ERROR')) { throw ('SRAM download failed; see '+$evidence) }
Copy-Item -LiteralPath $evidence -Destination (Join-Path $taskRoot 'build/hardware/sram_download.log')
[pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');stage=$stageForward;mode='jtag/SRAM';bit_sha256=$bitHash;log=$evidence} |
 ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskRoot 'build/hardware/sram_download_stage.json') -Encoding utf8
Write-Output ('SRAM bit SHA256: '+$bitHash)
