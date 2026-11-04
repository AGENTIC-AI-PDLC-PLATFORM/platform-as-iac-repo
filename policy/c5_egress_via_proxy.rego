# C5. Default routes in Build and Run target only the DLP reverse proxy: 0 others.
#
# On GCP the proxy is a Private Service Connect endpoint used as an explicit proxy, so the zones
# need no default route at all: networks drop GCP's automatic default route, no NAT or external IP
# exists, and the only route to the internet gateway is the one to private.googleapis.com.
package iac.c5

import data.iac.lib

google_api_ranges := {"199.36.153.8/30", "199.36.153.4/30"} # private / restricted.googleapis.com

default_destinations := {"0.0.0.0/0", "::/0"}

deny contains msg if {
	some r in lib.of_type({"google_compute_network"})
	object.get(r.change.after, "delete_default_routes_on_create", false) != true
	msg := sprintf("C5: %s keeps GCP's default route to the internet; set delete_default_routes_on_create = true", [r.address])
}

deny contains msg if {
	some r in lib.of_type({"google_compute_route"})
	r.change.after.dest_range in default_destinations
	msg := sprintf("C5: %s is a default route (%s); egress goes only through the DLP reverse proxy endpoint", [r.address, r.change.after.dest_range])
}

deny contains msg if {
	some r in lib.of_type({"google_compute_route"})
	not object.get(r.change.after, "next_hop_gateway", null) in {null, ""}
	not r.change.after.dest_range in google_api_ranges
	msg := sprintf("C5: %s sends %s to the internet gateway; only the Google APIs range may use it", [r.address, r.change.after.dest_range])
}

deny contains msg if {
	some r in lib.of_type({"google_compute_route"})
	lib.unknown(r, "dest_range")
	msg := sprintf("C5: %s: the destination is only known after apply, so the route cannot be checked", [r.address])
}

deny contains msg if {
	some r in lib.of_type({"google_compute_router_nat"})
	msg := sprintf("C5: %s is a Cloud NAT: internet egress that bypasses the DLP reverse proxy", [r.address])
}

deny contains msg if {
	some r in lib.of_type({"google_compute_address", "google_compute_global_address"})
	object.get(r.change.after, "address_type", "EXTERNAL") == "EXTERNAL"
	msg := sprintf("C5: %s reserves an external IP address", [r.address])
}

deny contains msg if {
	some r in lib.of_type({"google_compute_instance", "google_compute_instance_template", "google_compute_region_instance_template"})
	some nic in r.change.after.network_interface
	count(object.get(nic, "access_config", [])) > 0
	msg := sprintf("C5: %s gives a VM an external IP (access_config)", [r.address])
}
