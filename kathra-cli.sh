#!/bin/bash
##################################################################
## KATHRA CLI
## @author Julien Boubechtoula
## 
##################################################################
export SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export TEMP_DIRECTORY=/tmp/kathra-cli/
export KATHRA_CONTEXT_FILE=$HOME/.kathra-context
export VERSION="1.1.0"
[ ! -d $TEMP_DIRECTORY ] && mkdir $TEMP_DIRECTORY

. $SCRIPT_DIRECTORY/func/imports.sh

printDebug "Context file: $KATHRA_CONTEXT_FILE"

export resourceTypesExistings=( components apiversions implementations librairies pipelines sourcerepositories groups keypairs implementationversions )

function show_help() {
    printInfo "KATHRA CLI"
    printInfo "version: $VERSION"
    printInfo ""
    printInfo "Usage: "
    printInfo "--version"
    printInfo ""
    printInfo "login --username=<login> --password=<password> --host=<default:$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_HOST")>  : Get a token"
    
    printInfo ""
    printInfo "create components <swagger-file> <name> <team's name> <description>                               : add a new component with apiversion from swagger file"
    printInfo "import components <filePath>                                                                      : import component from file"
    printInfo ""
    printInfo "create implementations <name> <version> <component> <api-version> <language> <description>        : create new implementation"
    
    printInfo ""
    printInfo "get <resource-type>                                  : list resources"
    printInfo "get <resource-type> <uuid>                           : list all with details"
    printInfo "patch <resource-type> <uuid> <json>                  : patch resource"
    printInfo "delete <resource-type> <uuid>                        : delete resource"

    printInfo ""
    printInfo "Resource types :"
    for object in "${resourceTypesExistings[@]}"
    do
        printInfo "- $object"
    done

    return 0
}

findInArgs '--help' $* > /dev/null && show_help && exit 0
findInArgs '-h' $* > /dev/null && show_help && exit 0

. $SCRIPT_DIRECTORY/conf.sh



function getTypeResourceFromAlias() {
    local type=$1
    declare search=$(echo ${aliasTR[${type}]:-MISSING})
    [ "$search" == "MISSING" ] && return 1
    echo $search && return 0
}

function getVerb() {
    findInArgs 'get' $* > /dev/null && echo 'get' && return 0
    findInArgs 'create' $* > /dev/null && echo 'create' && return 0
    findInArgs 'delete' $* > /dev/null && echo 'delete' && return 0
    findInArgs 'patch' $* > /dev/null && echo 'patch' && return 0
    findInArgs 'import' $* > /dev/null && echo 'import' && return 0
    findInArgs 'edit' $* > /dev/null && echo 'edit' && return 0
}

