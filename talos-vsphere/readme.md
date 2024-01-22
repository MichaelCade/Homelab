# Talos on vSphere 

## Download Govc 
# extract govc binary to /usr/local/bin
# note: the "tar" command must run with root permissions
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | sudo tar -C /usr/local/bin -xvzf - govc

mkdir talos-vsphere
install talosctl - curl -sL https://talos.dev/install | sh

download cp.patch.yaml to your local machine and edit the VIP to match your chosen IP. You can do this by issuing: 
curl -fsSLO https://raw.githubusercontent.com/siderolabs/talos/master/website/content/v1.6/talos-guides/install/virtualized-platforms/vmware/cp.patch.yaml

## generate machine configs 
talosctl gen config vmware-test https://192.168.169.202:6443 --config-patch-control-plane @cp.patch.yaml

## added kubernetes version 
talosctl gen config --kubernetes-version=1.27.7 vmware-test https://192.168.169.202:6443 --config-patch-control-plane @cp.patch.yaml


## validate configs 
talosctl validate --config controlplane.yaml --mode cloud
talosctl validate --config worker.yaml --mode cloud

## env variables 
export GOVC_URL=https://192.168.169.181/
export GOVC_USERNAME=administrator@vzilla.local
export GOVC_PASSWORD=Passw0rd999!
export GOVC_DATACENTER="vZilla DC"
export GOVC_DATASTORE=NETGEAR716
export GOVC_NETWORK="VM Network"
export GOVC_INSECURE=true
export CLUSTER_NAME=vZilla-Cluster #This is for the OVA import steps 

## Scripted install 
curl -fsSLO "https://raw.githubusercontent.com/siderolabs/talos/master/website/content/v1.6/talos-guides/install/virtualized-platforms/vmware/vmware.sh"

## Check version (should be v1.1.6) You can also change what cluster size (Control Planes = 3, Workers = 2 - Default) 
nano vmware.sh

## Import OVA 
./vmware.sh upload_ova

## Create Cluster 
./vmware.sh create

Bootstrap Cluster - When above is complete, we can now bootstrap our cluster, When you check the vcenter console of one of your control planes you will see an IP address top right with that IP you should run the following 
talosctl --talosconfig talosconfig bootstrap -e 192.168.169.35 -n 192.168.169.35

KubeConfig 
talosctl --talosconfig talosconfig config endpoint 192.168.169.202
talosctl --talosconfig talosconfig config node 192.168.169.202
talosctl --talosconfig talosconfig kubeconfig .

now we could use to view our cluster nodes 
kubectl --kubeconfig=kubeconfig get nodes 

## Configure VMtools 
talosctl -n 192.168.169.202 config new vmtoolsd-secret.yaml --roles os:admin

kubectl --kubeconfig=kubeconfig -n kube-system create secret generic talos-vmtoolsd-config \
--from-file=talosconfig=./vmtoolsd-secret.yaml

## Verify VMtools 
kubectl --kubeconfig=kubeconfig get pods -n kube-system


## vSphere Cloud Provider Interface (CPI) 

export VERSION=1.27
wget https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/release-$VERSION/releases/v$VERSION/vsphere-cloud-controller-manager.yaml

nano vsphere-cloud-controller-manager.yaml

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  labels:
    vsphere-cpi-infra: service-account
    component: cloud-controller-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-cloud-secret
  labels:
    vsphere-cpi-infra: secret
    component: cloud-controller-manager
  namespace: kube-system
  # NOTE: this is just an example configuration, update with real values based on your environment
stringData:
  192.168.169.181.username: "administrator@vzilla.local"
  192.168.169.181.password: "Passw0rd999!"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: vsphere-cloud-config
  labels:
    vsphere-cpi-infra: config
    component: cloud-controller-manager
  namespace: kube-system
data:
  # NOTE: this is just an example configuration, update with real values based on your environment
  vsphere.conf: |
    # Global properties in this section will be used for all specified vCenters unless overriden in VirtualCenter section.
    global:
      port: 443
      # set insecureFlag to true if the vCenter uses a self-signed cert
      insecureFlag: true
      # settings for using k8s secret
      secretName: vsphere-cloud-secret
      secretNamespace: kube-system

    # vcenter section
    vcenter:
      VMware Virtual Center:
        server: 192.168.169.181
        user: administrator@vzilla.local
        password: Passw0rd999!
        datacenters:
          - vZilla DC
        secretName: cpi-engineering-secret
        secretNamespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: servicecatalog.k8s.io:apiserver-authentication-reader
  labels:
    vsphere-cpi-infra: role-binding
    component: cloud-controller-manager
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
  - apiGroup: ""
    kind: ServiceAccount
    name: cloud-controller-manager
    namespace: kube-system
  - apiGroup: ""
    kind: User
    name: cloud-controller-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:cloud-controller-manager
  labels:
    vsphere-cpi-infra: cluster-role-binding
    component: cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:cloud-controller-manager
subjects:
  - kind: ServiceAccount
    name: cloud-controller-manager
    namespace: kube-system
  - kind: User
    name: cloud-controller-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:cloud-controller-manager
  labels:
    vsphere-cpi-infra: role
    component: cloud-controller-manager
