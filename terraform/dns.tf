# All DNS for vawagners.cloud lives here (product invariant: Terraform owns every record).
# Record set verified against live DNS 2026-08-17. The recreate endpoint keeps the IP,
# so these never change during a rebuild.

locals {
  zone = "vawagners.cloud"
  ip   = "187.124.159.132"
}

resource "hostinger_dns_record" "apex" {
  zone  = local.zone
  name  = "@"
  type  = "A"
  value = local.ip
  ttl   = 300
}

resource "hostinger_dns_record" "www" {
  # Was a CNAME to the apex; declared as an A record here (plan D2) — same answer.
  zone  = local.zone
  name  = "www"
  type  = "A"
  value = local.ip
  ttl   = 300
}

resource "hostinger_dns_record" "todo" {
  zone  = local.zone
  name  = "todo"
  type  = "A"
  value = local.ip
  ttl   = 300
}

resource "hostinger_dns_record" "exploring_elan" {
  zone  = local.zone
  name  = "exploring-elan"
  type  = "A"
  value = local.ip
  ttl   = 300
}

resource "hostinger_dns_record" "fiddlesticks" {
  zone  = local.zone
  name  = "fiddlesticks"
  type  = "A"
  value = local.ip
  ttl   = 300
}
