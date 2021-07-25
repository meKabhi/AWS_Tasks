/* Initial settings */
provider "aws" {
  region= "us-east-1"
  profile= "default"
}

/* Creation of security group */
resource "aws_security_group" "webserver_EFS_SG" {
  name        = "webserver_EFS_SG"
  description = "Allow SSH, HTTP, NFS  inbound traffic"
  vpc_id      = "vpc-80c924fd"

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
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
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
    Name = "webserver_EFS_SG"
  }
}

/* Create file system */
resource "aws_efs_file_system" "efs1" {
   creation_token = "efs1"
   performance_mode = "generalPurpose"
   throughput_mode = "bursting"
   tags = {
     Name = "EFS1"
   }
   depends_on=[
       aws_security_group.webserver_EFS_SG
   ]
 }

/* Mount target */
 resource "aws_efs_mount_target" "efs-mount-target2" {
   file_system_id  = "${aws_efs_file_system.efs1.id}"
   subnet_id = "subnet-5d825d7c" 
   security_groups = ["${aws_security_group.webserver_EFS_SG.id}"]
   depends_on=[
       aws_efs_file_system.efs1
   ]
 }

/* Instance Creation */
resource "aws_instance" "OS1" {
  ami           = "ami-08f3d892de259504d"
  instance_type = "t2.micro"
  subnet_id = "subnet-5d825d7c"
  security_groups= ["${aws_security_group.webserver_EFS_SG.id}"]
  key_name = "openstack-key"
  tags = {
    Name = "webserver_EFS_OS"
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/home/abhishek/openstack-key.pem")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum -y install httpd git php",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo systemctl status httpd",
      "sudo yum -y install nfs-utils",
      "sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.efs1.dns_name}:/   /var/www/html  ",
      "df -h"
    ]
  }
  depends_on= [
    aws_security_group.webserver_EFS_SG, 
    aws_efs_mount_target.efs-mount-target2,
  ]
}


/* Cloning repo*/
resource "null_resource" "mounting" {
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/home/abhishek/openstack-key.pem")
    host        = aws_instance.OS1.public_ip
  }

  provisioner "remote-exec" {
     inline = [
       "sudo rm -rf /var/www/html/*",
       "sudo git clone https://github.com/Abhishekkr3003/html5-practice.git /var/www/html/",
       "sudo systemctl status httpd"
    ]
  }
  depends_on = [
    aws_instance.OS1
  ]
}

/* Bucket Creation */
resource "aws_s3_bucket" "bucket_for_image" {
  bucket = "abhishek.bucket.002"
  acl    = "public-read"

  tags ={
    Name = "bucket_terra"
  }
  provisioner "local-exec" {
     command = "aws s3 cp /home/abhishek/terraform/task2/html5-practice/IMG_20200314_191513.jpg  s3://${aws_s3_bucket.bucket_for_image.bucket}/image2.jpg --acl public-read"
  }
  depends_on = [
    null_resource.local_exec
  ]
}

/* Null resouce for local exection to clone repo */
resource "null_resource" "local_exec"{
  provisioner "local-exec" {
    command = "git clone https://github.com/Abhishekkr3003/html5-practice.git"
  }
}

/* CloudFront Creation */
resource "aws_cloudfront_distribution" "for_s3_image" {
    origin {
        domain_name = "${aws_s3_bucket.bucket_for_image.bucket_domain_name}"
        origin_id = "S3-${aws_s3_bucket.bucket_for_image.bucket}"
 
        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "http-only"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
    }

    default_root_object = "index.html"
    enabled = true
    is_ipv6_enabled = true

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-${aws_s3_bucket.bucket_for_image.bucket}"

        # Forward all query strings, cookies and headers
        forwarded_values {
            query_string = true

            cookies {
              forward = "none"
            }
        }

        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    # Distributes content to US and Europe
    price_class = "PriceClass_All"

    # Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }

    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
    depends_on =[
      aws_s3_bucket.bucket_for_image
    ]
}

/* Adding Cloud front link to the web-app */
resource "null_resource" "appned_link" {
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/home/abhishek/openstack-key.pem")
    host        = aws_instance.OS1.public_ip
  }

  provisioner "remote-exec" {
     inline = [
       "sudo sed -i 's+https://s3.ap-south-1.amazonaws.com/abhishek.bucket.002/image2.jpg+https://${aws_cloudfront_distribution.for_s3_image.domain_name}/image2.jpg+' /var/www/html/index.html"
    ]
  }
  depends_on = [
    aws_cloudfront_distribution.for_s3_image,
    aws_instance.OS1
  ]
}

/* Needed while destroying */
resource "null_resource" "while_destroy" {
  provisioner "local-exec" {
    when = destroy
     command = "rm -rf /home/abhishek/terraform/task2/html5-practice"
  }
  provisioner "local-exec" {
    when = destroy
     command = "aws s3 rm s3://${aws_s3_bucket.bucket_for_image.bucket} --recursive"
  }
  
}

/* Instance IP */
output "instance_ip" {
  value = aws_instance.OS1.public_ip
}
