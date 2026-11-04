project_id  = "example-pdlc-run"
region      = "europe-west9"
cost_center = "agentic-pdlc"

# Disjoint from the Build ranges, so a route between them could never be ambiguous (C3).
subnets = {
  workloads = "10.31.0.0/20"
  endpoints = "10.31.16.0/24"
}

dlp_proxy = {
  service_attachment = "projects/example-network-hub/regions/europe-west9/serviceAttachments/dlp-reverse-proxy"
  port               = 3128
}
