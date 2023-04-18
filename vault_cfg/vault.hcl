cluster_addr  = "https://cisb-node-x:8201"
api_addr      = "https://cisb-node-x:8200"
ui = true


listener "tcp" {
  address            = "0.0.0.0:8200"
  tls_cert_file      = "/opt/vault/tls/vault.cisb.local-fullchain.pem"
  tls_key_file       = "/opt/vault/tls/vault.cisb.local-key.pem"
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "cisb-node-x"

  retry_join {
    leader_api_addr         = "https://cisb-node-1:8200"
    leader_client_cert_file = "/opt/vault/tls/vault.cisb.local-fullchain.pem"
    leader_client_key_file  = "/opt/vault/tls/vault.cisb.local-key.pem"
  }
  retry_join {
    leader_api_addr         = "https://cisb-node-2:8200"
    leader_client_cert_file = "/opt/vault/tls/vault.cisb.local-fullchain.pem"
    leader_client_key_file  = "/opt/vault/tls/vault.cisb.local-key.pem"
  }
  retry_join {
    leader_api_addr         = "https://cisb-node-3:8200"
    leader_client_cert_file = "/opt/vault/tls/vault.cisb.local-fullchain.pem"
    leader_client_key_file  = "/opt/vault/tls/vault.cisb.local-key.pem"
  }
}
