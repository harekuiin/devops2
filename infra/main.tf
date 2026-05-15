# ============================================================
# PROVEEDOR AWS
# ============================================================
provider "aws" {
  region = "us-east-1"
}


# ============================================================
# VPC Y SUBNETS
# Una VPC es nuestra red privada virtual en AWS.
# Dentro tenemos subnets: una pública (Front) y dos privadas (Back y Data).
# ============================================================
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "spa-vpc"
  }
}

# Subnet pública: aquí vive el Front (tiene acceso a Internet)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "spa-subnet-publica"
  }
}

# Subnet privada 1: aquí vive el Back
resource "aws_subnet" "private_subnet_back" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "spa-subnet-privada-back"
  }
}

# Subnet privada 2: aquí vive el Data
resource "aws_subnet" "private_subnet_data" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "spa-subnet-privada-data"
  }
}


# ============================================================
# INTERNET GATEWAY Y RUTAS
# El Internet Gateway permite que la subnet pública salga a Internet.
# ============================================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "spa-igw"
  }
}

# Tabla de rutas para la subnet pública: el tráfico sale por el IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "spa-rt-publica"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "nat" {
  tags = {
    Name = "spa-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "spa-nat-gateway"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "spa-rt-privada"
  }
}

resource "aws_route_table_association" "private_back_assoc" {
  subnet_id      = aws_subnet.private_subnet_back.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_data_assoc" {
  subnet_id      = aws_subnet.private_subnet_data.id
  route_table_id = aws_route_table.private_rt.id
}


# ============================================================
# SECURITY GROUPS
# Son como "reglas de firewall" que controlan qué tráfico
# puede entrar o salir de cada instancia.
# ============================================================

# --- Security Group del FRONT ---
# Permite: HTTP (80) y SSH (22) desde cualquier IP pública
resource "aws_security_group" "sg_front" {
  name        = "spa-sg-front"
  description = "Acceso publico al servidor web"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH desde Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Todo el trafico saliente permitido"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-front"
  }
}

# --- Security Group del BACK ---
# Solo acepta tráfico del Front (en puerto 8080 para el microservicio y 22 para SSH)
resource "aws_security_group" "sg_back" {
  name        = "spa-sg-back"
  description = "Acceso solo desde el Front"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "Microservicio desde Front"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_front.id]
  }

  ingress {
    description     = "SSH desde Front (para administracion)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_front.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-back"
  }
}

# --- Security Group del DATA ---
# Solo acepta tráfico del Back (puerto 3306 para MySQL)
resource "aws_security_group" "sg_data" {
  name        = "spa-sg-data"
  description = "Acceso solo desde el Back"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "MySQL desde Back"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_back.id]
  }

  ingress {
    description     = "SSH desde Back (para administracion)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_back.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-data"
  }
}


# ============================================================
# INSTANCIA FRONT (pública)
# - Nginx como servidor web
# - Docker instalado
# - Git instalado
# - Actualizaciones de seguridad aplicadas
# ============================================================
resource "aws_instance" "front" {
  ami                    = "ami-0c02fb55956c7d316" # Amazon Linux 2
  instance_type          = "t2.micro"
  key_name               = "spa-key"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.sg_front.id]

  user_data = <<-EOF
              #!/bin/bash

              # --- Actualizaciones de seguridad ---
              yum update -y --security
              yum update -y

              # --- Servidor web (Nginx) ---
              amazon-linux-extras install nginx1 -y
              systemctl start nginx
              systemctl enable nginx

              # --- Docker ---
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user

              # --- Git ---
              yum install git -y

              # --- Verificacion (los resultados quedan en el log de user_data) ---
              echo "=== VERSION DOCKER ===" >> /var/log/instalaciones.log
              docker --version        >> /var/log/instalaciones.log
              echo "=== VERSION GIT ===" >> /var/log/instalaciones.log
              git --version           >> /var/log/instalaciones.log
              echo "=== ESTADO NGINX ===" >> /var/log/instalaciones.log
              systemctl status nginx  >> /var/log/instalaciones.log
              EOF

  tags = {
    Name = "spa-front"
    Capa = "Front"
  }
}


