data "aws_availability_zones" "available" {
  state = "available"
}

# checkov:skip=CKV2_AWS_11: flow logs custariam mais (Logs/S3 + storage) do
# que o próprio worker que protegem, SG já nega toda entrada, nada a
# investigar numa única instância Spot sem ingress.
resource "aws_vpc" "this" {
  cidr_block           = "10.60.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "k8s-spot-worker" }
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  # Sem regras de propósito, ninguém deve usar o default SG, tudo (launch
  # template do worker) usa aws_security_group.spot_worker explicitamente.
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "k8s-spot-worker" }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  # O IP público é atribuído só pela launch
  # template do worker Spot (network_interfaces), não por padrão a qualquer
  # instância que caia nessa subnet.
  tags = { Name = "k8s-spot-worker-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "k8s-spot-worker" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# checkov:skip=CKV2_AWS_5: attachado via network_interfaces.security_groups
# na launch template (asg.tf). O Checkov não traça a referência através do
# mixed_instances_policy/launch_template aninhado do ASG.
resource "aws_security_group" "spot_worker" {
  name_prefix = "k8s-spot-worker-"
  vpc_id      = aws_vpc.this.id
  description = "Worker Spot sem regra de entrada, só conecta outbound (Tailscale)"

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS (fallback TCP)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP (mirrors apt)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS (apt, SSM, Tailscale DERP fallback)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Tailscale WireGuard direto"
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-spot-worker" }
}
