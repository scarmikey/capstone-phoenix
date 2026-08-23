# Cost

The Phoenix Capstone was deployed on Azure using a three-node K3s Kubernetes cluster. Azure Cost Management was used to track the actual infrastructure spend during the deployment.

The cost figures below are based on the Azure Cost Management dashboard captured during the project.

## Monthly itemized cost

| Item | Spec | Qty | Cost |
|---|---|---:|---:|
| Control-plane VM | Standard_B2ls_v2 Linux VM | 1 | Included in Azure actual |
| Worker VMs | Standard_B2ls_v2 Linux VMs | 2 | Included in Azure actual |
| Load balancer / public IP | Azure public networking | 1+ | Included in Azure actual |
| Block storage (PVC) | 5 GiB PostgreSQL local-path storage | 1 | No separate PVC charge |
| Object storage | Not deployed | 0 | $0 |
| DNS / domain | nip.io | 1 | $0 |
| **Actual accumulated Azure cost** | | | **$36.93** |
| **August forecast** | Current billing-period forecast | | **$51.08** |

> The $36.93 figure represents the actual accumulated Azure cost shown in Cost Management at the time of the evidence capture. Azure forecasts the August 2026 total at approximately $51.08.

The actual cost is lower than a theoretical full-month on-demand estimate because the cluster was not running for the entire billing period. The infrastructure was created, configured, tested, demonstrated, and prepared for shutdown within the project period.

## Compared to the single-server Compose + Portainer deploy

- Single-server Compose + Portainer: **lower infrastructure cost**
- Phoenix K3s deployment: **$36.93 actual cost to date**
- August forecast: **$51.08**

The single-server architecture would be cheaper for a small application because it requires only one VM and has fewer supporting infrastructure components.

However, the Phoenix Kubernetes deployment provides capabilities beyond simply running the application:

- **High availability:** frontend and backend workloads use multiple replicas.
- **Autoscaling:** the backend uses a Horizontal Pod Autoscaler.
- **Zero-downtime deployment:** rolling updates can maintain application availability.
- **Multi-node self-healing:** Kubernetes can reschedule workloads when nodes or Pods fail.
- **Persistent storage:** PostgreSQL uses persistent storage.
- **GitOps:** Argo CD continuously reconciles the desired state from GitHub.
- **Ingress:** Traefik manages application routing.
- **TLS:** cert-manager manages HTTPS certificates.
- **Network security:** Kubernetes NetworkPolicies restrict workload communication.

### Is the extra cost worth it?

For this specific small TaskApp, **not necessarily**.

A single Docker Compose + Portainer server would be cheaper and simpler to operate. The Kubernetes architecture becomes more valuable when availability, automated scaling, workload isolation, repeatable deployments, and failure recovery are important.

For this capstone, the additional infrastructure cost is justified primarily because the objective is to demonstrate production-style DevOps and Kubernetes engineering rather than simply hosting the cheapest possible application.

The main trade-off is:

> **Single server:** cheaper and simpler.
>
> **Kubernetes cluster:** more infrastructure cost, but significantly more resilience, automation, scalability, and operational capability.

## How I'd halve this

I would reduce cost primarily by running the Kubernetes environment only when it is required for development, testing, or demonstrations. Azure VMs could be stopped/deallocated when the environment is not being used, while smaller VM sizes could be considered where the workload permits. For a non-production environment, I would also evaluate a smaller K3s topology or fewer worker nodes and avoid unnecessary public networking resources. Spot/preemptible worker capacity could also reduce compute costs where occasional node interruption is acceptable. The biggest saving for this capstone is therefore **not running the cluster 24/7**.

## Cost Evidence

Azure Cost Management was used to monitor the deployment cost.

At the time of evidence capture:

```text
Actual accumulated cost:  $36.93
August forecast:           $51.08
