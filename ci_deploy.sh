#!/bin/bash
#Description: This script is intended to be used with CI systems to create deployments in appLariat
#Usage: Add this script to your project and then configure your CI tool to execute it
#Variables that should be set as part of CI settings
#APL_API
#APL_SERVICE_USER
#APL_SERVICE_PASS
start=`date +%s`
set -e # Exit with nonzero exit code if anything fails

#Map CI specific Variables to limit changes below
JOB_BRANCH=${TRAVIS_BRANCH:-Testing}
JOB_TAG=${TRAVIS_TAG}
JOB_COMMIT=${TRAVIS_COMMIT}

#appLariat CLI Version to download
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE=darwin
else
    OS_TYPE=linux
fi
FIND_LATEST="https://api.github.com/repos/applariat/go-apl/releases/latest"
#DOWNLOAD_URL=$(wget -qO- ${FIND_LATEST} | grep browser_download_url | grep ${OS_TYPE} | head -n 1 | cut -d '"' -f 4)
DOWNLOAD_URL=$(curl -Ss ${FIND_LATEST} | grep browser_download_url | grep ${OS_TYPE} | head -n 1 | cut -d '"' -f 4)
echo $DOWNLOAD_URL
APL_CLI_VER=$(echo "$DOWNLOAD_URL" | cut -d '/' -f 8)
APL_FILE=$(echo $DOWNLOAD_URL | cut -d '/' -f 9)

#Project variables
CREATE_RELEASE=${CREATE_RELEASE:-false}
REPO_NAME=${REPO_NAME:-acme-air}
REPO_PATH="https://github.com/applariat/${REPO_NAME}/archive"

#APL Platform variables
#Required as env variable inputs from CI
APL_LOC_DEPLOY_NAME=${APL_LOC_DEPLOY_NAME}
APL_LOC_ARTIFACT_NAME=${APL_LOC_ARTIFACT_NAME}
WORKLOAD_TYPE=${WORKLOAD_TYPE:-level2}

#APL STACK variables
#Required as env variable inputs from CI
APL_STACK_NAME=${APL_STACK_NAME:?Missing required env var} #The machine name of the stack - all lower case, with no spaces
APL_RELEASE_VERSION=${APL_RELEASE_VERSION:?Missing required env var} #The integer version of the release
APL_COMPONENT_NAME=${APL_COMPONENT_NAME:?Missing required env var} #The name given for the component to be updated in appLariat

set +e

#We will look up the necessary info based on envvars
#APL_LOC_DEPLOY_ID=""
#APL_LOC_ARTIFACT_ID=""
#APL_STACK_ID=""
#APL_RELEASE_ID=""
#APL_STACK_VERSION_ID=""
#APL_STACK_COMPONENT_ID=""
#APL_COMP_SERVICE_NAME=""
#APL_ARTIFACT_TYPE=""


echo "Starting the appLariat ci_deploy.sh"
echo "JOB_BRANCH: $JOB_BRANCH"
echo "JOB_TAG: $JOB_TAG"
echo "JOB_COMMIT: $JOB_COMMIT"

if [ ! -z "$JOB_TAG" ]; then
    APL_ARTIFACT_NAME="staging-${JOB_TAG}"
    CODE_LOC=${JOB_TAG}
    WORKLOAD_TYPE=level5
    CREATE_RELEASE=true
else
    JOB_COMMIT=`echo $JOB_COMMIT |cut -c 1-12`
    APL_ARTIFACT_NAME="qa-${JOB_COMMIT}"
    CODE_LOC=${JOB_COMMIT}
    WORKLOAD_TYPE=level2
fi

