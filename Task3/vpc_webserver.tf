provider "aws" {
  region  = "us-east-1"
  profile = "default"
}

resource "aws_vpc" "wordpress_mysql_VPC" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "wordpress_mysql_VPC"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = "${aws_vpc.wordpress_mysql_VPC.id}"
  cidr_block              = "192.168.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-a"
  }
  depends_on = [
    aws_vpc.wordpress_mysql_VPC
  ]
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = "${aws_vpc.wordpress_mysql_VPC.id}"
  cidr_block        = "192.168.1.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "subnet-b"
  }

  depends_on = [
    aws_vpc.wordpress_mysql_VPC
  ]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.wordpress_mysql_VPC.id}"

  tags = {
    Name = "igw"
  }
  depends_on = [
    aws_vpc.wordpress_mysql_VPC
  ]
}

resource "aws_route_table" "for_subnet_a" {
  vpc_id = "${aws_vpc.wordpress_mysql_VPC.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags = {
    Name = "route1"
  }
  depends_on = [
    aws_internet_gateway.igw,
    aws_vpc.wordpress_mysql_VPC
  ]
}

/* Creation of security group for mysqlOS*/
resource "aws_route_table_association" "to_subnet_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.for_subnet_a.id
  depends_on = [
    aws_route_table.for_subnet_a,
    aws_vpc.wordpress_mysql_VPC
  ]
}

resource "aws_security_group" "mysqlSG" {
  name        = "mysqlSG"
  description = "Allow wordpress inbound traffic"
  vpc_id      = "${aws_vpc.wordpress_mysql_VPC.id}"

  ingress {
    description     = "MYSQL"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.SG1.id}"]
  }

  ingress {
    description     = "SSH"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.SG1.id}"]
  }

  tags = {
    Name = "mysqlSG"
  }

  depends_on = [
    aws_security_group.SG1,
    aws_vpc.wordpress_mysql_VPC,
  ]
}

/* Creation of security group for wordpressOS*/
resource "aws_security_group" "SG1" {
  name        = "SG1"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = "${aws_vpc.wordpress_mysql_VPC.id}"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG1"
  }
}

resource "aws_instance" "mysqlOS" {
  ami             = "ami-0e113431ab80e4b75"
  instance_type   = "t2.micro"
  security_groups = ["${aws_security_group.mysqlSG.id}"]
  key_name        = "openstack-key"
  subnet_id       = aws_subnet.subnet_b.id
  tags = {
    Name = "mysqlOS"
  }

  depends_on = [
    aws_security_group.mysqlSG,
    aws_vpc.wordpress_mysql_VPC,
  ]
}

/* Instance Creation */
resource "aws_instance" "wordpressOS" {
  ami             = "ami-08f3d892de259504d"
  instance_type   = "t2.micro"
  security_groups = ["${aws_security_group.SG1.id}"]
  key_name        = "openstack-key"
  subnet_id       = aws_subnet.subnet_a.id
  tags = {
    Name = "wordpressOS"
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/home/abhishek/openstack-key.pem")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum -y install httpd php php-mysql",
      "cd /var/www/html",
      "sudo wget https://wordpress.org/wordpress-5.1.1.tar.gz",
      "sudo tar -xzf wordpress-5.1.1.tar.gz",
      "sudo cp wordpress/wp-config-sample.php wordpress/wp-config.php",
      "sudo sed -i 's+database_name_here+wordpress-db+' /var/www/html/wordpress/wp-config.php",
      "sudo sed -i 's+username_here+wordpress-user+' /var/www/html/wordpress/wp-config.php",
      "sudo sed -i 's+password_here+password+' /var/www/html/wordpress/wp-config.php",
      "sudo sed -i 's+localhost+${aws_instance.mysqlOS.private_ip}+' /var/www/html/wordpress/wp-config.php",
      "sudo cp -r wordpress/* /var/www/html/",
      "sudo mkdir /var/www/html/blog",
      "sudo cp -r wordpress/* /var/www/html/blog/",
      "sudo yum install -y php-gd",
      "sudo chown -R apache /var/www",
      "sudo chgrp -R apache /var/www",
      "sudo chmod 2775 /var/www",
      "sudo find /var/www -type d -exec sudo chmod 2775 {} \\; ",
      "sudo find /var/www -type f -exec sudo chmod 0664 {} \\;  ",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd ",
      "sudo systemctl status httpd"
    ]
  }

  depends_on = [
    aws_security_group.SG1,
    aws_vpc.wordpress_mysql_VPC
  ]
}

resource "null_resource" "key-transfering" {
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i /home/abhishek/openstack-key.pem /home/abhishek/openstack-key.pem ec2-user@${aws_instance.wordpressOS.public_ip}:/home/ec2-user/"
  }
  depends_on = [
    aws_instance.wordpressOS,
    aws_vpc.wordpress_mysql_VPC
  ]
}
