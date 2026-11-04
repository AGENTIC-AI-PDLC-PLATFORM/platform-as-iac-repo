# modules/data-plane

One data-plane module for both zones (ADR-002), filled from Day 31. Build and Run reference it by
release tag (`data-plane-vX.Y.Z`); a change lands in Build first and Run follows by version, at
most one release behind (C10).

Release a new version after the change is merged:

```bash
git tag data-plane-v0.2.0 <merge-commit> && git push origin data-plane-v0.2.0
```

Then bump `?ref=` in `zones/build/main.tf` in one pull request, and in `zones/run/main.tf` in
another once Build has run it.
