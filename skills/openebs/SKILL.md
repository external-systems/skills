---
name: openebs
description: "OpenEBS cloud-native storage (4.6.x): the umbrella Helm chart's five CSI engines (Local PV hostpath/LVM/ZFS/rawfile + Replicated PV Mayastor), per-engine node prerequisites (HugePages, nvme_tcp, VGs/zpools), StorageClass parameter tables, DiskPool CRs, NVMe-oF TCP/RDMA, KubeVirt live migration, CloudNativePG storage choice, air-gapped install (incl. verbatim save/push scripts), upgrades, and troubleshooting symptom tables. Load when provisioning Kubernetes storage classes, OpenEBS/Mayastor, or choosing stateful workload storage."
---

# openebs

[OpenEBS](https://openebs.io/docs) is the CNCF Sandbox cloud-native storage
platform for Kubernetes: one umbrella Helm chart that deploys five CSI
storage engines — four node-local engines (Local PV Hostpath, LVM, ZFS,
Rawfile) and one replicated engine (Replicated PV Mayastor, NVMe-oF
TCP). Load this skill when working on OpenEBS, Kubernetes storage
classes / CSI provisioning, or stateful workload storage choices.

This reference is written against **OpenEBS 4.6.x** (umbrella chart
4.6.0, Mayastor extensions chart v2.8.0 / image tag `release-2.8`). The
docs banner at openebs.io/docs shows the current stable version; 4.x
chart values are largely stable, but check the release notes before
major upgrades.

## Where the docs are

| Topic | URL |
|---|---|
| Docs home (4.6.x) | https://openebs.io/docs |
| Prerequisites | https://openebs.io/docs/quickstart-guide/prerequisites |
| Installation | https://openebs.io/docs/quickstart-guide/installation |
| Upgrades | https://openebs.io/docs/user-guides/upgrade |
| Local storage user guide | https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-hostpath/hostpath-overview |
| Replicated storage user guide | https://openebs.io/docs/user-guides/replicated-storage-user-guide/replicated-pv-mayastor/rs-overview |
| Local PV Rawfile | https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-rawfile/rawfile-overview |
| LVM StorageClass parameters | https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-lvm/configuration/lvm-storageclass-parameters |
| ZFS StorageClass parameters | https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-zfs/configuration/zfs-storageclass-parameters |
| DiskPool (Mayastor) | https://openebs.io/docs/user-guides/replicated-storage-user-guide/replicated-pv-mayastor/configuration/rs-create-diskpool |
| Mayastor SC parameters | https://openebs.io/docs/user-guides/replicated-storage-user-guide/replicated-pv-mayastor/configuration/rs-storage-class-parameters |
| KubeVirt live migration (RWX block) | https://openebs.io/docs/Solutioning/kubevirt |
| NFS RWX PVCs | https://openebs.io/docs/Solutioning/read-write-many/nfspvc |
| Air-gapped installation | https://openebs.io/docs/Solutioning/airgapped-installation |
| Troubleshooting (local) | https://openebs.io/docs/troubleshooting |
| Troubleshooting (replicated) | https://openebs.io/docs/troubleshootingre |
| kubectl-openebs plugin | https://openebs.io/docs/user-guides/kubectl-openebs |
| Helm chart values (umbrella) | https://github.com/openebs/openebs/blob/v4.6.0/charts/values.yaml |
| Mayastor subchart values | https://github.com/openebs/mayastor-extensions/blob/v2.8.0/chart/values.yaml |
| Umbrella repo | https://github.com/openebs/openebs |
| Mayastor (data engine) repo | https://github.com/openebs/mayastor |

## One chart, five engines

The umbrella chart bundles everything; engines are toggled under
`engines.*`. The core choice: **Local** engines carve volumes from
plain host disks (no replication — pair with apps that replicate
themselves); **Replicated** (Mayastor) synchronously mirrors across
nodes.

| Engine | Type | Status | Provisioner | Choose when |
|---|---|---|---|---|
| Local PV Hostpath | node-local | stable, prod | `openebs.io/local` | dev/test; replacement for in-tree hostpath CSI |
| Local PV LVM | node-local | stable, prod | `local.csi.openebs.io` | LVM2 users; resize, snapshots, production local storage |
| Local PV ZFS | node-local | stable, prod | `zfs.csi.openebs.io` | ZFS users; datasets + ZVOLs, compression, raidz |
| Local PV Rawfile | node-local | beta, **off by default** | `rawfile.csi.openebs.io` | loop-device block volumes from a dir; CoW snapshots |
| Replicated PV Mayastor | multi-node | stable, prod | `io.openebs.csi-mayastor` | storage-level HA (NVMe-oF), snapshots, clones |

Data-plane characteristics:

- **Local**: no replication; node loss = data unavailability. Right
  choice when the app self-replicates (MongoDB, Cassandra, CloudNativePG)
  or in single-node dev.
- **Replicated**: sync 2/3-way mirroring across nodes, NVMe-oF targets,
  HA failover module; costs HugePages + 2 cores + 1GiB per io-engine pod.

## Prerequisites (per engine)

Supported baseline: Kubernetes ≥ 1.23, Linux kernel ≥ 5.15, LVM2,
ZFS ≥ 0.8. Helm ≥ 3.2 (Mayastor tooling prefers ≥ 3.7). Cluster-admin
context is required (`kubectl auth can-i 'create' 'crd' -A` to check).

### Hostpath

- Directory where volumes live — `BasePath` (default
  `/var/openebs/local`): root-disk dir, or an Ext4-formatted SSD
  mounted at e.g. `/mnt/openebs-local`.
- Needs `xfsprogs` on nodes if you use Local PV hostpath **quotas**.
- Rancher RKE: `extra_binds` for the BasePath
  (`/var/openebs/local:/var/openebs/local`).

### Local PV LVM

- `lvm2` userspace installed on every node; `dm-snapshot` module loaded.
- A volume group exists before install (test via loopback):

```bash
truncate -s 1024G /tmp/disk.img
sudo losetup -f /tmp/disk.img --show   # → /dev/loop0
sudo pvcreate /dev/loop0
sudo vgcreate lvmvg /dev/loop0
```

- Thin provisioning additionally needs `dm_thin_pool`
  (`lsmod | grep dm_thin_pool`, else `modprobe dm_thin_pool`).

### ZFS

- `zfsutils-linux` on every node; a zpool created per node
  (striped / mirror / raidz):

```bash
zpool create zfspv-pool /dev/sdb          # real disk
# testing only (loopback-backed sparse file):
truncate -s 100G /tmp/disk.img
zpool create zfspv-pool $(losetup -f /tmp/disk.img --show)
```

- Custom topology keys (zone/rack scheduling) are set as FAQ-documented
  node labels and referenced from the StorageClass.

### Rawfile

- Only a pool directory per node (default `/var/csi/rawfile`) with
  enough space; the image bundles `losetup` / `mkfs.ext4` / `mkfs.xfs`
  / `mkfs.btrfs`.
- CoW snapshots/clones need the **pool filesystem** to support
  reflinks: btrfs natively; XFS only when the pool device was formatted
  `mkfs.xfs -m reflink=1`; ext4 not at all (falls back to full copy).

### Replicated PV Mayastor

Per worker node hosting an io-engine pod (DaemonSet `openebs-io-engine`):

- **x86-64 with SSE4.2** (older CPUs fail with SIGILL — see exit 132).
- Kernel 5.15 tested, 5.13+ minimum; modules: `nvme_tcp`, `ext4`
  (xfs optional).
- For **exclusive** io-engine use: 2 CPU cores, 1GiB RAM, and HugePages
  — at least **1024 × 2MiB pages (2GiB)** available to the pod.
- `nvme_core.multipath=Y` for HA (optional but recommended).
- Free TCP ports on the node: **10124** (gRPC), **8420 / 4421**
  (NVMf targets). Firewall must not block node-to-node connect.
- Minimum **3 worker nodes**; io-engine nodes ≥ replication factor.
- Label every io-engine candidate node:

```bash
kubectl label node <node> openebs.io/engine=mayastor
```

Enable/persist HugePages (2MiB), then **restart kubelet or reboot** —
Mayastor won't deploy if kubelet's reported HugePages are short:

```bash
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
echo vm.nr_hugepages = 1024 | sudo tee -a /etc/sysctl.conf
```

- If `csi.node.topology.segments` `nodeSelector: true` is set, label
  nodes with the matching topology segments (both csi-node and
  agent-ha-node DaemonSets adopt them).

## Installation (Helm)

```bash
helm repo add openebs https://openebs.github.io/openebs
helm repo update
helm install openebs openebs/openebs -n openebs --create-namespace
```

Default install = hostpath + LVM + ZFS + Mayastor (rawfile off).
Common variants:

```bash
# Local-storage-only cluster (skip the whole Mayastor dependency set):
--set engines.replicated.mayastor.enabled=false
# Enable experimental rawfile:
  --set engines.local.rawfile.enabled=true
# Skip snapshot CRDs if they already exist in the cluster:
  --set openebs-crds.csi.volumeSnapshots.enabled=false
```

Custom kubelet dir (breaks provisioning silently otherwise):

- MicroK8s: `/var/snap/microk8s/common/var/lib/kubelet/`
- k0s: `/var/lib/k0s/kubelet/`
- Rancher/RKE: `/opt/rke/var/lib/kubelet/`

```bash
--set lvm-localpv.lvmNode.kubeletDir=<path>
--set zfs-localpv.zfsNode.kubeletDir=<path>
--set mayastor.csi.node.kubeletDir=<path>
```

View the full image list baked into the chart:

```bash
helm show chart openebs/openebs | yq '.annotations."helm.sh/images"'
```

Verify — pods (abridged for a full default install):

```text
openebs-agent-core-…            2/2  Running     # Mayastor control plane
openebs-api-rest-…              1/1
openebs-csi-controller-…        6/6
openebs-io-engine-…             2/2  (DaemonSet, labeled nodes only)
openebs-etcd-0/1/2              1/1
openebs-nats-0/1/2              3/3
openebs-localpv-provisioner-…   1/1
openebs-lvm-localpv-…           controller 5/5 + node 2/2 per node
openebs-zfs-localpv-…           controller 5/5 + node 2/2 per node
openebs-loki-0, -nats, -promtail, -obs-callhome …
```

StorageClasses created by default:

```text
mayastor-etcd-localpv      openebs.io/local          Delete  WaitForFirstConsumer
mayastor-loki-localpv      openebs.io/local          Delete  WaitForFirstConsumer
openebs-hostpath           openebs.io/local          Delete  WaitForFirstConsumer
openebs-single-replica     io.openebs.csi-mayastor   Delete  Immediate   expansion=true
```

LVM/ZFS produce no default SC — create one per the tables below.

## Helm values quick map

Umbrella `values.yaml` (v4.6.0):

| Value | Default | Meaning |
|---|---|---|
| `global.imageRegistry` | "" | Airgap: override registry host for all images |
| `global.imagePullSecrets` | `[]` | Pull secret(s) merged everywhere |
| `engines.local.{lvm,zfs,hostpath}.enabled` | `true` | Local engines |
| `engines.local.rawfile.enabled` | `false` | Experimental rawfile |
| `engines.replicated.mayastor.enabled` | `true` | Mayastor bundle |
| `openebs-crds.csi.volumeSnapshots.enabled` | `true` | Snapshot CRDs (`keep: true`) |
| `loki.enabled` / `alloy.enabled` | `true` | Log stack on hostpath localpv SCs |

Mayastor subchart high-impact values (`mayastor.*`):

| Value | Default | Note |
|---|---|---|
| `io_engine.cpuCount` | `"2"` | Cores bound per io-engine |
| `io_engine.resources.*.hugepages2Mi` | `"2Gi"` | Must be present on the node |
| `io_engine.nvme.ioTimeout` | `"110s"` | Block IO timeout |
| `csi.node.nvme.ctrl_loss_tmo` | `"1980"` | NVMe controller loss timeout (see reboots) |
| `csi.node.nvme.tcpFallback` | `true` | Falls back nvme-rdma→nvme-tcp |
| `csi.node.kubeletDir` | `/var/lib/kubelet` | Kubelet root |
| `csi.node.topology.segments.nodeSelector` | `false` | Pin DSs by topology segments |
| `io_engine.target.nvmf.rdma.enabled` | `false` | Optional RDMA transport |
| `agents.core.capacity.thin.*` | 250% / 40% | Thin-provisioning overcommit limits (see Replicated StorageClasses) |
| `etcd.replicaCount` | `3` | On `mayastor-etcd-localpv` hostpath |
| `nats.cluster.replicas` | `3` | JetStream, eventing bus |
| `storageClass.nameSuffix` | `single-replica` | SC `openebs-single-replica`, `repl: 1` |
| `eventing.enabled` | `true` | NATS-backed eventing + aggregator |
| `obs.callhome.enabled` | `true` | Phone-home stats (set `false` to silence) |

## Local PV Hostpath

Directory per node under a `BasePath`. SC via annotation:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-hostpath-retain
  annotations:
    cas.openebs.io/config: |
      - name: StorageType
        value: "hostpath"
      - name: BasePath
        value: "/var/openebs/local"
    openebs.io/cas-type: local
provisioner: openebs.io/local
reclaimPolicy: Retain          # safer with databases
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

Data survives PVC deletion under `<BasePath>/<pvc-uid>/` — dump/restore
or Velero (Restic) for real backup. Protects apps from raw hostpath via
masked PVs, and gives topology-aware local-PV scheduling.

## Local PV LVM

Provisioner `local.csi.openebs.io`. Needs `volgroup` **or** `vgpattern`
(one is mandatory; explicit `volgroup` wins over the pattern).

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-lvmpv
allowVolumeExpansion: true
provisioner: local.csi.openebs.io
parameters:
  storage: "lvm"
  vgpattern: "lvmvg.*"        # or: volgroup: "lvmvg" (wins)
  fsType: "xfs"               # ext2|ext3|ext4|xfs|btrfs, default ext4
  thinProvision: "no"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

| Parameter | Values | Notes |
|---|---|---|
| `vgpattern` / `volgroup` | regex / exact VG | One required; `volgroup` wins |
| `fsType` | ext2/3/4, xfs, btrfs | Default `ext4`; format + mount |
| `mountOptions` | list | Applied at pod mount; not applied to raw block volumes |
| `formatOptions` | mkfs string | Once, at first mount/format |
| `shared` | `yes` | Allow multi-pod mount on same node |
| `thinProvision` | `yes`/`no` | Needs `dm_thin_pool` |
| `scheduler` | SpaceWeighted (default), CapacityWeighted, VolumeWeighted | VG-only placement; use WaitForFirstConsumer for k8s-aware scheduling |
| topologies | `allowedTopologies` + `ALLOWED_TOPOLOGIES` env on `openebs-lvm-node` DS (`openebs.io/nodename` default key) | Pin VG availability |

`formatOptions` (per SC) replaces — never merges with — the node-level
`lvmNode.defaultFormatOptions.<fs>` Helm knob; repeat node-wide options
when overriding. Both only affect newly formatted volumes.

## Local PV ZFS

Provisioner `zfs.csi.openebs.io`. `poolname` (existing pool **or** child
dataset) is mandatory. `fstype: zfs` → ZFS **dataset** (no mkfs);
anything else → **ZVOL** formatted with the chosen fs (default ext4).
Parameters apply only to matching type (dataset/ZVOL/both).

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-zfspv
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
parameters:
  poolname: "zfspv-pool"
  fstype: "zfs"
  recordsize: "16K"          # dataset: file block size
  compression: "zstd"
  atime: "off"
  shared: "no"
provisioner: zfs.csi.openebs.io
```

| Parameter | Values | Applies to |
|---|---|---|
| `poolname` (required) | pool or child dataset | both |
| `fstype` | `zfs`, ext2/3/4, xfs, btrfs | both |
| `recordsize` | 512B–128Ki power of 2 | dataset |
| `volblocksize` | power of 2, 512B–128Ki | ZVOL |
| `compression` | on, lz4, zstd, gzip-1..9, … | both |
| `dedup` | on/off | both |
| `atime` | on/off | dataset |
| `logbias` | latency/throughput | both |
| `thinProvision` | yes/no | both |
| `quotatype` | quota (default) / refquota | dataset |
| `shared` | yes/no | both |

`thinProvision` interplay: `yes` allows provisioning past pool capacity;
`no` reserves via (ref)reservation per `quotatype`. Btrfs ZVOLs don't
support online resize. The ZFS engine compliments ZFS-native snapshots
and clones.

## Local PV Rawfile (experimental)

Enable `engines.local.rawfile.enabled=true`. Volumes are files exposed
as loop devices — thick by default (pre-allocated), optional sparse.
`volumeBindingMode: WaitForFirstConsumer` is **required**
(`Immediate` → "No preferred topology set"), as the scheduler must
choose the node first.

| Parameter | Values | Note |
|---|---|---|
| `csi.storage.k8s.io/fstype` | ext4 (default), xfs, btrfs | Ignored for `volumeMode: Block` |
| `thinProvision` | `true`/`false` | Thin = sparse file; monitor pool |
| `copyOnWrite` | true/false/unset | Reflink CoW; unset = autodetect per pool |
| `freezeFs` | `true`/`false` | FS freeze during in-use snapshots |
| `formatOptions` | e.g. `-m 0` | ext4 reserves 5% root unless `-m 0` |
| `storagePool` | name | Omit entirely for default pool (`""` invalid) |
| `mountOptions` | e.g. `noatime` | Passed to mount |

CoW support matrix (snapshot/clone speed):

| Pool filesystem | CoW | Setup |
|---|---|---|
| btrfs | yes | none |
| XFS | yes | `mkfs.xfs -m reflink=1` on pool device |
| ext4 | no | full-copy snapshots |

VolumeSnapshotClass `rawfile-localpv` ships with the chart. Monitor
`rawfile_pool_remaining_capacity_bytes` when thin-provisioned.

## Replicated PV Mayastor

### Create DiskPools

Each pool owns exactly one whole block device per node, exclusive
forever (data destroyed). One pool per replica slot; no two replicas of
a volume land on the same node (3-way mirror ⇒ ≥3 nodes, each with a
pool).

```yaml
apiVersion: "openebs.io/v1beta3"
kind: DiskPool
metadata:
  name: pool-on-node-1
  namespace: openebs
spec:
  node: worker-1
  disks: ["aio:///dev/disk/by-id/<id>"]
  maxExpansion: "5x"
```

- Reference a stable device link (`by-id`/`by-path`), never `/dev/sdx`
  (name changes on reboot → data loss).
- Scheme options: `aio:///dev/disk/by-id/…` (best practice),
  `uring:///dev/disk/by-id/…`, or plain `/dev/...`.
- `maxExpansion` (factor `5x` or absolute `6TiB`) is **set at creation**,
  immutable later; unset = no expansion (1×).
- Replica-topology placement: label pools
  `spec.topology.labelled.<key>: <value>` (or
  `kubectl openebs mayastor label pool <pool> key=value -n openebs`) and
  read them from the SC's `poolHasTopologyKey` /
  `poolAffinityTopologyLabel`.

Verify: `kubectl get dsp -n openebs` — State `Online`, `Healthy`.

### Replicated StorageClasses

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mayastor-3
provisioner: io.openebs.csi-mayastor
allowVolumeExpansion: true
parameters:
  protocol: nvmf
  repl: "3"
  thin: "true"
  fsType: "xfs"
```

| Parameter | Values | Note |
|---|---|---|
| `repl` | `"1"`..`"3"` | Copies maintained; tolerates repl−1 node failures || `protocol` | `nvmf` | Only valid value |
| `thin` | `true`/`false` | Default thick; thin ⇒ watch pool commitment |
| `fsType` | ext4 (default), xfs, btrfs | Prefer xfs |
| `formatOptions` | mkfs flags | Concatenated with global xfs opts |
| `overrideGlobalFormatOpts` | `true` | Ignore Helm-global xfs options |
| `encrypted` | `true` | Needs ≥ repl encrypted-capable pools |
| `snapshotRestorePolicy` | `strict`(default)/`bestEffort` | bestEffort restores under-replicated then rebuilds |
| `ioTimeout` | string | Fight NVMe timeouts (see reboots) |

Key behaviors:

- `thin: true` volumes are **thin-provisioned end to end** — pool
  commitment scheduling is governed by
  `agents.core.capacity.thin.{poolCommitment=250%,volumeCommitment=40%,volumeCommitmentInitial=40%}`.
  Out-of-space pools trigger replica migration + rebuild rather than
  faulting, but monitor exporter metrics.
- Replicas are either all thick or all thin; pools cannot be expanded
  retroactively (size cap fixed by device; only `maxExpansion` growth).
- The chart's built-in `openebs-single-replica` SC is a repl=1 template
  with expansion enabled.
- Volumes are "highly durable"; without NVMe multipathing they are not
  "highly available" — a single target instance (NVMe-oF) serves the
  volume, and the HA failover agent moves the target on node loss
  (needs `nvme_core.multipath=Y`).

## NVMe-oF (TCP)

- StorageClass `protocol: nvmf`. Export is **NVMe-oF TCP only**.
- Initiator (every scheduling) node: kernel ≥ 5.13 and `nvme_tcp`
  module loaded; otherwise mounts fail or degrade.
- RDMA possible on RNICs:
  `mayastor.io_engine.target.nvmf.rdma.enabled=true` +
  `iface: <rdma-netdev>` (e.g. mlx5_0-backed eth0);
  `csi.node.nvme.tcpFallback: true` keeps TCP initiators working
  where RDMA is absent.
- Out-of-the-box HA detection: per *node-path*
  (asymmetric partitions can ping-pong, see KubeVirt limitations).
- The default `ctrl_loss_tmo` is long (1980s) which makes node reboots
  slow when apps hold volumes; cordon + drain first, or tune
  `csi.node.nvme.io_timeout` / SC `ioTimeout`.

## KubeVirt VM live migration

Two documented paths:

### 1. Native RWX block (experimental)

Mayastor-only, KubeVirt-only, `volumeMode: Block` only. StorageClass:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mayastor-rwx-block
provisioner: io.openebs.csi-mayastor
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
parameters:
  protocol: nvmf
  repl: "2"
  thin: "true"
  rwxBlock: "true"
```

Flow: KubeVirt operator + CR → CDI operator + `cdi-cr` → a CDI
DataVolume with `accessModes: [ReadWriteMany]`, `volumeMode: Block` →
VM manifest (`evictionStrategy: LiveMigrate`, virtio disk from the PVC)
→ `virtctl migrate <vm>`; validated against KubeVirt v1.8.3 / K8s
v1.33.12 / OpenEBS v4.5.0 / CDI v1.65.0. Both source and destination
nodes hold the NVMe path during migration; only one VM instance writes
at a time.

Caveats: containerd may need
`device_ownership_from_security_context = true` (in
`/etc/containerd/config.toml` + restart) for CDI block imports.

Known limitation: during a network partition where the *source* node's
NVMe path stays reachable but the migration *target* node's path fails,
the HA agent may repeatedly fail over/republish (ping-pong) instead of
settling, until migration recovery fails; per-path detection is not yet
volume-aware for multi-attach scenarios. Expect quirks under complex
network faults; normal migrations are stable.

### 2. NFS intermediary (stable, more portable)

Mayastor RWO PVC (e.g. `mayastor-3`) → `nfs-server-alpine` pod
(`SHARED_DIRECTORY: /nfsshare`, privileged, port 2049) → ClusterIP
service → install NFS CSI driver `nfs.csi.k8s.io` (namespace
`csi-nfs`) → StorageClass:

```yaml
storageClass:
  create: true
  name: nfs-csi
  parameters:
    server: nfs-server.nfs-server.svc.cluster.local
    share: /
  mountOptions: [nfsvers=4.1]
```

Then RWX PVCs against `nfs-csi` for shared access (or the KubeVirt NFS
migration guide).

## Using with LVM and ZFS (host design)

The Hostpath engine is generic, but LVM and ZFS LocalPVs want prepared
per-node pools and are node-fate-bound (a PV's node affinity is
permanent). All they need is for a VG (`lvmvg`) or zpool
(`zfspv-pool`) to exist per node: LVM consumes an existing VG (one or
more PVs), ZFS an existing zpool (striped/mirror/raidz). On this
flake, machines declare their disk layouts with disko — use it to
carve the dedicated VG or pool before installing the driver (see
`skills/disko/SKILL.md`).

- Keep storage-pool devices out of the boot/root pool; LocalPV volume
  data lands directly in the VG/zpool, one LV or dataset/zvol per PV.
- Create pool capacity before installing the driver (the driver picks
  it up at start; `lvmdiskscan`, `zpool status` to verify).
- ZFS: choose the SC `quotatype` (`quota` counts snapshots/clones
  against the limit, `refquota` does not) and know that `thinProvision`
  overrides whether space is reserved at all.

## CloudNativePG (brief)

CNPG clusters work with any StorageClass — but it **replicates
Postgres itself** across instances, so prefer **single-replica
storage** (`openebs-single-replica`, or a local engine such as LVM —
the popular on-prem choice); Replicated `repl > 1` doubles writes and
inflates disk I/O/space ("write amplification"). Keep dynamic
provisioning (don't pre-provision PVs — it breaks CNPG self-healing),
add pod anti-affinity so instance volumes spread across nodes (each
instance's volume stays node-local), pick a snapshot-capable backend
(all OpenEBS engines are) for VolumeSnapshot-based backups, and
benchmark first with `fio` + `pgbench`. Docs:
https://cloudnative-pg.io/docs/current/storage/.

## Upgrades

`kubectl openebs` (plugin) drives all storage upgrades:

```bash
# binary from https://github.com/openebs/openebs/releases
kubectl openebs upgrade -n openebs
kubectl openebs upgrade status -n openebs
```

Upgrade from 4.x → 4.6: run the plugin, then verify CRDs/volumes/
snapshot/StoragePools unaffected. **Downgrades are not supported.**
Upgrading installs **all four engines**; add
`--set engines.replicated.mayastor.enabled=false` if you only want
Local PV.

Upgrade from **3.x → 4.x**: the Helm repo URL changed with 4.x; re-add
it (`helm repo remove openebs && helm repo add openebs
https://openebs.github.io/openebs`) before the plugin upgrade. Also
pass `--set mayastor.agents.core.rebuild.partial.enabled=false` during
the upgrade (data consistency), then re-enable after with
`kubectl openebs upgrade -n <ns> --set
mayastor.agents.core.rebuild.partial.enabled=true`.

## Uninstall + kubectl-openebs cheatsheet

```bash
kubectl openebs mayastor get pools   -n openebs   # pool health
kubectl openebs mayastor get volumes -n openebs   # states, repl, sizes
kubectl openebs mayastor get block-devices worker-1   # disk candidates
kubectl openebs mayastor drain node <node>            # node ops
kubectl openebs localpv-lvm get volumes              # local engines
kubectl openebs localpv-zfs get pools
kubectl openebs localpv-hostpath get volumes
```

Plugin namespace: defaults to the *kubeconfig context namespace*, set
with `kubectl config set-context --namespace=openebs --current`;
`--kubeconfig` / `-n` override per call.

Uninstall is `helm uninstall openebs -n openebs` — CRDs are kept
(`crds.keep: true`) so PVC data survives; follow the docs before
deleting PV data.

## Air-gapped installation

Official playbook (commands pinned to the release; keep **chart
version = images.txt tag = `--version` identical** — mixing versions
yields missing-image/digest-mismatch):

Artifacts on the internet-connected host:

```bash
export OPENEBS_VERSION=4.6.0
mkdir -p openebs-airgap && cd openebs-airgap
# Image list (all images for this chart tag):
wget https://raw.githubusercontent.com/openebs/openebs/refs/tags/v${OPENEBS_VERSION}/charts/images.txt
# Chart as a local tgz:
helm repo add openebs https://openebs.github.io/openebs
helm repo update
helm pull openebs/openebs --version ${OPENEBS_VERSION}
# (+ kubectl-openebs plugin binary, and helm itself if the offline side lacks it)
```

Image list spans `docker.io`, `quay.io`, `registry.k8s.io`,
`ghcr.io` — the save/push scripts **keep each image's original
org/path and only rewrite the registry host**, which keeps multiple
tags of the same binary apart (e.g. `csi-snapshotter` v7/v8). For a
Local-PV-only install, delete the Mayastor + observability + dev image
lines from `images.txt` before running (keep `provisioner-localpv`,
`lvm-driver`, `zfs-driver`, `rawfile-localpv`, `linux-utils`,
`alpine-bash`, plus the CSI sidecars of what you enable).

Save images on the connected host (export optional; skip the tarball
when it can push directly):

```bash
./openebs-save-images.sh --image-list images.txt
# or pull AND export:
./openebs-save-images.sh --image-list images.txt --images openebs-images.tar.gz
```

Transfer `openebs-images.tar.gz` / chart tgz / `images.txt` / scripts
to the air-gapped host, `docker login <registry-url>`, then push:

```bash
./openebs-push-images.sh --registry <registry-url> \
  --image-list images.txt --images openebs-images.tar.gz
```

Install from the local tgz with registry overrides:

```bash
kubectl create namespace openebs
kubectl create secret docker-registry openebs-regcred -n openebs \
  --docker-server=<registry-url> \
  --docker-username='<user>' --docker-password='<password>'
helm install openebs ./openebs-${OPENEBS_VERSION}.tgz \
  --namespace openebs --create-namespace --values airgap-values.yaml
```

`airgap-values.yaml` shape:

```yaml
global:
  imageRegistry: "<registry-url>"      # ZFS/LVM/rawfile/Mayastor/etcd
  imagePullSecrets:
    - openebs-regcred
  image:
    registry: "<registry-url>"         # Loki + Alloy
    pullSecrets:
      - name: openebs-regcred
mayastor:
  nats:
    imagePullSecrets:
      - name: openebs-regcred
    nats:
      image:
        registry: "<registry-url>"
    reloader:
      image:
        registry: "<registry-url>"
    exporter:
      image:
        registry: "<registry-url>"
loki:
  imagePullSecrets:
    - name: openebs-regcred
  minio:
    imagePullSecrets:
      - name: openebs-regcred
    image:
      repository: "<registry-url>/minio/minio"
    mcImage:
      repository: "<registry-url>/minio/mc"
  sidecar:
    image:
      repository: "<registry-url>/kiwigrid/k8s-sidecar"
```

If your registry uses a private CA, install it on every node's
container runtime first.

Verify:

```bash
kubectl get pods -n openebs -o wide           # no ImagePullBackOff
kubectl get pods -n openebs \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u
kubectl get sc
```

A wrong host, a dropped org/path segment, or a missing pull secret is
almost always the ImagePullBackOff cause — cross-check against registry
catalog.

### openebs-save-images.sh

```bash
#!/usr/bin/env bash
#
# openebs-save-images.sh
# Pulls every image in an OpenEBS images.txt on an internet-connected host,
# and (optionally) exports them to a single tar.gz for transfer into an
# air-gapped environment.
#
# Unlike a single-namespace flatten, this script does NOT rewrite image
# paths. It pulls each reference exactly as listed so the full
# registry/org/path structure is preserved for the push step.

list="images.txt"
CONTAINER_CLI=${CONTAINER_CLI:-docker}

while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
		-i|--images)
		images="$2"
		shift; shift
		;;
		-l|--image-list)
		list="$2"
		shift; shift
		;;
		-p|--platform)
		platform="$2"
		shift; shift
		;;
		-h|--help)
		help="true"
		shift
		;;
		*)
		echo "Error! invalid flag: ${key}"
		help="true"
		break
		;;
	esac
done

usage () {
	echo "USAGE: $0 [--image-list images.txt] [--images openebs-images.tar.gz] [--platform linux/amd64]"
	echo "  [-l|--image-list path]   text file with a list of images, one per line."
	echo "  [-p|--platform os/arch]  pull each image for the specified platform (e.g. linux/amd64)."
	echo "  [-i|--images path]       tar.gz to create via 'save'. If omitted, images are only pulled,"
	echo "                           not exported (use this when the connected host can push directly"
	echo "                           to the private registry)."
	echo "  [-h|--help]              this message."
	echo ""
	echo "To use podman instead of docker set the environment variable CONTAINER_CLI=podman"
}

if [[ $help ]]; then
	usage
	exit 0
fi

if [[ ! -f "$list" ]]; then
	echo "Error: image list '$list' not found." >&2
	exit 1
fi

set -e -x

# Ignore blank lines and comments so the list stays editable.
mapfile -t refs < <(grep -vE '^[[:space:]]*(#|$)' "${list}")

for i in "${refs[@]}"; do
	if [ -n "$platform" ]; then
		$CONTAINER_CLI pull "${i}" --platform "$platform"
	else
		$CONTAINER_CLI pull "${i}"
	fi
done

if [[ $images ]]; then
	$CONTAINER_CLI save "${refs[@]}" | gzip -c > "${images}"
fi
```

### openebs-push-images.sh

```bash
#!/usr/bin/env bash
#
# openebs-push-images.sh
# Loads images (optionally from a tar.gz) and pushes them to a private
# registry, PRESERVING each image's original org/path and tag.
#
# The OpenEBS image list spans several source registries
# (docker.io, ghcr.io, quay.io, registry.k8s.io). This script rewrites
# ONLY the source-registry host, e.g.
#
#   docker.io/openebs/lvm-driver:1.9.1
#     -> my.registry:5000/openebs/lvm-driver:1.9.1
#
#   registry.k8s.io/sig-storage/csi-attacher:v4.8.1
#     -> my.registry:5000/sig-storage/csi-attacher:v4.8.1
#
#   ghcr.io/openebs/mayastor/dev/mayastor-io-engine:v2.11.1
#     -> my.registry:5000/openebs/mayastor/dev/mayastor-io-engine:v2.11.1
#
# Preserving the path keeps otherwise-identical basenames distinct
# (the docker.io/openebs/* set vs the ghcr.io/openebs/mayastor/dev/* set)
# and keeps multiple tags of the same image (e.g. csi-snapshotter v7/v8)
# intact. It also means your Helm overrides only need to change the
# registry host, not every repository path.

list=""
CONTAINER_CLI=${CONTAINER_CLI:-docker}

while [[ $# -gt 0 ]]; do
	key="$1"
	require_value () {
		if [[ -z "$2" || "$2" == -* ]]; then
			echo "Error: option '$1' requires a value." >&2
			exit 1
		fi
	}
	case $key in
		-r|--registry)
		require_value "$key" "$2"
		reg="$2"
		shift; shift
		;;
		-l|--image-list)
		require_value "$key" "$2"
		list="$2"
		shift; shift
		;;
		-i|--images)
		require_value "$key" "$2"
		images="$2"
		shift; shift
		;;
		-h|--help)
		help="true"
		shift
		;;
		*)
		echo "Error! invalid flag: ${key}"
		help="true"
		break
		;;
	esac
done

usage () {
	echo "USAGE: $0 --registry <registry-url> --image-list images.txt [--images openebs-images.tar.gz]"
	echo "  [-r|--registry host:port] target private registry (required)."
	echo "  [-l|--image-list path]    text file with a list of images, one per line (required)."
	echo "  [-i|--images path]        tar.gz produced by the save step. If omitted, the script"
	echo "                              assumes the images are already present locally."
	echo "  [-h|--help]               this message."
	echo ""
	echo "To use podman instead of docker set the environment variable CONTAINER_CLI=podman"
}

if [[ $help ]]; then
	usage
	exit 0
fi

if [[ -z $reg ]]; then
	echo "Error: --registry is required." >&2
	usage
	exit 1
fi

if [[ -z $list ]]; then
	echo "Error: --image-list is required." >&2
	usage
	exit 1
fi

if [[ ! -f "$list" ]]; then
	echo "Error: image list '$list' not found." >&2
	exit 1
fi

set -e -x

if [[ $images ]]; then
	$CONTAINER_CLI load --input "${images}"
fi

 mapfile -t refs < <(grep -vE '^[[:space:]]*(#|$)' "${list}")

for src in "${refs[@]}"; do
	# Strip the source-registry host (first path segment) only.
	# All source refs here are fully qualified (docker.io/..., ghcr.io/...,
	# quay.io/..., registry.k8s.io/...), so the first segment before the
	# first '/' is always the host.
	path="${src#*/}"
	dst="${reg}/${path}"

	# Resolve the locally-stored reference. Docker Hub images are normalized
	# on pull: 'docker.io/grafana/alloy:x' is stored as 'grafana/alloy:x',
	# and 'docker.io/nats:x' (implicit library/) as 'nats:x'. Try the ref as
	# listed first, then the docker.io-stripped form, then the bare name.
	local_ref=""
	for cand in "${src}" "${src#docker.io/}" "${src#docker.io/library/}"; do
		if $CONTAINER_CLI image inspect "${cand}" >/dev/null 2>&1; then
			local_ref="${cand}"
			break
		fi
	done

	if [[ -z $local_ref ]]; then
		echo "ERROR: image not found locally for '${src}'." >&2
		echo "       Run the save step first, or pass --images <tarball> to load it." >&2
		exit 1
	fi

	$CONTAINER_CLI tag "${local_ref}" "${dst}"
	$CONTAINER_CLI push "${dst}"
done
```

## Troubleshooting

Collect control-plane and data-plane logs as needed; if unsure,
collect logs of all Replicated Storage control-plane pods
(csi-controller, core-agent, rest, msp-operator):

```bash
kubectl -n openebs get pods -o wide
kubectl -n openebs logs <io-engine-pod> mayastor        # data plane
kubectl -n openebs logs <mayastor-csi-pod> mayastor-csi # (un)mount issues
kubectl logs -n openebs -l openebs.io/component-name=openebs-localpv-provisioner
```

CSI sidecar logs (attacher/provisioner/registrar) live in the same
pods when driver registration fails.

### Local storage symptom → cause → fix

| Symptom | Cause | Fix |
|---|---|---|
| PVC Pending, PV never created | SC is `WaitForFirstConsumer` — provision waits for a pod to schedule | Deploy the consumer pod; don't use `nodeName` (bypasses scheduler); use `nodeSelector: kubernetes.io/hostname` |
| `Forbidden` creating clusterroles on install | kubelet-installer lacks cluster-admin (AKS/GKE RBAC off) | Grant cluster-admin to the installing user first |
| provisioner pod CrashLoopBackOff | CNI / network plumbing — apiserver requests lost | Check network pods, use current CNI images |
| xfs volume: `mount: wrong fs type, bad superblock` + `dmesg` shows `unknown incompatible features (0x20)` | Newer `mkfs.xfs` (in driver image) sets features too new for node kernel (`nrext64` needs ≥5.19; `bigtime`/`inobtcount` ≥5.10) | Upgrade kernel, or format without the feature: SC `formatOptions: "-i nrext64=0"` or Helm `--set-string 'lvmNode.defaultFormatOptions.xfs=-i nrext64=0'` (LVM) / `--set-string 'zfsNode.defaultFormatOptions.xfs=-i nrext64=0'` (ZFS). Already-formatted volumes must be recreated |
| Pods `Running→unknown→Terminating` under heavy I/O | Node under-resourced (evictions, NodeControllerEviction) | Add node CPU/memory |
| OpenShift: driver can't see disks | `multipath.conf` claims all SCSI devices | Set `find_multipaths yes` in `/etc/multipath.conf`, `multipath -w /dev/<dev>` |
| openSUSE CaaS nodes reboot almost daily | transactional-update/rebootmgr scheduled reboots | `systemctl disable --now rebootmgr.service transactional-update.timer`, or stagger the reboot timers so nodes reboot one at a time |
| OpenEBS "install failed" in cluster with client cert-based admin | kubeconfig context not cluster-admin | `kubectl auth can-i 'create' 'crd' -A`; else create admin context |

### Replicated storage symptom → cause → fix

| Symptom | Cause | Fix |
|---|---|---|
| io-engine pod exits code **132** at PVC mount | `SIGILL` — CPU lacks SSE4.2 | Use SSE4.2-capable nodes |
| io-engine fails: `couldn't allocate memory due to IOVA exceeding limits of current DMA mask` | Host IOMMU on | `--set mayastor.io_engine.envcontext=iova-mode=pa` (PA DMA) |
| Eventing-aggregator pod stuck in Init | NATS not up | Wait for NATS readiness; check namespace pods |
| `kubectl openebs mayastor get events` empty | eventing/aggregator disabled, or filters/window too narrow | Confirm `mayastor.eventing.enabled` + `aggregator.enabled`; widen with `--since 7d`, drop filters |
| Events older than requested window missing | No Loki; aggregator's emptyDir + `dirSizeLimit` bound | Deploy Loki (or enlarge `mayastor.eventing.aggregator.dirSizeLimit`) |
| Loki returns fewer events than `--since` | Loki retention / max query range (default 30d) | Tune `retention_period` + `max_query_range` in `limits_config` |
| `kubectl get dsp` errors after upgrade | stale v1alpha1/v1beta1 discovery cache | Query `kubectl get diskpools.openebs.io -n openebs`; verify served version with `kubectl get crd diskpools.openebs.io`; use `apiVersion: openebs.io/v1beta3` in manifests |
| Node reboots take tens of minutes with Mayastor volumes | Long default NVMe `ctrl_loss_tmo` (1980s) | Cordon/drain before reboot; tune SC `ioTimeout` or `csi.node.nvme.io_timeout` |
| Node restarts when scheduling an exporter+mayastor pod | hwmon kernel bug (`/host/sys/class/hwmon` leak on nexus disconnect) | Kernel ≥ 5.13 |
| pool disk goes offline, io-engine restart loops | pool device inaccessible | Rework disk cabling/replacement; keep device by stable by-id links |
| RKE/RancherOS: CSI registration fails, no provisioned volumes | kubelet plugin path mismatch | `extra_binds` / `services_kubelet.extra_binds`: `/opt/rke/var/lib/kubelet/plugins:/var/lib/kubelet/plugins` |

Coredumps (Rust panic/post-mortem): install `systemd-coredump` + `gdb`,
`coredumpctl list`, extract the `.lz4`, copy the container's `/bin` +
`/nix` filesystems out with `docker cp`, then
`gdb -c core /tmp/rootdir/bin/mayastor` with `set sysroot /tmp/rootdir`
and `thread apply all bt` — see the docs page for the full recipe.

## Gotchas

- **WaitForFirstConsumer semantics** — hostpath derived SCs won't bind
  until a consuming pod schedules, and `nodeName` bypasses the
  scheduler so the PVC hangs forever.
- **`io.openebs.csi-mayastor` SCs need an NVMe-oF TCP initiator** —
  every worker that mounts a replicated volume needs kernel ≥ 5.13 with
  `nvme_tcp` loaded; no NVMe multipath = durable but not HA.
- **HugePages are a hard gate** — short of 1024×2MiB pages, io-engine
  never schedules, and a hugepage tweak requires kubelet restart or
  reboot.
- **`engines.replicated.mayastor.enabled=false`** is the way to a lean
  local-only install; the umbrella always tries to install all engines
  on *upgrade* if left unset.
- **Rawfile must use WaitForFirstConsumer** (`Immediate` provisioning
  fails) and its CoW snapshots depend on the *pool* filesystem
  (btrfs/XFS-with-reflink only — ext4 full-copies).
- **LVM/ZFS engines need the pool pre-created per node** (VG or zpool),
  and `volgroup`/`poolname` must match global names across nodes.
- **DiskPool devices are consumed destructively** — exclusive whole
  block devices, `aio:///dev/disk/by-id/…` links only, `maxExpansion`
  fixed at creation.
- **Kernel-vs-mkfs.xfs drift** breaks `xfs` volume mounts — when the
  `mkfs.xfs` inside the driver image is newer than node kernels, pin
  `formatOptions` (per SC) or node-level `defaultFormatOptions` Helm
  values (e.g. `-i nrext64=0`).
- **XFS features** (`bigtime`, `inobtcount`, `nrext64`) fail at
  *mount* time, not format time — the volume formats fine and then
  won't mount; format options only apply on first formatting, so
  already-formatted volumes must be recreated.
- **Upgrades are one-way** (no downgrade); 3.x→4.x additionally needs
  `partial rebuild disabled` for data consistency (re-enable after).
- **OpenEBS components log via `openebs.io/logging: "true"` labels** —
  Loki/Alloy/promtail scrape those; without the observability subset
  some flags (`--loki-endpoint`, Loki retention) mis-fire.
