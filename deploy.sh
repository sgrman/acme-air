#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

# AppLariat vars
APL_LOC_DEPLOY_ID=${APL_LOC_DEPLOY_ID:?Missing required env var}
APL_LOC_ARTIFACT_ID=${APL_LOC_ARTIFACT_ID:?Missing required env var}
APL_STACK_ID=${APL_STACK_ID:?Missing required env var}
APL_RElEASE_ID=${APL_RElEASE_ID:?Missing required env var}
APL_STACK_COMPONENT_ID=${APL_STACK_COMPONENT_ID:?Missing required env var}
APL_ARTIFACT_NAME=${APL_ARTIFACT_NAME:?Missing required env var}

set +e

#if [ -z "$TRAVIS_TAG" ]; then
#    echo "Exiting, only deploy for tags"
#    exit 0
#fi


APL_CMD_RELEASE=0.0.44
APL_FILE=apl-${APL_CMD_RELEASE}-linux_amd64.tgz
if [[ "$OSTYPE" == "darwin"* ]]; then
    APL_FILE=apl-${APL_CMD_RELEASE}-darwin_amd64.tgz
fi
echo
echo "Downloading cli: https://github.com/applariat/go-apl/releases/download/${APL_CMD_RELEASE}/${APL_FILE}"
wget https://github.com/applariat/go-apl/releases/download/${APL_CMD_RELEASE}/${APL_FILE}
tar zxf ${APL_FILE}

# Create the stack-artifact yaml to submit.
cat >stack-artifact.yaml <<EOL
loc_artifact_id: ${APL_LOC_ARTIFACT_ID}
stack_id: ${APL_STACK_ID}
artifact_name: https://github.com/applariat/acme-air/archive/${TRAVIS_COMMIT}.zip
name: ${APL_ARTIFACT_NAME}-${TRAVIS_BUILD_NUMBER}
EOL

echo
echo "Submitting stack artifact file:"
cat stack-artifact.yaml

APL_SA_CREATE_RESULT_JSON=$(./apl stack-artifacts create -f stack-artifact.yaml -o json)

echo
echo "Result: ${APL_SA_CREATE_RESULT_JSON}"
if [ $? -ne 0 ]
then
    echo $APL_SA_CREATE_RESULT_JSON | jq -r '.message'
    exit 1
fi

# create the stack artifact and get the new ID
APL_STACK_ARTIFACT_ID=$(echo $APL_SA_CREATE_RESULT_JSON | jq -r '.data')

echo
echo "Stack Artifact ID: ${APL_STACK_ARTIFACT_ID}"

cat >deploy.yaml <<EOL
name: ${APL_ARTIFACT_NAME}
release_id: ${APL_RElEASE_ID}
loc_deploy_id: ${APL_LOC_DEPLOY_ID}
lease_type: temporary
qos_level: wl-level1
lease_period_days: 6
components:
- stack_component_id: ${APL_STACK_COMPONENT_ID}
  services:
  - component_service_id: ct-node-build
    overrides:
      stack_artifact_id: ${APL_STACK_ARTIFACT_ID}
EOL

echo
echo "Submitting deployment:"
cat deploy.yaml

# deploy it
APL_DEPLOY_CREATE_RESULT_JSON=$(./apl deployments create -f deploy.yaml -o json)

echo
echo "Result: ${APL_DEPLOY_CREATE_RESULT_JSON}"
if [ $? -ne 0 ]
then
    echo $APL_DEPLOY_CREATE_RESULT_JSON | jq -r '.message'
    exit 1
fi

# create the stack artifact and get the new ID
APL_DEPLOYMENT_ID=$(echo $APL_SA_CREATE_RESULT_JSON | jq -r '.data.deployment_id')

echo
echo "Deployment ID: $APL_DEPLOYMENT_ID"