rules:
  - apiGroups:
      - ""
    resources:
      - events
    verbs:
      - create
      - patch
      - update
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - "*"
  - apiGroups:
      - ""
    resources:
      - nodes/status
    verbs:
      - patch
  - apiGroups:
      - ""
    resources:
      - services
    verbs:
      - list
      - patch
      - update
      - watch
  - apiGroups:
      - ""
    resources:
      - services/status
    verbs:
      - patch
  - apiGroups:
      - ""
    resources:
      - serviceaccounts
    verbs:
      - create
      - get
      - list
      - watch
      - update
  - apiGroups:
      - ""
    resources:
      - persistentvolumes
    verbs:
      - get
      - list
      - update
      - watch
  - apiGroups:
      - ""
    resources:
      - endpoints
    verbs:
      - create
      - get
      - list
      - watch
      - update
  - apiGroups:
      - ""
    resources:
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - "coordination.k8s.io"
    resources:
      - leases
    verbs:
      - create
      - get
      - list
      - watch
      - update
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: vsphere-cloud-controller-manager
  labels:
    component: cloud-controller-manager
    tier: control-plane
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: vsphere-cloud-controller-manager
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: vsphere-cloud-controller-manager
        component: cloud-controller-manager
        tier: control-plane
    spec:
      tolerations:
        - key: node.cloudprovider.kubernetes.io/uninitialized
          value: "true"
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
          operator: Exists
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule
          operator: Exists
        - key: node.kubernetes.io/not-ready
          effect: NoSchedule
          operator: Exists
      securityContext:
        runAsUser: 1001
      serviceAccountName: cloud-controller-manager
      priorityClassName: system-node-critical
      containers:
        - name: vsphere-cloud-controller-manager
          image: gcr.io/cloud-provider-vsphere/cpi/release/manager:v1.28.0
          args:
            - --cloud-provider=vsphere
            - --v=2
            - --cloud-config=/etc/cloud/vsphere.conf
          volumeMounts:
            - mountPath: /etc/cloud
              name: vsphere-config-volume
              readOnly: true
          resources:
            requests:
              cpu: 200m
      hostNetwork: true
      volumes:
        - name: vsphere-config-volume
          configMap:
            name: vsphere-cloud-config
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: Exists
            - matchExpressions:
              - key: node-role.kubernetes.io/master
                operator: Exists

kubectl --kubeconfig=kubeconfig apply -f vsphere-cloud-controller-manager.yaml

## vSphere CSI 

Namespace 
kubectl --kubeconfig=kubeconfig apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.0.0/manifests/vanilla/namespace.yaml

reference for the next command - https://github.com/rook/rook/issues/11755
kubectl --kubeconfig=kubeconfig label ns vmware-system-csi pod-security.kubernetes.io/enforce=privileged

## vSphere Config File 
nano csi-vsphere.conf

[Global]
cluster-id = "vZilla-Cluster"

[VirtualCenter "192.168.169.181"]
insecure-flag = "true"
user = "administrator@vzilla.local"
password = "Passw0rd999!"
port = "443"
datacenters = "vZilla DC"

## Create a Kubernetes secret for vSphere Credentials 
kubectl --kubeconfig=kubeconfig create secret generic vsphere-config-secret --from-file=csi-vsphere.conf --namespace=vmware-system-csi

## Confirm that you have a new secret 
kubectl --kubeconfig=kubeconfig get secret vsphere-config-secret --namespace=vmware-system-csi

You should now delete the csi-vsphere.conf but I am in a homelab and know this will come and go, plus you have seen my super secure password now

## Install vSphere Container Storage Plug-in 
kubectl --kubeconfig=kubeconfig apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.0.0/manifests/vanilla/vsphere-csi-driver.yaml

## Verify
kubectl --kubeconfig=kubeconfig get deployment --namespace=vmware-system-csi
kubectl --kubeconfig=kubeconfig get pods --namespace=vmware-system-csi
kubectl --kubeconfig=kubeconfig describe csidrivers
kubectl --kubeconfig=kubeconfig get CSINode

## Define StorageClass 

nano vsphere-sc.yaml

kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: example-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.vmware.com
parameters:
  datastoreurl: "ds:///vmfs/volumes/203747f8-c8b69fd1/"

kubectl --kubeconfig=kubeconfig apply -f vsphere-sc.yaml

## Testing 

nano example-pvc.yaml 

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

kubectl --kubeconfig=kubeconfig apply -f example-pvc.yaml

kubectl --kubeconfig=kubeconfig get pvc

## Merge Kubeconfig files 
KUBECONFIG=~/.kube/config:kubeconfig kubectl config view --flatten > ~/.kube/config_tmp
mv ~/.kube/config_tmp ~/.kube/config
kubectl config get-contexts

## Delete Cluster 
As a note you will need to define your cluster name if you have not used "vmware-test" 

export CLUSTER_NAME="vZilla-Cluster"

./vmware.sh destroy  
