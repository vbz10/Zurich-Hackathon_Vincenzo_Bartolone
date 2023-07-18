resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/24"
}

resource "aws_subnet" "app_subnet" {
  vpc_id     = aws_vpc.app_vpc.id
  cidr_block = "10.0.0.0/28"
}

resource "aws_security_group" "app_sg" {
  name        = "app_sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "tcp access port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "tcp access port 1337"
    from_port   = 1337
    to_port     = 1337
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "tcp access port 3035"
    from_port   = 3035
    to_port     = 3035
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "udp access port 3035"
    from_port   = 3035
    to_port     = 3035
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "Instance_1_key" {
  key_name   = "Instance_1_key"
  public_key = var.public_key_1
}

resource "aws_instance" "Instance_1" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  key_name        = aws_key_pair.Instance_1_key.key_name
  security_groups = [aws_security_group.app_sg.id]
  subnet_id = aws_subnet.app_subnet.id

  depends_on = [
    aws_vpc.app_vpc,
    aws_subnet.app_subnet
  ]

  tags = {
    Name = "Instance_1"
  }
}

resource "aws_key_pair" "Instance_2_key" {
  key_name   = "Instance_2_key"
  public_key = var.public_key_2
}

resource "aws_instance" "Instance_2" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  key_name        = aws_key_pair.Instance_2_key.key_name
  security_groups = [aws_security_group.app_sg.id]
  subnet_id = aws_subnet.app_subnet.id

  depends_on = [
    aws_vpc.app_vpc,
    aws_subnet.app_subnet
  ]

  tags = {
    Name = "Instance_2"
  }
}

resource "aws_elb" "app_load_balancer" {
  name               = "app_load_balancer"
  subnets            = [aws_subnet.app_subnet.id]
  security_groups    = [aws_security_group.app_sg.id]
  instances          = [aws_instance.Instance_1.id, aws_instance.Instance_2.id]
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  listener {
    instance_port     = 443
    instance_protocol = "TCP"
    lb_port           = 443
    lb_protocol       = "TCP"
  }
}

output "load_balancer_dns" {
  value = aws_lb.app_load_balancer.dns_name
}

resource "aws_autoscaling_group" "grupo_autoescalado" {
  name                 = "grupo_autoescalado"
  min_size             = 2
  max_size             = 4
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.app_subnet.id]
  launch_configuration = aws_launch_configuration.lanzamiento.name
}

resource "aws_launch_configuration" "lanzamiento" {
  name                 = "lanzamiento"
  image_id             = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"  # Reemplaza con la AMI deseada
  instance_type        = "t2.micro"      # Reemplaza con el tipo de instancia deseado
  security_groups      = [aws_security_group.app_sg.id]
  key_name             = aws_key_pair.Instance_1_key.key_name # Reemplaza con el nombre de tu clave SSH
}

resource "aws_autoscaling_policy" "politica_autoescalado" {
  name                   = "politica_autoescalado"
  autoscaling_group_name = aws_autoscaling_group.grupo_autoescalado.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
}

resource "aws_cloudwatch_metric_alarm" "alarma_escalado" {
  alarm_name          = "alarma_escalado"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Escalar si la utilización de CPU es mayor al 80% duerante 3 periodos consecutivos"
  alarm_actions       = [aws_autoscaling_policy.politica_autoescalado.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.auto_scaling_group.name
  }
}