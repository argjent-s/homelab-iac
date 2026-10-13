provider "proxmox" {
  endpoint = var.pve_endpoint
  insecure = var.pve_insecure

  # Aucun secret dans le code : le token est lu dans la variable d'environnement
  # PROXMOX_VE_API_TOKEN (format "terraform@pve!iac=<secret>").
  # - en local : ~/.config/iac/proxmox.env
  # - en CI    : secret GitHub PROXMOX_VE_API_TOKEN
}
