# Proposal: vps-rebuild / chg-004 — a sign-in page for practice.vawagners.cloud

**Trigger:** Andrew wants to practise on the iPad inside a "Web MIDI" iOS app. Its WKWebView has no
authentication delegate, so it never shows the Basic prompt and renders the empty 401 as a blank page
(practice slice 05, `ipad-webmidi/FINDINGS.md` §1). Andrew chose Option A, a sign-in page and cookie in Caddy
(2026-11-08 16:53Z). An approved capability change, not a defect.

**Summary:** The practice site block gains a public `GET /signin` form and a `POST /signin/check` that sits
behind the existing `basic_auth`: the form sends the typed credentials as that request's `Authorization`, so
they are checked by the same bcrypt hash; only on success does Caddy set an HttpOnly, Secure, SameSite=Lax
cookie whose value is a new 64-hex `PRACTICE_SESSION_SECRET` from the same env file. A request carrying that
exact cookie, or passing basic auth, reaches the app; neither credential reaches it. Anything else still gets
401 + `WWW-Authenticate`, so Safari and Chrome are unchanged; the 401 body now sends a web view to `/signin`.
No practice app change.

## Blast radius
- Requirements affected: AC-14 (the practice block is no longer only `basic_auth` in front of everything;
  the user and hash are unchanged), AC-8 (one more secret name), AC-9/AC-16 (README). New AC-17.
- product-global (main-branch-only, NOT edited here): the hostname invariant names practice as "Caddy basic
  auth, then proxy to practice:8770". The target is unchanged; the auth wording needs a mainline patch (od-3).
- Design decisions: D9 (practice) gains a second way in for the same user. No decision reversed.
- Already-built code: `caddy/Caddyfile` (practice block only), new `caddy/practice-signin/signin.html`,
  `compose.yaml` (one read-only caddy mount; env_file comment), `scripts/practice-auth.sh` (writes the secret;
  `--session-secret`, `--rotate-session-secret`), `scripts/verify.sh`, `README.md`. Every other site block and
  service resolves identically.
- Live effects when applied (hs-5): one new line in `/srv/secrets/practice-auth.env`; caddy recreated by
  `docker compose up -d caddy`, interrupting every site for a few seconds.

## Risks accepted
- One shared secret: no per-device sign-out; rotating it signs every device out.
- The cookie lives a year; anyone who copies it from a signed-in device has access until rotation.
- Sign-in has no lockout or rate limit, exactly like basic auth today (the password is ≥ 16 characters).

## Status
- [x] implemented & verified offline (verify.sh) and in a local caddy:2 v2.11.4 rehearsal of the real block
      (practice slice 05 `ipad-webmidi/signin-millwright/BUILD.md`)
- [ ] independent review (review-r2)
- [ ] mainline product-global wording (od-3)
- [ ] folded into the feature's spec.md (after review)
- [ ] live: needs Andrew's explicit approval (hs-5)
