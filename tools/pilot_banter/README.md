# pilot_banter — the pilot talking to himself (CAS (L) only)

`scripts/Pilot_Banter.lua` plays short cockpit lines (outSoundForGroup, no radio) at a few
moments of the sortie: canopy closed, engines up, checks done, cat shot, feet dry / wet,
tanker contact, JTAC target destroyed, threat over, trap by LSO grade, bolter / waveoff,
canopy opened after the trap, shutdown. 3–6 variants per moment, shuffle bag (no repeats
until every variant has played), a probability per moment. Not part of the template build:
the clips live here, not in `src/Sounds`.

| File | Role |
|---|---|
| `../../tts/pb_clips.csv` | Lines. `id = <moment>_<n>`; a new variant is one line + re-render, no Lua edit |
| `../../tts/make_clips.py --set pb` | Renders `out/Sounds/PB/*.ogg` (cockpit chain, voice = pilot readback voice at natural speed) and rewrites the `AUDIO` block of `scripts/Pilot_Banter.lua` between its markers |
| `install_pilot_banter.py` | Installs / updates script + clips in a `.miz` in place (backup `BackUps/<name>_before-PB-<ver>.miz`) |

## Render and install

```
python tts/make_clips.py --set pb
python tools/pilot_banter/install_pilot_banter.py "<Saved Games>/DCS/Missions/The Routine Things (With RAT)/Close Air Support (L).miz"
```

Close the mission in DCS / ME first. The installer refuses when the `AUDIO` block and the
`.ogg` files do not match one-to-one. Like `install_score_display.py`, it also refreshes every
other mapped `.lua` from `scripts/`; either installer keeps the other's assets.

Tuning (probabilities, gaps, silent phases): `CFG` at the top of `scripts/Pilot_Banter.lua`,
then re-run the installer. Voice / sound chain: `PILOT_IN` and `COCKPIT` in `make_clips.py`.

## Test flight: what to read in dcs.log (`[PB]`)

1. `Pilot_Banter v… loaded: … 66 clips, 16/16 moments with clips, seed …`
2. `canopy arg 38 first read …` and every `canopy open -> shut` line: confirms the arg and its direction.
3. `say <id> …` per line; `silent by roll`, `cooldown`, `dropped after … last reason: …` for the rest.
4. `overlap: CV|CD|AIRBOSS started during <id>`: radio call started on top of a line. Count these.
5. `LSO grade … -> <moment>`: grade string and timing of the AIRBOSS debrief relative to the trap / bolter.

Unverified in DCS: outSoundForGroup path form `Sounds/PB/x.ogg` (same form plays via
outSoundForCoalition in Score_Display), its volume / mixer channel, arg 38 direction,
S_EVENT_REFUELING for the hero, AIRBOSS debrief delay after a bolter.
