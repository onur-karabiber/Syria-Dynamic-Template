# score_cards — picture score cards for CAS (L)

Status: **feasibility test** (v0.1.0). Not used by the template build.

| File | Role |
|---|---|
| `make_cards.py` | Frames + full-canvas digit layers → `out/ScoreCards/`, previews → `out/preview/` (ignored), path-probe images → `out/test/` |
| `make_sfx.py` | Synthesised `reward` / `penalty` / `mission_end` → `out/Sounds/SCORE/*.ogg` (needs ffmpeg) |
| `make_test_miz.py` | Reads a `.miz`, writes `<name>_ScoreCardTest.miz` with the assets and `scripts/Score_Display_Test.lua` |
| `src_art/` | Source card art (Onur) |
| `fonts/` | Black Ops One (used), plus Stardos Stencil, Share Tech Mono, Orbitron — all SIL OFL, licences alongside |

## Layer scheme

Every digit layer has its card frame's exact pixel size; the glyph is pre-placed.
`<set>_<glyph>_<slot>.png`, glyph `0-9 | p (+) | m (−)`, slot `0..6`.
Character *i* (1-based) of a string of length *L* uses slot `2(i−1) − (L−1) + 3`,
so 1–4 characters stay centred with 7 positions per glyph.

Sets: `crt_t` (CRT total, orange), `crt_dp` / `crt_dn` (CRT delta, green / red, under the total), `med_t` (medal total).

## Test run

```
python tools/score_cards/make_test_miz.py "<Saved Games>/DCS/Missions/The Routine Things (With RAT)/Close Air Support (L).miz"
```

In DCS: F10 › Other › INFO › Score card test. Read results from `dcs.log` (`Score_Display_Test |` lines) and what is on screen.

Open questions the test answers: file-name form for `outPicture` (P1–P4), whether several pictures stay on screen together and in call order (S1–S3), whether `clearView=true` also wipes `outText` (S4), VR visibility, alpha, and whether the Mission Editor keeps `ScoreCards/` after a save.
