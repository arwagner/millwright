# Constitution — millwright

## Mission
Capture the configuration of the Hostinger VPS srv1491903 as code, so a rebuild of the box is a
repeatable procedure: disaster recovery first, reproducibility second, cheap new services third.

## Non-negotiables
- The repository is public. No secret, token, key, or state file is ever committed. Secrets live in
  Dropbox and are copied to `/srv/secrets/` on the box; Terraform state lives in Dropbox outside the
  repository via a gitignored `backend.hcl`.
- Terraform never manages the `hostinger_vps` subscription resource. The subscription stays under
  manual control in the Hostinger panel; rebuilds use the free `recreate` API endpoint, which keeps
  the IP address.
- The Hostinger Terraform provider is pinned exactly to `= 0.1.22`. Version bumps are a deliberate,
  reviewed change, never automatic.
- Steps that touch the live box or live DNS (deleting panel DNS records, `terraform apply`, cutover,
  rebuild) require an explicit go-ahead from Andrew first. Authoring files never does.

## Tech & architecture defaults
- Languages / frameworks: Terraform (HCL) for DNS, SSH key, and post-install script; bash for
  `bootstrap.sh` and `scripts/`; Docker Compose for everything that runs on the box.
- Architecture style: one public repo (millwright) holds all box configuration. The blank box clones
  it with no credentials. Dockerfiles live inline in `compose.yaml` (`dockerfile_inline`). Images
  build on the VPS from source the laptop delivers (rsync for myron, git push for todo).
- Data & integration defaults: Caddy is the single web entry point — TLS (ACME built in), reverse
  proxy, and static file serving. Ubuntu 24.04 host. Nightly laptop-side backups into Dropbox.

## Security & compliance
- Secrets are delivered as env files, never baked into images, never on process command lines
  (the current `TODO_TOKEN`-in-`ps` exposure must not survive the rebuild).
- Only Caddy (80/443) and SSH are reachable from the internet; every other service binds locally or
  is reachable only through Caddy or `docker exec`.
- Rotate the litellm master key even though the service is retired to cold storage.

## Quality bar
- Testing expectation: prototype — no test suite. The verification that matters is one real,
  deliberate rebuild run soon after the code exists (an untested rebuild is not a rebuild).
- Accessibility / performance / observability minimums: none for prototype.
- Review expectation: analyze gate before implement (soft at prototype depth); the two ask-first
  gates above are hard regardless of depth.

## Out of scope (project-wide)
- Managing the VPS subscription, billing, or plan through Terraform.
- ollama and litellm as running services (ollama deleted; litellm config kept in cold storage only).
- Application code for myron and todo — those live in their own repositories; millwright only runs
  and backs them up.
