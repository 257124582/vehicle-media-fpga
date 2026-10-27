param([string]$Port='COM5')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$null=New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'build/hardware')
$serial=New-Object System.IO.Ports.SerialPort $Port,115200,None,8,One
$serial.ReadTimeout=3000;$serial.WriteTimeout=3000
$serial.DtrEnable=$false;$serial.RtsEnable=$false
$records=New-Object System.Collections.Generic.List[object]
$passed=$false
function Send-Command([string]$Text) {
    $serial.DiscardInBuffer();$serial.Write($Text+"`n")
    $answer=$serial.ReadLine().Trim()
    $records.Add([pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');command=$Text;response=$answer})
    return $answer
}
function Check([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Set-Command([string]$Text) { Check ((Send-Command $Text) -eq 'OK') ('Command rejected: '+$Text) }
function Snapshot([string]$Text='STATUS') {
    $line=Send-Command $Text
    Check ($line -match '^S:[0-9A-Fa-f]{48}$') ('Invalid snapshot: '+$line)
    $bytes=New-Object byte[] 24
    for($i=0;$i -lt 24;$i++){$bytes[$i]=[Convert]::ToByte($line.Substring(2+2*$i,2),16)}
    return [pscustomobject]@{bytes=$bytes;line=$line}
}
function Check-Healthy($Snapshot) {
    $b=$Snapshot.bytes
    Check (($b[1] -band 56) -eq 56 -and ($b[2] -shr 5) -eq 4) 'Four-image load not complete'
    Check ($b[3] -eq 0 -and $b[4] -eq 0 -and $b[5] -eq 0) 'Media/SD/cache error'
    Check ($Snapshot.line.Substring(34,16) -eq '0000000000000000') 'Underflow or HDMI-input violation'
}
try {
    $serial.Open()
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {
        $s=Snapshot
        if(($s.bytes[1] -band 56) -eq 56 -and ($s.bytes[2] -shr 5) -eq 4){break}
        Check ([DateTime]::UtcNow -lt $deadline) 'TF load timed out'
        Start-Sleep -Milliseconds 500
    } while($true)
    Check-Healthy $s
    Set-Command 'AUTO 0';Set-Command 'TRANSITION 0'
    for($mode=0;$mode -le 5;$mode++) {
        Set-Command ('MODE '+$mode);Start-Sleep -Milliseconds 100
        $s=Snapshot;Check-Healthy $s
        Check ((($s.bytes[2] -shr 2) -band 7) -eq $mode) ('MODE readback mismatch: '+$mode)
    }
    foreach($command in @('PERIOD 1','VOLUME 15','COMPARE 1','ADAPTIVE 1','BRIGHT -32','THRESH 90','CONTRAST 384')){Set-Command $command}
    Start-Sleep -Milliseconds 100
    $s=Snapshot;Check-Healthy $s
    Check ($s.bytes[6] -eq 1 -and ($s.bytes[7] -shr 4) -eq 15 -and ($s.bytes[1] -band 3) -eq 3) 'Control flags/period/volume mismatch'
    $d=Snapshot 'DETAIL'
    Check ($d.bytes[6] -eq 90 -and $d.bytes[22] -eq 224) 'Threshold/signed brightness mismatch'
    foreach($command in @('MODE 6','PERIOD 0','VOLUME 16','UNKNOWN')){Check ((Send-Command $command) -eq 'ERR') ('Expected ERR: '+$command)}
    $s=Snapshot
    Check ((($s.bytes[2] -shr 2) -band 7) -eq 5 -and $s.bytes[6] -eq 1 -and ($s.bytes[7] -shr 4) -eq 15) 'Rejected command changed a setting'
    $before=$s.bytes[2] -band 3
    Set-Command 'NEXT';Start-Sleep -Milliseconds 150
    $s=Snapshot;Check-Healthy $s
    Check (($s.bytes[2] -band 3) -eq (($before+1) -band 3)) 'NEXT did not commit at a frame boundary'
    Set-Command 'AUTO 1';$before=$s.bytes[2] -band 3;$changed=$false
    for($sample=0;$sample -lt 12;$sample++) {
        Start-Sleep -Milliseconds 250;$s=Snapshot;Check-Healthy $s
        if(($s.bytes[2] -band 3) -ne $before){$changed=$true}
    }
    Check $changed 'Automatic slideshow did not advance'
    $passed=$true
} finally {
    if($serial.IsOpen) {
        foreach($command in @('AUTO 0','PERIOD 5','MODE 0','THRESH 128','BRIGHT 0','CONTRAST 256','VOLUME 8','COMPARE 0','ADAPTIVE 0','TRANSITION 1','AUTO 1')) {
            try { $null=Send-Command $command } catch { Write-Warning ('Could not restore '+$command) }
        }
        $serial.Close()
    }
    $serial.Dispose()
    $target=Join-Path $taskRoot ('build/hardware/controls_'+[DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')+'.json')
    [pscustomobject]@{passed=$passed;port=$Port;bit_sha256=(Get-FileHash -LiteralPath (Join-Path $taskRoot 'build/td/vehicle_media.bit') -Algorithm SHA256).Hash.ToLowerInvariant();records=$records} |
      ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Output ('Evidence: '+$target)
}
if($passed){Write-Output 'BOARD CONTROL TEST PASS: six modes, parameter readback, bounds, NEXT, automatic slideshow; defaults restored'}
