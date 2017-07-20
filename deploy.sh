#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

# AppLariat vars
APL_LOC_DEPLOY_ID=${APL_LOC_DEPLOY_ID:?Missing required env var}
APL_LOC_ARTIFACT_ID=${APL_LOC_ARTIFACT_ID:?Missing required env var}
APL_STACK_ID=${APL_STACK_ID:?Missing required env var}
APL_STACK_VERSION_ID=${APL_STACK_VERSION_ID:?Missing required env var}
APL_RELEASE_ID=${APL_RELEASE_ID:?Missing required env var}
APL_STACK_COMPONENT_ID=${APL_STACK_COMPONENT_ID:?Missing required env var}
APL_ARTIFACT_NAME=${APL_ARTIFACT_NAME:?Missing required env var}
APL_CMD_RELEASE=${APL_CMD_RELEASE:-v0.1.0}

set +e

echo "APL_API: $APL_API"
echo

if [ ! -z "$TRAVIS_TAG" ]; then
    APL_ARTIFACT_NAME="STAGING-${TRAVIS_TAG}"
    CODE_LOC=${TRAVIS_TAG}
    WORKLOAD_TYPE=level5
else
    TRAVIS_COMMIT=`echo $TRAVIS_COMMIT |cut -c 1-12`
    APL_ARTIFACT_NAME="QA-${TRAVIS_COMMIT}"
    CODE_LOC=${TRAVIS_COMMIT}
    WORKLOAD_TYPE=level2
fi

#APL_ARTIFACT_NAME="${APL_ARTIFACT_NAME}-${TRAVIS_BUILD_NUMBER}"
#APL_ARTIFACT_NAME="${APL_ARTIFACT_NAME}-${TRAVIS_TAG}"
#APL_ARTIFACT_NAME="QA-${TRAVIS_COMMIT}"


## Make the name domain safe. // TODO: The API should handle this
APL_ARTIFACT_NAME=${APL_ARTIFACT_NAME//[^A-Za-z0-9\\-]/-}

APL_FILE=apl-${APL_CMD_RELEASE}-linux_amd64.tgz
if [[ "$OSTYPE" == "darwin"* ]]; then
    APL_FILE=apl-${APL_CMD_RELEASE}-darwin_amd64.tgz
fi
echo
echo "Downloading cli: https://github.com/applariat/go-apl/releases/download/${APL_CMD_RELEASE}/${APL_FILE}"
wget -q https://github.com/applariat/go-apl/releases/download/${APL_CMD_RELEASE}/${APL_FILE}
tar zxf ${APL_FILE}

echo
echo "Submitting stack artifact file:"

APL_SA_CREATE_RESULT_JSON=$(./apl stack-artifacts create \
    --loc-artifact-id ${APL_LOC_ARTIFACT_ID} \
    --stack-id ${APL_STACK_ID} \
    --stack-artifact-type code \
    --artifact-name https://github.com/applariat/acme-air/archive/${CODE_LOC}.zip \
    --name ${APL_ARTIFACT_NAME} \
    -o json)

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

if [ ! -z "$TRAVIS_TAG" ]; then
cat >release.yaml <<EOL
meta_data:
    display_name: ${APL_ARTIFACT_NAME}
stack_id: ${APL_STACK_ID}
stack_version_id: ${APL_STACK_VERSION_ID}
components:
  - name: node-svc
    stack_component_id: ${APL_STACK_COMPONENT_ID}
    services:
    - name: node-service
      release:
        artifacts:
          code:
            stack_artifact_id: ${APL_STACK_ARTIFACT_ID}
EOL

#    APL_RELEASE_CREATE_RESULT_JSON=$(./apl releases create \
#        --name ${APL_ARTIFACT_NAME} \
#        --stack-id ${APL_STACK_ID} \
#        --stack-version-id ${APL_STACK_VERSION_ID} \
#        --service-name node-service \
#        --stack-artifact-id ${APL_STACK_ARTIFACT_ID} \
#        --stack-component-id ${APL_STACK_COMPONENT_ID} \
#        -o json)

    APL_RELEASE_CREATE_RESULT_JSON=$(./apl releases create -f release.yaml -o json)

    echo
    echo "Result: ${APL_RELEASE_CREATE_RESULT_JSON}"
    if [ $? -ne 0 ]
    then
        echo $APL_RELEASE_CREATE_RESULT_JSON | jq -r '.message'
        exit 1
    fi

    APL_RELEASE_ID=$(echo $APL_RELEASE_CREATE_RESULT_JSON | jq -r '.data')
    echo "Release ID: ${APL_RELEASE_ID}"
fi

echo
echo "Submitting deployment:"

# deploy it
APL_DEPLOY_CREATE_RESULT_JSON=$(./apl deployments create \
    --loc-deploy-id ${APL_LOC_DEPLOY_ID} \
    --name ${APL_ARTIFACT_NAME} \
    --workload-type ${WORKLOAD_TYPE} \
    --release-id ${APL_RELEASE_ID} \
    --stack-component-id ${APL_STACK_COMPONENT_ID} \
    --component-service-id ct-deployment \
    --service-name  node-service \
    --stack-artifact-id ${APL_STACK_ARTIFACT_ID} \
    -o json)

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
