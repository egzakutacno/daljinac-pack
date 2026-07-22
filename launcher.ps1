param([switch]$Retry)

if (![Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(527) -and !$Retry) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoP -c `$c=irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/launcher.ps1; &([scriptblock]::create(`$c)) -Retry"
} else {
    irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/install.ps1 | iex
}
