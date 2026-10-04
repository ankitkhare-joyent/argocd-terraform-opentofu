output "tenants" {
  value = { for k, t in module.tenant : k => {
    role   = t.role_name
    policy = t.policy_name
    secret = t.secret_path
  } }
}
