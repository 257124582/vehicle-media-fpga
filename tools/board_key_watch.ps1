param([string]$Port='COM5',[int]$TimeoutSeconds=150)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$null=New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'build/hardware')
$serial=New-Object System.IO.Ports.SerialPort $Port,115200,None,8,One
$serial.ReadTimeout=3000;$serial.WriteTimeout=3000;$serial.DtrEnable=$false;$serial.RtsEnable=$false
$records=New-Object System.Collections.Generic.List[object]
$steps=0;$baseline=0
function Send([string]$Text) {
 $serial.DiscardInBuffer();$serial.Write($Text+"`n");$answer=$serial.ReadLine().Trim()
 $records.Add([pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');command=$Text;response=$answer})
 return $answer
}
try {
 $serial.Open()
 foreach($command in @('AUTO 0','TRANSITION 0','MODE 0')){if((Send $command) -ne 'OK'){throw ('Rejected '+$command)}}
 Start-Sleep -Milliseconds 200
 $line=Send 'STATUS';if($line -notmatch '^S:[0-9A-Fa-f]{48}$'){throw 'Invalid STATUS'}
 $baseline=[Convert]::ToByte($line.Substring(6,2),16) -band 3
 Write-Output ('KEY WATCH READY: image='+$baseline+'; press K2, then K3, then K4, at least 2 seconds apart')
 $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
 while([DateTime]::UtcNow -lt $deadline -and $steps -lt 3) {
  Start-Sleep -Milliseconds 200;$line=Send 'STATUS'
  if($line -notmatch '^S:[0-9A-Fa-f]{48}$'){throw 'Invalid STATUS'}
  $flags=[Convert]::ToByte($line.Substring(4,2),16);$packed=[Convert]::ToByte($line.Substring(6,2),16)
  $index=$packed -band 3;$mode=($packed -shr 2) -band 7;$auto=($flags -band 4) -ne 0
  if($steps -eq 0 -and -not $auto -and $index -eq (($baseline+1) -band 3)){$steps=1;Write-Output 'K2 NEXT observed'}
  if($steps -eq 1 -and -not $auto -and $mode -eq 1){$steps=2;Write-Output 'K3 MODE observed'}
  if($steps -eq 2 -and $auto){$steps=3;Write-Output 'K4 AUTO observed'}
 }
} finally {
 if($serial.IsOpen){foreach($command in @('MODE 0','TRANSITION 1','AUTO 1')){try{$null=Send $command}catch{}};$serial.Close()}
 $serial.Dispose()
 $target=Join-Path $taskRoot ('build/hardware/keys_'+[DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')+'.json')
 [pscustomobject]@{passed=($steps -eq 3);observed_steps=$steps;port=$Port;baseline_index=$baseline;records=$records} |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $target -Encoding UTF8
 Write-Output ('Evidence: '+$target)
}
if($steps -eq 3){Write-Output 'BOARD KEYS TEST PASS'}else{Write-Output 'KEY TEST INCOMPLETE: requested physical sequence was not fully observed'}
