
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
#   cidr_blocks       = ["0.0.0.0/0"]
  source_security_group_id = aws_security_group.alb.id
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


resource "aws_security_group" "alb" {
  name = "${var.basename}-${var.name}-alb-sg"
  vpc_id      = var.network_info.vpc_id
  # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb" {
  name               = "${var.basename}-${var.name}"
  load_balancer_type = "application"
  subnets            = var.network_info.subnets.red.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_lb_target_group" "asg" {
  name     = "${var.stripped_basename}${var.name}tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.network_info.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_launch_configuration" "lc" {
  image_id        = data.aws_ami.ami.id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.ec2.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.id

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, Rapidratings from:" > index.html && $(ec2metadata | grep instance-id) >> index.html
              nohup busybox httpd -f -p 8080 &
              EOF

  # Required when using a launch configuration with an auto scaling group.
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.lc.name
  vpc_zone_identifier  = var.network_info.subnets.amber.ids
  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"
  desired_capacity = 2
  min_size = 2
  max_size = 2

  tag {
    key                 = "Name"
    value               = "${var.basename}-${var.name}-asg"
    propagate_at_launch = true
  }
}