# pilot_banter — the pilot talking to himself (CAS (L) only)

`scripts/Pilot_Banter.lua` (v2.0.0) plays cockpit lines with `outSoundForGroup` (no radio). Not part
of the template build: the clips live here, not in `src/Sounds`.

What he says:

| When | What | Source |
|---|---|---|
| Long legs (outbound, inbound, Marshal holding), every 55–120 s at NORMAL | fuel vs joker / bingo / tank, burn rate, bingo bug vs the card; CP Tiger / tanker / Mother distance, ETE, early / late against the ATO, push time; altitude; system scan (rpm, master caution); scenery (sun elevation, sea / land); daily life; noises | `TRT.TL`, `TRT.CD`, `TRT.CV`, position, cockpit read |
| On station, between attacks | fuel, VUL time left, noises | `TRT.TL.ato.VUL` |
| 35 NM before CP Tiger | fence in: master arm, dispenser, (radar), weapons left, fuel | cockpit read, `TRT.TL.ag` |
| JTAC readback correct | attack checks: master arm, A/G mode, laser, code | `TRT.JC` event `READBACK` |
| Leaving the area | fence out: master arm, laser if armed, weapons left, fuel vs bingo | CD phase |
| JOKER / BINGO / TANK crossed | the call | `TRT.TL` flags |
| Tanker | checks at join (probe, master arm, radar), closure > 15 kt inside 0.5 NM, astern, fuel every 50 s in contact, disconnect, post-tanker (probe, fuel) | `TRT.AAR` session |
| Recovery | holding (fuel, push), commencing (hook, fuel vs tank), Case I/II approach check at 12 NM, landing check on gear-down (wheels, flaps, hook, harness) | CV phases, external model |
| Events (v1.x) | canopy, engines, checks, cat shot, feet dry / wet, contact, good hits, weapon away, missile defeated, CAP splash, threat over, trap / bolter / waveoff, shutdown | |

A line is a chain of clips: header + value + comment ("Fuel check..." / "nine point eight" /
"Joker's..." / "five point nine" / "Good margin."). A radio call that starts mid-line cuts the
rest; a check resumes 2 s after the call ends.

F10 › INFO › **Pilot thoughts** › Off / Quiet / Normal / Chatty.

| File | Role |
|---|---|
| `../../tts/pb_clips.csv` | Lines. `id = <group>_<n>`; a new variant is one row + render, no Lua edit |
| `make_pb_values.py` | Writes `../../tts/pb_values.csv`: one whole-phrase clip per value (fuel 0.0–20.0, thousands, miles, minutes, early / late, percent, burn rate, weapons left, laser code) and the synthesized noises |
| `../../tts/make_clips.py --set pb [--missing]` | Renders `out/Sounds/PB/*.ogg` (cockpit chain) from both CSVs and rewrites the `AUDIO` block of `scripts/Pilot_Banter.lua` |
| `install_pilot_banter.py` | Installs / updates script + clips in a `.miz` in place (backup `BackUps/<name>_before-PB-<ver>.miz`) |

## Render and install

```
python tools/pilot_banter/make_pb_values.py
python tts/make_clips.py --set pb --missing
python tools/pilot_banter/install_pilot_banter.py "<Saved Games>/DCS/Missions/The Routine Things (With RAT)/Close Air Support (L).miz"
```

`--missing` renders only clips without an `.ogg`; drop it after changing the voice or the chain.
Close the mission in DCS / ME first. The installer refuses when the `AUDIO` block and the `.ogg`
files do not match one-to-one, and refreshes every other mapped `.lua` from `scripts/`.

Tuning: `CFG` at the top of `scripts/Pilot_Banter.lua` (`LEVELS`, `ITEMS`, `MOMENTS`, `NOISE_SYNTH`),
then re-run the installer. Voice / chain: `PILOT_IN`, `COCKPIT`, `synth_noise` in `make_clips.py`.

## Cockpit read

The checks read cockpit switches through the export environment (`net.dostring_in("export", …)`,
DCS-BIOS FA-18C argument numbers). Spoken: master arm (49), A/G mode light (48), LTD/R (441),
radar knob (440), dispenser (517), master caution (13), engine rpm, IFEI bingo. If the read fails
three times the checks fall back to mission data (fuel, position, external model: wheels 0/3/5,
flaps 9, hook 25, probe 22). Master arm 1 = ARM is assumed; the first A/G release re-calibrates it.

## Test flight: what to read in dcs.log (`[PB]`)

1. `Pilot_Banter v2.0.0 loaded: … 928 clips in 124 groups …`
2. `cockpit read: available | 49=…` — or `cockpit read failed` ×3 / `cockpit read OFF`.
3. `cockpit (fence in|attack|tanker|sys|fence out) 49=… 441=… 440=…` — compare with the switches in
   the cockpit at that moment. `master arm mapping confirmed|INVERTED` after the first release.
4. `landing check: gear … flaps … hook …` — external-model values at gear-down.
5. `say <moment> (… s) "…" [why / item]`, `cut <moment> at clip i/n (CV|CD|JC|FA|AIRBOSS)`,
   `dropped after … last reason: …`, `overlap: …`.

Unverified in DCS: the export read from the mission environment, LTD/R and master-arm value
meaning, gear args 0/3/5 and flaps 9 on the Hornet, IFEI bingo text, `UTC_OFFSET` 3 for the sun,
how the synthesized noises (`snd_*`) sound. `NOISE_SYNTH = false` removes them from the mix.
