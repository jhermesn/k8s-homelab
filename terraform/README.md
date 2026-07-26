# Terraform - worker Spot AWS

Um ASG Spot (`t3.micro`, ~53% de desconto) que entra no cluster via
Tailscale quando escalado. VPC, subnets e AMI (Ubuntu, sempre a última) são
criadas automaticamente - só precisa de uma conta AWS e os parâmetros SSM.

Aplicado localmente ou por [`cd.sh`](../cd.sh), com as credenciais AWS de
quem roda (`aws configure` / SSO).

## Setup (uma vez)

1. **Bucket do state:** [`bootstrap/`](bootstrap/) é um módulo Terraform à
   parte (state local, de propósito pois não dá pra guardar remotamente o
   bucket que ainda não existe):

   ```bash
   cd bootstrap
   cp terraform.tfvars.example terraform.tfvars   # preencher região + nome do bucket
   terraform init && terraform apply
   cd ..
   ```

2. **Config principal:** Terraform cria os parâmetros SSM `SecureString`
   (`tailscale_authkey`, `kubeadm_join_command`) a partir do `tfvars`:

   ```bash
   cp terraform.tfvars.example terraform.tfvars   # preencher região, nomes dos parâmetros e os segredos
   cp backend.hcl.example backend.hcl             # bucket = output do passo 1
   terraform init -backend-config=backend.hcl
   ```

   `terraform.tfvars` fica com os segredos em texto, gitignored, nunca vai
   pro repo. Eles também ficam no state (bucket já é SSE-KMS + TLS-only +
   sem acesso público).

## Uso

```bash
terraform apply
```

O ASG sobe com `desired_capacity = 0` (custo zero quando não precisa do
worker extra). Quem escala é o **cluster-autoscaler**
(`manifests/cluster-autoscaler/`), rodando dentro do cluster. Sobe o
worker quando há pod pendente sem capacidade, derruba quando ocioso. Dá pra
escalar manual também, se quiser:

```bash
aws autoscaling set-desired-capacity --auto-scaling-group-name k8s-spot-worker --desired-capacity 1
```

`cd.sh` roda `terraform apply` a cada sync, mas ignora mudanças em
`desired_capacity` - nem o CD nem o cluster-autoscaler brigam pelo valor.

## cluster-autoscaler

Roda fora da AWS (no control plane on-prem), então usa credenciais estáticas
em vez de instance profile/IRSA. Depois do `apply`:

```bash
terraform output cluster_autoscaler_access_key_id
terraform output -raw cluster_autoscaler_secret_access_key
```

Criar o Secret `aws-secret` (namespace `kube-system`) com esses valores num
arquivo `credentials` formato ini, é isso que `manifests/cluster-autoscaler/`
monta como volume (não env var, pra não vazar segredo em `/proc/*/environ`
ou logs):

```bash
kubectl create secret generic aws-secret -n kube-system \
  --from-literal=credentials="[default]
aws_access_key_id = <output acima>
aws_secret_access_key = <output acima>"
```

IAM da role escopado só ao ASG `k8s-spot-worker` (ver `cluster-autoscaler.tf`).