/* Initial settings */
provider "aws" {
  region= "us-east-1"
  profile= "default"
}

/* Creation of the key*/
resource "tls_private_key" "key01" {
  algorithm = "RSA"
}

resource "aws_key_pair" "key01" {
  key_name   = "web_OS_key"
  public_key = tls_private_key.key01.public_key_openssh
}

/* Creation of security group */
resource "aws_security_group" "webserver_EBS_SG" {
  name        = "webserver_EBS_SG"
  description = "Allow SSH and HTTP inbound traffic"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags ={
    Name = "webserver_EBS_SG"
  }
}

/* Instance Creation */
resource "aws_instance" "OS1" {
  ami           = "ami-08f3d892de259504d"
  instance_type = "t2.micro"
  security_groups= ["webserver_EBS_SG"]
  key_name = "web_OS_key"
  tags = {
    Name = "webserver_EBS_OS"
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key01.private_key_pem
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum -y install httpd git php",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo systemctl status httpd",
    ]
  }
  depends_on= [
    aws_security_group.webserver_EBS_SG,
    aws_key_pair.key01    
  ]
}


/* To mount the new volume*/
resource "null_resource" "mounting" {
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key01.private_key_pem
    host        = aws_instance.OS1.public_ip
  }

  provisioner "remote-exec" {
     inline = [
       "sudo fdisk -l",
       "sudo mkfs.ext4 /dev/xvdh",
       "sudo mount /dev/xvdh /var/www/html/",
       "sudo rm -rf /var/www/html/*",
       "sudo git clone https://github.com/Abhishekkr3003/html5-practice.git /var/www/html/",
       "sudo systemctl status httpd"
    ]
  }
  depends_on = [
    aws_volume_attachment.ebs_att
  ]
}

/* Size of volume to be created */
variable "Size_of_Volume_to_Create_in_GiB" {
  type = number
  default= 1
}

/* Volume Creation */
resource "aws_ebs_volume" "ebs_1_GiB" {
  availability_zone = aws_instance.OS1.availability_zone
  size              = var.Size_of_Volume_to_Create_in_GiB

  tags ={
    Name = "Vol_1GiB"
  }
}


/* Volume attachment */
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_1_GiB.id
  instance_id = aws_instance.OS1.id
  depends_on = [
    aws_ebs_volume.ebs_1_GiB
  ]
  force_detach = true
}

/* Bucket Creation */
resource "aws_s3_bucket" "bucket_for_image" {
  bucket = "abhishek.bucket.002"
  acl    = "public-read"

  tags ={
    Name = "bucket_terra"
  }
  provisioner "local-exec" {
     command = "aws s3 cp /home/abhishek/terraform/web-server/html5-practice/IMG_20200314_191513.jpg  s3://${aws_s3_bucket.bucket_for_image.bucket}/image2.jpg --acl public-read"
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

/*Launching web-app locally*/
resource "null_resource" "show_website"{
  provisioner "local-exec" {
    command= "firefox ${aws_instance.OS1.public_ip}"
  }
  depends_on =[
    null_resource.appned_link
  ]
}

/* Adding Cloud front link to the web-app */
resource "null_resource" "appned_link" {
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key01.private_key_pem
    host        = aws_instance.OS1.public_ip
  }

  provisioner "remote-exec" {
     inline = [
       "sudo sed -i 's+https://s3.ap-south-1.amazonaws.com/abhishek.bucket.002/image2.jpg+https://${aws_cloudfront_distribution.for_s3_image.domain_name}/image2.jpg+' /var/www/html/index.html"
    ]
  }
  depends_on = [
    aws_cloudfront_distribution.for_s3_image
  ]
}

/* Snapshot of the volume*/
/* resource "aws_ebs_snapshot" "Webserver_snapshot" {
  volume_id = "${aws_ebs_volume.ebs_1_GiB.id}"

  tags = {
    Name = "WebServer"
  }
  depends_on =[
    null_resource.appned_link,
    aws_instance.OS1
  ]
} */

/* Needed while destroying */
resource "null_resource" "while_destroy" {
  provisioner "local-exec" {
    when = destroy
     command = "rm -rf /home/abhishek/terraform/web-server/html5-practice"
  }
  provisioner "local-exec" {
    when = destroy
     command = "aws s3 rm s3://${aws_s3_bucket.bucket_for_image.bucket} --recursive"
  }
  
}

output "Cloud_front" {
  value = "https://${aws_cloudfront_distribution.for_s3_image.domain_name}/image2.jpg"
}

output "instance_ip" {
  value = aws_instance.OS1.public_ip
}

output "Bucket_name" {
  value = "${aws_s3_bucket.bucket_for_image.bucket}"
}


