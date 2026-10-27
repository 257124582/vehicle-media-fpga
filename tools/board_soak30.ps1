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
$stamp=[DateTime]::Now.ToString('yyyyMMdd_HHmmss')
$logPath=Join-Path $taskRoot ('build/hardware/soak30_'+$stamp+'.jsonl')
$resultPath=Join-Path $taskRoot ('build/hardware/soak30_'+$stamp+'.json')
$watch=[Diagnostics.Stopwatch]::new()
$samples=0;$failure=$null;$baseline=$null;$last=$null;$previousFrames=$null
function U32($s,[int]$offset){return [Convert]::ToUInt64($s.line.Substring(2+2*$offset,8),16)}
try {
    $serial.Open()
    foreach($c in @('AUTO 1','TRANSITION 1','PERIOD 5')){Set-Command $c}
    $watch.Start()
    do {
        $s=Snapshot 'STATUS';$d=Snapshot 'DETAIL'
        Check ($s.bytes[0] -eq 161 -and $d.bytes[0] -eq 162) 'Unexpected firmware schema'
        $current=[pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');elapsed_seconds=[math]::Round($watch.Elapsed.TotalSeconds,3);underflows=(U32 $s 16);read_timeouts=(U32 $d 16);hdmi_violations=(U32 $s 20);frames=(U32 $d 8);image_index=($s.bytes[2] -band 3);status=$s.line;detail=$d.line}
        $current | ConvertTo-Json -Compress | Add-Content -LiteralPath $logPath -Encoding UTF8
        $samples++;$last=$current
        if($null -eq $baseline){$baseline=$current}
        Check-Healthy $s
        Check ($current.read_timeouts -eq 0) 'SDRAM read timeout nonzero'
        Check (($s.bytes[1] -band 4) -ne 0 -and ($d.bytes[5] -band 32) -ne 0) 'Autoplay or transition disabled'
        Check (($d.bytes[3] -band 15) -eq 15) 'Verified slot mask lost'
        Check ($current.underflows -eq $baseline.underflows -and $current.read_timeouts -eq $baseline.read_timeouts -and $current.hdmi_violations -eq $baseline.hdmi_violations) 'Error counters changed'
        if($null -ne $previousFrames){Check ($current.frames -gt $previousFrames) 'Frame counter stopped or reset'}
        $previousFrames=$current.frames
        if(($samples % 6) -eq 1 -or $watch.Elapsed.TotalSeconds -ge 1800){Write-Output ('SOAK '+[math]::Round($watch.Elapsed.TotalSeconds,1)+'s; samples='+$samples+'; errors='+$current.underflows+'/'+$current.read_timeouts+'/'+$current.hdmi_violations)}
        if($watch.Elapsed.TotalSeconds -ge 1800){break}
        Start-Sleep -Seconds 5
    } while($true)
    $passed=$true
} catch {
    $failure=$_.Exception.Message
    Write-Output ('SOAK FAILED: '+$failure)
} finally {
    $watch.Stop()
    if($serial.IsOpen){$serial.Close()};$serial.Dispose()
    [pscustomobject]@{passed=$passed;port=$Port;duration_seconds=$watch.Elapsed.TotalSeconds;samples=$samples;failure=$failure;baseline=$baseline;last=$last;raw_log=$logPath;expected_bit_sha256=(Get-FileHash (Join-Path $taskRoot 'build/td/vehicle_media.bit')).Hash.ToLowerInvariant();note='No reset or download performed by this test; STATUS and DETAIL sampled every 5 seconds.'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Output ('RESULT: '+$resultPath)
}
if(-not $passed){exit 1}
