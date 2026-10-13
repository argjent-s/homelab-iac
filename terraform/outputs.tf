output "containers" {
  description = "Conteneurs créés : ID, nœud et IP."
  value = {
    for name, c in proxmox_virtual_environment_container.lxc : name => {
      vm_id = c.vm_id
      node  = c.node_name
      ip    = split("/", var.containers[name].ip)[0]
    }
  }
}

# Inventaire Ansible dérivé de l'état Terraform : une seule source de vérité.
# Utilisation : terraform output -raw ansible_inventory > ../ansible/inventory/hosts.yml
output "ansible_inventory" {
  description = "Inventaire Ansible (YAML) des conteneurs gérés par Terraform."
  value = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    hosts = {
      for name, c in proxmox_virtual_environment_container.lxc : name => split("/", var.containers[name].ip)[0]
    }
  })
}
