# Runbook

This runbook describes how to rebuild the Phoenix TaskApp environment from infrastructure provisioning through Kubernetes, platform services, application deployment, GitOps, and day-2 operations.

The intended final state is GitOps-managed: GitHub is the source of truth and Argo CD reconciles the Kubernetes application state. The capstone requires a minimum three-node cluster consisting of one control-plane node and two or more workers.

---

# 1. Provision from Zero

## 1.1 Provision Azure infrastructure

The Terraform configuration provisions the Azure infrastructure required for the Phoenix K3s cluster.

```bash
cd infra/terraform

terraform init
terraform validate
terraform plan
terraform apply
```

After Terraform completes, record the public/private IP addresses of:

```text
k3s-control
phoenix-worker-1
phoenix-worker-2
```

The final environment used:

```text
k3s-control       10.0.1.4
phoenix-worker-1  10.0.1.6
phoenix-worker-2  10.0.1.5
```

Do not commit Terraform state, credentials, or other secrets to Git.

---

## 1.2 Configure the Kubernetes nodes with Ansible

The Ansible configuration installs and configures K3s across the provisioned machines.

K3s version: **v1.36.3+k3s1**

Validate playbook syntax:

```bash
cd ../ansible

ansible-playbook --syntax-check -i inventory site.yml
```

Expected output:
```
playbook: site.yml
```

Provision the cluster:

```bash
ansible-playbook -i inventory site.yml
```

This command runs three roles on the cluster nodes:
- **hardening:** System preparation (swap off, base packages)
- **k3s-server:** K3s control-plane installation
- **k3s-agent:** K3s worker node configuration and cluster join

Verify that all nodes have joined the cluster:

```bash
kubectl get nodes -o wide
```

Expected result:

```text
NAME               STATUS   ROLES          AGE     VERSION
k3s-control        Ready    control-plane  5m      v1.36.3+k3s1
phoenix-worker-1   Ready    <none>         3m      v1.36.3+k3s1
phoenix-worker-2   Ready    <none>         3m      v1.36.3+k3s1
```

The capstone requires all three nodes to be Ready after a clean cluster installation.

---

# 2. Configure Kubeconfig

Obtain the K3s kubeconfig from the control-plane node and configure the local environment:

```bash
export KUBECONFIG=/path/to/kubeconfig
```

Verify access:

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

---

# 3. Install / Verify Platform Components

The Phoenix platform requires:

- K3s (provisioned by Ansible)
- Traefik (bundled with K3s)
- cert-manager (installed manually)
- Metrics Server (installed manually)
- Argo CD (installed manually, manages application state)

The capstone specifically requires an ingress controller, cert-manager, metrics-server, and a GitOps controller.

## 3.1 Verify Traefik

K3s provides the Traefik ingress controller used by the application.

```bash
kubectl get pods -n kube-system | grep traefik
kubectl get svc -n kube-system | grep traefik
```

Verify the ingress resources:

```bash
kubectl get ingress -A
```

---

## 3.2 Install / verify cert-manager

If cert-manager is not already installed:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
```

Verify:

```bash
kubectl get pods -n cert-manager
```

All cert-manager components should eventually report:

```text
Running
```

The project uses cert-manager and Let's Encrypt for TLS certificate management.

---

## 3.3 Verify Metrics Server

```bash
kubectl get pods -n kube-system | grep metrics-server
```

Then verify metrics:

```bash
kubectl top nodes
kubectl top pods -n phoenix
```

If metrics are unavailable immediately after installation, allow the metrics server time to become Ready before troubleshooting.

---

## 3.4 Install Argo CD

If Argo CD is not already installed:

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml
```

Verify:

```bash
kubectl get pods -n argocd
```

Optional local UI access:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Argo CD is then used to manage the application from Git. The deployment guide uses the Argo CD application manifest to bootstrap the application and then verifies that Argo reports `Healthy` and `Synced`.

---

# 4. GitOps Takes Over

Once the platform is available, GitHub becomes the source of truth for the application state.

Verify the GitOps application:

```bash
kubectl get application phoenix -n argocd
```

Expected:

```text
SYNC STATUS   HEALTH STATUS
Synced        Healthy
```

The final application state should be managed by Argo CD rather than repeated manual `kubectl apply` commands.

If the Argo CD Application resource has not yet been bootstrapped:

```bash
kubectl apply -f gitops/
```

This command is a **one-time GitOps bootstrap step**. After Argo CD is managing the application, application changes should be made through Git commits and synchronized by Argo CD.

---

# 5. Verify the Complete Deployment

Run:

```bash
kubectl get deployments -n phoenix
kubectl get statefulset -n phoenix
kubectl get pods -n phoenix -o wide
kubectl get svc -n phoenix
kubectl get ingress -n phoenix
kubectl get hpa -n phoenix
kubectl get pdb -n phoenix
kubectl get networkpolicy -n phoenix
kubectl get job -n phoenix
```

