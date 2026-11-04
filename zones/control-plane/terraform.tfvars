project_id  = "example-pdlc-control"
region      = "europe-west9"
cost_center = "agentic-pdlc"

subnets = {
  services = "10.100.0.0/22"
}
psc_nat_cidr = "10.100.8.0/24"

dlp_proxy = {
  service_attachment = "projects/example-network-hub/regions/europe-west9/serviceAttachments/dlp-reverse-proxy"
  port               = 3128
}

consumer_projects = {
  build = "example-pdlc-build"
  run   = "example-pdlc-run"
}
