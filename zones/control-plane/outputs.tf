# Published to Build and Run through published/control-plane.tfvars.json (non-secret; no zone reads
# another zone's state). The apply job fails if that file and this output disagree.
output "control_plane_services" {
  description = "Published services: name => Private Service Connect service attachment."
  value       = { for name, attachment in google_compute_service_attachment.this : name => attachment.id }
}
