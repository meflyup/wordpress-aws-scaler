#!/bin/bash

function get_config
{
	while read -r a b; do
		if [[ $1 == $a ]]
		then
			regex="^\"(.*)\"$"
			if [[ $b =~ $regex ]]
			then
				echo ${BASH_REMATCH[1]}
			fi
		fi
	done < manage_wordpress.ini
}

function parse_json
{
    regex="\"${1}\":[[:space:]]?\"?([^,}\"]*)\"?(,|[[:space:]]\})"
 
    if [[ $2 =~ $regex ]]; then
        echo ${BASH_REMATCH[1]}
    else
        echo 
    fi
}

# Set values from configuration file
SEC_GROUP_NAME=$(get_config SEC_GROUP_NAME)
SEC_GROUP_DESC=$(get_config SEC_GROUP_DESC)
AMI=$(get_config AMI)
INSTANCE_TYPE=$(get_config INSTANCE_TYPE)
REGION=$(get_config REGION)
VPC_IP_BLOCK=$(get_config VPC_IP_BLOCK)
LOG_FILE="manage_wordpress.log"

if [[ $1 == "create" ]]; then

    echo "[1/5] Creating VPC..."
    # sample OUTPUT: { "Vpc": { "VpcId": "vpc-xxxxxxxx", "InstanceTenancy": "default", "State": "pending", "DhcpOptionsId": "dopt-xxxxxxxx", "CidrBlock": "172.31.0.0/16", "IsDefault": false } }    
    OUTPUT=$(aws ec2 create-vpc --cidr-block $VPC_IP_BLOCK)
    echo "$OUTPUT" > "$LOG_FILE"
    VPC_ID=$(parse_json VpcId "$OUTPUT")
    echo "VPC ID: $VPC_ID"
    
    echo "[2/5] Creating Security Group..."
    # sample OUTPUT: { "GroupId": "sg-xxxxxxxxx" }       
    OUTPUT=$(aws ec2 create-security-group --group-name $SEC_GROUP_NAME --description "$SEC_GROUP_DESC" --vpc-id $VPC_ID)
    echo "$OUTPUT" > "$LOG_FILE"
    SEC_GROUP_ID=$(parse_json GroupId "$OUTPUT")    
    echo "Security Group Id: $SEC_GROUP_ID"
        
    echo "[3/5] Creating EC2 instances..."        
    #OUTPUT=$(aws ec2 run-instances --cli-input-json file://ec2-config.json)
    #OUTPUT=$(aws ec2 run-instances --image-id $AMI --instance-type $INSTANCE_TYPE --security-group-ids $SEC_GROUP_ID --region $REGION --block-device-mapping "/dev/sda1=:16:true" --instance-initiated-shutdown-behavior stop --user-data-file ec2-user-data.sh)
    OUTPUT=$(aws ec2 run-instances --image-id $AMI --instance-type $INSTANCE_TYPE --security-group-ids $SEC_GROUP_ID --region $REGION --cli-input-json file://ec2-config.json)
    echo "$OUTPUT" > "$LOG_FILE"
    echo "OUT $OUTPUT"  

    INSTANCE_NAME=$(echo $OUTPUT | sed 's/RESERVATION.*INSTANCE //' | sed 's/ .*//')

    times=0
    echo
    while [ 5 -gt $times ] && ! ec2-describe-instances $INSTANCE_NAME | grep -q "running"
    do
        times=$(( $times + 1 ))
        echo Attempt $times at verifying $INSTANCE_NAME is running...
    done

    echo

    if [ 5 -eq $times ]; then
        echo Instance $INSTANCE_NAME is not running. Exiting...
        exit    
    fi

    echo 
    echo "WordPress instances up and running."   

elif [[ $1 == "list" ]]; then

    echo "Settings"
    echo $SEC_GROUP_NAME
    echo $SEC_GROUP_DESC
    echo $AMI
    echo $INSTANCE_TYPE
    echo $REGION
    echo $VPC_IP_BLOCK 
    echo

    echo "Searching Security Group..."
    OUTPUT=$(aws ec2 describe-security-groups --group-names $SEC_GROUP_NAME)
    echo "$OUTPUT" > "$LOG_FILE"
    # SEC_GROUP_ID=$(parse_json $SEC_GROUP_NAME GroupId "$OUTPUT")    
    # "VpcId": "vpc-xxxxxxxx"
    
elif [[ $1 == "delete" ]]; then
    echo -e "Please enter OK: \c "
    read  ok
    if [ $ok = "OK" ]; then

        echo "[1/5] Searching Security Group..."
        OUTPUT=$(aws ec2 describe-security-groups --group-names $SEC_GROUP_NAME)
        echo "$OUTPUT" > "$LOG_FILE"
        # SEC_GROUP_ID=$(parse_json $SEC_GROUP_NAME GroupId "$OUTPUT")    
        # "VpcId": "vpc-xxxxxxxx"

        echo "[2/5] Deleting EC2 instances..."

        echo "[3/5] Deleting Security Group..."
        OUTPUT=$(aws ec2 delete-security-group --group-id $SEC_GROUP_ID)
        echo "$OUTPUT" > "$LOG_FILE"

        echo "[4/5] Deleting VPC..."
        OUTPUT=$(aws ec2 delete-vpc --vpc-id $VPC_ID)
        echo "$OUTPUT" > "$LOG_FILE"
    
        echo 
        echo "WordPress and all depending data deleted."   
    fi

else 
    echo "##################################"
    echo "# Plesk WordPress Scaler for AWS #"
    echo "##################################"
    echo 
    echo "Commands:"
    echo "   manage_wordpress.sh create        Create a new WordPress in your AWS account via AWS CLI."
    echo "   manage_wordpress.sh delete        Delete the WordPress incl. database etc BE CAREFUL - this deletes all that the script created before."
    echo "   manage_wordpress.sh list          List settings and WordPress instances."
    echo 
fi
