# Delta: vps-rebuild / chg-005: practice-convert

## ADDED
- **AC-18.** `compose.yaml` defines `practice-convert`, built from `/opt/practice/app/convert` (container name
  `practice-convert`, `restart: unless-stopped`), with:
  - `network_mode: none`, and no networks, ports or expose;
  - `read_only: true`, `cap_drop: [ALL]`, `no-new-privileges`;
  - `mem_limit` 1536m, with `memswap_limit` equal to it;
  - `cpus` 1.0, `pids_limit` 64, and a `/tmp` tmpfs;
  - no env file or environment;
  - exactly two mounts: `practice-convert-in` at `/spool/in` (read-only) and `practice-convert-out` at
    `/spool/out`.

  `practice` mounts the same two volumes at `PRACTICE_CONVERT_IN` and `PRACTICE_CONVERT_OUT`, and its image
  makes those mount points world-writable. No other service mounts them. README has a "Converter (chg-005)"
  section.

## MODIFIED
- **AC-4.** Was: five services. Now: six, adding practice-convert. Still only caddy maps a port.
- **AC-13.** The practice service's one data volume is still `practice-data`. The spool volumes are excluded
  from that check and covered by AC-18.
- **AC-9.** Runbook step 8 notes that the build downloads the pinned MuseScore AppImage.

## REMOVED
- Nothing.
