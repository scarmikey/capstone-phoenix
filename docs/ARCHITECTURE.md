# Phoenix Capstone Architecture

## Overview

The Phoenix TaskApp is a containerized application deployed on a three-node K3s Kubernetes cluster running on Azure Virtual Machines.

The platform uses GitHub as the source of truth, Argo CD for GitOps continuous reconciliation, Traefik for ingress routing, cert-manager for TLS certificate management, Kubernetes NetworkPolicies for workload isolation, and Ansible for cluster provisioning.

---

## Infrastructure & Provisioning Pipeline

The complete infrastructure pipeline spans three layers:

```text
Developer Code
     ↓
GitHub Repository
     ↓
Terraform
     ↓
Azure Virtual Machines (3 nodes)
     ↓
Ansible
     ↓
K3s Kubernetes Cluster (v1.36.3+k3s1)
     ↓
Platform Components (Traefik, cert-manager, metrics-server)
     ↓
Argo CD
     ↓
Kubernetes Manifests (application state)
     ↓
Running Workloads (TaskApp)
```

### Layer 1: Terraform — Infrastructure Provisioning

Terraform provisions the Azure infrastructure:
- 3 Virtual Machines (1 control-plane, 2 workers)
- Virtual network, subnet, and security groups
- Public IPs for external access
- Firewall rules (port 22, 80, 443 open; 6443 restricted to internal)

**Output:** Three bare Linux VMs with SSH access.

### Layer 2: Ansible — Cluster Configuration

Ansible configures the provisioned VMs into a functional K3s cluster:
- **hardening role:** System hardening (swap off, base packages, firewall)
- **k3s-server role:** K3s server installation on the control-plane
- **k3s-agent role:** K3s agent installation and node joining on workers

**K3s version:** v1.36.3+k3s1 (pinned for reproducibility)

**Output:** Multi-node K3s cluster with all nodes Ready.

### Layer 3: Kubernetes & GitOps — Application State Management

Once K3s is running:
- Platform components (Traefik, cert-manager, metrics-server) are installed
- Argo CD is deployed to manage application state
- GitHub becomes the source of truth for all workloads
- Commits → Argo syncs → running workloads

**Ansible does not manage application state.** That is Argo CD's role.

---

## Architecture Diagram

```mermaid
flowchart TB

    DEV["Developer"]

    GIT["GitHub Repository<br/>Source of Truth"]

    ARGO["Argo CD<br/>GitOps Controller"]

    subgraph AZURE["Microsoft Azure"]
        
        subgraph K3S["K3s Kubernetes Cluster"]
            
            CONTROL["k3s-control<br/>10.0.1.4<br/>Control Plane"]

            subgraph WORKERS["Worker Nodes"]
                W1["phoenix-worker-1<br/>10.0.1.6"]
                W2["phoenix-worker-2<br/>10.0.1.5"]
            end

            TRAEFIK["Traefik Ingress<br/>HTTP / HTTPS"]

            CERT["cert-manager<br/>Let's Encrypt"]

            FRONT["Frontend Service<br/>ClusterIP"]
            BACK["Backend Service<br/>ClusterIP"]
            POSTGRES["PostgreSQL Service<br/>ClusterIP"]

            subgraph APP["Phoenix Namespace"]
                FP["Frontend Pods<br/>2 Replicas"]
                BP["Backend Pods<br/>2+ Replicas"]
                DB["PostgreSQL StatefulSet<br/>1 Replica"]
                PVC["PersistentVolumeClaim<br/>5Gi"]
                MIG["Database Migration Job"]
            end

            HPA["Horizontal Pod Autoscaler<br/>Backend"]
            PDB["PodDisruptionBudgets"]
            NP["NetworkPolicies"]
        end
    end

    DEV -->|"git push"| GIT
    GIT -->|"Sync / Reconcile"| ARGO
    ARGO -->|"Deploy Manifests"| CONTROL
    CONTROL --> W1
    CONTROL --> W2

    USER["User / Browser"] -->|"HTTPS"| TRAEFIK

    TRAEFIK -->|"Web Traffic"| FRONT
    TRAEFIK -->|"API /api"| BACK

    FRONT --> FP
    BACK --> BP

    BP -->|"TCP 5432"| POSTGRES
    MIG -->|"Database Migration"| POSTGRES
    POSTGRES --> DB
    DB --> PVC

    CERT -->|"TLS Certificate"| TRAEFIK

    HPA -->|"Scale"| BP
    PDB -.-> FP
    PDB -.-> BP
    NP -.-> BP
    NP -.-> DB

    W1 --- FP
    W1 --- BP
    W2 --- FP
    W2 --- BP
```

