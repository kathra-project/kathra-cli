#!/bin/bash

##################################################################
## Init kathra's components into kathra
## @author Julien Boubechtoula
## 
##################################################################

export SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export TEMP_DIRECTORY=/tmp/kathra-cli/
export KATHRA_CONTEXT_FILE=$HOME/.kathra-context
[ ! -d $TEMP_DIRECTORY ] && mkdir $TEMP_DIRECTORY

. $SCRIPT_DIRECTORY/func/imports.sh

printDebug "Context file: $KATHRA_CONTEXT_FILE"

. $SCRIPT_DIRECTORY/conf.sh

export team="my-team"
export teamPath="/kathra-projects/$team"
export jenkinsComponentsRootDir="/KATHRA-PROJECTS/$team/components"
export artifactGroupId="org.kathra"

retreiveGroup $team $TEMP_DIRECTORY/team.uuid

export teamUUID=$(cat  $TEMP_DIRECTORY/team.uuid)
export deployKey=$(cat  $TEMP_DIRECTORY/team.uuid)

export kathraComponentsConf="$1"
export componentName="$2"


if [ "${kathraComponentsConf}" == "" ]
then
    printError "Specify kathra components json file"
    exit 1
fi

[ ! -f "${kathraComponentsConf}" ] && printError "Unable to find file $kathraComponentsConf" && exit 1

if [ "${componentName}" == "" ]
then
    initKathraComponents "$kathraComponentsConf"
else
    jq ".[] | select(.componentName == \"$componentName\")" < "$kathraComponentsConf" > ${TEMP_DIRECTORY}/initKathraComponent.json
    [ $? -ne 0 ] && exit 1
    [ "$(jq 'length' < ${TEMP_DIRECTORY}/initKathraComponent.json)" == "" ] && printError "Unable to find component '${componentName}'" && exit 1
    cat ${TEMP_DIRECTORY}/initKathraComponent.json
    initKathraComponent "${TEMP_DIRECTORY}/initKathraComponent.json"
fi

