# Palpatine Soundboard

Static HTML/CSS/vanilla JS soundboard. No framework, no build step, no auth, no DB.

## Get it onto T-BRUH and run it

In PowerShell on the Windows machine:

```powershell
git clone --depth 1 -b claude/palpatine-soundboard-app-6173f1 `
  https://github.com/ligunn/SpotiFLAC-Module-Version "$env:TEMP\pb"
New-Item -ItemType Directory -Force C:\Users\liamg\_PROJECTS | Out-Null
Copy-Item "$env:TEMP\pb\palpatine-soundboard" C:\Users\liamg\_PROJECTS\ -Recurse -Force
Remove-Item "$env:TEMP\pb" -Recurse -Force
cd C:\Users\liamg\_PROJECTS\palpatine-soundboard
powershell -ExecutionPolicy Bypass -File .\start.ps1
```

`start.ps1` prints the exact URL to open on the phone. It starts the file server
as a detached hidden process, so it survives the terminal closing, then publishes
it with `tailscale serve` (trying HTTPS first, then plain HTTP if the tailnet has
no HTTPS certs enabled).

If `tailscale serve` isn't available in this Tailscale version, run the fallback
in an **Administrator** PowerShell -- it binds all interfaces and adds a firewall
rule for the port:

```powershell
powershell -ExecutionPolicy Bypass -File .\start.ps1 -Direct
# then open http://100.120.230.53:8080/
```

Stop everything: `powershell -ExecutionPolicy Bypass -File .\stop.ps1`

## Adding the real clips

Drop MP3s into `audio\` and make the filenames match `sounds.json`:

```json
{ "label": "Do it.", "file": "audio/do-it.mp3" }
```

Edit `sounds.json` to add, remove, reorder or rename -- no code changes needed.
Any entry whose file is missing renders as a greyed-out, disabled button marked
`(no clip)` instead of failing on tap; the count of missing clips shows at the
bottom of the screen. Reload the page after adding files.

The grid is 2 columns tall enough to fit 12 buttons on an iPhone screen without
scrolling. Adding entries past 12 will start to require scrolling.

## Files

| File | Purpose |
| --- | --- |
| `index.html` / `styles.css` / `app.js` | The app |
| `sounds.json` | label -> filename map |
| `audio/` | Your MP3s |
| `serve.ps1` | Static file server (HEAD + byte ranges, which iOS Safari needs for audio) |
| `start.ps1` | Starts the server and publishes it on the tailnet |
| `stop.ps1` | Stops the server and resets `tailscale serve` |
