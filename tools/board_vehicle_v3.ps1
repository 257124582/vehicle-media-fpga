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
    $s=Snapshot;Check-Healthy $s
    Set-Command 'EMERGENCY 0'
    Set-Command 'NIGHT 0'
    Set-Command 'VIEW 0'
    Set-Command 'AUTO 0'
    Set-Command 'TRANSITION 0'
    foreach($value in @(1,0)) {
        Set-Command ('NIGHT '+$value);Start-Sleep -Milliseconds 400
        $v=Snapshot 'VEHICLE'
        Check ($v.bytes[0] -eq 163 -and (($v.bytes[1] -band 2) -ne 0) -eq ($value -eq 1)) 'Night state mismatch'
    }
    Set-Command 'STATION 5';Start-Sleep -Milliseconds 60
    $v=Snapshot 'VEHICLE';Check ($v.bytes[2] -eq 5 -and $v.bytes[3] -eq 255) 'Terminal route mismatch'
    Set-Command 'VIEW 1';Start-Sleep -Milliseconds 60
    $v=Snapshot 'VEHICLE';Check (($v.bytes[1] -band 4) -ne 0) 'Technical view mismatch'
    Set-Command 'EMERGENCY 1';Start-Sleep -Milliseconds 60
    $v=Snapshot 'VEHICLE';Check (($v.bytes[1] -band 1) -ne 0 -and $v.bytes[5] -eq 1) 'Emergency not active'
    Check ([Convert]::ToUInt64($v.line.Substring(34,8),16) -lt 2500000) 'Emergency commit exceeded 100ms'
    $s=Snapshot;$index=$s.bytes[2] -band 3
    foreach($c in @('NEXT','AUTO 0','STATION 0','VIEW 0','NIGHT 2','VEHICLE 1')){Check ((Send-Command $c) -eq 'ERR') ('Expected rejection '+$c)}
    $s=Snapshot;Check (($s.bytes[2] -band 3) -eq $index) 'Emergency changed image'
    Set-Command 'EMERGENCY 0';Start-Sleep -Milliseconds 60
    $v=Snapshot 'VEHICLE';Check (($v.bytes[1] -band 1) -eq 0 -and $v.bytes[5] -eq 0) 'Emergency not released'
    $s=Snapshot;Check-Healthy $s
    $passed=$true
} finally {
    if($serial.IsOpen){
        foreach($c in @('EMERGENCY 0','NIGHT 0','VIEW 0','STATION 0','TRANSITION 1','AUTO 1')){try{$null=Send-Command $c}catch{}}
        $serial.Close()
    }
    $serial.Dispose()
    $target=Join-Path $taskRoot ('build/hardware/vehicle_v3_'+[DateTime]::Now.ToString('yyyyMMdd_HHmmss')+'.json')
    [pscustomobject]@{passed=$passed;port=$Port;records=$records;scope='UART states and counters only; actual pixels, audio and physical keys need observation'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Output ('Evidence: '+$target)
}
if(-not $passed){exit 1}
Write-Output 'V3 BOARD PROTOCOL TEST PASS'
