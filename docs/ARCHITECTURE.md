# Capstone Phoenix Architecture

## 1. Topology

Capstone Phoenix runs on a three-node K3s Kubernetes cluster.

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
                  |   K3s Cluster     |
                  |                   |
                  |  k3s-control      |
                  |  10.0.1.4         |
                  |  Control Plane    |
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
        Backend Pod                 Backend Pod
        Frontend Pod                Frontend Pod

                         phoenix namespace
                               |
                    +----------+----------+
                    |                     |
                    v                     v
             Frontend Service       Backend Service
                    |                     |
                    |                     |
              Frontend Pods         Backend Pods
                                          |
                                          v
                                   PostgreSQL Service
                                          |
                                          v
                                   PostgreSQL Pod
