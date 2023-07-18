resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "eks_subnet" {
  vpc_id                  = aws_vpc.net.id
  cidr_block              = "10.0.0.0/25"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "internet_gw" {
  vpc_id     = aws_vpc.eks_vpc.id
  depends_on = [aws_vpc.eks_vpc]
}

resource "aws_route_table" "route_tab_int" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gw.id
  }
}

resource "aws_route_table_association" "internet_access" {
  subnet_id      = aws_subnet.eks_subnet.id
  route_table_id = aws_route_table.route_tab_int.id
}

resource "aws_eip" "vpc_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.vpc_eip.id
  subnet_id     = aws_subnet.eks_subnet.id
  depends_on    = [aws_internet_gateway.internet_gw]
}

resource "aws_iam_role" "eks_role" {
  name = "eks-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_instance_profile" "nodes_profile" {
  name = "profile_nodes"
  role = aws_iam_role.eks_role.name
}

resource "aws_iam_role" "workernodes" {
  name = "workers-eks-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly-EKS" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.workernodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.workernodes.name
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.workernodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.workernodes.name
}

resource "aws_iam_role_policy_attachment" "EC2InstanceProfileForImageBuilderECRContainerBuilds" {
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
  role       = aws_iam_role.workernodes.name
}


resource "aws_s3_bucket" "bucket_App" {
  bucket = "bucket_App"
}

resource "aws_s3_bucket_acl" "bucket_App_acl" {
  bucket = aws_s3_bucket.bucket_App.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket_App_config" {
  bucket = aws_s3_bucket.bucket_App.id

  rule {
    id = "expiration"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_eks_cluster" "cluster_App" {
  name     = "cluster_App"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks_subnet.id]
  }

  depends_on = [
    aws_iam_role.eks_role,
  ]
}

resource "aws_eks_node_group" "worker_node_group" {
  cluster_name    = aws_eks_cluster.cluster_App.name
  node_group_name = "node_group"
  node_role_arn   = aws_iam_role.workernodes.arn
  subnet_ids      = [aws_subnet.eks_subnet.id]
  instance_types  = ["t2.medium"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  depends_on = [
    aws_iam_role.workernodes,
  ]
}

output "endpoint" {
  value = aws_eks_cluster.cluster_App.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.cluster_App.certificate_authority[0].data
}

data "aws_eks_cluster_auth" "cluster_App_token" {
  name = aws_eks_cluster.cluster_App.id
}

provider "kubernetes" {
  host                   = aws_eks_cluster.cluster_App.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.cluster_App.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster_App_token.token
}

resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = "app-namespace"
  }
}

resource "kubernetes_deployment" "app_deployment" {
  metadata {
    name      = "app-deployment"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "app"
      }
    }

    template {
      metadata {
        labels = {
          app = "app"
        }
      }

      spec {
        container {
          name  = "app-Images"
          image = aws_ecr_repository.app_repository.repository_url
        }
      }
    }
  }
}

resource "kubernetes_service" "app_service" {
  metadata {
    name      = "app-service"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }

  spec {
    selector = {
      app = "app"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "app_autoscaler" {
  metadata {
    name      = "app-autoscaler"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.app_deployment.metadata[0].name
    }

    min_replicas = 1
    max_replicas = 5

    metric {
      type = "Resource"

      resource {
        name               = "cpu"
        target_average_utilization = 80
      }
    }
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

resource "aws_launch_configuration" "eks_launch" {
  name_prefix     = "eks-launch"
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t2.medium"
  security_groups = [aws_security_group.eks_security_group.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "eks_autoscaling_group" {
  name                 = "eks-autoscaling-group"
  min_size             = 1
  max_size             = 2
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.eks_launch.name
  vpc_zone_identifier  = [aws_subnet.eks_subnet.id]

  lifecycle {
    create_before_destroy = true
  }
}