# Guide de mise en place

Objectif : passer de « je crée mes LXC à la main » à « Git → contrôles → plan → approbation → déploiement automatique ».

| Étape | Contenu |
|---|---|
| 1 | Template Debian 13 et LXC de contrôle `ctl-iac` |
| 2 | Proxmox : rôle limité et utilisateur dédié |
| 3 | Outils sur `ctl-iac` et token API |
| 4 | Premier déploiement à la main (Terraform puis Ansible) |
| 5 | GitHub : secret, environnement protégé, runner auto-hébergé |
| 6 | Premier push : CI et déploiement par le pipeline |
| 7 | Changement complet par pull request |

Les valeurs des exemples sont celles de mon lab (cluster Proxmox VE 9 `pve1`/`pve2`, réseau `192.168.1.0/24`, bridge `vmbr1`, stockage `local-zfs`) : adapte-les à ton environnement.

Conventions du dépôt, vérifiées par le code :
- IDs `300–399` réservés aux conteneurs gérés par Terraform ;
- IP fixes en notation CIDR, hors de la plage DHCP ;
- conteneurs non privilégiés, accès root par clé SSH uniquement.

---

## Étape 1 — Template Debian 13 et LXC de contrôle `ctl-iac`

`ctl-iac` est le seul conteneur créé à la main. Un seul suffit pour tout le cluster : il pilote les nœuds via l'API Proxmox. Shell d'un nœud (ici **pve1**) :

```bash
# Paramètres du conteneur de contrôle (à adapter)
CTID=111; CT_IP=192.168.1.23/24; GW=192.168.1.254; DNS=192.168.1.14
BRIDGE=vmbr1; DISK_STORE=local-zfs; TPL_STORE=local   # TPL_STORE = nom du stockage seul

# Stockages qui acceptent les templates LXC (type de contenu « vztmpl »)
pvesm status --content vztmpl

# Template Debian 13 — filtrer sur amd64 : la liste contient aussi une variante arm64
pveam update >/dev/null
TPL_NAME=$(pveam available --section system | awk '/debian-13-standard_.*_amd64/{print $2}' | sort -V | tail -1)
pveam list $TPL_STORE | grep -q "$TPL_NAME" || pveam download $TPL_STORE "$TPL_NAME"
echo "Template : $TPL_STORE:vztmpl/$TPL_NAME"    # → valeur de lxc_template (étape 4)

# Conteneur de contrôle
pct create $CTID "$TPL_STORE:vztmpl/$TPL_NAME" \
  --hostname ctl-iac --unprivileged 1 --features nesting=1 \
  --cores 2 --memory 2048 --swap 512 \
  --rootfs $DISK_STORE:16 \
  --net0 name=eth0,bridge=$BRIDGE,ip=$CT_IP,gw=$GW \
  --nameserver $DNS --onboot 1 --tags iac \
  --description "Controleur IaC : Terraform, Ansible, runner GitHub"
pct start $CTID
```

Le template n'est nécessaire que sur les nœuds où Terraform **crée** des conteneurs. Pour cibler un autre nœud (`node = "pve2"` dans le tfvars), télécharger le même template sur ce nœud.

---

## Étape 2 — Proxmox : rôle limité et utilisateur dédié

**Une seule fois pour tout le cluster** : rôles, utilisateurs, ACL et tokens sont stockés dans `/etc/pve`, répliqué sur tous les nœuds.

```bash
# Rôle limité à ce dont Terraform a besoin pour gérer des LXC (moindre privilège)
pveum role add TerraformLXC -privs "Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Audit,SDN.Audit,SDN.Use,Sys.Audit,Sys.Console,VM.Allocate,VM.Audit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Console,VM.PowerMgmt"

# Utilisateur technique (realm pve, pas de shell, pas de root)
pveum user add terraform@pve --comment "IaC - homelab-iac"
pveum acl modify / --users terraform@pve --roles TerraformLXC
```

Le token API est créé à l'étape 3, une fois `ctl-iac` prêt.

---

## Étape 3 — Outils sur `ctl-iac` et token API

**Outils** — console du conteneur (`pct enter 111`), en root :

```bash
apt update && apt install -y git
git clone https://github.com/<ton-compte>/homelab-iac.git /root/homelab-iac   # ton fork du dépôt
bash /root/homelab-iac/bootstrap/ctl-iac-setup.sh
```

