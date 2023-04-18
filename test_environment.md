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

### Setup host resolv conf
```bash
sudo virsh net-dhcp-leases default | grep cisb-node | sed 's/  */ /g' | cut -d ' ' -f 6,7 | sed 's/\/24//g' | sed -r 's/ (.*)$/ \1 \1.cisb.local/g' | sudo tee /etc/hosts
```

### Step 3: Deploy distributed vault
#### Create the root ca with cfssl

```bash
mkdir -p CA/out/{root.ca,infrastructure.ca,intermediate.ca,certs/vault}
cfssl gencert -initca ./CA/root.ca.json | cfssljson -bare CA/out/root.ca/root.ca

cfssl gencert -initca ./CA/infrastructure.ca.json | cfssljson -bare CA/out/infrastructure.ca/infrastructure.ca
cfssl sign -ca CA/out/root.ca/root.ca.pem -ca-key CA/out/root.ca/root.ca-key.pem -config CA/cfssl.json -profile intermediate CA/out/infrastructure.ca/infrastructure.ca.csr | cfssljson -bare CA/out/infrastructure.ca/infrastructure.ca

#Generate Vault Web certificates
cfssl gencert -ca CA/out/infrastructure.ca/infrastructure.ca.pem -ca-key CA/out/infrastructure.ca/infrastructure.ca-key.pem -config CA/cfssl.json -profile=server CA/vault.cisb.local.json | cfssljson -bare CA/out/certs/vault/vault.cisb.local
cat CA/out/certs/vault/vault.cisb.local.pem CA/out/infrastructure.ca/infrastructure.ca.pem CA/out/root.ca/root.ca.pem > CA/out/certs/vault/vault.cisb.local-fullchain.pem
cat CA/out/infrastructure.ca/infrastructure.ca.pem CA/out/root.ca/root.ca.pem > CA/out/certs/vault/vault.cisb.local-ca.pem
```

#### On all the nodes

start python webserver on the host
`python -m http.server`

```bash
#Download and trust root ca
curl --silent 'http://192.168.122.1:8000/CA/out/root.ca/root.ca.pem' | sudo tee /etc/pki/ca-trust/source/anchors/root.ca.pem
curl --silent 'http://192.168.122.1:8000/CA/out/infrastructure.ca/infrastructure.ca.pem' | sudo tee /etc/pki/ca-trust/source/anchors/infrastructure.ca.pem
sudo update-ca-trust extract

#install vault
sudo dnf install -y dnf-utils
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install vault

#copy config and certificates
curl --silent 'http://192.168.122.1:8000/vault/vault.hcl' | sed "s/cisb-node-x/$(hostname | cut -d '.' -f 1)/g" | sudo tee /etc/vault.d/vault.hcl
curl --silent 'http://192.168.122.1:8000/CA/out/certs/vault/vault.cisb.local.pem' | sudo tee /opt/vault/tls/vault.cisb.local.pem
curl --silent 'http://192.168.122.1:8000/CA/out/certs/vault/vault.cisb.local-key.pem' | sudo tee /opt/vault/tls/vault.cisb.local-key.pem
curl --silent 'http://192.168.122.1:8000/CA/out/certs/vault/vault.cisb.local-ca.pem' | sudo tee /opt/vault/tls/vault.cisb.local-ca.pem

#Start vault service
sudo systemctl enable vault
sudo systemctl start vault
vault status
```

On node 1 `vault operator init -key-shares 1 -key-threshold 1`
then wait for sync and then operator unseal after 
```
export VAULT_TOKEN=""
vault operator raft list-peers
```

Unseal Key 1: tzZ4YvRR3FyB/sFwD85UE5jwa8N1ys+2zDJw9ASXL58=
Initial Root Token: hvs.WNz82j6QBLIVx2GfkTDs08QI

### Deploy K3S

update node resolv conf !!

On node 1:
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server --cluster-init --write-kubeconfig-mode 644
```

On other nodes
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server --server https://cisb-node-1:6443
```

### Import cas into vault

```bash
sudo dnf install jq
vault secrets enable pki
vault secrets tune -max-lease-ttl=43800h pki
vault write -format=json pki/intermediate/generate/internal common_name="CISB IEEESTB 1019 intermediate CA" issuer_name="cisb-intermediate-ca" | jq -r '.data.csr' > pki_intermediate.csr
```
move pki_intermediate.csr and signi it with the root ca

on the host
```bash
cfssl sign -ca CA/out/root.ca/root.ca.pem -ca-key CA/out/root.ca/root.ca-key.pem -config CA/cfssl.json -profile intermediate pki_intermediate.csr | cfssljson -bare CA/out/intermediate.ca/intermediate.ca
cat CA/out/intermediate.ca/intermediate.ca.pem CA/out/root.ca/root.ca.pem > CA/out/intermediate.ca/intermediate.ca-fullchain.pem
```

move CA/out/intermediate.ca/intermediate.ca/intermediate.ca.pem to the node
on the node
```bash
vault write pki/intermediate/set-signed certificate=@intermediate.ca.pem
```
set issuer name

### create cas

```bash
vault secrets enable -path=pki_db pki
vault secrets tune -max-lease-ttl=43800h pki_db
vault write -format=json pki_db/intermediate/generate/internal common_name="CISB DB CA"  issuer_name="cisb-db-ca"  | jq -r '.data.csr' > pki_db.csr
vault write -format=json pki/root/sign-intermediate issuer_ref="cisb-intermediate-ca" csr=@pki_db.csr format=pem_bundle ttl="43800h" | jq -r '.data.certificate' > db.cert.pem
vault write pki_db/intermediate/set-signed certificate=@db.cert.pem
!!! roles
vault write pki_db/roles/server issuer_ref="$(vault read -field=default pki_int/config/issuers)" allowed_domains="cisb.local,localhost" allow_subdomains=true max_ttl="720h"

vault secrets enable -path=pki_http pki
vault secrets tune -max-lease-ttl=43800h pki_http
vault write -format=json pki_http/intermediate/generate/internal common_name="CISB HTTP CA"  issuer_name="cisb-http-ca"  | jq -r '.data.csr' > pki_http.csr
vault write -format=json pki/root/sign-intermediate issuer_ref="cisb-intermediate-ca" csr=@pki_http.csr format=pem_bundle ttl="43800h" | jq -r '.data.certificate' > pki_http.cert.pem
vault write pki_http/intermediate/set-signed certificate=@pki_http.cert.pem
```
set issuer name

### Deploy cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install  cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.11.0 --set installCRDs=true


```

### Deploy postgres

create certificate


https://kubernetes.io/docs/reference/access-authn-authz/authentication/
https://docs.k3s.io/cli/server#customized-flags-for-kubernetes-processes
use --write-kubeconfig-mode 644

follow https://docs.k3s.io/datastore/ha-embedded
https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-external-vault
https://picluster.ricsanfre.com/docs/vault/

sudo /usr/local/bin/k3s server --cluster-init --write-kubeconfig-mode 644 --kube-apiserver-arg oidc-username-claim=email --kube-apiserver-arg oidc-username-claim=email --kube-apiserver-arg oidc-issuer-url=https://cisb-node-2:1235/ --kube-apiserver-arg oidc-client-id=ciao 

### Setup vault ca

### Setup authentik on kubernetes

### Change kubernetes configspem -config CA/cfssl.json -profile intermediate CA/out/intermediate.ca/intermediate.ca.csr | cfssljson -bare CA/out/intermediate.ca/intermediate.ca