locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "proxmox_virtual_environment_container" "lxc" {
  for_each = var.containers

  node_name     = coalesce(each.value.node, var.pve_node)
  vm_id         = each.value.vm_id
  description   = trimspace("Géré par Terraform (homelab-iac). ${each.value.description}")
  tags          = sort(distinct(concat(["terraform"], each.value.tags)))
  unprivileged  = true # conteneur non privilégié : isolation renforcée
  started       = true
  start_on_boot = true

  features {
    nesting = true # requis par systemd récent ; seule option modifiable sans root@pam
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.network.gateway
      }
    }

    dns {
      servers = var.network.dns_servers
      domain  = var.network.dns_domain
    }

    # Accès root par clé uniquement (aucun mot de passe défini).
    user_account {
      keys = [local.ssh_public_key]
    }
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = var.datastore_rootfs
    size         = each.value.disk
  }

  network_interface {
    name   = "eth0"
    bridge = var.network.bridge
  }

  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }
}
