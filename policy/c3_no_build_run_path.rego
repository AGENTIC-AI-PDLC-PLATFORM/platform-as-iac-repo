# C3. No Build <-> Run peering, transit or route: 0 in plans.
#
# No resource that joins networks may exist in any zone, only the control plane may publish
# services, and Private Service Connect endpoints may only lead to the company DLP reverse proxy or
# to a service the control plane published (published/control-plane.tfvars.json). Endpoints are
# one-way, so these rules leave no path between Build and Run.
package iac.c3

import data.iac.lib

path_types := {
	"google_compute_network_peering",
	"google_compute_network_peering_routes_config",
	"google_compute_shared_vpc_host_project",
	"google_compute_shared_vpc_service_project",
	"google_compute_vpn_gateway",
	"google_compute_ha_vpn_gateway",
	"google_compute_vpn_tunnel",
	"google_compute_external_vpn_gateway",
	"google_compute_router_peer",
	"google_compute_router_interface",
	"google_compute_interconnect_attachment",
	"google_compute_network_attachment",
	"google_network_connectivity_hub",
	"google_network_connectivity_spoke",
}

deny contains msg if {
	some r in lib.of_type(path_types)
	msg := sprintf("C3: %s (%s) joins networks; no peering, VPN, interconnect, hub or shared VPC may exist", [r.address, r.type])
}

# Only the control plane publishes services: a service published in Build or Run would let the
# other zone connect to it.
deny contains msg if {
	lib.zone in {"build", "run", "bootstrap"}
	some r in lib.of_type({"google_compute_service_attachment"})
	msg := sprintf("C3: %s publishes a service from the %s root; only the control plane may", [r.address, lib.zone])
}

allowed_targets contains target if {
	target := lib.variable("dlp_proxy").service_attachment
}

allowed_targets contains target if {
	some target in lib.variable("control_plane_services")
}

forwarding_types := {"google_compute_forwarding_rule", "google_compute_global_forwarding_rule"}

deny contains msg if {
	some r in lib.of_type(forwarding_types)
	target := object.get(r.change.after, "target", "")
	contains(target, "/serviceAttachments/")
	not target in allowed_targets
	msg := sprintf("C3: %s connects to %s, which is neither the DLP reverse proxy nor a published control-plane service", [r.address, target])
}

deny contains msg if {
	some r in lib.of_type(forwarding_types)
	lib.unknown(r, "target")
	object.get(r.change.after, "load_balancing_scheme", null) == ""
	msg := sprintf("C3: %s: the endpoint's target is only known after apply, so where it leads cannot be checked", [r.address])
}

# Routes that hand traffic to another network or an appliance.
deny contains msg if {
	some r in lib.of_type({"google_compute_route"})
	some hop in ["next_hop_vpn_tunnel", "next_hop_instance", "next_hop_ip"]
	hop_set(r, hop)
	msg := sprintf("C3: %s routes %s through %s; zones only route to Google APIs", [r.address, r.change.after.dest_range, hop])
}

hop_set(r, hop) if {
	value := object.get(r.change.after, hop, null)
	not value in {null, ""}
}

# GCP reports the unused next-hop fields as computed: an unknown one only counts when the route has
# no known gateway or internal load balancer as its next hop.
hop_set(r, hop) if {
	lib.unknown(r, hop)
	not known_hop(r, "next_hop_gateway")
	not known_hop(r, "next_hop_ilb")
}

known_hop(r, field) if not object.get(r.change.after, field, null) in {null, ""}
