# Capstone Phoenix Architecture

## 1. Architecture Overview

The Phoenix TaskApp runs on a three-node K3s Kubernetes cluster hosted on Azure. GitHub serves as the source repository, while Argo CD provides GitOps-based deployment and reconciliation.

```text
                         GitHub
                           |
                           | GitOps
                           v
                       Argo CD
                           |
                           | Reconcile
                           v
                  +-------------------+
                  |    K3s Cluster    |
                  |                   |
                  |   k3s-control     |
                  |     10.0.1.4      |
                  |   Control Plane   |
                  +---------+---------+
                            |
              +-------------+-------------+
              |                           |
              v                           v
      +---------------+           +---------------+
      | phoenix-      |           | phoenix-      |
      | worker-1      |           | worker-2      |
      | 10.0.1.6      |           | 10.0.1.5      |
      +---------------+           +---------------+
              |                           |
              |                           |
        Backend Pods                Backend Pods
        Frontend Pods               Frontend Pods


                    PUBLIC APPLICATION FLOW

                              |
                              v
                 taskapp.<PUBLIC-IP>.nip.io
                              |
                              v
                    +-------------------+
                    |  Traefik Ingress  |
                    |   HTTP / HTTPS    |
                    +---------+---------+
                              |
                 +------------+------------+
                 |                         |
                 v                         v
        Frontend Service            Backend Service
                 |                         |
                 v                         v
        Frontend Pods                Backend Pods
                                           |
                                           v
                                  PostgreSQL Service
                                           |
                                           v
                                  PostgreSQL StatefulSet
                                           |
                                           v
                                  PostgreSQL Pod
                                           |
                                           v
                              PersistentVolumeClaim
                                      5Gi


                    TLS / CERTIFICATE MANAGEMENT

                         cert-manager
                              |
                              v
                         Let's Encrypt
                              |
                              v
                     Traefik HTTPS/TLS