Le script installe Terraform, Ansible, ansible-lint, Git et make, crée l'utilisateur `iac`, ses deux clés SSH (accès aux conteneurs / GitHub), les dossiers `/srv/terraform/{state,plans}`, le fichier `~/.config/iac/proxmox.env` (chargé par `.bashrc`) et copie le dépôt dans `/home/iac/homelab-iac`. Il affiche à la fin la clé publique GitHub (étape 5).

**Token API** — shell du nœud. Le secret est écrit directement dans `ctl-iac`, sans copier-coller dans une console web (qui peut altérer la valeur) :

```bash
apt install -y jq
# privsep 0 = le token hérite des droits de terraform@pve
TOK=$(pveum user token add terraform@pve iac --privsep 0 --comment "homelab-iac" --output-format json | jq -r '."full-tokenid" + "=" + .value')
umask 077; printf "export PROXMOX_VE_API_TOKEN='%s'\n" "$TOK" > /root/proxmox.env; unset TOK
pct push 111 /root/proxmox.env /home/iac/.config/iac/proxmox.env --user 1000 --group 1000 --perms 0600
cat /root/proxmox.env      # à ranger dans un gestionnaire de secrets ; sert aussi de secret GitHub (étape 5)
shred -u /root/proxmox.env
```

Pour régénérer le token : `pveum user token remove terraform@pve iac`, puis relancer le bloc.

**Test** — dans `ctl-iac`, en `iac` (`su - iac`) :

```bash
curl -sk -w '\nHTTP %{http_code}\n' -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" https://192.168.1.11:8006/api2/json/version
# attendu : {"data":{"release":"9.x",...}} puis HTTP 200
```

---

## Étape 4 — Premier déploiement à la main

