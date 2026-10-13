# Valeurs du homelab (aucun secret ici : le token Proxmox passe par PROXMOX_VE_API_TOKEN).

pve_endpoint     = "https://192.168.1.11:8006/" # pve1
pve_node         = "pve1"
datastore_rootfs = "local-zfs"

# Nom exact affiché par « pveam list local » (docs/GUIDE.md, étape 1).
lxc_template = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"

network = {
  bridge      = "vmbr1"
  gateway     = "192.168.1.254"  # Bbox
  dns_servers = ["192.168.1.14"] # AdGuard Home
}

# IDs 300-399 réservés à Terraform. IPs hors de la plage DHCP (192.168.1.50-200).
containers = {
  "lab-demo01" = {
    vm_id       = 301
    ip          = "192.168.1.24/24"
    memory      = 2048
    tags        = ["demo"]
    description = "Conteneur de démonstration du pipeline IaC."
  }
}
