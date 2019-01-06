#!/bin/bash

## Check that an Environment was Provided
if [ "$1" = "" ]
then
  echo "Usage: $0 [ dev / prod ]"
  exit
else
    ## Set Build Environment
    buildEnv=$1
    multi=$2
fi

P="`dirname \"$0\"`"              # relative
P="`( cd \"$(dirname P)\" && pwd  )`"  # absolutized and normalized
if [ -z "$P" ] ; then
  exit 1  # fail
fi


### Derive projectName from Folder Name, remove Lambda_   
### We must default BEFORE loading variables so that any variable substitution
### will work if projectName is not defined as a variable
if [[ ! $projectName ]]; then 
	echo "ProjectName not detected, setting"
	projectName="$(basename $P)"
	projectName="${projectName/lambda_/}"
fi 

### Import Variables from Settings File
set -o allexport
source "settings/$buildEnv.txt" 
set +o allexport


## Check that PythonVersion was provided
if [ "$pythonVersion" = "" ]; then
    pythonVersion=3.6   
    echo "pythonVersion not set in $buildEnv.txt file.  Defaulting to $pythonVersion"
fi

## Check for Docker
docker -v 2>/dev/null 1>/dev/null || { echo >&2 "This script requires DOCKER but it's not installed.  Aborting."; exit 1; }

## Check for Required Python Image Version
if [[ "$(docker images -q python:$pythonVersion 2> /dev/null)" == "" ]]; then
  echo "This scripts requires the Python $pythonVersion Docker image, but it is not installed. "
  echo "Attempt to Download"
  docker pull python:$pythonVersion
  exit
fi

## Set Working Directory
t=$P/target/content
echo "Working Directory $P"

## Create if not exists
if [ ! -d "$t" ]; then
	echo 'Creating Target Directory'
	mkdir -p $t 
	echo "Target Directory $t"
else
	echo "Target Directory exists $t"
fi

### Check the files to see if we need to repackage them
if [[ "$(find . -not -path "*target*" -not -path "*__pycache__*" -name '*.py' -exec diff {} $t/{} \;)" == "" ]] && ! [ -z "$(ls -A $t)" ]; then
    echo "No changes detect, don't repackage"
    uploaded=""
    versionId=($(aws s3api get-object --bucket $PARAM_S3Bucket --key $projectName/$zipFileName $zipFileName| jq '.VersionId'))
