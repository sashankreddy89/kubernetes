#!/bin/bash
set -e

REGION="ap-south-1"
VPC_ID="vpc-0d7a6a31be7babf08"

echo "Creating public subnet in ap-south-1a"
PUB_1A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.0.0/24 --availability-zone ap-south-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=chatapp-pub-1a},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/chatapp-cluster,Value=owned}]' \
  --query "Subnet.SubnetId" --output text)

echo "Creating public subnet in ap-south-1b"
PUB_1B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ap-south-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=chatapp-pub-1b},{Key=kubernetes.io/role/elb,Value=1},{Key=kubernetes.io/cluster/chatapp-cluster,Value=owned}]' \
  --query "Subnet.SubnetId" --output text)

echo "Creating private subnet in ap-south-1a"
PVT_1A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ap-south-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=chatapp-pvt-1a},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/chatapp-cluster,Value=owned}]' \
  --query "Subnet.SubnetId" --output text)

echo "Creating private subnet in ap-south-1b"
PVT_1B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone ap-south-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=chatapp-pvt-1b},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/chatapp-cluster,Value=owned}]' \
  --query "Subnet.SubnetId" --output text)

echo "Enabling public IP on launch for public subnets"
aws ec2 modify-subnet-attribute --subnet-id $PUB_1A --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $PUB_1B --map-public-ip-on-launch

echo "Creating Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=chatapp-igw}]' \
  --query "InternetGateway.InternetGatewayId" --output text)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

echo "Allocating Elastic IP"
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

echo "Creating NAT Gateway in public subnet 1a"
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id $PUB_1A --allocation-id $EIP_ALLOC_ID \
  --query "NatGateway.NatGatewayId" --output text)

echo "Waiting for NAT to become available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

echo "Creating public route table"
PUB_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=chatapp-pub-rt}]' \
  --query "RouteTable.RouteTableId" --output text)

aws ec2 create-route --route-table-id $PUB_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUB_RT_ID --subnet-id $PUB_1A
aws ec2 associate-route-table --route-table-id $PUB_RT_ID --subnet-id $PUB_1B

echo "Creating private route table"
PVT_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=chatapp-pvt-rt}]' \
  --query "RouteTable.RouteTableId" --output text)

aws ec2 create-route --route-table-id $PVT_RT_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID
aws ec2 associate-route-table --route-table-id $PVT_RT_ID --subnet-id $PVT_1A
aws ec2 associate-route-table --route-table-id $PVT_RT_ID --subnet-id $PVT_1B

echo "✅ VPC networking setup complete"

