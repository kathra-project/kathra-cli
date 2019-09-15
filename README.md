# KATHRA CLI

Tool allowing to connect to kathra and execute few commands

## Authentication
For usage, you have to be connected to keycloak, gitlab and jenkins.
Your context is store in file : ~/.kathra-context
Stored variable :
 - RESOURCE_MANAGER_HOST: resource manager hostname
 - PIPELINE_MANAGER_HOST: pipeline manager hostname
 - SOURCE_MANAGER_HOST: sourcemanager hostname
 - JENKINS_HOST: jenkins hostname
 - GITLAB_HOST: gitlab hostname
 - KEYCLOAK_HOST: keycloak hostname
 - KEYCLOAK_CLIENT_REALM: keycloak's realm name
 - KEYCLOAK_CLIENT_ID: keycloak's client id
 - KEYCLOAK_CLIENT_SECRET: keycloak's client secret
 - JENKINS_API_TOKEN: Jenkins API Token
 - GITLAB_API_TOKEN: Gitlab API Token
 - TOKEN: Kathra token

If your token is expired, remove entry in context's file.

## Features
### All resources
#### List resources with name, uuid and status
```
./kathra-cli.sh get <resource-type>
```
#### Get resource by uuid with details
```
./kathra-cli.sh get <resource-type> <uuid>
```
#### Patch resource by uuid
```
./kathra-cli.sh patch <resource-type> <uuid> <json>
```

### Components
#### Create component with new ApiVersion
```
./kathra-cli.sh create components <swagger-file> <component's name> <group UUID or name> <description>
./kathra-cli.sh create components "swagger.example.yaml" "my-first-component" "my-team" "Component's description"
```
#### Delete component 
```
./kathra-cli.sh delete components <uuid>
```
#### Delete component with pipeline and sources repositories 
```
./kathra-cli.sh delete components <uuid> --purge
```
#### Create implementation
```
./kathra-cli.sh create implementations <implementation's name> <component's name or UUID> <component's version> <implementation's language> <implementation's description>
./kathra-cli.sh create implementations "my-implementation" "my-first-component" "1.0.0" "JAVA" "implementation description"
```


#### Import component and implementation with existing sources and pipelines
```
./kathra-cli.sh import components <file-component>
```
File example
```
{
  "name": "pipelinemanager",
  "version": "1.0.0-RC-SNAPSHOT",
  "status": "READY",
  "metadata": {
    "artifact-artifactName": "pipelinemanager",
    "artifact-groupId": "org.kathra",
    "groupId": "38239189-a83b-4c95-bfec-70f69c292dd4",
    "groupPath": "/kathra-projects/my-team"
  },
  "description": "component-example",
  "implementationRepositoryUrl": "git@gitlab.kathra-opensourcing.irtsystemx.org:/kathra-projects/my-team/components/pipelinemanager/implementations/pipelinemanager-jenkins.git",
  "implementationName": "pipelinemanager-jenkins",
  "implementationRepositoryPath": "/kathra-projects/my-team/components/pipelinemanager/implementations/pipelinemanager-jenkins",
  "implementationPipelinePath": "/KATHRA-PROJECTS/my-team/components/pipelinemanager/implementations/java/pipelinemanager-jenkins",
  "apiRepositoryPath": "/kathra-projects/my-team/components/pipelinemanager/pipelinemanager-api",
  "apiRepositoryUrl": "git@gitlab.kathra-opensourcing.irtsystemx.org:/kathra-projects/my-team/components/pipelinemanager/pipelinemanager-api.git",
  "modelRepositoryUrl": "git@gitlab.kathra-opensourcing.irtsystemx.org:/kathra-projects/my-team/components/pipelinemanager/JAVA/pipelinemanager-model.git",
  "modelRepositoryPath": "/kathra-projects/my-team/components/pipelinemanager/JAVA/pipelinemanager-model",
  "modelPipelinePath": "/KATHRA-PROJECTS/my-team/components/pipelinemanager/pipelinemanager-model",
  "interfaceRepositoryUrl": "git@gitlab.kathra-opensourcing.irtsystemx.org:/kathra-projects/my-team/components/pipelinemanager/JAVA/pipelinemanager-interface.git",
  "interfaceRepositoryPath": "/kathra-projects/my-team/components/pipelinemanager/JAVA/pipelinemanager-interface",
  "interfacePipelinePath": "/KATHRA-PROJECTS/my-team/components/pipelinemanager/pipelinemanager-interface",
  "clientRepositoryUrl": "git@gitlab.kathra-opensourcing.irtsystemx.org:/kathra-projects/my-team/components/pipelinemanager/JAVA/pipelinemanager-client.git",
  "clientRepositoryPath": "/kathra-projects/my-team/components/pipelinemanager/JAVA/pipelinemanager-client",
  "clientPipelinePath": "/KATHRA-PROJECTS/my-team/components/pipelinemanager/pipelinemanager-client"
}
```

## Imports Kathra's components
You can import Kathra's components into your own Kathra's instance.
KATHRA's source repositories are cloned and imported into your Gitlab.

### Import all components
```
./init-kathra-components.sh kathra-components.json
```
### Import specific component
```
./init-kathra-components.sh kathra-components.json kathra-pipelinemanager
```