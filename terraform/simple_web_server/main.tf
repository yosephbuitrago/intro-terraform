resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.basename}-${var.name}"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.basename}-${var.name}"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "policies" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_security_group" "ec2" {
  name        = "${var.basename}-${var.name}-sg"
  vpc_id      = var.network_info.vpc_id
}

resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2.id
}

data "aws_ami" "ami" {
  filter {
    name   = "name"
    values = ["*ubuntu-focal-20.04-amd64-server*"]
  }

  most_recent = true
  owners      = ["099720109477"] # Canonical
}

resource "aws_instance" "ec2" {
  ami                         = data.aws_ami.ami.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.id
  subnet_id                   = var.network_info.subnets.red.ids[0]
  security_groups             = [aws_security_group.ec2.id]

  tags = {
    Name = "intro-terraform"
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  user_data = <<EOF
#!/bin/bash
ID=$(ec2metadata | grep instance-id);
echo "Hello, Rapidratings from: $ID" > index.html
nohup busybox httpd -f -p 8080 &
EOF
}