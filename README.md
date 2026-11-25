# 📚 Biblioteca Digital EduAndes — Terraform en AWS

> Proyecto de estudio para el **certamen de Terraform** (DUOC UC).
> Incluye el código de la **Evaluación Formativa 3**, una guía de estudio desde cero y preguntas de práctica.
> Entorno de trabajo: **AWS Academy (Learner Lab) + Visual Studio Code**.

---

## 🧭 Índice

1. [¿Qué hace este proyecto?](#1-qué-hace-este-proyecto)
2. [Arquitectura](#2-arquitectura)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [Requisitos previos](#4-requisitos-previos)
5. [Inicio rápido (10 comandos)](#5-inicio-rápido)
6. [Qué cambia entre `dev` y `prod`](#6-qué-cambia-entre-dev-y-prod)
7. [Checklist de evaluación del profesor](#7-checklist-de-evaluación-del-profesor)
8. [Funciones internas usadas](#8-funciones-internas-usadas-y-qué-hace-cada-una)
9. [Guías de estudio](#9-guías-de-estudio)

---

## 1. ¿Qué hace este proyecto?

EduAndes quiere migrar a AWS su aplicación **Biblioteca Digital** (los alumnos consultan y descargan material de estudio).
Este código de Terraform despliega **toda la infraestructura** con un solo comando (`terraform apply`) y la elimina con otro (`terraform destroy`).

Los requisitos de diseño que pidió el profesor:

| Requisito | Cómo se cumple |
|---|---|
| Script corto, parametrizable y reutilizable | Todo valor variable está en `variables.tf` / `terraform.tfvars` |
| Sin repetir bloques por servidor | `for_each` sobre un mapa de servidores |
| Sin repetir bloques por subred | `for_each` sobre un mapa de subredes |
| Cambiar de ambiente cambiando una variable | `var.ambiente` + operador ternario `? :` |
| Contraseña fuera del código | Variable `sensitive` + variable de entorno `TF_VAR_db_password` |

## 2. Arquitectura

```
                     Internet
                        │
                        ▼
   ┌──────────────────── VPC 10.0.0.0/16 ─────────────────────┐
   │                                                          │
   │        ┌──────────── NLB (listener TCP :80) ────────┐    │
   │        └───────┬──────────────────────────┬─────────┘    │
   │                ▼                          ▼              │
   │   ┌─ Subred pública 1 ──┐    ┌─ Subred pública 2 ──┐     │
   │   │ Biblioteca-A t3.med │    │ Biblioteca-C t3.lrg │     │
   │   │ Biblioteca-B t3.med │    │   (reportes) 60 GB  │     │
   │   └──────────┬──────────┘    └──────────┬──────────┘     │
   │              │  (solo SG de servidores, puerto 3306)      │
   │   ┌─ Subred privada 1 ──┐    ┌─ Subred privada 2 ──┐     │
   │   │  RDS MySQL (princ.) │◄──►│  RDS standby (prod) │     │
   │   └─────────────────────┘    └─────────────────────┘     │
   └──────────────────────────────────────────────────────────┘

        S3 Bucket (versionado solo en prod) ← fuera de la VPC
```

**Los 3 puntos condicionales del diagrama del profesor:**

| # | Recurso | `dev` | `prod` |
|---|---|---|---|
| 1 | Disco de los servidores | disco base | disco × 2 |
| 2 | RDS MySQL | Single-AZ | **Multi-AZ** (standby) |
| 3 | Bucket S3 | sin versionado (`Suspended`) | versionado (`Enabled`) |

## 3. Estructura del repositorio

```
biblioteca-digital-terraform/
├── providers.tf        # Proveedor AWS + versión de Terraform
├── variables.tf        # Declaración de TODAS las variables (tipos, defaults, validaciones)
├── terraform.tfvars    # Valores concretos (aquí se cambia dev ↔ prod)
├── main.tf             # Recursos: VPC, subredes, SG, EC2, NLB, RDS, S3
├── outputs.tf          # DNS del NLB, endpoint RDS, nombre del bucket (+ extras)
├── userdata.tpl        # Plantilla del script de arranque de las EC2 (templatefile)
├── .gitignore          # Evita subir state, .terraform y llaves .pem
└── docs/
    ├── 01-fundamentos.md          # Qué es Terraform y AWS, desde cero
    ├── 02-funciones-builtin.md    # Funciones predefinidas (unidad 3.1.1)
    ├── 03-condicionales.md        # Condicionales (unidad 3.2.1)
    ├── 04-ciclos-y-expresiones.md # count, for_each, for, splat, dynamic
    ├── 05-lifecycle-y-validaciones.md
    ├── 06-guia-paso-a-paso.md     # Cómo hacer la formativa en AWS Academy + VS Code
    └── 07-preguntas-certamen.md   # Preguntas tipo prueba con respuestas
```

## 4. Requisitos previos

- Cuenta de **AWS Academy** con acceso al **Learner Lab**.
- **Visual Studio Code** con la extensión *HashiCorp Terraform*.
- **Terraform** ≥ 1.5 instalado (`terraform -version`).
- **AWS CLI** instalado (`aws --version`).

Instalación detallada en [docs/06-guia-paso-a-paso.md](docs/06-guia-paso-a-paso.md).

## 5. Inicio rápido

```powershell
# 1) Credenciales: copiar desde Learner Lab > AWS Details > AWS CLI: Show
#    y pegarlas en  %USERPROFILE%\.aws\credentials
aws sts get-caller-identity          # comprueba que funcionan

# 2) Contraseña de la base de datos (solo vive en esta ventana de PowerShell)
$env:TF_VAR_db_password = "Biblioteca2026"

# 3) Ciclo de Terraform
terraform init                       # descarga el proveedor AWS
terraform validate                   # revisa sintaxis
terraform plan                       # muestra qué va a crear
terraform apply                      # crea todo (escribir yes). RDS demora ~5-10 min

# 4) Validar
terraform output                     # DNS del NLB, endpoint, bucket...

# 5) Simular producción SIN aplicar
terraform plan -var="ambiente=prod"

# 6) Limpiar (¡no olvidar!)
terraform destroy
```

## 6. Qué cambia entre `dev` y `prod`

Se modifica **una sola línea** en `terraform.tfvars` (`ambiente = "prod"`) o se usa `-var="ambiente=prod"`.

```hcl
# main.tf
locals {
  es_prod = var.ambiente == "prod"        # true / false
}

volume_size = local.es_prod ? each.value.disco_gb * 2 : each.value.disco_gb
multi_az    = local.es_prod
status      = local.es_prod ? "Enabled" : "Suspended"
```

Lectura del ternario: `condición ? valor_si_verdadero : valor_si_falso`.

> ⚠️ Como el nombre de varios recursos incluye el ambiente (`eduandes-biblioteca-dev-...`), un `plan` de `prod`
> sobre un `dev` ya desplegado mostrará muchos recursos como *"must be replaced"*. Es normal: `dev` y `prod`
> son entornos distintos. Lo que debe mirar son las líneas `volume_size`, `multi_az` y `status`.
> Ver detalle en [docs/06-guia-paso-a-paso.md](docs/06-guia-paso-a-paso.md#etapa-3--validación).

## 7. Checklist de evaluación del profesor

| Pregunta de verificación | Dónde se cumple |
|---|---|
| ¿Los 3 servidores se crean con un único bloque? | `resource "aws_instance" "servidor"` con `for_each = var.servidores` |
| ¿Agregar un 4º servidor solo requiere una entrada en el mapa? | Agregar una línea al mapa `servidores` en `terraform.tfvars` |
| ¿No hay valores hardcodeados que deberían ser variables? | Región, CIDRs, tipos, discos, clase RDS, puertos, key pair → todos en `variables.tf` |
| ¿Cambiar `ambiente` modifica el plan sin editar código? | `local.es_prod` controla disco, Multi-AZ y versionado |
| ¿La contraseña no aparece en los `.tf`? | `variable "db_password"` sin default, `sensitive = true`, valor por `TF_VAR_db_password` |
| ¿Puede explicar cada función usada? | Sección siguiente |

## 8. Funciones internas usadas y qué hace cada una

| Función | Dónde se usa | Qué hace |
|---|---|---|
| `format()` | nombre del bucket, prefijo, output `resumen` | Arma un texto usando una plantilla: `format("%s-%s", "a", "b")` → `"a-b"`. `%s` = texto, `%d` = entero, `%t` = booleano |
| `lower()` | nombre del bucket | Pasa a minúsculas (S3 no acepta mayúsculas) |
| `lookup()` | `local.nombre_ambiente` | Busca una clave en un mapa y devuelve un valor por defecto si no existe |
| `merge()` | `tags` de **todos** los recursos | Une mapas; si hay claves repetidas gana el último |
| `keys()` | NLB, subnet group, output | Devuelve la lista de claves de un mapa |
| `length()` | output `resumen`, validación de contraseña | Cuenta elementos de una lista/mapa o caracteres de un texto |
| `join()` | output `resumen` | Une una lista en un texto con un separador |
| `contains()` | validación de `ambiente` | Dice si un valor está dentro de una lista (`true`/`false`) |
| `templatefile()` | `user_data` de las EC2 | Lee un archivo plantilla y reemplaza `${variables}` |

## 9. Guías de estudio

Si **no sabe nada de Terraform**, lea en este orden:

1. [01 · Fundamentos](docs/01-fundamentos.md)
2. [02 · Funciones built-in](docs/02-funciones-builtin.md)
3. [03 · Condicionales](docs/03-condicionales.md)
4. [04 · Ciclos y expresiones](docs/04-ciclos-y-expresiones.md)
5. [05 · Lifecycle y validaciones](docs/05-lifecycle-y-validaciones.md)
6. [06 · Guía paso a paso de la formativa](docs/06-guia-paso-a-paso.md)
7. [07 · Preguntas tipo certamen](docs/07-preguntas-certamen.md)

---

**Licencia:** uso educativo.
