# Capstone — Phoenix: TaskApp on Real Kubernetes

> **Mission.** Take the **TaskApp** you containerized and shipped to one server with
> Portainer, and run it on a **multi-node Kubernetes cluster you provision yourself** —
> highly available, autoscaling, zero-downtime, behind HTTPS on your own domain, with
> **no manual `kubectl apply` in your final state** (GitOps owns the cluster).
>
> You already know Terraform, Ansible, Docker, GHCR, CI/CD, and domains/TLS. This capstone
> bolts Kubernetes onto exactly those skills. The hard parts are deliberately the *new*
> parts — orchestration, HA, and the assumptions that break when you stop running on one box.

**Type:** individual · **Duration:** 3 weeks · **Repo:** `ts-a-devops/capstone-phoenix` (fork it)
**App under test:** TaskApp — React/nginx frontend, Flask/Postgres backend, GHCR images
`ghcr.io/ts-a-devops/taskapp-backend`, `ghcr.io/ts-a-devops/taskapp-frontend`.

---

## 1. What you're given vs. what you build

**Given (don't rebuild):**
- The two app images, already on GHCR (you built them in the Docker lesson).
- The K8s lesson + reference manifests in `cicd_dockerized/k8s-lesson/` — these target a
  *single-node laptop* cluster. They are a **starting point, not a submission.** Lifting
  them onto real multi-node infra with HA, GitOps, TLS, and the advanced requirements
  below is the work.

**You build:**
1. **Infrastructure** (Terraform) — the nodes, network, firewall.
2. **Cluster** (Ansible) — install k3s across those nodes; join workers.
3. **Platform** (manifests/Helm) — ingress controller, cert-manager, metrics-server, GitOps controller.
4. **App** (manifests) — TaskApp, hardened for multi-replica, multi-node, HA.
5. **Docs + demo** — architecture, runbook, cost, and a live failure demo.

---

## 2. Infrastructure (Terraform) — you've done 90% of this before

Provision a **multi-node** cluster. Reuse your single-EC2 Terraform as the seed and grow it.

**Required:**
- **3 nodes minimum**: 1 control-plane (k3s server) + **2+ workers** (k3s agents). Real
  scheduling across real machines — single-node does not satisfy this.
- Modular Terraform (`network`, `security_group`/firewall, `compute`) with **remote state**
  (S3 + DynamoDB lock, or equivalent for your provider). No local `terraform.tfstate` in git.
- Least-privilege firewall: only `22` (your IP), `80`, `443` open to the world. The
  Kubernetes API (`6443`) and node-to-node ports are **not** open to the internet.
- All node config from variables — no hardcoded IPs, AMIs, or secrets.
- Outputs: node public/private IPs, so Ansible can consume them.

> Cloud is your choice (AWS / GCP / Azure / Hetzner / DigitalOcean). Pick the cheapest that
> gives you 3 small VMs. Keep the control plane simple — **one k3s server is fine; you do not
> need a multi-master/HA control plane.** The difficulty in this capstone is Kubernetes
> itself, not etcd quorum.

---

## 3. Cluster bring-up (Ansible) — reuse your provisioning muscle

Write a playbook (roles!) that turns bare VMs into a working cluster:

**Required:**
- Base hardening role (you already have one): non-root user, SSH keys only, ufw/firewalld, fail2ban optional.
- `k3s-server` role: install k3s on the control-plane, capture the node token.
- `k3s-agent` role: join each worker to the server using that token.
- Idempotent — `ansible-playbook` twice in a row makes no changes the second time.
- Fetch the kubeconfig back to your machine and rewrite the server address to the public IP.

**Acceptance:** `kubectl get nodes` shows `Ready` for the server + all workers, from your laptop.

---

## 4. The application on Kubernetes — where the real grading is

This is the heart of it. Everything in the K8s lesson, done *for real*, plus hardening.

### Core (must have — non-negotiable)
- [ ] Dedicated **namespace**; **ConfigMap** (non-secret) + **Secret** (secret), split the
      same way your Compose deploy split committed `.env` vs Portainer env vars.
- [ ] **Postgres as a StatefulSet** with a **PVC** (real persistent storage on the cluster's
      storage class). Prove data survives a Pod delete.
- [ ] **Backend + frontend as Deployments**, **2+ replicas each**, spread across **different
      nodes** (`topologySpreadConstraints` or pod anti-affinity — don't let both replicas land
      on one node).
- [ ] **Migrations as a Job/initContainer**, *not* in the running replicas' entrypoint. Solve
      the race: running migrations in the entrypoint is fine for a single replica, but at
      2+ replicas they race on `alembic upgrade head`.
- [ ] **liveness + readiness + startup probes** on every workload, using the app's real
      endpoints (`/api/health`, `/healthz`, `pg_isready`).
- [ ] **resources.requests + limits** on every container.
- [ ] **RollingUpdate with `maxUnavailable: 0`** — prove zero dropped requests during a deploy.
- [ ] **Ingress + TLS** via cert-manager + Let's Encrypt on **your real domain**
      (`taskapp.<you>.dev` and `api.<you>.dev`, or same-origin `/api` — justify your choice).
      A valid public certificate, not self-signed.
- [ ] **Pinned image tags** (commit SHA or semver). `:latest` anywhere = automatic fail.

### Advanced (required for a distinction — pick **at least 3**)
- [ ] **HPA** on the backend (CPU and/or memory), demonstrated under a load test with graphs/logs.
- [ ] **NetworkPolicy**: default-deny in the namespace; Postgres only reachable from the
      backend; backend only from the frontend/ingress. (k3s ships Traefik + you'll need a CNI
      that enforces policy — document your choice.)
- [ ] **PodDisruptionBudget** + graceful shutdown (`terminationGracePeriodSeconds`, SIGTERM
      handling) so node drains don't drop the app.
- [ ] **Observability**: metrics-server + a dashboard (kube-prometheus-stack, or at minimum
      Grafana/Prometheus) showing CPU/mem/replicas/request rate. Screenshots in `docs/`.
- [ ] **Resource hardening**: `securityContext` (runAsNonRoot, readOnlyRootFilesystem where
      possible, drop capabilities), `seccompProfile: RuntimeDefault`.

### GitOps (required — this is the Portainer-GitOps idea, leveled up)
- [ ] Install **Argo CD** (or Flux) on the cluster. Your app's desired state lives in this
      git repo; the controller syncs it. **Your final, graded state must be reconciled by
      GitOps — not by you running `kubectl apply` by hand.** Show a commit → auto-sync → live
      change. This is the direct successor to your Portainer push-to-redeploy.

### Stretch (bonus — for the strong)
- [ ] CI that builds/pushes a new image and **bumps the tag in the GitOps repo** (full
      git-driven deploy, mirroring your `cd.yaml`).
- [ ] Sealed Secrets / External Secrets so the Secret can live in git safely.
- [ ] Automated Postgres backup (CronJob → object storage) + a documented restore test.
- [ ] Multi-replica HA Postgres or a managed DB, with a written trade-off analysis.

---

## 5. Hard constraints (violations cap your grade)

**Forbidden:**
- `:latest` (or untagged) images anywhere.
- Plaintext passwords / `SECRET_KEY` / kubeconfig / node token / `terraform.tfstate` committed to git.
- The Kubernetes API (`6443`) exposed to `0.0.0.0/0`.
- Manual console/`kubectl` changes as your *final* state (GitOps must own it; ad-hoc debugging is fine mid-build).
- A single-node "cluster." Workers must be real, separate nodes.
- Self-signed or placeholder TLS. Real domain, real cert.

**Required git hygiene:** meaningful commits, no secrets in history (`git log -p` will be
checked), a `.gitignore` that covers state/kubeconfig/`.env`, no root SSH.

---

## 6. Deliverables

1. **This repo**, structured roughly as `STRUCTURE.md` describes: `infra/terraform/`,
   `infra/ansible/`, `manifests/` (or a Helm chart / kustomize overlays), `gitops/`, `docs/`.
2. **`docs/ARCHITECTURE.md`** — diagram + prose: node topology, networking, how a request
   flows from DNS → ingress → frontend → backend → Postgres, and **for each Core requirement,
   the single-server assumption it fixes**.
3. **`docs/RUNBOOK.md`** — exact commands to provision from zero, deploy, scale, roll back,
   and recover from: a dead worker, a dead backend, a bad migration.
4. **`docs/COST.md`** — monthly cost of your infra, itemized, with one paragraph on how you'd
   cut it in half.
5. **`docs/EVIDENCE/`** — screenshots/logs proving: `kubectl get nodes` (multi-node Ready),
   pods spread across nodes, a valid TLS cert (`curl -vI` or SSL Labs), data surviving a Pod
   kill, a zero-downtime rollout (unbroken 200s), HPA scaling, and Argo CD synced/healthy.
6. **Live demo (10 min):** architecture walkthrough + a **live failover** — drain or power
   off a worker node on camera and show the app stays up and Pods reschedule.

---

## 7. Grading (100 pts)

| Area | Pts | What earns it |
|---|---:|---|
| Infrastructure (Terraform, multi-node, remote state, least-priv) | 15 | reproducible, modular, no secrets/state in git |
| Cluster bring-up (Ansible, idempotent, workers joined) | 10 | `get nodes` all Ready from a clean run |
| Core app on K8s (§4 Core, all boxes) | 30 | every box ticked and demonstrated |
| Advanced (≥3 of §4 Advanced) | 15 | working + evidence, not just present |
| GitOps owns the cluster | 10 | commit → auto-sync shown live |
| Security & constraints (§5) | 10 | zero violations; secrets clean |
| Docs (architecture / runbook / cost) | 10 | a teammate could rebuild from your runbook |
| Viva + live failover demo | varies | you can explain *why*, and the node-kill demo works |

**Caps:** any §5 violation caps you at 60. A non-working app (can't load `taskapp.<domain>`
over HTTPS) caps you at 50, regardless of how nice the YAML is.

**Distinction (90+):** all Core + GitOps + ≥3 Advanced + a clean failover demo + docs a
stranger could follow.

---

## 8. Suggested 3-week milestones

| By end of | You have |
|---|---|
| Day 3 | Terraform up: 3 VMs, remote state, firewall. `ssh` works. |
| Day 6 | Ansible installs k3s; `kubectl get nodes` shows 3 Ready from your laptop. |
| Day 10 | Core app deployed by hand: Postgres+PVC, migration Job, 2 replicas/tier spread across nodes, probes, Ingress+TLS live on your domain. |
| Day 14 | Argo CD owns the app (GitOps); zero-downtime rollout + HPA demos recorded. |
| Day 18 | ≥3 Advanced done; NetworkPolicy/PDB/observability evidence captured. |
| Day 21 | Docs finished; failover demo rehearsed; submit. |

---

Start by reading the K8s lesson, then open `STRUCTURE.md`.

SUBMISSION LINK:
https://docs.google.com/forms/d/e/1FAIpQLSdp-5Zfvt431gY8m2L_MOZ7NQ-8zN2L3jvkgL7P3yP7-pd94Q/viewform?usp=header

## Live Application

The Phoenix TaskApp is deployed on a multi-node K3s Kubernetes cluster and is accessible here:

**https://taskapp.102.37.138.23.nip.io**

## Final Deployment Evidence

Supporting deployment evidence is available in [`docs/EVIDENCE/`](docs/EVIDENCE/), including:

- Kubernetes node readiness and workload distribution
- PostgreSQL persistent storage
- Services and Traefik ingress
- HPA, PDB, and NetworkPolicy configuration
- Database migration completion
- Argo CD synchronization and health status
