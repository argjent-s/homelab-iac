#!/usr/bin/env bash
# =============================================================================
# Prépare le LXC de contrôle « ctl-iac » (Debian 12/13), à lancer UNE fois en root
# depuis le dossier du dépôt :  bash bootstrap/ctl-iac-setup.sh
#
# Installe : Terraform (dépôt officiel HashiCorp), Ansible, ansible-lint, Git, make
# Crée     : l'utilisateur « iac » (exécutions manuelles + runner GitHub),
#            ses clés SSH, les dossiers d'état Terraform, le fichier du token.
# =============================================================================
set -euo pipefail

IAC_USER="iac"
IAC_HOME="/home/${IAC_USER}"
REPO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ${EUID} -ne 0 ]]; then
  echo "Ce script doit être lancé en root." >&2
  exit 1
fi

echo "==> Paquets de base"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git make jq unzip openssh-client \
  python3 ansible ansible-lint

echo "==> Terraform (dépôt HashiCorp)"
# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${VERSION_CODENAME}"
if ! curl -fsI "https://apt.releases.hashicorp.com/dists/${CODENAME}/Release" >/dev/null 2>&1; then
  echo "    Dépôt HashiCorp indisponible pour ${CODENAME}, utilisation de bookworm (binaire identique)."
  CODENAME="bookworm"
fi
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform

echo "==> Utilisateur ${IAC_USER}"
id "${IAC_USER}" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "${IAC_USER}"
install -d -m 0700 -o "${IAC_USER}" -g "${IAC_USER}" "${IAC_HOME}/.ssh"

# Clé 1 : accès root aux conteneurs (injectée par Terraform, utilisée par Ansible)
[[ -f "${IAC_HOME}/.ssh/id_ed25519" ]] || \
  runuser -u "${IAC_USER}" -- ssh-keygen -q -t ed25519 -N "" -C "iac@ctl-iac (conteneurs)" -f "${IAC_HOME}/.ssh/id_ed25519"

# Clé 2 : push vers GitHub (séparée de la clé d'accès aux conteneurs)
[[ -f "${IAC_HOME}/.ssh/github" ]] || \
  runuser -u "${IAC_USER}" -- ssh-keygen -q -t ed25519 -N "" -C "iac@ctl-iac (github)" -f "${IAC_HOME}/.ssh/github"

if ! grep -q "Host github.com" "${IAC_HOME}/.ssh/config" 2>/dev/null; then
  cat >> "${IAC_HOME}/.ssh/config" <<'EOF'
Host github.com
  User git
  IdentityFile ~/.ssh/github
  IdentitiesOnly yes
EOF
fi
chown "${IAC_USER}:${IAC_USER}" "${IAC_HOME}/.ssh/config"
chmod 0600 "${IAC_HOME}/.ssh/config"

echo "==> Dossiers d'état et de plans Terraform"
install -d -m 0700 -o "${IAC_USER}" -g "${IAC_USER}" /srv/terraform /srv/terraform/state /srv/terraform/plans

echo "==> Fichier du token Proxmox (à compléter)"
install -d -m 0700 -o "${IAC_USER}" -g "${IAC_USER}" "${IAC_HOME}/.config" "${IAC_HOME}/.config/iac"
ENV_FILE="${IAC_HOME}/.config/iac/proxmox.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF'
# Token API Proxmox — NE JAMAIS COMMITTER CE FICHIER
# export PROXMOX_VE_API_TOKEN='terraform@pve!iac=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
EOF
fi
chown "${IAC_USER}:${IAC_USER}" "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"
grep -q "proxmox.env" "${IAC_HOME}/.bashrc" || \
  echo '[ -f ~/.config/iac/proxmox.env ] && . ~/.config/iac/proxmox.env' >> "${IAC_HOME}/.bashrc"

echo "==> Copie du dépôt dans ${IAC_HOME}/homelab-iac"
if [[ "${REPO_SRC}" != "${IAC_HOME}/homelab-iac" && ! -d "${IAC_HOME}/homelab-iac" ]]; then
  cp -a "${REPO_SRC}" "${IAC_HOME}/homelab-iac"
fi
chown -R "${IAC_USER}:${IAC_USER}" "${IAC_HOME}/homelab-iac"

cat <<EOF

=============================================================================
 ctl-iac prêt.
   $(terraform version | head -1)
   $(ansible --version | head -1)

 Clé publique « conteneurs » (utilisée automatiquement par Terraform) :
   $(cat "${IAC_HOME}/.ssh/id_ed25519.pub")

 Clé publique « GitHub » (à ajouter dans GitHub > Settings > SSH and GPG keys) :
   $(cat "${IAC_HOME}/.ssh/github.pub")

 Étape suivante : su - ${IAC_USER}  puis suivre docs/GUIDE.md (étape 3).
=============================================================================
EOF
