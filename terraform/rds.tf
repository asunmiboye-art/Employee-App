# Subnet group - places RDS in the same private subnets as EKS nodes
resource "aws_db_subnet_group" "main" {
  name       = "landmark-db-subnet-${var.environment}"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name        = "landmark-db-subnet-${var.environment}"
    Environment = var.environment
  }
}

# Security group for RDS - allows PostgreSQL from EKS cluster and node SGs
resource "aws_security_group" "rds" {
  name        = "landmark-rds-sg-${var.environment}"
  description = "Allow PostgreSQL from EKS cluster"
  vpc_id      = module.vpc.vpc_id

  # Allow from EKS node security group
  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  # Allow from EKS cluster security group
  ingress {
    description     = "PostgreSQL from EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.cluster_security_group_id]
  }

  # Allow from VPC CIDR (covers all pods via VPC CNI)
  ingress {
    description = "PostgreSQL from VPC CIDR"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "landmark-rds-sg-${var.environment}"
    Environment = var.environment
  }
}

# RDS PostgreSQL instance
resource "aws_db_instance" "main" {
  identifier     = "landmark-db-${var.environment}"
  engine         = "postgres"
  engine_version = "15.7"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                  = var.environment == "prod" ? true : false
  publicly_accessible       = false
  skip_final_snapshot       = var.environment == "prod" ? false : true
  final_snapshot_identifier = var.environment == "prod" ? "landmark-db-final-${var.environment}" : null

  backup_retention_period = var.environment == "prod" ? 7 : 1

  tags = {
    Name        = "landmark-db-${var.environment}"
    Environment = var.environment
  }
}
