output "role_name" {
  value = vault_kubernetes_auth_backend_role.this.role_name
}

output "policy_name" {
  value = vault_policy.read.name
}

output "secret_path" {
  value = "${var.kv_mount}/${local.secret_path}"
}
