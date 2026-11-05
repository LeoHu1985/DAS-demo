# Spec: Kubernetes cluster on vSphere from a template VM (v2)

Updated from the original one-line spec (`vsphere-vm-k8s-spec.md`) to reflect what was built, deployed and learned. Blueprint ID: `vsphere-k8s-cluster`, current revision **1.1.0**.

## 1. Goal

Deploy a kubeadm Kubernetes cluster in vCenter by cloning an existing Ubuntu VM. The user supplies a VM name and a static IP for every node. All nodes go on the same ESXi host, datastore and port group as the template.

Changes from the original spec:
- Cluster size: 3 nodes (1 control plane + 2 workers) became **4 nodes (1 control plane + 3 workers)**.
- Credentials: the guest password is no longer in the spec or the blueprint. It is read from a DAP secret.

## 2. Environment

| Item | Value |
|---|---|
| vCenter secret | `vcenter-vCenter01-20260505145203-2104f5` (type `vsphere`) |
| Datacenter / cluster | `Migration Datacenter` / `Cluster` |
| ESXi host | `esxi04.demo.local` |
| Datastore | `esxi04-local-256GB` |
| Port group | `VM Network` (standard switch) |
| Template VM | `LinuxVM-01`, Ubuntu 24.04, 192.168.1.41 |
| Guest user | `demo`, sudo-capable; password held in a DAP secret (the secret named `demo`, type General) |
| Node network | 192.168.1.0/24, gateway 192.168.1.1, DNS 192.168.1.2 |
| Orchestrator plugins | vSphere 3.1.1.0, Fabric 3.3.2.0 (already installed) |

## 3. Functional requirements

1. Clone `LinuxVM-01` into one control-plane VM and three worker VMs, each with a user-supplied name and static IP.
2. Place every node on the user-chosen ESXi host, datastore and port group.
3. Prepare each node over SSH:
   - set hostname and `/etc/hosts` entries for all nodes
   - turn off swap, load kernel modules, set sysctl values
   - install containerd, `conntrack`, `socat`, and kubeadm/kubelet/kubectl
4. Initialise the control plane with `kubeadm init` and apply a pinned Flannel manifest.
5. Join each worker using a fresh token requested from the control plane over SSH.
6. Each step waits until its node reports `Ready`.
7. Uninstall reverses every step: workers leave the cluster, kubeadm is reset, packages and config files are removed, and the VMs are deleted.
8. Nodes keep their IP and hostname after a reboot.

## 4. Inputs

| Group | Inputs |
|---|---|
| Connection | `vsphere_secret_name` (secret) |
| Placement | `source_vm_name`, `target_datacenter`, `target_cluster`, `target_host_name`, `target_datastore`, `resource_pool_name`, `vm_cpus` (min 2), `vm_memory_mb` (min 2048) |
| Network | `network_name`, `switch_distributed`, `network_cidr`, `gateway`, `dns_servers` (list), `domain` |
| Cluster nodes | `master_vm_name`/`master_ip`, `worker1_*`, `worker2_*`, `worker3_*` |
| Credentials | `vm_username`, `vm_password_secret` (any secret type whose value is the password) |
| Kubernetes | `k8s_version` (1.30 / 1.31 / 1.32), `pod_network_cidr`, `cni_manifest_url` |

Defaults match the environment above. IPs have no defaults. Secret inputs have no defaults.

## 5. Blueprint design

- Files: `blueprint.yaml`, `inputs.yaml`, `capabilities.yaml`, `CHANGELOG.yaml`, `cluster/definitions.yaml`, and six POSIX shell scripts in `scripts/`.
- Node chain: `*_vm` (vSphere `Server` clones) -> `*_prep` (SSH, Fabric) -> `k8s_control_plane` -> `k8s_worker1..3`.
- Shared settings are defined once as YAML anchors: connection, VM defaults, SSH auth, script environment.
- Capabilities: API endpoint, kubeconfig location, master node, worker list with vSphere IDs, Kubernetes version, ESXi host.
- Scripts are idempotent and safe to retry. Fabric sources scripts in the remote shell, so they use POSIX `sh` only.

## 6. Prerequisites and constraints

- **Template customization:** cloud-init in `LinuxVM-01` must allow VMware customization (`disable_vmware_customization: false`), otherwise clones boot with no IP and SSH never connects. This was fixed on the template; a backup of the original network file is at `/root/50-cloud-init.yaml.bak`.
- **Template reboot risk:** if the template boots without its `OVF ENV` ISO it may fall back to DHCP. Converting it to a real vSphere template removes this.
- **DNS:** the lab blocks 8.8.8.8. Use an internal DNS server, here 192.168.1.2. Nodes must reach `pkgs.k8s.io`, the Ubuntu mirrors and `github.com`.
- **Only the first DNS server is used:** the blueprint writes a single nameserver into each node.
- **Passwordless sudo:** prep gives `demo` passwordless sudo; uninstall removes it.
- **Secrets:** the CLI cannot create secrets (HTTP 405), so they are created in the DAP UI.
- **Orchestrator access:** CLI commands need `--trust-all` because of the self-signed certificate.
- **Unique names:** two clusters cannot share VM names or IPs. Check both before deploying.

## 7. Acceptance criteria

- Blueprint passes `dap-bpa blueprint lint --verify` with no issues and uploads with state `uploaded`.
- Install completes, and all nodes show `Ready` in `kubectl get nodes`.
- Flannel, CoreDNS and kube-system pods are all `Running`.
- Each node has the IP and name the user entered.
- Node IP and hostname are unchanged after a reboot (verified for the master's config only; not yet for a rebooted node).
- Uninstall removes all VMs.

## 8. Revision history and lessons

| Rev | Change | Reason |
|---|---|---|
| 1.0.0 | Initial 3-node blueprint | Original spec |
| 1.0.1 | `vm_password_secret` accepts any secret type | The user's secret was type General |
| 1.0.2 | Install `conntrack` and `socat` | kubeadm 1.31 preflight failed: "conntrack not found" |
| 1.0.3 | Pin static network config, disable cloud-init network and hostname management | Rebooted nodes fell back to DHCP and kubectl broke |
| 1.1.0 | 4 nodes (3 workers) | Request to scale up |

Deployment history:
- `k8s-cluster-01`: failed at creation. The password secret did not exist yet.
- `k8s-cluster-02`: SSH never connected because the clones had no IP. It was uninstalled.
- `k8s-cluster-03`: deployed from 1.0.1 (3 nodes, `.45`-`.47`). The `conntrack` and DNS fixes were applied by hand. It is still running.
- `k8s-cluster-04`: deployed from 1.1.0 (4 nodes, `k8s4-*`, `.48`-`.51`). All nodes `Ready`. It is still running.

## 9. Open items

- Reboot a node of `k8s-cluster-04` to confirm the 1.0.3 fix works on a rebooted node.
- Delete the failed `k8s-cluster-01` and the uninstalled `k8s-cluster-02` in the UI (the CLI has no delete).
- Decide whether `k8s-cluster-03` should be uninstalled. It uses the same host and datastore as `k8s-cluster-04`.
- Convert `LinuxVM-01` to a vSphere template.
- Add multiple DNS servers to the node network config.
- Test a deployment update (adding a node to a running cluster), which has not been tried.
