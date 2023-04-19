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
for i in {1..3}; do cp ./cloud-config "./data/cloud-config-$i"; echo "hostname: cisb-node-$i.cisb.local" >> "./data/cloud-config-$i"; echo "fqdn: cisb-node-$i.cisb.local" >> "./data/cloud-config-$i"; cloud-localds "./data/cloudinit-$i.iso" "./data/cloud-config-$i"; sudo virt-install --name "cisb-node-$i" --disk "./data/node-$i.qcow2",device=disk,bus=virtio --disk "./data/cloudinit-$i.iso",device=cdrom --os-variant="rocky9" --virt-type kvm --graphics none --vcpus 2 --memory 3072 --network network=default,model=virtio --console pty,target_type=serial --import; done

#check ips
sudo virsh net-dhcp-leases default 
```

### Setup host resolv conf
```bash
sudo virsh net-dhcp-leases default | grep cisb-node | sed 's/  */ /g' | cut -d ' ' -f 6,7 | sed 's/\/24//g' | sed -r 's/ (.*)$/ \1 \1.cisb.local/g' > ./hosts
export HOSTALIASES=$PWD/hosts
```
then add domain resolution for cisb.local, vlt.cisb.local, sql.cisb.local, kube.cisb.local and sso.cisb.local

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
`python -m http.server &`

```bash
#Download and trust root ca
curl --silent 'http://192.168.122.1:8000/CA/out/root.ca/root.ca.pem' | sudo tee /etc/pki/ca-trust/source/anchors/root.ca.pem
sudo update-ca-trust extract

#install vault
sudo dnf install -y dnf-utils
sudo dnf config-manager -y --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install vault -y

#copy config and certificates
curl --silent 'http://192.168.122.1:8000/vault_cfg/vault.hcl' | sed "s/cisb-node-x/$(hostname | cut -d '.' -f 1)/g" | sudo tee /etc/vault.d/vault.hcl
curl --silent 'http://192.168.122.1:8000/CA/out/certs/vault/vault.cisb.local-fullchain.pem' | sudo tee /opt/vault/tls/vault.cisb.local-fullchain.pem
curl --silent 'http://192.168.122.1:8000/CA/out/certs/vault/vault.cisb.local-key.pem' | sudo tee /opt/vault/tls/vault.cisb.local-key.pem
curl --silent 'http://192.168.122.1:8000/CA/out/certs/vault/vault.cisb.local-ca.pem' | sudo tee /opt/vault/tls/vault.cisb.local-ca.pem

#Start vault service
sudo systemctl enable vault
sudo systemctl start vault
vault status
```

On node 1 `vault operator init -key-shares 1 -key-threshold 1`
then wait for sync and then operator unseal all nodes after 
```
export VAULT_TOKEN=""
vault operator raft list-peers
```

Unseal Key 1: ZUFptFjoYrcdP3Laqm95KPidbDv1G4c+mrKAOmq4K7A=
Initial Root Token: hvs.j0aETCwuxCP2Cq53f6UYEHCL

### create intermediate ca

We can now work on the host =)
First download vault
```bash
wget https://releases.hashicorp.com/vault/1.13.1/vault_1.13.1_linux_amd64.zip
unzip vault_*.zip
rm vault_*.zip
chmod +x vault
```

```bash
export VAULT_TOKEN="hvs.j0aETCwuxCP2Cq53f6UYEHCL"
export VAULT_ADDR="https://vlt.cisb.local:8200"
export VAULT_CACERT="$PWD/CA/out/root.ca/root.ca.pem"
./vault secrets enable pki
./vault secrets tune -max-lease-ttl=43800h pki
./vault write -format=json pki/intermediate/generate/internal common_name="CISB IEEESTB 1019 intermediate CA" issuer_name="cisb-intermediate-ca" | jq -r '.data.csr' > pki_intermediate.csr
cfssl sign -ca CA/out/root.ca/root.ca.pem -ca-key CA/out/root.ca/root.ca-key.pem -config CA/cfssl.json -profile intermediate pki_intermediate.csr | cfssljson -bare CA/out/intermediate.ca/intermediate.ca
cat CA/out/intermediate.ca/intermediate.ca.pem CA/out/root.ca/root.ca.pem > CA/out/intermediate.ca/intermediate.ca-fullchain.pem
./vault write pki/intermediate/set-signed certificate=@CA/out/intermediate.ca/intermediate.ca-fullchain.pem
rm pki_intermediate.csr
```

### create subintermediates cas

```bash
./vault secrets enable -path=pki_db pki
./vault secrets tune -max-lease-ttl=43800h pki_db
./vault write -format=json pki_db/intermediate/generate/internal common_name="CISB DB CA" key_type="ec" key_bits=256  | jq -r '.data.csr' > pki_db.csr
./vault write -format=json pki/root/sign-intermediate csr=@pki_db.csr format=pem_bundle ttl="43800h" | jq -r '.data.certificate' > db.cert.pem
./vault write pki_db/intermediate/set-signed certificate=@db.cert.pem
rm db.cert.pem pki_db.csr
./vault write pki_db/roles/server allowed_domains="cisb.local,localhost" allow_subdomains=true allow_bare_domains=true allow_glob_domains=true max_ttl="720h" server_flag=true client_flag=false key_type=ec key_bits=256
./vault write pki_db/roles/client allow_subdomains=true allow_bare_domains=true allow_glob_domains=true max_ttl="720h" allow_any_name=true enforce_hostnames=false server_flag=false client_flag=true key_type=ec key_bits=256

