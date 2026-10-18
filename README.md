# Syria Dynamic Template for DCS World

This repository contains a modular, "living" mission template for the DCS World Syria map. 

To overcome the limitations of tracking binary `.miz` files in Git, the mission structure has been unpacked. This allows for proper version control, collaborative development, and seamless external script management without fighting the DCS Mission Editor (ME).

## Features

* **Living Environment:** Active civilian air traffic, airports, and routes utilizing the Civil Aircraft Mod and Random Air Traffic (RAT) scripts.
* **Populated Infrastructure:** Ugra Media's detailed airbases are populated with guards, patrols, and SAM defenses to fill the otherwise empty static structures.
* **Integrated Skynet IADS:** Seamless integration of Skynet IADS, operating alongside MOOSE and MIST frameworks.
* **Dynamic Scoring:** Built-in operational scoring for Departure/Approach, ROE adherence, and precision strikes. Includes integration of Bankler's CASE I recovery metrics.
* **Lightweight & Modular:** Functions like a dynamic campaign but remains lightweight. Set the date and weather, drop in your specific flight, and launch into an active theater.

## Repository Structure

* `src/`: Contains the unpacked raw mission files (`mission`, `options`, `warehouses`, `dictionary`, etc.). Git tracks the structural changes here. `src/Sounds/` holds the audio packs (ATIS, AIRBOSS, RANGE, General, ... ~22 MB, ~1300 files) that are packed into the `.miz` as-is.
* `scripts/`: Holds all external Lua scripts (MOOSE, Skynet, RAT, custom logic). `scripts/legacy/` holds superseded scripts that the mission no longer references; `build.py` does not embed them.
* `build.py`: Python script used to pack the `src/` directory **and the Lua scripts from `scripts/`** into a playable `.miz` file, and copy it to the DCS Missions folder.
* `extract.py`: the reverse of `build.py`; unpacks a Mission Editor-saved `.miz` into `src/`.
* `dcslua.py`: dependency-free reader/writer for DCS's plain-Lua data files, used by `extract.py` to write them in key order.
* `config.py`: shared settings (Missions folder, `.miz` name).
* `build/`: The output directory for the compiled `.miz` file (ignored by Git).

## Development Workflow

### 1. Building the Mission
Whenever you need to test the mission in DCS or prepare it for a server, run the build script from the root directory:
```bash
python build.py
```
This will generate `Syria_Dynamic_Template.miz` inside the `build/` folder. The build embeds every Lua script that the mission references (`src/l10n/DEFAULT/mapResource`) from `scripts/`, prints each script's header line, and aborts without writing anything if a referenced script is missing.

### 2. Editing the Mission (Mission Editor)
The `.miz` that DCS opens (`config.py`: `Saved Games\DCS\Missions\The Routine Things (With RAT)\Syria_Dynamic_Template.miz`) is the working copy; `src/` is its Git mirror. Syncing is only required **before the next build or commit**, not after every ME save.

1. Edit and save in the Mission Editor as usual.
2. Before the next build/commit, pull the ME changes into the repo:
   ```bash
   python extract.py          # reads the .miz from config.py; or: python extract.py "path\to\file.miz"
   python extract.py -n       # dry-run: only report what would change
   ```
   * Only files with different content are written (size + CRC32), so `git diff` stays clean.
   * Files missing from the `.miz` are deleted from `src/`, but only inside top-level folders/files that the `.miz` contains. If the saved `.miz` has no `Sounds/`, `src/Sounds/` is left untouched.
   * `l10n/DEFAULT/*.lua` copies are skipped (stale by definition; `scripts/` wins).
   * **Key-ordered output:** `mission`, `options`, `warehouses`, `l10n/DEFAULT/dictionary` and `mapResource` are rewritten with table keys sorted. The Mission Editor writes the same data in a different order on every save, which made `git diff` ~16,000 lines for a tiny edit. The data is unchanged: the output is re-parsed and compared with the original (types included) before it is written, and if parsing or that check fails the file is written raw with a `UYARI` line. Array element order is never touched. `--no-normalize` writes the ME output as-is.
   * The first run after this feature was added rewrites those five files once (large one-time diff); commit it on its own.
   * The same comparison is used by the `build.py` copy guard, so an ME save that only reordered tables is not treated as an unextracted change.
   * Safety: an archive without a `mission` entry or with unsafe paths is rejected; deleting more than 50 files needs `--force`.
3. `git status`, commit.
4. `python build.py` rebuilds the `.miz` and copies it to the Missions folder (see 2a).

