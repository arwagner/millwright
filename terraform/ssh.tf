# Public key only — the private key never touches Terraform or its state.
resource "hostinger_vps_ssh_key" "laptop" {
  name = "andrew-laptop"
  key  = file("~/.ssh/id_ed25519.pub")
}
