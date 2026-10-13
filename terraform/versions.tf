terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # Provider communautaire le plus maintenu pour Proxmox VE (cible PVE 9.x).
    # Version 0.x : on fige la mineure, les montées de version passent par une PR (Dependabot).
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
  }

  # L'état (state) reste dans le homelab, jamais dans Git.
  # Il est partagé entre les exécutions manuelles et le runner GitHub (même LXC, même utilisateur).
  backend "local" {
    path = "/srv/terraform/state/homelab.tfstate"
  }
}
