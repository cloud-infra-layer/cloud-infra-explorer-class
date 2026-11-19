# UI Design

## Dashboard

### Planned improvements

- [ ] Remove the EC2 instances and S3 buckets anchor links beneath the page description; the resource cards already provide navigation.
- [ ] Remove the Manual AWS discovery heading and read-only credentials explanation from the dashboard.
- [ ] Consolidate scanning into one compact scan control. Display the environment name, AWS region, and numerical scan count together in smaller text on the same line (e.g. `Course demo · us-east-1 · 0 scans`).
- [ ] Preserve authorized, read-only scanning and existing scan feedback; this is a presentation change, not a change to AWS permissions.
- [ ] Retain the existing EC2 and S3 resource cards and their links to dedicated inventory pages.
- [ ] Remove the EC2 and S3 inventory tables and duplicate resource counts from the dashboard. Detailed inventory belongs on the dedicated resource pages.

These are planned changes, not completed implementation. Update affected UI tests when implementing them.