---

## 1. Infrastructure Layer

The Kubernetes cluster is hosted on Microsoft Azure Virtual Machines.

| Node | Private IP | Role |
|---|---|---|
| `k3s-control` | `10.0.1.4` | K3s Control Plane |
| `phoenix-worker-1` | `10.0.1.6` | Worker Node |
| `phoenix-worker-2` | `10.0.1.5` | Worker Node |

The three-node architecture provides workload distribution across multiple machines instead of running the application on a single node.

Terraform is used to provision and manage the Azure infrastructure.

Ansible is used to configure the VMs into a working K3s cluster.

---

## 2. GitOps Deployment Architecture

GitHub is the source of truth for the Kubernetes manifests.

```text
Developer
    |
    | git push
    v
GitHub
    |
    | repository changes
    v
Argo CD
    |
    | reconciliation
    v
K3s Cluster
    |
    +--> Frontend Deployment
    +--> Backend Deployment
    +--> PostgreSQL StatefulSet
    +--> Services
    +--> Ingress
    +--> NetworkPolicies
```

Argo CD continuously compares the desired state stored in GitHub with the state running inside Kubernetes.

The final deployment state is:

```text
Argo CD
  Sync Status:   Synced
  Health Status: Healthy
```

---

## 3. Application Request Flow

The public application is exposed through the nip.io hostname:

```text
https://taskapp.102.37.138.23.nip.io
```

Traffic follows this path:

```text
User / Browser
      |
      v
Public DNS / nip.io
      |
      v
Traefik Ingress
      |
      +----------------------+
      |                      |
      v                      v
Frontend Service       Backend Service
      |                      |
      v                      v
Frontend Pods          Backend Pods
                              |
                              | TCP 5432
                              v
                      PostgreSQL Service
                              |
                              v
                     PostgreSQL StatefulSet
                              |
                              v
                     PersistentVolumeClaim
                            5Gi
```

### Routing

| Request | Destination |
|---|---|
| `/` | Frontend Service |
| `/api` | Backend Service |

Traefik provides the external entry point into the Kubernetes application.

---

## 4. Frontend

The frontend application runs as a Kubernetes Deployment.

```text
Frontend Deployment
        |
        +---- Frontend Pod
        |
        +---- Frontend Pod
```

The frontend Service provides stable internal access to the frontend Pods.

Multiple replicas allow frontend traffic to be distributed across the available worker nodes.

---

## 5. Backend

The backend application runs as a Kubernetes Deployment.

```text
Backend Deployment
        |
        +---- Backend Pod
        |
        +---- Backend Pod
```

The backend is configured with a Horizontal Pod Autoscaler.

Current configuration:

```text
Minimum Replicas: 2
Maximum Replicas: 4
CPU Target:       70%
```

This allows Kubernetes to increase backend capacity when CPU utilization increases.

---

## 6. PostgreSQL Persistence

PostgreSQL runs as a Kubernetes StatefulSet.

```text
PostgreSQL StatefulSet
          |
          v
   PostgreSQL Pod
          |
          v
PersistentVolumeClaim
        5Gi
          |
          v
     local-path
```

The database uses persistent storage so that application data is not tied exclusively to the lifecycle of an individual PostgreSQL Pod.

The PostgreSQL Service provides stable internal connectivity for backend workloads.

---

## 7. Database Migration

Database migrations are handled through a Kubernetes Job:

```text
Phoenix Migration Job
          |
          | Database Migration
          v
PostgreSQL Service
          |
          v
PostgreSQL
```

The migration Job completed successfully during the deployment validation.

---

## 8. Ingress and TLS

