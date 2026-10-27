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
    foreach($pair in @(@('TICKER',1),@('WAVE',2),@('TESTAUDIO',4))) {
        foreach($value in @(0,1)) {
            Set-Command ($pair[0]+' '+$value)
            Start-Sleep -Milliseconds 80
            $d=Snapshot 'DETAIL'
            Check ((($d.bytes[2] -band $pair[1]) -ne 0) -eq ($value -eq 1)) ('Extension flag mismatch: '+$pair[0])
        }
    }
    foreach($command in @('TESTAUDIO 2','TICKER 2','WAVE 2','TESTAUDIO','WAVE','TICKER')) {
        Check ((Send-Command $command) -eq 'ERR') ('Expected ERR: '+$command)
    }
    Set-Command 'VOLUME 8'
    Set-Command 'MODE 0'
    Set-Command 'BRIGHT 0'
    Set-Command 'CONTRAST 256'
    Set-Command 'AUTO 1'
    for($sample=0;$sample -lt 60;$sample++) {
        Start-Sleep -Seconds 1
        $s=Snapshot
        Check-Healthy $s
        if(($sample % 10) -eq 0){Write-Output ('Healthy sample '+$sample+': '+$s.line)}
    }
    $d=Snapshot 'DETAIL'
    Check ($d.line.Substring(34,8) -eq '00000000') 'SDRAM read timeout'
    $passed=$true
} finally {
    if($serial.IsOpen){$serial.Close()}
    $serial.Dispose()
    $target=Join-Path $taskRoot ('build/hardware/extensions_'+[DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')+'.json')
    [pscustomobject]@{passed=$passed;port=$Port;continuous_audio_left_on=$true;bit_sha256=(Get-FileHash -LiteralPath (Join-Path $taskRoot 'build/td/vehicle_media.bit') -Algorithm SHA256).Hash.ToLowerInvariant();records=$records} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Output ('Evidence: '+$target)
}
if($passed){Write-Output 'EXTENSION FLAGS, BOUNDS AND 60 SECOND RUN PASS'}
