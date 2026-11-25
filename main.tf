# ============================================================
# main.tf  ·  Biblioteca Digital EduAndes
# ============================================================
# Orden del archivo:
#   0. Datos y locals      3. Servidores (for_each)
#   1. Red (VPC, subnets)  4. NLB (target group + listener)
#   2. Security groups     5. RDS MySQL    6. Bucket S3

# ------------------------------------------------------------
# 0. DATA SOURCES Y LOCALS
# ------------------------------------------------------------

# Zonas de disponibilidad existentes en la región (no se escriben a mano)
data "aws_availability_zones" "disponibles" {
  state = "available"
}

# ID de la cuenta AWS: lo usamos para que el nombre del bucket sea único en el mundo
data "aws_caller_identity" "actual" {}

# Última AMI de Amazon Linux 2023 (se busca, no se copia un ID fijo)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  # ---- Condicional central: UNA sola comparación, usada en todo el código ----
  es_prod = var.ambiente == "prod"

  # ---- Tags comunes: se combinan con merge() en cada recurso ----
  tags_comunes = {
    Proyecto    = var.proyecto
    Ambiente    = var.ambiente
    Responsable = var.responsable
  }

  # ---- Expresiones for con filtro: separan subredes públicas y privadas ----
  subnets_publicas = { for k, v in var.subnets : k => v if v.publica }
  subnets_privadas = { for k, v in var.subnets : k => v if !v.publica }

  # ---- Funciones internas ----
  prefijo         = format("%s-%s-%s", var.proyecto, var.aplicacion, var.ambiente)
  nombre_ambiente = lookup({ dev = "Desarrollo", prod = "Produccion" }, var.ambiente, "Desconocido")
}

# ------------------------------------------------------------
# 1. RED: VPC + 4 subredes (un solo bloque con for_each)
# ------------------------------------------------------------
resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-vpc" })
}

resource "aws_subnet" "principal" {
  for_each = var.subnets # <- 1 bloque = 4 subredes

  vpc_id                  = aws_vpc.principal.id
  cidr_block              = each.value.cidr
  availability_zone       = data.aws_availability_zones.disponibles.names[each.value.az_index]
  map_public_ip_on_launch = each.value.publica

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-${each.key}" })
}

# Las subredes públicas necesitan salida a internet: Internet Gateway + tabla de rutas
resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-igw" })
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.principal.id
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-rt-publica" })
}

# Solo se asocian las subredes públicas (for_each sobre el mapa filtrado)
resource "aws_route_table_association" "publica" {
  for_each = local.subnets_publicas

  subnet_id      = aws_subnet.principal[each.key].id
  route_table_id = aws_route_table.publica.id
}

# ------------------------------------------------------------
# 2. SECURITY GROUPS
# ------------------------------------------------------------
resource "aws_security_group" "servidores" {
  name        = "${local.prefijo}-sg-servidores"
  description = "Acceso a los servidores de la biblioteca"
  vpc_id      = aws_vpc.principal.id

  # Bloque dynamic: genera un bloque "ingress" por cada regla de la variable
  dynamic "ingress" {
    for_each = var.reglas_ingreso_servidores
    content {
      description = ingress.value.descripcion
      from_port   = ingress.value.puerto
      to_port     = ingress.value.puerto
      protocol    = "tcp"
      cidr_blocks = [ingress.value.cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-sg-servidores" })
}

# La RDS SOLO acepta tráfico MySQL que venga del security group de los servidores.
# No hay ningún CIDR de internet: por eso no se puede entrar desde su PC.
resource "aws_security_group" "rds" {
  name        = "${local.prefijo}-sg-rds"
  description = "MySQL solo desde los servidores"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "MySQL desde servidores"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.servidores.id]
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-sg-rds" })
}

# ------------------------------------------------------------
# 3. SERVIDORES: 3 instancias con UN solo bloque (for_each)
# ------------------------------------------------------------
resource "aws_instance" "servidor" {
  for_each = var.servidores # clave: "biblioteca-a", valor: {instance_type, disco_gb, subnet}

  ami                         = data.aws_ami.al2023.id
  instance_type               = each.value.instance_type
  subnet_id                   = aws_subnet.principal[each.value.subnet].id
  vpc_security_group_ids      = [aws_security_group.servidores.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = var.instance_profile

  user_data = templatefile("${path.module}/userdata.tpl", {
    hostname = each.key
    ambiente = local.nombre_ambiente
  })

  root_block_device {
    volume_type = "gp3"
    # CONDICIONAL 1: en prod el disco se duplica
    volume_size = local.es_prod ? each.value.disco_gb * 2 : each.value.disco_gb
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-${each.key}" })

  lifecycle {
    precondition {
      condition     = data.aws_ami.al2023.architecture == "x86_64"
      error_message = "La AMI debe ser x86_64 para usar instancias t3."
    }
  }
}

# ------------------------------------------------------------
# 4. NLB: balanceador + target group + listener TCP
# ------------------------------------------------------------
resource "aws_lb" "nlb" {
  name               = "${local.prefijo}-nlb"
  load_balancer_type = "network"
  internal           = false
  # keys() entrega los nombres de las subredes públicas; el for arma la lista de IDs
  subnets = [for k in keys(local.subnets_publicas) : aws_subnet.principal[k].id]

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-nlb" })
}

resource "aws_lb_target_group" "app" {
  name        = "${local.prefijo}-tg"
  port        = var.puerto_app
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.principal.id

  health_check {
    protocol = "TCP"
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-tg" })
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.puerto_app
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-listener" })
}

# Registro de los 3 servidores como targets, con un ciclo (for_each sobre las instancias)
resource "aws_lb_target_group_attachment" "servidor" {
  for_each = aws_instance.servidor

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = each.value.id
  port             = var.puerto_app
}

# ------------------------------------------------------------
# 5. RDS MySQL en subredes privadas
# ------------------------------------------------------------
resource "aws_db_subnet_group" "bd" {
  name       = "${local.prefijo}-subnet-group"
  subnet_ids = [for k in keys(local.subnets_privadas) : aws_subnet.principal[k].id]

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-subnet-group" })
}

resource "aws_db_instance" "bd" {
  identifier        = "${local.prefijo}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password # viene de TF_VAR_db_password, nunca escrita en los .tf

  db_subnet_group_name   = aws_db_subnet_group.bd.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # no accesible desde internet

  # CONDICIONAL 2: Multi-AZ solo en prod
  multi_az = local.es_prod

  skip_final_snapshot = true # evita que "destroy" quede pegado pidiendo un snapshot

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-mysql" })
}

# ------------------------------------------------------------
# 6. BUCKET S3 (fuera de la VPC)
# ------------------------------------------------------------
resource "aws_s3_bucket" "material" {
  # format() + lower(): el nombre sale de variables y es único gracias al ID de cuenta
  bucket        = lower(format("%s-%s-%s-%s", var.proyecto, var.aplicacion, var.ambiente, data.aws_caller_identity.actual.account_id))
  force_destroy = true # permite que "terraform destroy" borre el bucket aunque tenga archivos

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-bucket" })
}

resource "aws_s3_bucket_public_access_block" "material" {
  bucket                  = aws_s3_bucket.material.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "material" {
  bucket = aws_s3_bucket.material.id

  versioning_configuration {
    # CONDICIONAL 3: versionado habilitado solo en prod
    status = local.es_prod ? "Enabled" : "Suspended"
  }
}
