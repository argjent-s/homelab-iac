variable "pve_endpoint" {
  description = "URL de l'API Proxmox VE (ex. https://192.168.1.11:8006/)."
  type        = string
}

variable "pve_insecure" {
  description = "Accepter le certificat auto-signé de Proxmox (lab uniquement ; en production : certificat valide)."
  type        = bool
  default     = true
}

variable "pve_node" {
  description = "Nœud Proxmox par défaut sur lequel créer les conteneurs."
  type        = string
}

variable "datastore_rootfs" {
  description = "Stockage Proxmox des disques racine des LXC (ex. local-zfs)."
  type        = string
}

variable "lxc_template" {
  description = "Template LXC au format <stockage>:vztmpl/<fichier> (doit exister sur chaque nœud utilisé)."
  type        = string

  validation {
    condition     = can(regex("^[^:]+:vztmpl/.+\\.tar\\.(zst|gz|xz)$", var.lxc_template)) && !strcontains(var.lxc_template, "XX")
    error_message = "Renseigne le nom exact du template (pveam list local) au format local:vztmpl/<fichier>.tar.zst."
  }
}

variable "ssh_public_key_path" {
  description = "Clé publique SSH injectée dans root@conteneur (utilisée ensuite par Ansible)."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "network" {
  description = "Paramètres réseau communs aux conteneurs."
  type = object({
    bridge      = string
    gateway     = string
    dns_servers = list(string)
    dns_domain  = optional(string)
  })
}

variable "containers" {
  description = "Conteneurs LXC gérés par Terraform. La clé de la map devient le hostname."
  type = map(object({
    vm_id       = number
    ip          = string # notation CIDR, ex. 192.168.1.31/24
    node        = optional(string)
    cores       = optional(number, 1)
    memory      = optional(number, 1024) # Mo
    swap        = optional(number, 512)  # Mo
    disk        = optional(number, 8)    # Go
    tags        = optional(list(string), [])
    description = optional(string, "")
  }))

  validation {
    condition     = alltrue([for c in values(var.containers) : can(cidrhost(c.ip, 0))])
    error_message = "Chaque conteneur doit avoir une IP en notation CIDR (ex. 192.168.1.31/24)."
  }

  validation {
    condition     = alltrue([for c in values(var.containers) : c.vm_id >= 300 && c.vm_id < 400])
    error_message = "Convention du lab : les conteneurs gérés par Terraform utilisent les IDs 300 à 399."
  }
}
