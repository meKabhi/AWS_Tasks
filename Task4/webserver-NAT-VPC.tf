provider "aws" {
  region= "us-east-1"
  profile= "default"
}

resource "aws_vpc" "vpc4" {
  cidr_block       = "192.168.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "vpc4"
  }
}

resource "aws_subnet" "subnet-public" {
  vpc_id     = "${aws_vpc.vpc4.id}"
  cidr_block = "192.168.0.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-public"
  }
}

resource "aws_subnet" "subnet-private" {
  vpc_id     = "${aws_vpc.vpc4.id}"
  cidr_block = "192.168.1.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "subnet-private"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc4.id}"

  tags = {
    Name = "igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc4.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags = {
    Name = "public"
  }

  depends_on = [
      aws_internet_gateway.igw
  ]
}

resource "aws_route_table_association" "subnet_public" {
  subnet_id      = aws_subnet.subnet-public.id
  route_table_id = aws_route_table.public.id
  depends_on = [
      aws_route_table.public
  ]
}

resource "aws_eip" "for_nat" {
}



resource "aws_nat_gateway" "gw" {
  allocation_id = "${aws_eip.for_nat.id}"
  subnet_id     = "${aws_subnet.subnet-public.id}"

  tags = {
    Name = "gw NAT"
  }
  depends_on = [
      aws_internet_gateway.igw,
      aws_eip.for_nat
      ]
}

resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.vpc4.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.gw.id}"
  }

  tags = {
    Name = "private"
  }

  depends_on = [
      aws_nat_gateway.gw
  ]
}

resource "aws_route_table_association" "subnet_private" {
  subnet_id      = aws_subnet.subnet-private.id
  route_table_id = aws_route_table.private.id
  depends_on = [
      aws_route_table.private
  ]
}

/* Creation of security group for wordpress*/
resource "aws_security_group" "wordpressSG" {
  name        = "wordpressSG"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = "${aws_vpc.vpc4.id}"

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

  tags ={
    Name = "wordpressSG"
  }
}

resource "aws_security_group" "bastionSG" {
  name        = "bastionSG"
  description = "Allow SSH inbound traffic"
  vpc_id      = "${aws_vpc.vpc4.id}"

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

  tags ={
    Name = "bastionSG"
  }
}

resource "aws_security_group" "mysqlSG" {
  name        = "mysqlSG"
  description = "Allow wordpress and bastion inbound traffic"
  vpc_id      = "${aws_vpc.vpc4.id}"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = ["${aws_security_group.bastionSG.id}" ]
  }
  ingress {
    description = "MYSQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = ["${aws_security_group.wordpressSG.id}" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags ={
    Name = "mysqlSG"
  }

  depends_on = [
      aws_security_group.wordpressSG,
      aws_security_group.bastionSG
  ]
}

resource "aws_instance" "mysqlOS" {
  ami           = "ami-0e9089763828757e1"
  instance_type = "t2.micro"
  security_groups= ["${aws_security_group.mysqlSG.id}"]
  key_name = "openstack-key"
  subnet_id = aws_subnet.subnet-private.id
  tags = {
    Name = "mysqlOS"
  }


  depends_on= [
    aws_security_group.mysqlSG    
  ]
}

resource "aws_instance" "bastionOS" {
  ami           = "ami-0e9089763828757e1"
  instance_type = "t2.micro"
  security_groups= ["${aws_security_group.bastionSG.id}"]
  key_name = "openstack-key"
  subnet_id = aws_subnet.subnet-public.id
  tags = {
    Name = "bastionOS"
  }

  depends_on= [
    aws_security_group.bastionSG    
  ]
}

/* Instance Creation */
resource "aws_instance" "wordpressOS" {
  ami           = "ami-08f3d892de259504d"
  instance_type = "t2.micro"
  security_groups= ["${aws_security_group.wordpressSG.id}"]
  key_name = "openstack-key"
  subnet_id = aws_subnet.subnet-public.id
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

  depends_on= [
    aws_security_group.wordpressSG,
    aws_instance.mysqlOS
    ]
}

resource "null_resource" "key-transfering" {
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i /home/abhishek/openstack-key.pem /home/abhishek/openstack-key.pem ec2-user@${aws_instance.bastionOS.public_ip}:/home/ec2-user/"
  }
  depends_on = [
    aws_instance.bastionOS,
    aws_vpc.vpc4,
  ]
}