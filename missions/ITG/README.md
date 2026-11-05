# Into The Grey (ITG)

Deep strike, F/A-18C, Hornet 5-1 (Player_01) + AI wingman Hornet 5-2 (Player_02), CASE III night recovery.
ITG is its own mission (decision Onur 2026-11-05): it is NOT generated from the template and `sync_missions.py`
does not touch it. Scripts are shared with SDT / SEA2STEEL.

    python extract.py --mission ITG        # Missions\Into The Grey\Into The Grey.miz -> missions/ITG/src
    python build.py   --mission ITG        # missions/ITG/src + scripts -> build/Into The Grey.miz (+ deploy)

* `missions/ITG/src/` - unpacked ME data (key-ordered, like `src/`).
* `missions/ITG/scripts/legacy/` - ITG scripts replaced by shared modules in P1 (CASE-III_v20, CASE_III_Departure, ITG Carrier_Geometry_v1, old Moose.lua); not built.
* `missions/ITG/scripts/` - ITG-only scripts and ITG versions of shared names. The build looks here first, then in
  `scripts/`. Migration plan (project doc `claude/itg-s2s-migration-plan-2026-11-05.md`): this folder shrinks as
  ITG moves onto the shared modules (P1).
* Audio / pictures (`*.ogg`, `*.png` in `src/l10n/DEFAULT/`) and the old `Moose.lua` copy are gitignored
  (recordings, music, third-party radio clips; public repo). The build packs them when they are on disk.
* Device shell: set `DCS_ITG_DIR` to the Into The Grey folder when `~` is not the Windows profile.
* P0 check (2026-11-05): `build.py --mission ITG` reproduces the deployed `Into The Grey.miz` entry for entry
  (ME tables compared key-ordered); the SDT build is unchanged.
