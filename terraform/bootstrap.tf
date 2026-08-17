# Registers a post-install script so a recreate can bootstrap automatically.
# Cloudflare's WAF on the Hostinger API 403s the full bootstrap.sh content
# (its firewall/sshd lines pattern-match as an attack), so this uploads a tiny
# stub that fetches and runs the real script from the public repo instead.
# Manual fallback either way: ssh root@... 'bash -s' < bootstrap.sh (runbook step 3).
resource "hostinger_vps_post_install_script" "bootstrap" {
  name    = "millwright-bootstrap"
  content = <<-EOT
    #!/bin/bash
    curl -fsSL https://raw.githubusercontent.com/arwagner/millwright/main/bootstrap.sh | bash
  EOT
}

output "post_install_script_id" {
  value = hostinger_vps_post_install_script.bootstrap.id
}