## Make sure the name is domain safe.
APL_ARTIFACT_NAME=${APL_ARTIFACT_NAME//[^A-Za-z0-9\\-]/-}

DEPLOYMENT_NAME=${APL_ARTIFACT_NAME}

#Check the environment
#Install apl command
#if ! [ `command -v apl` ]; then
  APL_FILE=apl-${APL_CLI_VER}-linux_amd64.tgz
  if [[ "$OSTYPE" == "darwin"* ]]; then
    APL_FILE=apl-${APL_CLI_VER}-darwin_amd64.tgz
  fi
  echo
  echo "Downloading cli: $DOWNLOAD_URL"
  wget -q $DOWNLOAD_URL
  tar zxf ${APL_FILE}
  mv bin/apl .
  echo "Running APL Version - $(./apl version)"
#fi
#Confirm jq is available
#if ! [ `command -v jq` ]; then
    #Let's install jq
    echo "This script requires jq 1.5 tool, installing"
    JQ_TOOL=jq-linux64
    if [[ "$OSTYPE" == "darwin"* ]]; then
      JQ_TOOL=jq-osx-amd64
    fi
    echo "Downloading jq: https://github.com/stedolan/jq/releases/download/jq-1.5/${JQ_TOOL}"
    wget -q https://github.com/stedolan/jq/releases/download/jq-1.5/${JQ_TOOL}

    if [ -f ${JQ_TOOL} ]; then
      echo "Download complete, installing jq command"
      chmod +x ${JQ_TOOL}
      mv -f ${JQ_TOOL} jq
      #mv -f jq /usr/local/bin
    else
      echo "Error: There was a problem with the download of ${JQ_TOOL}, exiting"
	  exit 1
    fi
#fi
#End of Environment checks

#Lookup APL PLATFORM ids
if [ -z $APL_LOC_DEPLOY_ID ]; then
  APL_LOC_DEPLOY_ID=$(./apl loc-deploys -o json | ./jq -r '.[0].id')
  echo "Using Default Deployment Location with id $APL_LOC_DEPLOY_ID"
fi
if [ ! -z ${APL_LOC_ARTIFACT_NAME} ]; then
  APL_LOC_ARTIFACT_ID=$(./apl loc-artifacts --name $APL_LOC_ARTIFACT_NAME -o json | ./jq -r '.[0].id')
  echo "Using Artifact Location with $APL_LOC_ARTIFACT_NAME and id: $APL_LOC_ARTIFACT_ID"
fi

#Just in case make sure to convert stack display name to machine name
APL_STACK_NAME=$(echo ${APL_STACK_NAME} | tr -d ' ' | tr '[:upper:]' '[:lower:]')
#Lookup APL Stack info
if [ -z $APL_STACK_ID ]; then
  APL_STACK_ID=$(./apl stacks --name $APL_STACK_NAME -o json | ./jq -r '.[0].id')
  echo "Found $APL_STACK_NAME with id: $APL_STACK_ID"
fi
#We have to lookup several items from the release record, so we will load the records and then parse
RELEASE_LIST=$(./apl releases --stack-id $APL_STACK_ID -o json)
#echo $RELEASE_LIST

#Get Release Info
if [ -z $APL_RELEASE_ID ]; then
    RELEASE_REC=$(echo ${RELEASE_LIST} | \
      ./jq -c --argjson rv $APL_RELEASE_VERSION '.[] | select(.version == $rv) ')
    #echo $RELEASE_REC
    APL_RELEASE_ID=$(echo ${RELEASE_REC} | \
      ./jq -r '.id')
    #echo $APL_RELEASE_ID
    APL_STACK_VERSION_ID=$(echo ${RELEASE_REC} | \
      ./jq -r '.stack_version_id')
    #echo $APL_STACK_VERSION_ID
    APL_STACK_COMPONENT_REC=$(echo ${RELEASE_REC} | \
      ./jq -r --arg cname $APL_COMPONENT_NAME '.components[] | select(.name == $cname)')
    APL_STACK_COMPONENT_ID=$(echo ${APL_STACK_COMPONENT_REC} | \
      ./jq -r '.stack_component_id')
    #echo $APL_STACK_COMPONENT_ID
    APL_COMP_SERVICE_NAME=$(echo ${APL_STACK_COMPONENT_REC} | \
      ./jq -r '.services[0].name')
    #echo $APL_COMP_SERVICE_NAME
    #Get the artifact type for the component
    APL_ARTIFACT_TYPE=$(echo ${APL_STACK_COMPONENT_REC} | \
      ./jq -r '.services[0].build.artifacts | keys |
      if contains(["code"]) then "code" elif contains(["builder"]) then "builder" else "image" end')
    #echo $APL_ARTIFACT_TYPE
    if [ -z ${APL_LOC_ARTIFACT_ID} ]; then
        CUR_STACK_ARTIFACT_ID=$(echo ${APL_STACK_COMPONENT_REC} | \
          ./jq -r '.services[0].build.artifacts |  if has("code") then .code elif has("builder") then .builder else .image end')
        SA_REC=$(./apl stack-artifacts get $CUR_STACK_ARTIFACT_ID -o json)
        APL_LOC_ARTIFACT_ID=$(echo ${SA_REC} | ./jq -r '.loc_artifact_id')
    fi
fi

#Submit to appLariat
#First register the new artifact
echo
echo "Submitting the new artifact"
SA_CREATE=$(./apl stack-artifacts create --stack-id $APL_STACK_ID --loc-artifact-id \
            ${APL_LOC_ARTIFACT_ID} --artifact-name ${REPO_PATH}/${CODE_LOC}.zip --stack-artifact-type \
            ${APL_ARTIFACT_TYPE} --name ${APL_ARTIFACT_NAME} -o json)

if [[ $(echo $SA_CREATE | ./jq -r '. | has("message")') == "true"  ]]; then
    echo $SA_CREATE | ./jq -r '.message'
    exit 1
elif [[ $(echo $SA_CREATE | ./jq -r '. | has("data")') == "true" ]]; then
    STACK_ARTIFACT_ID=$(echo $SA_CREATE | ./jq -r '.data')
    echo "Created artifact with id: $STACK_ARTIFACT_ID"
else
    echo "ERROR: ${SA_CREATE}"
    exit 1
fi

#Second, if this is a TAGGED build, create a release
if [[ $CREATE_RELEASE == true ]]; then
    echo
    echo "Creating a release before deploying"
    NUM_COMPS=$(echo ${RELEASE_REC} | \
      ./jq -r '.components | length')
    COUNTER=0
    COMPONENTS=()

    while [ $COUNTER -lt $NUM_COMPS ]; do
		comp_id=$(echo ${RELEASE_REC} | ./jq -r ".components[$COUNTER].stack_component_id")
		svc_name=$(echo ${RELEASE_REC} | ./jq -r ".components[$COUNTER].services[0].name")
		artifacts=$(echo ${RELEASE_REC} | ./jq -c ".components[$COUNTER].services[0].build.artifacts")
		if [[ $comp_id == $APL_STACK_COMPONENT_ID ]]; then
			#override the values for this component
			comp=(StackComponentID=${APL_STACK_COMPONENT_ID})
			comp+=(ServiceName=${APL_COMP_SERVICE_NAME})
			comp+=(StackArtifactID=${STACK_ARTIFACT_ID})
			artifacts=$(echo ${artifacts} | ./jq -c --arg art ${APL_ARTIFACT_TYPE} 'with_entries(select(.key != $art))')
			comp+=( `echo ${artifacts} | ./jq -r 'map_values("StackArtifactID=" + .) |to_entries|.[].value'` )

			COMPONENTS[$COUNTER]=$(IFS=, ; echo "${comp[*]}")
		else
			#reuse the values for the current release
			comp=(StackComponentID=${comp_id})
			comp+=(ServiceName=${svc_name})
			comp+=( `echo ${artifacts} | ./jq -r 'map_values("StackArtifactID=" + .) |to_entries|.[].value'` )

			COMPONENTS[$COUNTER]=$(IFS=, ; echo "${comp[*]}")
		fi
		let COUNTER+=1
	done
    #echo ${COMPONENTS[@]}

    #construct release command
    rel_flds=( "--name ${APL_ARTIFACT_NAME}" "--stack-id ${APL_STACK_ID}" "--stack-version-id ${APL_STACK_VERSION_ID}" )
    for c in ${COMPONENTS[@]}; do
        rel_flds+=( "--component $c" )
    done

    echo "Submitting the release"
    APL_RELEASE_CREATE=$(./apl releases create -o json ${rel_flds[@]})

    if [[ $(echo $APL_RELEASE_CREATE | ./jq -r '. | has("message")') == "true" ]]; then
     	echo $APL_RELEASE_CREATE | ./jq -r '.message'
     	exit 1
	elif [[ $(echo $APL_RELEASE_CREATE | ./jq -r '. | has("data")') == "true" ]]; then
    	APL_RELEASE_ID=$(echo $APL_RELEASE_CREATE | ./jq -r '.data')
    	echo "Created release with id: $APL_RELEASE_ID"
	else
   		echo "ERROR: $APL_RELEASE_CREATE"
   		exit 1
	fi
fi

#Finally, create the deployment
echo
if [[ $CREATE_RELEASE == true ]]; then
    echo "Creating deployment for new release with id: $APL_RELEASE_ID"
	DEPLOY_COMMAND="./apl deployments create --name $DEPLOYMENT_NAME --release-id $APL_RELEASE_ID --loc-deploy-id $APL_LOC_DEPLOY_ID -o json"
else
  	echo "Creating deployment with overrides to release with id: $APL_RELEASE_ID"
	#Create a yaml file for the deployment with overrides
	cat >deploy.yaml <<EOL
name: ${DEPLOYMENT_NAME}
release_id: ${APL_RELEASE_ID}
loc_deploy_id: ${APL_LOC_DEPLOY_ID}
workload_type: ${WORKLOAD_TYPE}
components:
- stack_component_id: ${APL_STACK_COMPONENT_ID}
  services:
  - name: $APL_COMP_SERVICE_NAME
    overrides:
      build:
        artifacts:
          ${APL_ARTIFACT_TYPE}: ${STACK_ARTIFACT_ID}
EOL

	DEPLOY_COMMAND="./apl deployments create -f deploy.yaml -o json"
fi

echo "Submitting the deployment"
APL_DEPLOY_CREATE=$(${DEPLOY_COMMAND})
echo
if [[ $(echo $APL_DEPLOY_CREATE | ./jq -r '. | has("message")') == "true" ]]; then
     echo $APL_DEPLOY_CREATE | ./jq -r '.message'
     exit 1
elif [[ $(echo $APL_DEPLOY_CREATE | ./jq -r '. | has("data")') == "true" ]]; then
    APL_DEPLOYMENT_ID=$(echo $APL_DEPLOY_CREATE | ./jq -r '.data.deployment_id')
    echo "Created deployment with id: $APL_DEPLOYMENT_ID"
else
   echo "ERROR: $APL_DEPLOY_CREATE"
   exit 1
fi

#### Optional: Wait for appLariat to complete the deployment ####
# To use remove the <<COMMENT and COMMENT above and below the if Statement

<<COMMENT
if [ -z $APL_DEPLOYMENT_ID ]; then
  echo "Failed to get deployment id, you can try apl deployments command to return a list of deployments"
  exit
else
  echo "Tracking Deployment Status"
  state=$(./apl deployments get $APL_DEPLOYMENT_ID -o json | ./jq -r '.status.state')
  while [[ $(./apl deployments get $APL_DEPLOYMENT_ID -o json | ./jq -r '.status.state') =~ ^(queued|deploying|pending)$ ]]; do
      echo "Deployment Pending"
      sleep 30
  done
  echo "Deployment completed with the following info:"
  echo "Details:"
  echo
  ./apl deployments get $APL_DEPLOYMENT_ID -o json |
    ./jq '.status | { name: .namespace, state: .state, description: .description, services: .components[].services[]}'
fi
COMMENT

end=`date +%s`
runtime=$((end-start))
echo
echo "APL Deployed:
	Name = $DEPLOYMENT_NAME
  	ID = $APL_DEPLOYMENT_ID"
