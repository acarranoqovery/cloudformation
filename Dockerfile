FROM alpine:3.20.0

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

RUN cat <<EOF > entrypoint.sh
#!/bin/sh

if [ "\$JOB_INPUT" != '' ]
then
  PARAMETERS="file://\$JOB_INPUT"
fi

CMD=\$1; shift
set -ex

cd cloudformation

STACK_NAME="qovery-stack-\${QOVERY_JOB_ID%%-*}"

case "\$CMD" in
start)
  echo 'start command invoked'
  aws cloudformation deploy --stack-name \$STACK_NAME --template \$CF_TEMPLATE_NAME --parameter-overrides \$PARAMETERS 
  echo 'generating stack output - injecting it as Qovery environment variable for downstream usage'
  aws cloudformation describe-stacks --stack-name \$STACK_NAME --output json --query ""Stacks[0].Outputs"" > /data/output.json
  jq '.[] | { (.OutputKey): { "value": .OutputValue, "type" : "string", "sensitive": false } }' /data/output.json > /qovery-output/qovery-output.json
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

ENV CF_TEMPLATE_NAME=must-be-set-as-env-var
ENV AWS_REGION = must-be-set-as-env-var
ENV AWS_SECRET_ACCESS_KEY = must-be-set-as-env-var
ENV AWS_ACCESS_KEY_ID = must-be-set-as-env-var


ENTRYPOINT ["/usr/bin/dumb-init", "-v", "--", "/data/entrypoint.sh"]
CMD ["start"]