Verify Argo:

```bash
kubectl get application phoenix -n argocd
```

Verify metrics:

```bash
kubectl top pods -n phoenix
```

Verify the public application:

```bash
curl -I https://taskapp.102.37.138.23.nip.io
```

Expected:

```text
HTTP/2 200
```

---

# 6. Day-2 Operations

## 6.1 Scale a tier

Prefer a Git change so Argo CD remains the source of truth.

For example, change the replica configuration in the appropriate Kubernetes manifest:

```yaml
spec:
  replicas: 2
```

Commit and push:

```bash
git add manifests/
git commit -m "scale phoenix application"
git push origin main
```

Then monitor Argo:

```bash
kubectl get application phoenix -n argocd
```

And verify:

```bash
kubectl get pods -n phoenix -o wide
```

For the backend, HPA should normally control replica count rather than manually changing replicas during normal operation.

---

## 6.2 Roll back a bad deployment

Use Git as the primary rollback mechanism.

Identify the bad commit:

```bash
git log --oneline
```

Revert it:

```bash
git revert <bad-commit>
git push origin main
```

Argo CD detects the Git change and reconciles the previous desired state.

Verify:

```bash
kubectl get application phoenix -n argocd
kubectl get pods -n phoenix
```

Expected:

```text
SYNC STATUS   HEALTH STATUS
Synced        Healthy
```

This preserves Git as the source of truth instead of creating configuration drift with a manual `kubectl rollout undo`.

---

## 6.3 Run a new migration safely

First inspect the current database and migration state.

```bash
kubectl get job -n phoenix
kubectl get pods -n phoenix
```

Review the migration Job:

```bash
kubectl describe job phoenix-migration -n phoenix
kubectl logs job/phoenix-migration -n phoenix
```

For a new migration:

1. Make the migration change in the application/repository.
2. Update the migration manifest or image reference in Git.
3. Commit and push the change.
4. Allow Argo CD to reconcile it.
5. Confirm the migration Job completes.
6. Confirm the backend remains healthy.

Verify:

```bash
kubectl get job phoenix-migration -n phoenix
kubectl get pods -n phoenix
kubectl get application phoenix -n argocd
```

Expected migration state:

```text
STATUS       Complete
COMPLETIONS  1/1
```

---

## 6.4 Rotate a secret

Secrets must not be committed to Git as plaintext.

For an operational rotation, create the new value securely and update the Kubernetes Secret using the project's approved secret-management approach.

Verify that the Secret exists:

```bash
kubectl get secrets -n phoenix
```

Do not print secret values to the terminal or commit them to Git.

After rotation, restart the affected workload if required:

```bash
kubectl rollout restart deployment/backend -n phoenix
```

Then verify:

```bash
kubectl rollout status deployment/backend -n phoenix
kubectl get pods -n phoenix
```

For a GitOps-managed environment, the permanent desired secret configuration must also be updated through the repository's secure secret-management mechanism so that Argo CD does not reintroduce the old secret.

---

# 7. Failure Recovery

## 7.1 Worker node dies or is drained

### What happens

Kubernetes detects that the node is unavailable and workloads running on that node can be rescheduled onto available nodes, provided sufficient capacity exists.

The Phoenix application uses multiple frontend and backend replicas, allowing the application to remain available during a worker-node disruption.

The capstone specifically requires a live failover demonstration where a worker is drained or powered off and the application remains available while Pods reschedule.

### Demonstration

First identify the workers:

```bash
kubectl get nodes -o wide
```

Drain a worker:

```bash
kubectl drain phoenix-worker-1 \
  --ignore-daemonsets \
  --delete-emptydir-data
```

Watch the workloads:

```bash
kubectl get pods -n phoenix -o wide -w
```

Check the node:

```bash
kubectl get nodes
```

Test the application while the node is drained:

```bash
curl -I https://taskapp.102.37.138.23.nip.io
```

Expected:

```text
HTTP/2 200
```

Check where Pods were rescheduled:

```bash
kubectl get pods -n phoenix -o wide
```

### Restore the node

After the demonstration:

```bash
kubectl uncordon phoenix-worker-1
```

Verify:

```bash
kubectl get nodes
kubectl get pods -n phoenix -o wide
```

The exact recovery time depends on Kubernetes scheduling, image availability, readiness probes, and application startup time. The important success criteria are that the application remains reachable and Pods are rescheduled to available nodes.

---

# 8. Backend Pod CrashLoopBackOff

First inspect the Pods:

```bash
kubectl get pods -n phoenix
```

Identify the failing Pod:

```bash
kubectl describe pod <backend-pod> -n phoenix
```

Check current logs:

```bash
kubectl logs <backend-pod> -n phoenix
```

Check logs from the previous crashed container:

```bash
kubectl logs <backend-pod> -n phoenix --previous
```