./vault secrets enable -path=pki_http pki
./vault secrets tune -max-lease-ttl=43800h pki_http
./vault write -format=json pki_http/intermediate/generate/internal common_name="CISB HTTP CA" key_type="ec" key_bits=256 | jq -r '.data.csr' > pki_http.csr
./vault write -format=json pki/root/sign-intermediate csr=@pki_http.csr format=pem_bundle ttl="43800h" | jq -r '.data.certificate' > pki_http.cert.pem
./vault write pki_http/intermediate/set-signed certificate=@pki_http.cert.pem
rm pki_http.cert.pem pki_http.csr
./vault write pki_http/roles/server allowed_domains="cisb.local,localhost" allow_subdomains=true allow_bare_domains=true allow_glob_domains=true max_ttl="720h" server_flag=true client_flag=false key_type=ec key_bits=256
```

### Deploy K3S

On node 1:
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=cisbisabeautifulconference sh -s - server --cluster-init --write-kubeconfig-mode 644
```

On other nodes
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=cisbisabeautifulconference sh -s - server --server https://cisb-node-1.cisb.local:6443
```

From host
```bash
mkdir .kube
scp cisb-node-1:/etc/rancher/k3s/k3s.yaml .kube/kubeconfig.yaml
sed -i 's/127.0.0.1/cisb-node-1.cisb.local/g' .kube/kubeconfig.yaml
export KUBECONFIG="$PWD/.kube/kubeconfig.yaml"
```

### Deploy cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install  cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.11.0 --set installCRDs=true
```

deploy issuers

```bash
cp k3s/cert-manager-cluster-issuer.template.yaml k3s/cert-manager-cluster-issuer.yaml
sed -i "s/TOKEN/$(echo ${VAULT_TOKEN} | base64 -w0)/" k3s/cert-manager-cluster-issuer.yaml
sed -i "s/CABUNDLE/$(cat CA/out/root.ca/root.ca.pem | base64 -w0)/" k3s/cert-manager-cluster-issuer.yaml
kubectl apply -f k3s/cert-manager-cluster-issuer.yaml
kubectl get clusterissuer
```

### Deploy storage class on ha storage

on host, deploy nfs
```bash
mkdir nfs
```

add export line to /etc/exports

reload
`sudo exportfs -arv`

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-exter
nal-provisioner --create-namespace --namespace nfs-provisioner  --set nfs.server=192.168.122.1 --set nfs.path=/home/stefano/Projects/IEEE/cisb4-kubernetes-ha-oauth/nfs
```

### Deploy postgres

```bash
kubectl apply -f k3s/postgres.yaml

```

### Deploy authelia

todo

# schifo

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