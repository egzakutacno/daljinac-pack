# Daljinac Launcher — self-elevates to admin, then runs install.ps1
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoP -c iex(irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/launcher.ps1)"
} else {
    iex(irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/install.ps1)
}
