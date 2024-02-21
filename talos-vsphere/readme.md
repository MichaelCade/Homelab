# Setting up Talos Kubernetes Cluster on vSphere
## Introduction
In this guide, we will walk through the steps to create a Talos Kubernetes cluster on VMware vSphere. Talos is a modern operating system designed for Kubernetes, and we will leverage Govc and Talosctl for the setup process.

## Prerequisites
- A running VMware vSphere infrastructure.
- Govc installed on your local machine.
```
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | sudo tar -C /usr/local/bin -xvzf - govc
```

- Talosctl installed on your local machine.

```
mkdir talos-vsphere
curl -sL https://talos.dev/install | sh
```

## Configuration
1. Download the Talos patch YAML file for vSphere and configure the VIP.

```
curl -fsSLO https://raw.githubusercontent.com/siderolabs/talos/master/website/content/v1.6/talos-guides/install/virtualized-platforms/vmware/cp.patch.yaml
```

2. Generate machine configurations for the Talos cluster.

```
talosctl gen config vmware-test https://192.168.169.202:6443 --config-patch-control-plane @cp.patch.yaml
```

3. Add Kubernetes version to the generated configuration.

```
talosctl gen config --kubernetes-version=1.27.7 vmware-test https://192.168.169.202:6443 --config-patch-control-plane @cp.patch.yaml
```
4. Validate the configurations.

```
talosctl validate --config controlplane.yaml --mode cloud
talosctl validate --config worker.yaml --mode cloud
```

## Environment Variables
Set up environment variables for Govc.

```
export GOVC_URL=https://192.168.169.181/
export GOVC_USERNAME=administrator@vzilla.local
export GOVC_PASSWORD=Passw0rd999!
export GOVC_DATACENTER="vZilla DC"
export GOVC_DATASTORE=NETGEAR716
export GOVC_NETWORK="VM Network"
export GOVC_INSECURE=true
export CLUSTER_NAME=vZilla-Cluster
```

## Scripted Installation
Download the Talos installation script and configure the cluster size.

```
curl -fsSLO "https://raw.githubusercontent.com/siderolabs/talos/master/website/content/v1.6/talos-guides/install/virtualized-platforms/vmware/vmware.sh"
nano vmware.sh
```

Check the Talos version and modify the cluster size if needed.

```
./vmware.sh version
```

## Cluster Deployment
1. Import the Talos OVA.

```
./vmware.sh upload_ova
```
2. Create the Talos cluster.

```
./vmware.sh create
```

3. Bootstrap the cluster.

The node `-n` is going to come from either checking the vSphere terminal or 

```
talosctl --talosconfig talosconfig bootstrap -e <IP> -n <IP>
```

## Kubeconfig Configuration
Configure Kubeconfig for Talos cluster.  In my case here `192.168.169.202` is my IP 

```
talosctl --talosconfig talosconfig config endpoint <IP>
talosctl --talosconfig talosconfig config node <IP>
talosctl --talosconfig talosconfig kubeconfig .
```
View cluster nodes.

```
kubectl --kubeconfig=kubeconfig get nodes
```

## VMtools Configuration
Configure VMtools for Talos.
```
talosctl --talosconfig talosconfig -n 192.168.169.202 config new vmtoolsd-secret.yaml --roles os:admin

kubectl --kubeconfig=kubeconfig -n kube-system create secret generic talos-vmtoolsd-config --from-file=talosconfig=./vmtoolsd-secret.yaml

kubectl --kubeconfig=kubeconfig get pods -n kube-system
```

## vSphere Cloud Provider Interface (CPI)
Download and configure vSphere Cloud Controller Manager.

```
export VERSION=1.27
wget https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/release-$VERSION/releases/v$VERSION/vsphere-cloud-controller-manager.yaml

nano vsphere-cloud-controller-manager.yaml

kubectl --kubeconfig=kubeconfig apply -f vsphere-cloud-controller-manager.yaml
```

## vSphere CSI
1. Apply the vSphere CSI namespace and label.

```
kubectl --kubeconfig=kubeconfig apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.0.0/manifests/vanilla/namespace.yaml

kubectl --kubeconfig=kubeconfig label ns vmware-system-csi pod-security.kubernetes.io/enforce=privileged
```
2. Create a vSphere config file.

```
nano csi-vsphere.conf
```

```
[Global]
cluster-id = "vZilla-Cluster"

[VirtualCenter "192.168.169.181"]
insecure-flag = "true"
user = "administrator@vzilla.local"
password = "Passw0rd999!"
port = "443"
datacenters = "vZilla DC"
```
3. Create a Kubernetes secret for vSphere credentials.

```
kubectl --kubeconfig=kubeconfig create secret generic vsphere-config-secret --from-file=csi-vsphere.conf --namespace=vmware-system-csi

kubectl --kubeconfig=kubeconfig get secret vsphere-config-secret --namespace=vmware-system-csi
```
4. Install vSphere Container Storage Plug-in.

```
kubectl --kubeconfig=kubeconfig apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.0.0/manifests/vanilla/vsphere-csi-driver.yaml
```
5. Verify the installation.

```
kubectl --kubeconfig=kubeconfig get deployment --namespace=vmware-system-csi
kubectl --kubeconfig=kubeconfig get pods --namespace=vmware-system-csi
kubectl --kubeconfig=kubeconfig describe csidrivers
kubectl --kubeconfig=kubeconfig get CSINode
```
## Define StorageClass
Create a StorageClass for vSphere.

```
nano vsphere-sc.yaml
```
```
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: example-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.vmware.com
parameters:
  datastoreurl: "ds:///vmfs/volumes/203747f8-c8b69fd1/"
```

Apply the StorageClass.

```
kubectl --kubeconfig=kubeconfig apply -f vsphere-sc.yaml
```
## Testing
Create a Persistent Volume Claim (PVC) for testing.

```
nano example-pvc.yaml
```
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: example-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: example-sc
```
Apply the PVC.

```
kubectl --kubeconfig=kubeconfig apply -f example-pvc.yaml
kubectl --kubeconfig=kubeconfig get pvc
```
## Merge Kubeconfig Files
Merge Kubeconfig files for easier management.

```
KUBECONFIG=~/.kube/config:kubeconfig kubectl config view --flatten > ~/.kube/config_tmp
mv ~/.kube/config_tmp ~/.kube/config
kubectl config get-contexts
```


## Delete Cluster
If needed, delete the Talos cluster.

```
export CLUSTER_NAME="vZilla-Cluster"
```
```
./vmware.sh destroy
```

This concludes the comprehensive guide for setting up a Talos Kubernetes cluster on VMware vSphere, including configuring vSphere CSI and StorageClass, testing, and cleanup.
