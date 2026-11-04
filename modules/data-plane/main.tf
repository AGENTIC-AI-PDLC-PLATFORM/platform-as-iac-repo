# The data plane of one zone, instantiated by zones/build and zones/run from the same release tag
# (C10: Run at most one release behind Build). Filled from Day 31, per the CoE's plan:
#
#   both zones   OPA/Cerbos PDP sidecar, fail-closed, pulling signed bundles (Day 31, ADR-004)
#                DLP-MCP gateway on the company DLP reverse proxy, inline tokenization (Day 36)
#                LLM gateway + MCP fleet, EU egress (Days 19, 39)
#   build only   sandbox pool: gVisor CI runners, Firecracker microVMs (Day 37)
#   run only     release pipelines, runtime operators, prod vault namespace, detokenization (Day 44)
#
# Until then the module creates nothing; its inputs fix the contract the zones already honour.
