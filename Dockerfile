FROM alpine:3.20.0

# downloading dependencies and initializing working dir
RUN <<EOF
set -e
apk update
apk add dumb-init
apk add 'aws-cli>2.16' --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community
apk add jq
adduser -D app
mkdir /data
chown -R app:app /data
EOF

WORKDIR /data
USER app

# Create the entrypoint script with the commands to be run on the environment:
# - start --> run "cloudformation deploy" + use "cloudformation describe-stacks" to generate the output to be fetched by Qovery and injected later as an environment variable for the other services within the same environment
# - stop --> nothing
# - delete --> run "cloudformation delete-stack"
# other commands are available and can be customized in this Dockerfile
# the stack name is created based on the QOVERY_JOB_ID environment variable

RUN cat <<EOF > entrypoint.sh
#!/bin/sh

if [ "\$CF_TEMPLATE_INPUT" != '' ]
then
  PARAMETERS="file://\$CF_TEMPLATE_INPUT"
fi

CMD=\$1; shift
set -ex

cd cloudformation

STACK_NAME="qovery-stack-\${QOVERY_JOB_ID%%-*}"

case "\$CMD" in
start)
  echo 'start command invoked'
  # Check if the stack exists
  if aws cloudformation list-stacks --query "StackSummaries[?StackName=='\$STACK_NAME'].[StackStatus]" --output text; then
    # Get the stack status
    STACK_STATUS=\$(aws cloudformation describe-stacks --stack-name \$STACK_NAME  --query "Stacks[0].StackStatus" --output text)
    # Check if the status is ROLLBACK_COMPLETE and delete the stack if true
    if [ "\$STACK_STATUS" == "ROLLBACK_COMPLETE" ]; then
      echo 'Stack is in ROLLBACK_COMPLETE. Deleting the stack...'
      aws cloudformation delete-stack --stack-name \$STACK_NAME
      aws cloudformation wait stack-delete-complete --stack-name \$STACK_NAME
      echo 'Stack deletion completed.'
    else
      echo 'Stack is not in ROLLBACK_COMPLETE. Current status: \$STACK_STATUS'
    fi
  fi
  aws cloudformation deploy --stack-name \$STACK_NAME --template \$CF_TEMPLATE_NAME --parameter-overrides \$PARAMETERS 
  echo 'generating stack output - injecting it as Qovery environment variable for downstream usage'
  aws cloudformation describe-stacks --stack-name \$STACK_NAME --output json --query ""Stacks[0].Outputs"" > /data/output.json
  jq -n '[inputs[] | { (.OutputKey): { "value": .OutputValue, "type" : "string", "sensitive": true } }] | add' /data/output.json > /qovery-output/qovery-output.json
  ;;

stop)
  echo 'stop command invoked'
  exit 0
  ;;

delete)
  echo 'delete command invoked'
  aws cloudformation delete-stack --stack-name \$STACK_NAME
  aws cloudformation wait stack-delete-complete --stack-name \$STACK_NAME
  ;;

raw)
  echo 'raw command invoked'
  aws cloudformation "\$1" "\$2" "\$3" "\$4" "\$5" "\$6" "\$7" "\$8" "\$9"
  ;;

debug)
  echo 'debug command invoked. sleeping for 9999999sec'
  echo 'Use remote shell to connect and execute commands'
  sleep 9999999999
  exit 1
  ;;

*)
  echo "Command not handled by entrypoint.sh: '\$CMD'"
  exit 1
  ;;
esac

EOF

COPY --chown=app:app . cloudformation

RUN <<EOF
set -e
chmod +x entrypoint.sh
cd cloudformation
EOF

# These env vars shall be set as environment variables within the Qovery console
ENV CF_TEMPLATE_NAME=must-be-set-as-env-var
ENV AWS_DEFAULT_REGION=must-be-set-as-env-var
ENV AWS_SECRET_ACCESS_KEY=must-be-set-as-env-var
ENV AWS_ACCESS_KEY_ID=must-be-set-as-env-var


ENTRYPOINT ["/usr/bin/dumb-init", "-v", "--", "/data/entrypoint.sh"]
CMD ["start"]
