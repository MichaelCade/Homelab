#!/bin/bash
T="$(date +%s)"
set -e

## The following commented environment variables should be set
## before running this script

export GOVC_USERNAME='administrator@vzilla.local'
export GOVC_PASSWORD='Passw0rd999!'
export GOVC_INSECURE=true
export GOVC_URL='https://192.168.169.181'
export GOVC_DATASTORE='NETGEAR716'
export CLUSTER_NAME='vZilla-Cluster'

# If a cluster name is not defined then it will be vmware-test, I hard coded the cluster name for ease.
CLUSTER_NAME=${CLUSTER_NAME:=talos-vsphere}
TALOS_VERSION=v1.7.6
OVA_PATH=${OVA_PATH:="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/vmware-amd64.ova"}

CONTROL_PLANE_COUNT=${CONTROL_PLANE_COUNT:=3}
CONTROL_PLANE_CPU=${CONTROL_PLANE_CPU:=2}
CONTROL_PLANE_MEM=${CONTROL_PLANE_MEM:=4096}
CONTROL_PLANE_DISK=${CONTROL_PLANE_DISK:=10G}
CONTROL_PLANE_MACHINE_CONFIG_PATH=${CONTROL_PLANE_MACHINE_CONFIG_PATH:="./controlplane.yaml"}

WORKER_COUNT=${WORKER_COUNT:=2}
WORKER_CPU=${WORKER_CPU:=2}
WORKER_MEM=${WORKER_MEM:=4096}
WORKER_DISK=${WORKER_DISK:=10G}
WORKER_MACHINE_CONFIG_PATH=${WORKER_MACHINE_CONFIG_PATH:="./worker.yaml"}

#upload_ova () {
#    ## Import desired Talos Linux OVA into a new content library
#    govc library.create ${CLUSTER_NAME}
#    govc library.import -n talos-${TALOS_VERSION} ${CLUSTER_NAME} ${OVA_PATH}
#}

upload_ova () {
    echo "Starting upload_ova function..."

    # Check if the content library already exists
    echo "Checking if content library ${CLUSTER_NAME} exists..."
    govc library.ls | grep -q ${CLUSTER_NAME} && {
        echo "Content library ${CLUSTER_NAME} already exists."
    } || {
        echo "Creating content library ${CLUSTER_NAME}..."
        if govc library.create ${CLUSTER_NAME}; then
            echo "Content library ${CLUSTER_NAME} created successfully."
        else
            echo "Failed to create content library ${CLUSTER_NAME}."
            exit 1
        fi
    }

    # Import desired Talos Linux OVA into the content library
    echo "Importing Talos Linux OVA into content library ${CLUSTER_NAME}..."
    if govc library.import -n talos-${TALOS_VERSION} ${CLUSTER_NAME} ${OVA_PATH}; then
        echo "Talos Linux OVA imported successfully."
    else
        echo "Failed to import Talos Linux OVA."
        exit 1
    fi

    echo "Finished upload_ova function."
}

create () {
    ## Encode machine configs
    CONTROL_PLANE_B64_MACHINE_CONFIG=$(cat ${CONTROL_PLANE_MACHINE_CONFIG_PATH}| base64 | tr -d '\n')
    WORKER_B64_MACHINE_CONFIG=$(cat ${WORKER_MACHINE_CONFIG_PATH} | base64 | tr -d '\n')

    ## Create control plane nodes and edit their settings
    for i in $(seq 1 ${CONTROL_PLANE_COUNT}); do
        echo ""
        echo "launching control plane node: ${CLUSTER_NAME}-control-plane-${i}"
        echo ""

        govc library.deploy ${CLUSTER_NAME}/talos-${TALOS_VERSION} ${CLUSTER_NAME}-control-plane-${i}

        govc vm.change \
        -c ${CONTROL_PLANE_CPU}\
        -m ${CONTROL_PLANE_MEM} \
        -e "guestinfo.talos.config=${CONTROL_PLANE_B64_MACHINE_CONFIG}" \
        -e "disk.enableUUID=1" \
        -vm ${CLUSTER_NAME}-control-plane-${i}

        govc vm.disk.change -vm ${CLUSTER_NAME}-control-plane-${i} -disk.name disk-1000-0 -size ${CONTROL_PLANE_DISK}

        govc vm.power -on ${CLUSTER_NAME}-control-plane-${i}
    done

    ## Create worker nodes and edit their settings
    for i in $(seq 1 ${WORKER_COUNT}); do
        echo ""
        echo "launching worker node: ${CLUSTER_NAME}-worker-${i}"
        echo ""

        govc library.deploy ${CLUSTER_NAME}/talos-${TALOS_VERSION} ${CLUSTER_NAME}-worker-${i}

        govc vm.change \
        -c ${WORKER_CPU}\
        -m ${WORKER_MEM} \
        -e "guestinfo.talos.config=${WORKER_B64_MACHINE_CONFIG}" \
        -e "disk.enableUUID=1" \
        -vm ${CLUSTER_NAME}-worker-${i}

        govc vm.disk.change -vm ${CLUSTER_NAME}-worker-${i} -disk.name disk-1000-0 -size ${WORKER_DISK}

        govc vm.power -on ${CLUSTER_NAME}-worker-${i}
    done

}

destroy() {
    for i in $(seq 1 ${CONTROL_PLANE_COUNT}); do
        echo ""
        echo "destroying control plane node: ${CLUSTER_NAME}-control-plane-${i}"
        echo ""

        govc vm.destroy ${CLUSTER_NAME}-control-plane-${i}
    done

    for i in $(seq 1 ${WORKER_COUNT}); do
        echo ""
        echo "destroying worker node: ${CLUSTER_NAME}-worker-${i}"
        echo ""
        govc vm.destroy ${CLUSTER_NAME}-worker-${i}
    done
}

delete_ova() {
    govc library.rm ${CLUSTER_NAME}
}


bootstrap() {
# This function should be used when the create function has been used and now is time to create and bootstrap our cluster 
# We first need to obtain the IP addresses from the created cluster 
echo "Bootstrapping the Cluster..."




}

#vmware_ready() {
# This function will be used to install VMware Tools, VMware CPI and VMware CSI 
# We will also then create a storageclass within the Kubernetes cluster 
#}

"$@"

# Calculate the elapsed time in seconds
ELAPSED_TIME=$(( $(date +%s) - T ))

# Check if the elapsed time is greater than 60 seconds
if [ $ELAPSED_TIME -ge 60 ]; then
    # If the elapsed time is greater than or equal to 60 seconds, convert it to minutes
    ELAPSED_TIME=$(( ELAPSED_TIME / 60 ))
    UNIT="minutes"
else
    UNIT="seconds"
fi

echo "It took ${ELAPSED_TIME} ${UNIT}!"