### 2a. Build output in the Missions folder
`python build.py` writes `build/Syria_Dynamic_Template.miz` and then also copies it to the Missions folder from `config.py` (override with the `DCS_MISSIONS_DIR` environment variable). The copy is **refused** (exit code 2) when the `.miz` already there differs from `src/`, because that means ME edits have not been extracted yet and would be overwritten. Run `python extract.py`, or use `python build.py --force` to overwrite anyway. `--no-deploy` skips the copy. If the Missions folder does not exist, the copy is skipped. If DCS has the file open, the copy fails with exit code 3; close the mission and rebuild.

### 3. Handling Lua Scripts
`scripts/` is the single source of truth. Do not edit the copies inside a `.miz`; they are overwritten on every build.

* **Edit a script:** change it in `scripts/`, then run `python build.py` and use the new `.miz`. A running mission never sees changes until it is rebuilt (no hot reload).
* **Add a script:** in the Mission Editor add a `Do Script File` trigger and pick the file from `scripts/`, save, extract the saved `.miz` over `src/` (this adds its key to `mapResource`), then build.
* **Remove a script:** delete its `Do Script File` action in the Mission Editor and re-extract. Scripts that are not referenced by `mapResource` are not embedded.
* The Mission Editor only runs the scripts in trigger order; the load order requirements noted in each script header still apply.

### 4. Player Slot Convention
* The scenario's "hero" slot is the unit named `Player_01`. The **group name is free** (`CAS-1`, `SEAD-1`, ...); no scoring script depends on it.
* Additional human slots should be named `Player_02` ... `Player_NN`. Bankler's `TrapTraining.lua` grades `Player_01`-`Player_44` per slot; the TRT scoring layer (flags, departure, approach, kill/landing score) follows only the hero.
* To make another unit the hero in a specific `.miz`, add a `Do Script` trigger that runs **before every script load** (including `Carrier_Geometry_v1.lua`, which does not depend on `Core_Scoring.lua`):
```lua
_G.TRT = _G.TRT or {}; _G.TRT.PLAYER_NAME = "Player_03"
```
* Each script logs `Player unit: <name>` when it loads. Check `dcs.log` to confirm all of them resolved the same name.
* Unit names are unique per mission. Renaming a slot to `Player_01` requires renaming the previous holder.
* Legacy, not migrated: `scripts/legacy/CASE-I/II/III_v14.lua`, `CASE_IorII_Departure.lua`, `CASE_III_Departure.lua` still hardcode `Player_01`. They are superseded by `Recovery_Approach.lua` / `Departure.lua`, are not referenced by the mission and are not built. To reuse one, move it back to `scripts/` (`build.py` looks for referenced scripts only directly in `scripts/`).

### 5. AI JTAC Placement Rule
An AI JTAC (a ground group with a `FAC_AttackGroup` task, e.g. `JTAC-1`) lases only targets it can see. Observed in `dcs.log` tests (2026-10): when terrain blocked the line of sight (LOS) from the JTAC to its target group, the JTAC gave coordinates but no laser, said "type-3 in effect", and its comm menu showed `Repeat brief` instead of `IP INBOUND`. After the target was moved to a position with clear LOS, all four test JTACs lased, said "type-2 in effect" and showed `IP INBOUND`.

* **Rule:** the target group must be visible from the JTAC's position over terrain. A 0.4-0.7 m terrain rise on the line was enough to block it at ~190 m. The elevation difference between JTAC and target does not matter by itself, in either direction: a JTAC 3.6 m above its target was blocked by a rise in between, and a JTAC 5.6 m below its target lased with clear terrain in between.
* **Check:** `scripts/JTAC_LOS_Audit.lua` runs once ~15 s after mission start and writes `[JTAC_LOS]` lines to `dcs.log` for every FAC group: `OK`, `MARGINAL` (LOS but clearance < 1 m), `BLOCKED` (warning, with the observer height at which LOS would open), or `SKIP` (group not spawned yet). It only logs; it never moves units. Search `dcs.log` for `JTAC_LOS` after each build or after moving a JTAC or its target.
* **Fix a BLOCKED pair in the Mission Editor:** move the target group or the JTAC to another position and rebuild; re-check the log.
* **Known limits:** the audit uses `land.isVisible` (terrain only) with assumed eye heights of 2.5 m. Whether buildings, trees or vehicles between JTAC and target affect JTAC lasing is **not verified**. The cause-and-effect link above rests on a small number of test pairs; DCS does not document the JTAC detection logic.
* The audit script is wired into the mission start trigger (`mapResource` key `ResKey_Action_312`).

### Scripting Guidelines
**Strict Requirement:** Every Lua script update or creation within this repository must feature the script title and version number as the top comment line. 

Example:
```lua
-- Skynet_IADS_Init | v1.0.4
-- Script logic starts here...
```