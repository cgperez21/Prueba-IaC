# ============================================================
# terraform.tfvars  ·  Valores concretos de las variables
# ============================================================
# Terraform carga este archivo AUTOMÁTICAMENTE.
# Para pasar a producción solo se cambia la línea de "ambiente".
#
# La contraseña NO va aquí. Se entrega así (PowerShell):
#   $env:TF_VAR_db_password = "MiClaveSegura123"

proyecto    = "eduandes"
aplicacion  = "biblioteca"
responsable = "alumno-duoc" # <- cambie por su nombre
ambiente    = "dev"         # <- "dev" o "prod"
region      = "us-east-1"

# Para agregar un 4to servidor, descomente y listo:
# servidores = {
#   "biblioteca-a" = { instance_type = "t3.medium", disco_gb = 30, subnet = "publica-1" }
#   "biblioteca-b" = { instance_type = "t3.medium", disco_gb = 30, subnet = "publica-1" }
#   "biblioteca-c" = { instance_type = "t3.large",  disco_gb = 60, subnet = "publica-2" }
#   "biblioteca-d" = { instance_type = "t3.medium", disco_gb = 30, subnet = "publica-2" }
# }