Traefik provides the Kubernetes ingress layer.

```text
Internet
   |
   v
nip.io hostname
   |
   v
Traefik
   |
   +--> Frontend
   |
   +--> Backend API
```

TLS certificate management is handled by cert-manager.

```text
cert-manager
     |
     v
Let's Encrypt
     |
     v
TLS Certificate
     |
     v
Traefik
```

This provides HTTPS support for the public application endpoint.

---

## 9. Network Security

Kubernetes NetworkPolicies restrict communication between workloads.

The Phoenix namespace contains policies for:

```text
Frontend
   |
   v
Backend
   |
   v
PostgreSQL
```

The PostgreSQL workload is not exposed directly to the public internet.

Database traffic is restricted to approved internal workloads.

---

## 10. Resilience and Availability

The application includes several availability mechanisms:

- Three-node K3s cluster.
- Two frontend replicas.
- Two backend replicas.
- Backend Horizontal Pod Autoscaler.
- PodDisruptionBudgets for frontend and backend.
- PostgreSQL persistent storage.
- Kubernetes Services for stable service discovery.
- Argo CD continuous reconciliation.
- Multiple worker nodes for workload distribution.

The backend HPA is configured to scale between two and four replicas based on CPU utilization.

---

## 11. Observability

The Kubernetes environment includes Kubernetes Metrics Server, allowing resource utilization to be inspected through Kubernetes metrics.

Example:

```text
kubectl top pods -n phoenix
```

This provides CPU and memory visibility for application workloads.

---

## 12. Deployment Components

| Component | Technology | Purpose |
|---|---|---|
| Infrastructure | Terraform | Azure infrastructure provisioning |
| Cluster Configuration | Ansible | K3s cluster provisioning and node hardening |
| Container Orchestration | K3s | Kubernetes runtime |
| GitOps | Argo CD | Continuous reconciliation |
| Ingress | Traefik | HTTP/HTTPS routing |
| TLS | cert-manager + Let's Encrypt | Certificate management |
| Frontend | Kubernetes Deployment | Web application |
| Backend | Kubernetes Deployment | API application |
| Database | PostgreSQL StatefulSet | Persistent application data |
| Scaling | HPA | Backend autoscaling |
| Availability | PDB | Disruption protection |
| Security | NetworkPolicies | Workload isolation |
| Storage | PVC | Persistent PostgreSQL storage |
| Monitoring | Metrics Server | CPU and memory metrics |

---

## 13. Evidence

Deployment evidence is stored in:

```text
docs/EVIDENCE/
```

Evidence includes:

- Kubernetes node readiness.
- Workload distribution.
- PostgreSQL persistent storage.
- Services and Traefik ingress.
- HPA and PodDisruptionBudgets.
- NetworkPolicies.
- Database migration completion.
- Argo CD synchronization and health.
- Cluster resource metrics.

The live application demonstration is documented in the root README.

---

## 14. Live Application

The Phoenix TaskApp is available at:

**https://taskapp.102.37.138.23.nip.io**

A screenshot of the working live application is included in the root `README.md` as final deployment evidence.

---

## 15. Architecture Summary

The Phoenix Capstone combines cloud infrastructure (Terraform), cluster provisioning (Ansible), Kubernetes orchestration (K3s), GitOps (Argo CD), ingress management (Traefik), TLS (cert-manager), persistent storage, autoscaling, network security, and observability into one production-style system.

The overall flow is:

```text
Developer
    |
    v
GitHub
    |
    v
Terraform → Azure VMs
    |
    v
Ansible → K3s Cluster
    |
    v
Argo CD
    |
    v
K3s Cluster
    |
    +-----------------------------+
    |                             |
    v                             v
Traefik Ingress              Kubernetes Workloads
    |                             |
    |                     +-------+-------+
    |                     |               |
    v                     v               v
Frontend              Backend         PostgreSQL
Service               Service         StatefulSet
    |                     |               |
    v                     v               v
Frontend Pods        Backend Pods       PVC
```

This architecture provides a reproducible, scalable, persistent, secure, and GitOps-managed Kubernetes deployment for the Phoenix TaskApp.
