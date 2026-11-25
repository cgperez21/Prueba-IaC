#!/bin/bash
# Plantilla renderizada con templatefile(). Las variables ${hostname} y ${ambiente}
# las inyecta Terraform antes de enviar el script a la instancia.
dnf install -y httpd mariadb105
systemctl enable --now httpd
cat > /var/www/html/index.html <<HTML
<h1>Biblioteca Digital EduAndes</h1>
<p>Servidor: ${hostname}</p>
<p>Ambiente: ${ambiente}</p>
HTML
