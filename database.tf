resource "random_password" "accounts_db_password" {
  length  = 32
  special = true
  # Exclude characters that can be troublesome in connection strings
  override_special = "!-_"
}

resource "scaleway_rdb_instance" "main" {
  name          = "htk-production-db"
  node_type     = "DB-DEV-S"
  engine        = "PostgreSQL-17"
  region        = var.region
  is_ha_cluster = true

  disable_backup            = false
  backup_schedule_frequency = 6 # =4 times a day
  backup_schedule_retention = 365

  volume_type        = "sbs_5k"
  volume_size_in_gb  = 5
  encryption_at_rest = true

  private_network {
    pn_id       = scaleway_vpc_private_network.main.id
    enable_ipam = true
  }

  tags = ["htk", "production"]
}

resource "scaleway_rdb_database" "accounts_db" {
  instance_id = scaleway_rdb_instance.main.id
  name        = "accounts"
}

resource "scaleway_rdb_user" "accounts_user" {
  instance_id = scaleway_rdb_instance.main.id
  name        = "accounts"
  password    = random_password.accounts_db_password.result
  is_admin    = false
}

resource "scaleway_rdb_privilege" "accounts_user_perms" {
  instance_id   = scaleway_rdb_instance.main.id
  user_name     = scaleway_rdb_user.accounts_user.name
  database_name = scaleway_rdb_database.accounts_db.name
  permission    = "all"
}

output "database_url" {
  value     = "postgres://${scaleway_rdb_user.accounts_user.name}:${scaleway_rdb_user.accounts_user.password}@${scaleway_rdb_instance.main.private_network[0].ip}:${scaleway_rdb_instance.main.private_network[0].port}/${scaleway_rdb_database.accounts_db.name}"
  sensitive = true
}