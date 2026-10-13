# Deployment Evidence Index

This folder contains captured evidence for the Phoenix capstone deployment.

## Command Output Evidence

| Evidence | File | What it demonstrates |
|---|---|---|
| Node readiness | [`nodes-ready.txt`](nodes-ready.txt) | 3-node K3s cluster (`Ready` status) |
| Pod placement | [`pods-spread.txt`](pods-spread.txt) | Frontend/backend replicas distributed across nodes |
| Storage, services, ingress | [`storage-services.txt`](storage-services.txt) | PVC bound, core services, ingress resources |
| Resilience and security | [`resilience-security.txt`](resilience-security.txt) | HPA, PDB, and NetworkPolicy resources |
| Migration result | [`migration.txt`](migration.txt) | Database migration Job completed |
| Argo CD status | [`argocd.txt`](argocd.txt) | Application reported as `Synced` and `Healthy` |

## Screenshots and Media

- [`live-demo1.png`](live-demo1.png)
- `Azure infrastructure.png`
- `capture the final evidence screenshot.png`
- `capture the final evidence screenshot1.png`
- `final live health check.png`
- `phoenix-live-demo.mp4.mp4`

## Notes

- Evidence files are historical snapshots and should be interpreted with their capture time in mind.
- If deployment behavior changes, capture and add updated evidence rather than replacing original files.
