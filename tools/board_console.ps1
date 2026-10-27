param([Parameter(Mandatory=$true)][string]$Port,[string]$Command='STATUS',[switch]$SelfTest)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$null=New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'build/hardware')
$serial=New-Object System.IO.Ports.SerialPort $Port,115200,None,8,One
$serial.ReadTimeout=3000
$serial.WriteTimeout=3000
$serial.DtrEnable=$false
$serial.RtsEnable=$false
$records=New-Object System.Collections.Generic.List[object]
function Send-BoardCommand([string]$Text) {
    $serial.DiscardInBuffer()
    $serial.Write($Text+"`n")
    $answer=$serial.ReadLine().Trim()
    $records.Add([PSCustomObject]@{utc=[DateTime]::UtcNow.ToString('o');port=$Port;command=$Text;response=$answer})
    Write-Output $answer
}
try {
    $serial.Open()
    if($SelfTest) {
        $null=Send-BoardCommand 'AUTO 0'
        $null=Send-BoardCommand 'TRANSITION 0'
        for($taskImage=0;$taskImage -lt 4;$taskImage++) {
            Start-Sleep -Milliseconds 250
            Send-BoardCommand 'STATUS'
            $null=Send-BoardCommand 'NEXT'
        }
        $null=Send-BoardCommand 'TRANSITION 1'
        $null=Send-BoardCommand 'AUTO 1'
    } else { Send-BoardCommand $Command }
} finally {
    if($serial.IsOpen){$serial.Close()}
    $serial.Dispose()
    if($records.Count -gt 0) {
        $out=Join-Path $taskRoot 'build/hardware'
        $null=New-Item -ItemType Directory -Path $out -Force
        $target=Join-Path $out ('serial_'+[DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff')+'.json')
        $records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $target -Encoding UTF8
        Write-Host ('Saved '+$target)
    }
}