function resolvIfIdentifierIsNameOrUUID() {
    local resourceType=$1
    local identifier=$2
    if [[ ${identifier//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
        echo $identifier
    else
        callResourceManager "GET" "${resourceType}" | jq ".[] | select(.name==\"${identifier}\")" > ${TEMP_DIRECTORY}.resolvIfIdentifierIsNameOrUUID
        [ "$(jq -r '.id' < ${TEMP_DIRECTORY}.resolvIfIdentifierIsNameOrUUID)" == "" ] && printError "Unable to find resource ${resourceType} with name '$identifier'" && return 1
        echo "$(jq -r '.id' < ${TEMP_DIRECTORY}.resolvIfIdentifierIsNameOrUUID)"
    fi
    return 0
}

function getTypeResource() {
    declare -A aliasTR;
    aliasTR[c]="components";
    aliasTR[com]="components";
    aliasTR[component]="components";
    aliasTR[components]="components";
    aliasTR[a]="apiversions";
    aliasTR[api]="apiversions";
    aliasTR[apiversion]="apiversions";
    aliasTR[apiversions]="apiversions";
    aliasTR[i]="implementations";
    aliasTR[imp]="implementations";
    aliasTR[implementation]="implementations";
    aliasTR[implementations]="implementations";
    aliasTR[library]="libraries";
    aliasTR[libraries]="libraries";
    aliasTR[pipeline]="pipelines";
    aliasTR[pipelines]="pipelines";
    aliasTR[sourcerepository]="sourcerepositories";
    aliasTR[sourcerepositories]="sourcerepositories";
    aliasTR[group]="groups";
    aliasTR[groups]="groups";
    aliasTR[keypair]="keypairs";
    aliasTR[keypairs]="keypairs";
    aliasTR[implementationversion]="implementationversions";
    aliasTR[implementationversions]="implementationversions";
    aliasTR[binaryrepository]="binaryrepositories";
    aliasTR[binaryrepositories]="binaryrepositories";
    aliasTR[catalogentry]="catalogentries";
    aliasTR[catalogentries]="catalogentries";
    aliasTR[catalogentry]="catalogentries";
    aliasTR[catalogentrypackage]="catalogentrypackages";
    aliasTR[catalogentrypackages]="catalogentrypackages";
    for i in "${!aliasTR[@]}"
    do
        findInArgs $i $* > /dev/null && echo ${aliasTR[$i]} && return 0
    done
    return 1
}

function getUUID() {
    for uuid in "$@"
    do
        [[ ${uuid//-/} =~ ^[[:xdigit:]]{32}$ ]] && echo $uuid && return 0
    done
}

function getFormat() {
    findInArgs "-o" $* && return 0
    findInArgs "--out" $* && return 0
    echo "json"
}

function format() {
    [ "$format" == "yaml" ] && json2yaml && return 0
    jq && return 0
}
export -f format

function unformat() {
    [ "$format" == "yaml" ] && yaml2json - && return 0
    jq && return 0
}
export -f unformat

declare verb=$(getVerb $*)
declare resourceType=$(getTypeResource $*)
declare identifier=$(getUUID $*)
declare extra=$4
declare format=$(getFormat $*)

[ "$resourceType" == "" ] && printError "Unable to find type of resource, use help" && exit

case "${verb}" in
    create)   
        case "${resourceType}" in
            implementations)   
                kathraCreateImplementation "$3" "$4" "$5" "$6" "$7" "$8"
            ;;
            components)   
                kathraCreateComponent "$3" "$4" "$5" "$6"
            ;;
        esac  
    ;;
    get)   
        declare propertiesToDisplay=(name id status)
        declare propertiesToDisplayFilter=$(echo ${propertiesToDisplay[*]} | tr ' ' '\n' | sed 's#\(.*\)#\1: .\1#g' | tr '\n' ',')
        echo $propertiesToDisplayFilter
        [ "${identifier}" == "" ] && callResourceManager "GET" "${resourceType}" | jq -r ".[] | {${propertiesToDisplayFilter}}" | format && exit 0
        declare uuid=$(resolvIfIdentifierIsNameOrUUID "${resourceType}" "$identifier")
        [ "$uuid" == "" ] && exit 1
        callResourceManager "GET" "${resourceType}/${uuid}" | jq '.' | format && exit 0
    ;;
    edit)
        declare uuid=$(resolvIfIdentifierIsNameOrUUID "${resourceType}" "$identifier")
        [ "$uuid" == "" ] && exit 1
        callResourceManager "GET" "${resourceType}/${uuid}" | jq '.' | format > $TEMP_DIRECTORY/${resourceType}.${identifier}.$format
        cp $TEMP_DIRECTORY/${resourceType}.${identifier}.$format $TEMP_DIRECTORY/${resourceType}.${identifier}.$format.origin
        vim $TEMP_DIRECTORY/${resourceType}.${identifier}.$format
        cmp -s "$TEMP_DIRECTORY/${resourceType}.${identifier}.$format.origin" "$TEMP_DIRECTORY/${resourceType}.${identifier}.$format" && printInfo "Resource ${resourceType}/${uuid} unmodified" && exit 0
        unformat < $TEMP_DIRECTORY/${resourceType}.${identifier}.$format > $TEMP_DIRECTORY/${resourceType}.${identifier}.json 
        callResourceManager "PUT" "${resourceType}/${uuid}" "$( cat $TEMP_DIRECTORY/${resourceType}.${identifier}.json)" > /dev/null && printInfo "Resource ${resourceType}/${uuid} updated" && exit 0
    ;;
    delete)   
        case "${resourceType}" in
            components)   
                callResourceManager "DELETE" "${resourceType}/${identifier}" | jq '.' | format && exit 0
            ;;
            implementations)   
                callResourceManager "DELETE" "${resourceType}/${identifier}" | jq '.' | format && exit 0
            ;;
        esac  
    ;;
    patch)   
        declare uuid=$(resolvIfIdentifierIsNameOrUUID "${resourceType}" "$identifier")
        [ "$uuid" == "" ] && exit 1
        callResourceManager "PATCH" "${resourceType}/${uuid}" "${extra}" | jq | format && exit 0
    ;;
    import) 
        case "${resourceType}" in
            components)   
                kathraImportExistingComponent "${identifier}"
            ;;
        esac   
    ;;
    *)
        show_help   
    ;;
esac   

exit $?