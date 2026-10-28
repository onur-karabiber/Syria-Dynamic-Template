# score_cards — picture score cards for CAS (L)

Status: `Score_Display.lua` v1.0.0 installed in CAS (L) only. Not used by the template build.
Test kit moved to legacy 2026-10-28 (`scripts/legacy/Score_Display_Test.lua`, `tools/score_cards/legacy/make_test_miz.py`); test .miz copies deleted.

| File | Role |
|---|---|
| `make_cards.py` | Frames + full-canvas digit layers → `out/ScoreCards/`, previews → `out/preview/` (ignored), path-probe images → `out/test/` |
| `make_sfx.py` | Synthesised `reward` / `penalty` / `mission_end` → `out/Sounds/SCORE/*.ogg` (needs ffmpeg) |
| `install_score_display.py` | Installs/updates `scripts/Score_Display.lua` + assets in a `.miz` in place (backup to `BackUps/<name>_before-SD-<ver>.miz`) |
| `legacy/make_test_miz.py` | (legacy) Reads a `.miz`, writes `<name>_ScoreCardTest.miz` with the assets and `scripts/legacy/Score_Display_Test.lua` |
| `src_art/` | Source card art (Onur) |
| `fonts/` | Black Ops One (used), plus Stardos Stencil, Share Tech Mono, Orbitron — all SIL OFL, licences alongside |

## Layer scheme

Every digit layer has its card frame's exact pixel size; the glyph is pre-placed.
`<set>_<glyph>_<slot>.png`, glyph `0-9 | p (+) | m (−)`, slot `0..6`.
Character *i* (1-based) of a string of length *L* uses slot `2(i−1) − (L−1) + 3`,
so 1–4 characters stay centred with 7 positions per glyph.

Sets: `crt_t` (CRT total, orange), `crt_dp` / `crt_dn` (CRT delta, green / red, under the total), `med_t` (medal total).

## Install / update (CAS (L))

```
python tools/score_cards/install_score_display.py "<Saved Games>/DCS/Missions/The Routine Things (With RAT)/Close Air Support (L).miz"
```

Close the mission in DCS / ME first. Placement, sizes, durations: `CFG` at the top of `scripts/Score_Display.lua`, then re-run the installer.

## Verified mechanics (2026-10-27)

- `trigger.action.outPicture*` does not exist; pictures go through `net.dostring_in("mission", 'a_out_picture_s(...)')`.
- Paths: `ScoreCards/x.png` and `l10n/DEFAULT/x.png` resolve, bare `x.png` does not.
- Same-size layers overlay exactly; later calls draw on top.
- `ScoreCards/` and `Sounds/SCORE/` survive a Mission Editor save.

## Test run

```
python tools/score_cards/legacy/make_test_miz.py "<Saved Games>/DCS/Missions/The Routine Things (With RAT)/Close Air Support (L).miz"
```

In DCS: F10 › Other › INFO › Score card test. Read results from `dcs.log` (`Score_Display_Test |` lines) and what is on screen.

Open questions the test answers: file-name form for `outPicture` (P1–P4), whether several pictures stay on screen together and in call order (S1–S3), whether `clearView=true` also wipes `outText` (S4), VR visibility, alpha, and whether the Mission Editor keeps `ScoreCards/` after a save.
