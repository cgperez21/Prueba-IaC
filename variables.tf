# ============================================================
# variables.tf  ·  Todas las "perillas" del proyecto
# ============================================================
# Regla de oro: si un valor podría cambiar, va aquí y NO en main.tf.

# ---------- Generales ----------
variable "region" {
  description = "Región de AWS donde se despliega todo"
  type        = string
  default     = "us-east-1" # AWS Academy Learner Lab usa us-east-1
}

variable "proyecto" {
  description = "Nombre del proyecto (se usa en tags y nombres)"
  type        = string
  default     = "eduandes"
}

variable "aplicacion" {
  description = "Nombre de la aplicación"
  type        = string
  default     = "biblioteca"
}

variable "responsable" {
  description = "Persona responsable (va en los tags)"
  type        = string
  default     = "alumno-duoc"
}

variable "ambiente" {
  description = "Ambiente de despliegue: dev o prod. ES LA VARIABLE QUE ACTIVA LOS CONDICIONALES"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.ambiente)
    error_message = "El ambiente debe ser exactamente \"dev\" o \"prod\"."
  }
}

# ---------- Red ----------
variable "vpc_cidr" {
  description = "Rango de IPs de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Un solo mapa describe las 4 subredes. for_each lo recorre.
variable "subnets" {
  description = "Mapa de subredes: clave => datos de cada subred"
  type = map(object({
    cidr     = string
    az_index = number # 0 = primera zona de disponibilidad, 1 = segunda
    publica  = bool
  }))
  default = {
    "publica-1" = { cidr = "10.0.1.0/24", az_index = 0, publica = true }
    "publica-2" = { cidr = "10.0.2.0/24", az_index = 1, publica = true }
    "privada-1" = { cidr = "10.0.11.0/24", az_index = 0, publica = false }
    "privada-2" = { cidr = "10.0.12.0/24", az_index = 1, publica = false }
  }
}

# ---------- Servidores ----------
# Un solo mapa describe los 3 servidores. Para agregar un 4to servidor
# basta con agregar UNA entrada aquí (en terraform.tfvars). No se toca main.tf.
variable "servidores" {
  description = "Mapa de servidores: nombre => tipo de instancia, disco base y subred"
  type = map(object({
    instance_type = string
    disco_gb      = number
    subnet        = string # clave de var.subnets (debe ser una subred pública)
  }))
  default = {
    "biblioteca-a" = { instance_type = "t3.medium", disco_gb = 30, subnet = "publica-1" }
    "biblioteca-b" = { instance_type = "t3.medium", disco_gb = 30, subnet = "publica-1" }
    "biblioteca-c" = { instance_type = "t3.large", disco_gb = 60, subnet = "publica-2" }
  }
}

variable "puerto_app" {
  description = "Puerto en el que responde la aplicación (y que expone el NLB)"
  type        = number
  default     = 80
}

variable "reglas_ingreso_servidores" {
  description = "Reglas de entrada del security group de los servidores (se recorren con un bloque dynamic)"
  type = list(object({
    puerto      = number
    descripcion = string
    cidr        = string
  }))
  default = [
    { puerto = 80, descripcion = "HTTP desde internet / NLB", cidr = "0.0.0.0/0" },
    { puerto = 22, descripcion = "SSH para administracion", cidr = "0.0.0.0/0" },
  ]
}

variable "key_name" {
  description = "Par de llaves SSH. En AWS Academy ya existe una llamada vockey"
  type        = string
  default     = "vockey"
}

variable "instance_profile" {
  description = "Perfil IAM para las EC2. En AWS Academy se llama LabInstanceProfile (permite usar S3). Use null si da error"
  type        = string
  default     = "LabInstanceProfile"
}

# ---------- Base de datos ----------
variable "db_instance_class" {
  description = "Tamaño de la instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos inicial"
  type        = string
  default     = "biblioteca"
}

variable "db_username" {
  description = "Usuario administrador de la RDS"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Contraseña de la RDS. SIN valor por defecto: se entrega por variable de entorno TF_VAR_db_password"
  type        = string
  sensitive   = true # Terraform la oculta en plan, apply y outputs

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "La contraseña de MySQL debe tener al menos 8 caracteres."
  }
}
