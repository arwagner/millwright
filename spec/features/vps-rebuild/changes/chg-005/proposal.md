# Proposal: vps-rebuild / chg-005: practice-convert, MuseScore for uploaded scores

**Trigger:** practice slice 11 (practice sets). Andrew wants to add a set of `.mscz` scores from the browser or iPad alone, with no laptop step (approved 2026-11-08 19:39Z). The box has no MuseScore, so a converter service turns uploads into MusicXML.

The approach was decided by spike S0:
- **Parity:** 1133 of 1134 sources give the same `musical_hash` as the laptop.
- **The one miss:** a MuseScore 4.4-format file, which the app now refuses up front.
- **Cost:** peak memory ~130 MB; about 3 s per 300-piece book.

## Summary

- **New service `practice-convert`.** It is built from the practice repo's `convert/` (delivered by its `deploy/deploy.sh` to `/opt/practice/app/convert`).
  - **Image:** MuseScore Studio 4.6.5 from the official AppImage, pinned by sha256 and checked at build.
  - **Isolation:** no network at all, read-only root, non-root, no capabilities, 1.5 GB with no swap, 1 CPU, 64 processes.
- **Spool:** two new named volumes shared with `practice` only. Jobs go in read-only for the converter; answers come out.
- **`practice`** gains:
  - the two mounts;
  - `PRACTICE_CONVERT_IN` and `PRACTICE_CONVERT_OUT`;
  - world-writable mount points in its image, so a fresh volume works whichever container mounts it first.

## Blast radius

- **Requirements:**
  - AC-4: six services.
  - AC-13: the practice volume check ignores the spool volumes.
  - AC-9: runbook step 8 notes the build download.
  - New AC-18.
- **product-global (main-branch-only, NOT edited here):** the service list gains practice-convert. No hostname, DNS or backup change, since the spool holds only transient jobs.
- **Live effects when applied (hs-6):**
  - `practice` is rebuilt with new mounts and env;
  - a new container and two volumes;
  - the build downloads ~180 MB from GitHub on the box;
  - the image is ~0.8 GB on disk.
- **Other services:** caddy, todo and myron are unchanged.

## Risks accepted

- MuseScore parses files from the internet. Mitigated by the box above; only Andrew can upload (sign-in).
- Formats newer than 4.60 are refused until the converter is upgraded deliberately (a new S0-style parity run).

## Status

- [x] implemented and verified offline (verify.sh), with a container rehearsal of the spool permissions (practice slice 11 `11b2/BUILD.md`)
- [ ] independent review (slice 11 wave review, with a security pass)
- [ ] mainline product-global service list
- [ ] live: Andrew's approval (hs-6), together with the practice wave
