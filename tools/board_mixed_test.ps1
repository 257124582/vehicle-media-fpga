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
    Set-Command 'AUTO 0'
    Set-Command 'TRANSITION 0'
    Set-Command 'RESCAN'
    Start-Sleep -Milliseconds 500
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    do {
        $s=Snapshot
        if(($s.bytes[1] -band 56) -eq 56 -and ($s.bytes[2] -shr 5) -eq 4){break}
        Check ([DateTime]::UtcNow -lt $deadline) 'Mixed media reload timed out'
        Start-Sleep -Milliseconds 500
    } while($true)
    $expected=@('1F06BC1D','F24BF5EC','AE1D3114','5B2DCB95')
    $seen=@{}
    for($i=0;$i -lt 4;$i++) {
        Start-Sleep -Milliseconds 300
        $s=Snapshot;Check-Healthy $s
        $index=$s.bytes[2] -band 3
        Check ($s.line.Substring(18,8) -eq $expected[$index]) 'Scaled write checksum mismatch'
        Check ($s.line.Substring(26,8) -eq $expected[$index]) 'Scaled read checksum mismatch'
        $seen[$index]=$true
        Write-Output ('Mixed source index '+$index+' verified: '+$expected[$index])
        Set-Command 'NEXT'
    }
    Check ($seen.Count -eq 4) 'Not all four slots observed'
    $d=Snapshot 'DETAIL'
    Check (($d.bytes[3] -band 15) -eq 15) 'Verified slot mask incomplete'
    Check ($d.line.Substring(34,8) -eq '00000000') 'SDRAM timeout'
    Set-Command 'TRANSITION 1'
    Set-Command 'AUTO 1'
    for($i=0;$i -lt 60;$i++) {
        Start-Sleep -Seconds 1
        $s=Snapshot;Check-Healthy $s
        if(($i % 15) -eq 0){Write-Output ('Mixed playback healthy: '+$i+' seconds')}
    }
    $passed=$true
} finally {
    if($serial.IsOpen){
        foreach($c in @('TRANSITION 1','AUTO 1')){try{$null=Send-Command $c}catch{}}
        $serial.Close()
    }
    $serial.Dispose()
    $target=Join-Path $taskRoot ('build/hardware/mixed_'+[DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')+'.json')
    [pscustomobject]@{passed=$passed;port=$Port;bit_sha256=(Get-FileHash -LiteralPath (Join-Path $taskRoot 'build/td/vehicle_media.bit') -Algorithm SHA256).Hash.ToLowerInvariant();records=$records} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Output ('Evidence: '+$target)
}
if($passed){Write-Output 'MIXED SOURCE RESCAN, FOUR CHECKSUMS AND 60 SECOND PLAYBACK PASS'}
