# ============================================================
# outputs.tf  ·  Lo que Terraform muestra al terminar el apply
# ============================================================

output "nlb_dns" {
  description = "DNS del Network Load Balancer: pegar en el navegador con http://"
  value       = aws_lb.nlb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint de la RDS MySQL (solo accesible desde los servidores)"
  value       = aws_db_instance.bd.endpoint
}

output "bucket_name" {
  description = "Nombre del bucket S3"
  value       = aws_s3_bucket.material.bucket
}

# ---- Extras útiles para validar ----
output "ips_publicas_servidores" {
  description = "IP pública de cada servidor (para conectarse por SSH)"
  value       = { for nombre, srv in aws_instance.servidor : nombre => srv.public_ip }
}

output "disco_por_servidor_gb" {
  description = "Tamaño real del disco (cambia según el ambiente)"
  value       = { for nombre, srv in aws_instance.servidor : nombre => srv.root_block_device[0].volume_size }
}

output "resumen" {
  description = "Resumen rápido del despliegue"
  value = format(
    "Ambiente=%s | Servidores=%d (%s) | RDS Multi-AZ=%t",
    var.ambiente,
    length(var.servidores),
    join(", ", keys(var.servidores)),
    aws_db_instance.bd.multi_az
  )
}
