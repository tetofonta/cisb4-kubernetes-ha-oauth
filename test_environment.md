# Test environment

Will do 3 nodes cluster, high availability??

## 1 - Virtual machines 

Deploy three virtual machines based on rocky9. use nss module for libvirt

### Step 1: Download cloud enabled image
```bash
wget http://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-LVM.latest.x86_64.qcow2
curl http://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-LVM.latest.x86_64.qcow2.CHECKSUM --silent | shasum -c
```

### Step 2: Prepare disks and start vms
```bash
mkdir data
for i in {1..3}; do cp ./Rocky*.qcow2 "./data/node-$i.qcow2"; done

sudo virsh net-start default
for i in {1..3}; do cp ./cloud-config "./data/cloud-config-$i"; echo "hostname: cisb-node-$i.cisb.local" >> "./data/cloud-config-$i"; echo "fqdn: cisb-node-$i.cisb.local" >> "./data/cloud-config-$i"; cloud-localds "./data/cloudinit-$i.iso" "./data/cloud-config-$i"; sudo virt-install --name "cisb-node-$i" --disk "./data/node-$i.qcow2",device=disk,bus=virtio --disk "./data/cloudinit-$i.iso",device=cdrom --os-variant="rocky9" --virt-type kvm --graphics none --vcpus 2 --memory 2048 --network network=default,model=virtio --console pty,target_type=serial --import; done

#check ips
sudo virsh net-dhcp-leases default 
```

#### Basic nodes configuration
```bash
set resolv.conf
```

### Step 3: Deploy distributed vault
#### Create the root ca with cfssl

```bash
mkdir -p CA/out/{root.ca,infrastructure.ca,intermediate.ca,certs/vault}
cfssl gencert -initca ./CA/root.ca.json | cfssljson -bare CA/out/root.ca/root.ca

cfssl gencert -initca ./CA/infrastructure.ca.json | cfssljson -bare CA/out/infrastructure.ca/infrastructure.ca
cfssl sign -ca CA/out/root.ca/root.ca.pem -ca-key CA/out/root.ca/root.ca-key.pem -config CA/cfssl.json -profile intermediate CA/out/infrastructure.ca/infrastructure.ca.csr | cfssljson -bare CA/out/infrastructure.ca/infrastructure.ca

cfssl gencert -initca ./CA/intermediate.ca.json | cfssljson -bare CA/out/intermediate.ca/intermediate.ca
cfssl sign -ca CA/out/root.ca/root.ca.pem -ca-key CA/out/root.ca/root.ca-key.pem -config CA/cfssl.json -profile intermediate CA/out/intermediate.ca/intermediate.ca.csr | cfssljson -bare CA/out/intermediate.ca/intermediate.ca

#Generate Vault Web certificates
cfssl gencert -ca CA/out/infrastructure.ca/infrastructure.ca.pem -ca-key CA/out/infrastructure.ca/infrastructure.ca-key.pem -config CA/cfssl.json -profile=server CA/vault.cisb.local.json | cfssljson -bare CA/out/certs/vault/vault.cisb.local
cat CA/out/certs/vault/vault.cisb.local.pem CA/out/infrastructure.ca/infrastructure.ca.pem CA/out/root.ca/root.ca.pem > CA/out/certs/vault/vault.cisb.local-fullchain.pem
cat CA/out/infrastructure.ca/infrastructure.ca.pem CA/out/root.ca/root.ca.pem > CA/out/certs/vault/vault.cisb.local-ca.pem
```

#### On all the nodes

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install vault

todo
- copia i certificati e il file di config --- USA PYTHON HTTP SERVER!!!!
- trusta la root e la ca infrastructure (posso usare un fullchain ? mah)
- avvia cisb 1
- vault operator init
- vault operator unseal
- avvia gli altri due nodi
- unseal
```

Unseal Key 1: inhNjLgPOyq9HlTsv32pr+fz6yOplgz3FuHrSZnPqvV4
Unseal Key 2: pMPo9KNGDHfZ0r9hKmp3IiJYmHYda8CaVKP/SK1kL7A3
Unseal Key 3: hA0G3NAsKEQ0RHiR20HM118zXt/RZPrGr94LpnyNnErZ
Unseal Key 4: +LnTwJrsW1erxibnwrez0PtfN8JZQ2bMXFUqeb4EXiLE
Unseal Key 5: wzBPEQeF82Oj2j6krlg/S8FK0OKKRB9mHpgqihN+2n8R
Initial Root Token: hvs.d8ucR2gCFBOgCM5WBME6fAC4

### Deploy K3S

https://kubernetes.io/docs/reference/access-authn-authz/authentication/
https://docs.k3s.io/cli/server#customized-flags-for-kubernetes-processes
use --write-kubeconfig-mode 644

follow https://docs.k3s.io/datastore/ha-embedded
https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-external-vault
https://picluster.ricsanfre.com/docs/vault/

sudo /usr/local/bin/k3s server --cluster-init --write-kubeconfig-mode 644 --kube-apiserver-arg oidc-username-claim=email --kube-apiserver-arg oidc-username-claim=email --kube-apiserver-arg oidc-issuer-url=https://cisb-node-2:1235/ --kube-apiserver-arg oidc-client-id=ciao 

### Setup vault ca

### Setup authentik on kubernetes

### Change kubernetes configs