# ============================================================
# INSTANCIA BACK (privada)
# - Docker instalado
# - JDK (Java) instalado para el microservicio
# - Git instalado
# - Actualizaciones de seguridad aplicadas
# ============================================================
resource "aws_instance" "back" {
  ami                    = "ami-0c02fb55956c7d316" # Amazon Linux 2
  instance_type          = "t2.micro"
  key_name               = "spa-key"
  subnet_id              = aws_subnet.private_subnet_back.id
  vpc_security_group_ids = [aws_security_group.sg_back.id]

  user_data = <<-EOF
              #!/bin/bash

              # --- Actualizaciones de seguridad ---
              yum update -y --security
              yum update -y

              # --- Docker ---
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user

              # --- JDK 11 (Java Development Kit para microservicio) ---
              amazon-linux-extras install java-openjdk11 -y

              # --- Git ---
              yum install git -y

              # --- Verificacion ---
              echo "=== VERSION DOCKER ===" >> /var/log/instalaciones.log
              docker --version        >> /var/log/instalaciones.log
              echo "=== VERSION JAVA ===" >> /var/log/instalaciones.log
              java -version           >> /var/log/instalaciones.log 2>&1
              echo "=== VERSION GIT ===" >> /var/log/instalaciones.log
              git --version           >> /var/log/instalaciones.log
              EOF

  tags = {
    Name = "spa-back"
    Capa = "Back"
  }
}


# ============================================================
# INSTANCIA DATA (privada)
# - MySQL instalado (solo instalado, no configurado aún)
# - Git instalado
# - Actualizaciones de seguridad aplicadas
# ============================================================
resource "aws_instance" "data" {
  ami                    = "ami-0c02fb55956c7d316" # Amazon Linux 2
  instance_type          = "t2.micro"
  key_name               = "spa-key"
  subnet_id              = aws_subnet.private_subnet_data.id
  vpc_security_group_ids = [aws_security_group.sg_data.id]

  user_data = <<-EOF
              #!/bin/bash

              # --- Actualizaciones de seguridad ---
              yum update -y --security
              yum update -y

              # --- MySQL (motor de base de datos) ---
              # Se instala el servidor MySQL y se inicia el servicio
              yum install mysql-server -y
              systemctl enable mysqld
              systemctl start mysqld

              # --- Git ---
              yum install git -y

              # --- Verificacion ---
              echo "=== VERSION MYSQL ===" >> /var/log/instalaciones.log
              mysql --version         >> /var/log/instalaciones.log
              echo "=== VERSION GIT ===" >> /var/log/instalaciones.log
              git --version           >> /var/log/instalaciones.log
              EOF

  tags = {
    Name = "spa-data"
    Capa = "Data"
  }
}


# ============================================================
# LAUNCH TEMPLATES
# Un Launch Template es una "plantilla de lanzamiento": guarda
# toda la configuración de una instancia para que puedas
# recrearla rápidamente o usarla con Auto Scaling Groups.
# ============================================================

resource "aws_launch_template" "lt_front" {
  name_prefix   = "lt-front-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"
  key_name      = "spa-key"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.sg_front.id]
    subnet_id                   = aws_subnet.public_subnet.id
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y --security
    yum update -y
    amazon-linux-extras install nginx1 docker -y
    yum install git -y
    systemctl start nginx docker
    systemctl enable nginx docker
    usermod -aG docker ec2-user
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "spa-front-lt"
      Capa = "Front"
    }
  }
}

resource "aws_launch_template" "lt_back" {
  name_prefix   = "lt-back-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"
  key_name      = "spa-key"

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sg_back.id]
    subnet_id                   = aws_subnet.private_subnet_back.id
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y --security
    yum update -y
    amazon-linux-extras install docker java-openjdk11 -y
    yum install git -y
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "spa-back-lt"
      Capa = "Back"
    }
  }
}

resource "aws_launch_template" "lt_data" {
  name_prefix   = "lt-data-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"
  key_name      = "spa-key"

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sg_data.id]
    subnet_id                   = aws_subnet.private_subnet_data.id
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y --security
    yum update -y
    yum install mysql-server git -y
    systemctl enable mysqld
    systemctl start mysqld
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "spa-data-lt"
      Capa = "Data"
    }
  }
}


# ============================================================
# OUTPUTS
# Muestran información útil al terminar el "terraform apply"
# ============================================================
output "front_ip_publica" {
  description = "IP publica del servidor Front (acceso desde Internet)"
  value       = aws_instance.front.public_ip
}

output "back_ip_privada" {
  description = "IP privada del Back (solo accesible desde el Front)"
  value       = aws_instance.back.private_ip
}

output "data_ip_privada" {
  description = "IP privada del Data (solo accesible desde el Back)"
  value       = aws_instance.data.private_ip
}
