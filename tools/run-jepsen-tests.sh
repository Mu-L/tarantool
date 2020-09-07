#!/usr/bin/bash

# Script performs setup of test environment using Terraform,
# runs Jepsen tests and teardown test environment.
# Script expects evironment variables:
# 	TF_VAR_user_name
# 	TF_VAR_password
# 	TF_VAR_tenant_id
# 	TF_VAR_user_domain_id
# 	TF_VAR_keypair_name - name of used SSH keypair in MCS UI
# 	TF_VAR_ssh_key - content of SSH private key
# and two arguments: path to a Tarantool project directory
# and number on instances (optional).

set -Eeo pipefail

set -x

src_root=$1
tests_dir="$src_root/jepsen-tests-src"
terraform_config="$src_root/extra/tf"

[[ -n $src_root ]] || (echo "Please specify path to a Tarantool project directory")
[[ -n $TF_VAR_ssh_key ]] || (echo "Please specify TF_VAR_ssh_key env var"; exit 1)
[[ -n $TF_VAR_keypair_name ]] || (echo "Please specify TF_VAR_keypair_name env var"; exit 1)

TERRAFORM_BIN=$(which terraform)
LEIN_BIN=$(which lein)
CLOJURE_BIN=$(which clojure)

[[ -n $TERRAFORM_BIN ]] || (echo "terraform is not installed"; exit 1)
[[ -n $LEIN_BIN ]] || (echo "lein is not installed"; exit 1)
[[ -n $CLOJURE_BIN ]] || (echo "clojure is not installed"; exit 1)

SSH_KEY_FILENAME="tf-cloud-init"
NODES_FILENAME="nodes"

function cleanup {
    echo "cleanup"
    rm -f $NODES_FILENAME $SSH_KEY_FILENAME
    [[ -e .terraform ]] && terraform destroy -auto-approve
}

trap "{ cleanup; exit 255; }" SIGINT SIGTERM ERR

echo -e "${TF_VAR_ssh_key//_/\\n}" > $SSH_KEY_FILENAME
chmod 400 $SSH_KEY_FILENAME
$(pgrep ssh-agent) || eval "$(ssh-agent)"
ssh-add $SSH_KEY_FILENAME

if [[ -n $CI_JOB_ID ]]; then
    TF_VAR_id=$CI_JOB_ID
else
    RANDOM_ID=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13; echo '')
    TF_VAR_id=TF-$RANDOM_ID
fi

export TF_VAR_ssh_key_path=$SSH_KEY_FILENAME
export TF_VAR_id
export TF_VAR_instance_count=1

terraform init $terraform_config
terraform apply -auto-approve $terraform_config
terraform output instance_names
terraform output -json instance_ips | jq --raw-output '.[]' > $NODES_FILENAME
cd $tests_dir && lein run test --nodes-file $NODES_FILENAME --username ubuntu --workload register; cd -
zip -r jepsen_results.zip $tests_dir/store
cleanup
