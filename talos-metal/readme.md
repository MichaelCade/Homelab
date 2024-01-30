## Talos Linux on Metal 

This walkthrough is used in my home lab environment which consists of 

5 x Dell Optiplex 7060 
i5-8500T (6 Cores, 6 threads) 
16/32GB RAM 
256GB SSD 
512GB m.2 nvme

Dell X1026 - 24 Port Switch

![](Picture1.png)

There are some current upgrade plans 

- Upgrade all nodes to 32GB RAM 

## Current State / Update 

We have a 5 node (3 x Control Plane)(2 x Worker node) cluster running Talos Linux with configuration file in this folder. This Readme is so that I can remember how to start from scratch and help anyone else that stumbles across said readme to do the same in their homelab environment. 

A 5 node cluster with the OS being installed on the SSD drives, the nvme drives will be used in a CEPH cluster later on down the line. 

I also have a shared NAS device which will be used by the cluster with the (CSI-Driver-NFS)[https://github.com/kubernetes-csi/csi-driver-nfs?tab=readme-ov-file] Details and process shared below.

To Do list 
- CEPH Cluster 

## Getting Started 

From scratch I downloaded the Talos Linux ISO from the (Talos Release Page)[https://github.com/siderolabs/talos/releases/latest/] I then added this to my (Ventoy)[https://www.ventoy.net/en/index.html] Ventoy is an Open Source tool to create a bootable USB for ISO files. I then went through the manual process on each node of booting from the USB. 

On your workstation we will need `talosctl` this a CLI tool which interfaces with the TalosAPI, We can find out the steps required here in the (Getting Started)[https://www.talos.dev/v1.6/introduction/getting-started/] guide. 

Networking wise I have chosen static IPs in my network that I can use for both the VIP and each node without affecting DHCP on my home network. It is quite simple to run through and configure each node with this static IP address. `F3` and then change the values to your network configuration. 

## Configuration Files 

Next up we need to create some config files, you will see these steps documented but for me I am going to note down my steps. With the below command I am specifically using this version of Kubernetes because some software that I want to use supports up to this version and not 1.28. My cluster name is `talos-metal` and my endpoint or my VIP address is the address along with the port 6443. 

```
talosctl gen config --kubernetes-version=1.27.7 talos-metal https://192.168.169.210:6443
```

This will create 3 files, controlplane.yaml, worker.yaml and talosconfig. These files can also be found in the folder here. I have since modified these configurations so that I create a bridge network for each node you will see this below. 

## Validate Configuration 

```
talosctl validate --config talos-node1-controlplane.yaml --mode metal
talosctl validate --config talos-node2-controlplane.yaml --mode metal
talosctl validate --config talos-node3-controlplane.yaml --mode metal
talosctl validate --config talos-node4-worker.yaml --mode metal
talosctl validate --config talos-node5-worker.yaml --mode metal

```

## Apply the Config 

Now that we have our config files and we have our physical nodes ready with a static IP we can now apply said config to our nodes. 

*Note - I have modified the controlplane.yaml with a number of additional configurations required for my setup, one of which is the ability to run workloads on our control plane nodes*

```
# Apply the cluster configuration to each node
talosctl apply-config \
    --nodes 192.168.169.211 \
    --endpoints 192.168.169.211 \
    --file talos-node1-controlplane.yaml \
    --insecure 

talosctl apply-config \
    --nodes 192.168.169.212 \
    --endpoints 192.168.169.212 \
    --file talos-node2-controlplane.yaml \
    --insecure 

talosctl apply-config \
    --nodes 192.168.169.213 \
    --endpoints 192.168.169.213 \
    --file talos-node3-controlplane.yaml \
    --insecure 

talosctl apply-config \
    --nodes 192.168.169.214 \
    --endpoints 192.168.169.214 \
    --file talos-node4-worker.yaml \
    --insecure 

talosctl apply-config \
    --nodes 192.168.169.215 \
    --endpoints 192.168.169.215 \
    --file talos-node5-worker.yaml \
    --insecure 
```

On the console of your nodes you will see some activity at this stage, it is important that until the reboot phase takes place and the state is ready you cannot move to the next step. 


## Kubernetes Bootstrap 
If everything is ready then we can instruct the bootstrap process, I am choosing one of my 3 nodes `talos-node1` 
 
```
talosctl bootstrap \
    --nodes 192.168.169.211 \
    --endpoints 192.168.169.211 \
    --talosconfig talosconfig
```

## Interact with cluster 

We can interact with our cluster using the `talos-metal` config file we created earlier. 

`kubectl --kubeconfig=talos-metal get pods`


We can also merge to our KUBECONFIG with the following: 

```
KUBECONFIG=~/.kube/config:kubeconfig kubectl config view --flatten > ~/.kube/config_tmp
mv ~/.kube/config_tmp ~/.kube/config
kubectl config get-contexts
```

## NFS StorageClass 
I have an NFS Shared storage device on my network that can be used above and beyond the local fast CEPH cluster. 

```
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system --version v4.6.0 --set externalSnapshotter.enabled=true --set controller.runOnControlPlane=true --set controller.replicas=2
```

StorageClass 

`kubectl apply -f sc-nfs.yml` 


SnapshotClass 

`kubectl apply -f snapshotclass-nfs.yaml`

Apply default storageclass 

`kubectl patch storageclass nfs-csi -p '{"metadata": {"annotations":{"storageclass.ku
bernetes.io/is-default-class":"true"}}}'`


Test with PVC 

`kubectl apply -f pvc-nfs.yml`


## Reset 

talosctl reset --debug \
    --nodes 192.168.169.211 \
    --endpoints 192.168.169.211 \
    --system-labels-to-wipe STATE \
    --system-labels-to-wipe EPHEMERAL \
    --graceful=false \
    --reboot

talosctl reset --debug \
    --nodes 192.168.169.212 \
    --endpoints 192.168.169.212 \
    --system-labels-to-wipe STATE \
    --system-labels-to-wipe EPHEMERAL \
    --graceful=false \
    --reboot

talosctl reset --debug \
    --nodes 192.168.169.213 \
    --endpoints 192.168.169.213 \
    --system-labels-to-wipe STATE \
    --system-labels-to-wipe EPHEMERAL \
    --graceful=false \
    --reboot