Check recent namespace events:

```bash
kubectl get events -n phoenix --sort-by=.lastTimestamp
```

Also inspect the Deployment:

```bash
kubectl describe deployment backend -n phoenix
```

Typical investigation areas include:

- Image availability.
- Environment variables.
- Database connectivity.
- Secret configuration.
- Health probes.
- Resource limits.
- Application startup errors.
- NetworkPolicy restrictions.

After correcting the root cause through Git, allow Argo CD to reconcile the deployment.

---

# 9. Bad Migration

If a migration fails:

```bash
kubectl get job -n phoenix
kubectl describe job phoenix-migration -n phoenix
kubectl logs job/phoenix-migration -n phoenix
```

Do not repeatedly run destructive database commands without first identifying the migration failure.

Determine whether the migration is:

- Safe to retry.
- Partially applied.
- Requiring a corrective migration.
- Requiring restoration from a database backup.

If the migration change itself is incorrect, revert the Git commit:

```bash
git revert <migration-commit>
git push origin main
```

Then allow Argo CD to reconcile.

For destructive or partially applied migrations, restore PostgreSQL from the available backup/recovery procedure before attempting another migration.

---

# 10. PostgreSQL Pod Rescheduled

PostgreSQL uses persistent storage through its PVC.

Check the StatefulSet:

```bash
kubectl get statefulset -n phoenix
```

Check the Pod:

```bash
kubectl get pods -n phoenix -o wide
```

Check the PVC:

```bash
kubectl get pvc -n phoenix
```

Expected:

```text
STATUS
Bound
```

Inspect the volume:

```bash
kubectl describe pvc postgres-data-postgres-0 -n phoenix
```

If the PostgreSQL Pod is recreated or rescheduled, verify that the PVC remains bound and is mounted by the new Pod.

Then verify PostgreSQL:

```bash
kubectl logs postgres-0 -n phoenix
```

Finally verify application connectivity:

```bash
kubectl get pods -n phoenix
curl -I https://taskapp.102.37.138.23.nip.io
```

The expected result is that the PostgreSQL workload returns with its persistent volume attached and the application continues to operate against the existing database data.

---

# 11. Quick Health Check

Use the following commands for a rapid operational check:

```bash
echo "=== NODES ==="
kubectl get nodes -o wide

echo "=== ARGO CD ==="
kubectl get application phoenix -n argocd

echo "=== DEPLOYMENTS ==="
kubectl get deployments -n phoenix

echo "=== STATEFULSETS ==="
kubectl get statefulset -n phoenix

echo "=== PODS ==="
kubectl get pods -n phoenix -o wide

echo "=== STORAGE ==="
kubectl get pvc -n phoenix

echo "=== SERVICES ==="
kubectl get svc -n phoenix

echo "=== INGRESS ==="
kubectl get ingress -n phoenix

echo "=== HPA ==="
kubectl get hpa -n phoenix

echo "=== PDB ==="
kubectl get pdb -n phoenix

echo "=== NETWORK POLICIES ==="
kubectl get networkpolicy -n phoenix

echo "=== MIGRATION ==="
kubectl get job phoenix-migration -n phoenix

echo "=== METRICS ==="
kubectl top pods -n phoenix
```

---

# 12. Final Validation Checklist

Before declaring the environment healthy:

```text
[ ] All three Kubernetes nodes are Ready
[ ] Frontend replicas are Running
[ ] Backend replicas are Running
[ ] PostgreSQL StatefulSet is Ready
[ ] PostgreSQL PVC is Bound
[ ] Migration Job completed
[ ] Services exist
[ ] Traefik Ingress exists
[ ] TLS certificate is Ready
[ ] HPA is active
[ ] PDBs exist
[ ] NetworkPolicies exist
[ ] Metrics are available
[ ] Argo CD reports Synced
[ ] Argo CD reports Healthy
[ ] Public HTTPS URL returns HTTP 200
[ ] Worker-node failover has been tested
[ ] Evidence has been captured in docs/EVIDENCE/
```

---

# 13. Destruction / Shutdown

Once grading evidence has been captured, the live Azure environment can be shut down or destroyed to prevent unnecessary ongoing costs.

Before destruction, confirm that the following are committed and pushed:

```text
README.md
STRUCTURE.md
docs/ARCHITECTURE.md
docs/COST.md
docs/RUNBOOK.md
docs/EVIDENCE/
infra/terraform/
infra/ansible/
manifests/
gitops/
```

Verify:

```bash
git status
git log --oneline -5
git remote -v
```

Then destroy the infrastructure using Terraform:

```bash
cd infra/terraform
terraform destroy
```

Confirm the Azure resources have been removed in the Azure Portal.

The repository remains the source of truth and contains the Terraform, Ansible, Kubernetes manifests, GitOps configuration, documentation, and final deployment evidence required to reproduce the Phoenix Capstone environment.