En `iac`, dans `~/homelab-iac`, vérifier `terraform/terraform.tfvars` : `pve_endpoint`, `pve_node`, `datastore_rootfs`, `lxc_template` (valeur affichée à l'étape 1), `network`, et l'IP de chaque conteneur (libre, hors plage DHCP).

**Prérequis Wazuh** : `wazuh_agent_manager` (`ansible/group_vars/all.yml`) doit résoudre vers le **manager lui-même**, pas vers un reverse proxy HTTP : l'agent utilise TCP 1514/1515.

```bash
M=$(awk -F'"' '/^wazuh_agent_manager:/{print $2}' ansible/group_vars/all.yml)
getent hosts "$M"
for p in 1514 1515; do timeout 2 bash -c "</dev/tcp/$M/$p" 2>/dev/null && echo "$p ouvert" || echo "$p fermé"; done
ansible-galaxy collection install -r ansible/requirements.yml
```

Déploiement :

```bash
make init      # télécharge le provider, crée terraform/.terraform.lock.hcl (à committer)
make plan      # doit annoncer : 1 to add
make apply     # « yes » → le LXC 301 lab-demo01 apparaît dans Proxmox, tags demo + terraform
make ansible   # mises à jour, durcissement SSH, agent Wazuh
make ansible   # 2e passage : changed=0 partout = idempotence
```

Vérifications (adapter l'IP) :

```bash
ssh root@192.168.1.24 hostname                          # → lab-demo01, par clé
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password root@192.168.1.24
                                                        # → Permission denied (publickey)
ssh root@192.168.1.24 systemctl is-active wazuh-agent   # → active
```

L'agent `lab-demo01` doit apparaître **actif** dans le dashboard Wazuh.

---

## Étape 5 — GitHub : secret, environnement protégé, runner

1. **Clé SSH** : ajouter la clé publique de `~/.ssh/github.pub` (utilisateur `iac`) dans *Settings > SSH and GPG keys*, puis `ssh -T git@github.com`. À la première connexion, vérifier l'empreinte de GitHub (`SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` pour Ed25519).
2. **Secret** : dépôt > *Settings > Secrets and variables > Actions* → `PROXMOX_VE_API_TOKEN` = token complet.
3. **Environnement protégé** : dépôt > *Settings > Environments* → `homelab`, *Required reviewers* = soi-même, *Deployment branches* = `main` uniquement.
4. **Pull requests externes** : dépôt > *Settings > Actions > General* → approbation requise pour **tous** les contributeurs externes.
5. **Runner auto-hébergé** : dépôt > *Settings > Actions > Runners > New self-hosted runner* → *Linux x64*. Commandes affichées à exécuter **en `iac`** ; pendant `./config.sh` : nom `ctl-iac`, label supplémentaire **`homelab`** (ciblé par `deploy.yml`). Puis, en root :

   ```bash
   cd /home/iac/actions-runner
   ./bin/installdependencies.sh      # si la distribution n'est pas reconnue : apt install -y libicu76
   ./svc.sh install iac
   ./svc.sh start
   ```

   Le runner doit apparaître **Idle**.

Pourquoi un runner auto-hébergé reste sûr sur un dépôt public : `deploy.yml` ne se déclenche que sur un push vers `main` (ou manuellement), jamais sur une pull request ; la CI tourne sur les runners hébergés par GitHub ; le déploiement exige une approbation dans l'environnement `homelab`.

---

## Étape 6 — Premier push

En `iac` :

```bash
cd ~/homelab-iac
git config --global user.name "<Ton nom>"
git config --global user.email "<id>+<compte>@users.noreply.github.com"
git remote set-url origin git@github.com:<ton-compte>/homelab-iac.git   # push par la clé SSH de l'étape 5
git add .
git status        # contrôle : AUCUN .tfstate, proxmox.env ni ansible/inventory/hosts.yml
git commit -m "<message>"
git push -u origin main
```

Onglet **Actions** :
- **CI - Qualité et sécurité** : 3 jobs verts (Terraform, Ansible, Checkov) ;
- **Deploy - Homelab** : le plan affiche « No changes » (déjà déployé à l'étape 4), puis le job *apply* attend l'approbation (*Review deployments > Approve*) et rejoue Ansible.

---

## Étape 7 — Changement complet par pull request

```bash
git switch -c feat/lab-demo01-ram
# terraform/terraform.tfvars, conteneur lab-demo01 : ajouter  memory = 2048
git commit -am "lab-demo01 : 2 Go de RAM"
git push -u origin feat/lab-demo01-ram
```

1. Ouvrir la **pull request** → la CI tourne (contrôles + scan de sécurité).
2. **Merge** dans `main` → *Deploy - Homelab* démarre.
3. Le résumé du job *plan* montre `~ memory.dedicated = 1024 -> 2048`.
4. **Approve** → apply → Ansible.
5. Vérifier dans Proxmox : 2 Go.

Recommandé : *Settings > Rules > Rulesets* sur `main` pour exiger une PR et des checks CI verts avant tout merge.

---

## Dépannage

| Symptôme | Cause probable | Correction |
|---|---|---|
| `HTTP 401` au test `curl` / `401` dans Terraform | secret du token incomplet ou altéré | régénérer et injecter le token (étape 3) |
| `403 Permission check failed … (<privilège>)` | privilège manquant dans le rôle | `pveum role modify TerraformLXC --append 1 --privs <privilège>` |
| `storage '…' does not support templates` | stockage sans le type `vztmpl` | `pvesm status --content vztmpl` pour trouver le bon stockage |
| `unable to parse directory volume name` | chemin complet mis dans `TPL_STORE` | `TPL_STORE` = nom du stockage seul (`local`) |
| `Invalid value for variable` sur `lxc_template` | nom de template non renseigné | reprendre le nom exact de `pveam list local` |
| `volume … does not exist` | template absent du nœud cible | `pveam download local …` sur ce nœud |
| `pct push` : `can only push files to a running CT` | conteneur arrêté **ou inexistant** | `pct list` |
| `ping: socket: Operation not permitted` dans `ctl-iac` | utilisateur non root dans un LXC non privilégié | tester depuis le nœud, ou en root `setcap cap_net_raw+ep /usr/bin/ping` |
| Ansible `UNREACHABLE` | IP / bridge / conteneur arrêté | `ssh root@<ip>` depuis `iac`, vérifier le bridge dans le tfvars |
| Agent Wazuh déconnecté | nom du manager résolu vers un reverse proxy / ports / version | voir le prérequis Wazuh de l'étape 4 |
| Job *Deploy* bloqué en « Queued » | runner arrêté ou label `homelab` absent | `./svc.sh status` en root, labels du runner dans GitHub |
| `Saved plan is stale` | l'état a changé entre plan et apply | relancer **tout** le workflow, pas seulement le job apply |
