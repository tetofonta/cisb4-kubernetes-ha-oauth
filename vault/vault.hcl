cluster_addr  = "https://cisb-node-x:8201"
api_addr      = "https://cisb-node-x:8200"
ui = true


listener "tcp" {
  address            = "0.0.0.0:8200"
  tls_cert_file      = "/opt/vault/tls/vault.cisb.local.pem"
  tls_key_file       = "/opt/vault/tls/vault.cisb.local-key.pem"
  tls_client_ca_file = "/opt/vault/tls/vault.cisb.local-ca.pem"
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "cisb-node-x"

  retry_join {
    leader_tls_servername   = "cisb-node-x"
    leader_api_addr         = "https://cisb-node-1:8200"
    leader_ca_cert_file     = "/opt/vault/tls/vault.cisb.local-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/vault.cisb.local.pem"
    leader_client_key_file  = "/opt/vault/tls/vault.cisb.local-key.pem"
  }
  retry_join {
    leader_tls_servername   = "cisb-node-x"
    leader_api_addr         = "https://cisb-node-2:8200"
    leader_ca_cert_file     = "/opt/vault/tls/vault.cisb.local-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/vault.cisb.local.pem"
    leader_client_key_file  = "/opt/vault/tls/vault.cisb.local-key.pem"
  }
  retry_join {
    leader_tls_servername   = "cisb-node-x"
    leader_api_addr         = "https://cisb-node-2:8200"
    leader_ca_cert_file     = "/opt/vault/tls/vault.cisb.local-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/vault.cisb.local.pem"
    leader_client_key_file  = "/opt/vault/tls/vault.cisb.local-key.pem"
  }
}
