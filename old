# Use a base image with AWS CLI installed
FROM amazon/aws-cli:2.15.48

ADD EC2_Instance_With_Ephemeral_Drives.json main.json
ADD input_ec2.json input.json

# AWS CloudFormation create or update stack command
ENTRYPOINT [ "/bin/sh" ]