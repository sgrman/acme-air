#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

# AppLariat vars
APL_LOC_DEPLOY_ID=${APL_LOC_DEPLOY_ID:?Missing required env var}
APL_LOC_ARTIFACT_ID=${APL_LOC_ARTIFACT_ID:?Missing required env var}
APL_STACK_ID=${APL_STACK_ID:?Missing required env var}
APL_RElEASE_ID=${APL_RElEASE_ID:?Missing required env var}
APL_STACK_COMPONENT_ID=${APL_STACK_COMPONENT_ID:?Missing required env var}
APL_ARTIFACT_NAME=${APL_ARTIFACT_NAME:?Missing required env var}
APL_CMD_RELEASE=${APL_CMD_RELEASE:-v0.1.0}

set +e

echo "APL_API: $APL_API"
echo

if [ ! -z "$TRAVIS_TAG" ]; then
    APL_ARTIFACT_NAME="STAGING-${TRAVIS_TAG}"
    CODE_LOC=${TRAVIS_TAG}
    QOS_LEVEL=level5
else
    TRAVIS_COMMIT=`echo $TRAVIS_COMMIT |cut -c 1-8`
    APL_ARTIFACT_NAME="QA-${TRAVIS_COMMIT}"
    CODE_LOC=${TRAVIS_COMMIT}
    QOS_LEVEL=level2
fi

#APL_ARTIFACT_NAME="${APL_ARTIFACT_NAME}-${TRAVIS_BUILD_NUMBER}"
#APL_ARTIFACT_NAME="${APL_ARTIFACT_NAME}-${TRAVIS_TAG}"
#APL_ARTIFACT_NAME="QA-${TRAVIS_COMMIT}"


# Make the name domain safe. // TODO: The API should handle this
APL_ARTIFACT_NAME=${APL_ARTIFACT_NAME//[^A-Za-z0-9\\-]/-}

APL_FILE=apl-${APL_CMD_RELEASE}-linux_amd64.tgz
if [[ "$OSTYPE" == "darwin"* ]]; then
    APL_FILE=apl-${APL_CMD_RELEASE}-darwin_amd64.tgz
fi
echo
echo "Downloading cli: https://github.com/applariat/go-apl/releases/download/${APL_CMD_RELEASE}/${APL_FILE}"
wget -q https://github.com/applariat/go-apl/releases/download/${APL_CMD_RELEASE}/${APL_FILE}
tar zxf ${APL_FILE}

# Create the stack-artifact yaml to submit.
cat >stack-artifact.yaml <<EOL
loc_artifact_id: ${APL_LOC_ARTIFACT_ID}
stack_id: ${APL_STACK_ID}
stack_artifact_type: code
artifact_name: https://github.com/applariat/acme-air/archive/${CODE_LOC}.zip
name: ${APL_ARTIFACT_NAME}
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
qos_level: ${QOS_LEVEL}
lease_period_days: 6
components:
- stack_component_id: ${APL_STACK_COMPONENT_ID}
  services:
  - component_service_id: ct-deployment
    name: node-service
    overrides:
      build:
        artifacts:
          code: ${APL_STACK_ARTIFACT_ID}
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
APL_DEPLOYMENT_ID=$(echo $APL_DEPLOY_CREATE_RESULT_JSON | jq -r '.data.deployment_id')

echo
echo "Deployment ID: $APL_DEPLOYMENT_ID"