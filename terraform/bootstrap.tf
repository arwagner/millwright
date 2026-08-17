# Registers bootstrap.sh as a Hostinger post-install script, so a recreate can
# run it automatically. The canonical script lives at the repo root; this
# resource just uploads it.
resource "hostinger_vps_post_install_script" "bootstrap" {
  name    = "millwright-bootstrap"
  content = file("${path.module}/../bootstrap.sh")
}
