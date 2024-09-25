#!/bin/bash
set -e

# Use root home folder
ENV_FILE_PATH="/root/.env"

login() {
  echo "${PASSWORD}" | docker login "${REGISTRY}" -u "${USERNAME}" --password-stdin
}

configure_tls_files() {

  mkdir /tmp/certs
  printf '%s' "$REMOTE_CA" > "/tmp/certs/ca.pem"
  printf '%s' "$REMOTE_CERTIFICATE" > "/tmp/certs/cert.pem"
  printf '%s' "$REMOTE_PRIVATE_KEY" > "/tmp/certs/key.pem"
}

configure_env_file() {
  printf '%s' "$ENV_FILE" > "${ENV_FILE_PATH}"
  env_file_len=$(grep -v '^#' ${ENV_FILE_PATH}|grep -v '^$' -c)
  if [[ $env_file_len -gt 0 ]]; then
    echo "Environment Variables: Additional values"
    if [ "${DEBUG}" != "0" ]; then
      echo "Environment vars before: $(env|wc -l)"
    fi
    # shellcheck disable=SC2046
    export $(grep -v '^#' ${ENV_FILE_PATH} | grep -v '^$' | xargs -d '\n')
    if [ "${DEBUG}" != "0" ]; then
      echo "Environment vars after: $(env|wc -l)"
    fi
  fi
}

deploy() {
  docker stack deploy --with-registry-auth -c "${STACK_FILE}" "${STACK_NAME}"
}

check_deploy() {
  echo "Deploy: Checking status"
  /stack-wait.sh -t "${DEPLOY_TIMEOUT}" "${STACK_NAME}"
}

[ -z ${DEBUG+x} ] && export DEBUG="0"

# ADDITIONAL ENV VARIABLES
if [[ -z "${ENV_FILE}" ]]; then
  export ENV_FILE=""
else
  configure_env_file;
fi

# SET DEBUG
if [ "${DEBUG}" != "0" ]; then
  OUT=/dev/stdout;
  SSH_VERBOSE="-vvv"
  echo "Verbose logging"
else
  OUT=/dev/null;
  SSH_VERBOSE=""
fi

# PROCEED WITH LOGIN
if [ -z "${USERNAME+x}" ] || [ -z "${PASSWORD+x}" ]; then
  echo "Container Registry: No authentication provided"
else
  [ -z ${REGISTRY+x} ] && export REGISTRY=""
  if login > /dev/null 2>&1; then
    echo "Container Registry: Logged in ${REGISTRY} as ${USERNAME}"
  else
    echo "Container Registry: Login to ${REGISTRY} as ${USERNAME} failed"
    exit 1
  fi
fi

if [[ -z "${DEPLOY_TIMEOUT}" ]]; then
  export DEPLOY_TIMEOUT=600
fi

# CHECK REMOTE VARIABLES
if [[ -z "${REMOTE_HOST}" ]]; then
  echo "Input remote_host is required!"
  exit 1
fi
if [[ -z "${REMOTE_PORT}" ]]; then
  export REMOTE_PORT="22"
fi
if [[ -z "${REMOTE_USER}" ]]; then
  echo "Input remote_user is required!"
  exit 1
fi
if [[ -z "${REMOTE_PRIVATE_KEY}" ]]; then
  echo "Input private_key is required!"
  exit 1
fi
# CHECK STACK VARIABLES
if [[ -z "${STACK_FILE}" ]]; then
  echo "Input stack_file is required!"
  exit 1
else
  if [ ! -f "${STACK_FILE}" ]; then
    echo "${STACK_FILE} does not exist."
    exit 1
  fi
fi

if [[ -z "${STACK_NAME}" ]]; then
  echo "Input stack_name is required!"
  exit 1
fi


export DOCKER_HOST=tcp://${DOCKER_HOST}:2376
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH=/tmp/certs

if deploy > $OUT; then
  echo "Deploy: Updated services"
else
  echo "Deploy: Failed to deploy ${STACK_NAME} from file ${STACK_FILE}"
  exit 1
fi

if check_deploy; then
  echo "Deploy: Completed"
else
  echo "Deploy: Failed"
  exit 1
fi