else
    ## Clear output directory
    rm -rf target/content/*

    ## Get Requirements
    echo "Dumping Requirements.txt"
    pip freeze > $P/requirements.txt

    ## Strip non-required libraries
    echo "Stripping non-required libraries"
    sed -i '' '/pylint/d' $P/requirements.txt
    sed -i '' '/boto3/d' $P/requirements.txt
    sed -i '' '/botocore/d' $P/requirements.txt
    sed -i '' '/lambda[-]local[-]python/d' $P/requirements.txt

    cp $P/requirements.txt $t

    echo "Copying Source Files"
    find . -not -path "*target*" -not -path "*__pycache__*" -name '*.py' -print0 | rsync -av --files-from=- --from0 ./ $t

    echo "Installing Required Libraries"
    docker run --name AwesomeBuild$pythonVersion --volume $PWD/target/content:/venv \
        --rm --workdir /venv python:$pythonVersion \
        pip install --quiet -t /venv -r requirements.txt


    echo "Remove Not-Needed Libraries"
    rm -rf $t/boto3*
    rm -rf $t/botocore*

    find target/content -type d | xargs  chmod ugo+rx
    find target/content -type f | xargs  chmod ugo+r

    fileId=$P/target/$zipFileName

    echo "Zipping File $fileId"
    cd target/content && zip --quiet -9r $fileId  *
    chmod ugo+r $fileId

    echo "Uploading to S3: $fileId "
    versionId=($(aws s3api put-object --bucket $PARAM_S3Bucket --key $projectName/$zipFileName --body $fileId | jq '.VersionId'))
    echo "Updated Version:  $versionId"
    uploaded="True"
fi 


stackId=$(aws cloudformation describe-stacks --region $region | jq --arg stackName "$stackName"  '.Stacks[]  | select(.StackName | contains($stackName)) | .StackId')
stackStatus=$(aws cloudformation describe-stacks --region $region | jq --arg stackName "$stackName"  '.Stacks[]  | select(.StackName | contains($stackName)) | .StackStatus')
## Create New Template
if [ -z "$stackId" ]
then
    echo "Stack Does not Exist, Creating $stackName Stack"
    commandString="aws cloudformation create-stack --stack-name $stackName --template-body file://$P/$projectName.template.yaml --capabilities=CAPABILITY_IAM --region $region --parameters "
    params=$(export | grep 'PARAM_' | sed 's/^.................//' | awk -F "=" '{print "ParameterKey="$1",ParameterValue="$2}' | awk '{print}' ORS=' ')
    s3String="ParameterKey=S3ObjectVersion,ParameterValue=$versionId"

## Product Requires Update to Update Template
elif [ $stackStatus == "\"UPDATE_COMPLETE\"" ]
then
    echo "Found Stackid = $stackId, updating"
    commandString="aws cloudformation update-stack --stack-name $stackName --template-body file://$P/$projectName.update.template.yaml --capabilities=CAPABILITY_IAM --region $region --parameters "
    params=$(export | grep 'PARAM_' | sed 's/^.................//' | awk -F "=" '{print "ParameterKey="$1",ParameterValue="$2}' | awk '{print}' ORS=' ')
    if [[ $uploaded == "" ]]; then
        s3String=ParameterKey=S3ObjectVersion,UsePreviousValue=true
    else
        s3String=ParameterKey=S3ObjectVersion,ParameterValue=$versionId
    fi
## Update Original Template
else
    echo "Found Stackid = $stackId, updating"
    commandString="aws cloudformation update-stack --stack-name $stackName --template-body file://$P/$projectName.template.yaml --capabilities=CAPABILITY_IAM --region $region --parameters "
    params=$(export | grep 'PARAM_' | sed 's/^.................//' | awk -F "=" '{print "ParameterKey="$1",ParameterValue="$2}' | awk '{print}' ORS=' ')
    if [[ $uploaded == "" ]]; then
        s3String=ParameterKey=S3ObjectVersion,UsePreviousValue=true
    else
        s3String=ParameterKey=S3ObjectVersion,ParameterValue=$versionId
    fi
fi

printf "\n\n\nExecuting: \n\n $commandString $s3String $params"   
eval "$commandString $s3String $params"

## Update Stack on Stack Completion
if [ "$multi" = "2" ]
then
    
    stackStatus="$(aws cloudformation describe-stacks --stack-name $stackName | jq '.Stacks[0].StackStatus')"
    
    while [[ $stackStatus != "\"UPDATE_ROLLBACK_COMPLETE\"" && $stackStatus != "\"CREATE_COMPLETE\"" ]]
    do
        stackStatus="$(aws cloudformation describe-stacks --stack-name $stackName | jq '.Stacks[0].StackStatus')"
        echo "${stackStatus}"
        sleep 10s ## Wait 10 Seconds before querying stack update
    done 
    echo "While Loop Completed"

    ## Run Update Stack
    commandString="aws cloudformation update-stack --stack-name $stackName --template-body file://$P/$projectName.update.template.yaml --capabilities=CAPABILITY_IAM --region $region --parameters "
    params=$(export | grep 'PARAM_' | sed 's/^.................//' | awk -F "=" '{print "ParameterKey="$1",ParameterValue="$2}' | awk '{print}' ORS=' ')
    if [[ $uploaded == "" ]]; then
        s3String=ParameterKey=S3ObjectVersion,ParameterValue=$versionId
    else
        s3String=ParameterKey=S3ObjectVersion,ParameterValue=$versionId
    fi
    printf "\n\n\nUpdating: \n\n $commandString $s3String $params"   
    eval "$commandString $s3String $params"
else
    echo ".....stack completed!"
fi
