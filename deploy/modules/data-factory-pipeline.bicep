@description('The name of the data factory that this pipeline should be added to.')
param dataFactoryName string

@description('The resource name of the self-hosted integration runtime that should be used to run this pipeline\'s activities.')
param integrationRuntimeName string

@description('The private IP address of the virtual machine that contains the private web server, which the pipeline will access.')
param virtualMachinePrivateIPAddress string

var pipelineName = 'sample-pipeline'
var pipelineName2 = 'start-ir'

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' existing = {
  name: dataFactoryName

  resource integrationRuntime 'integrationRuntimes' existing = {
    name: integrationRuntimeName
  }
}

resource pipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: pipelineName
  properties: {
    activities: [
      {
        name: 'GetWebContent'
        type: 'WebActivity'
        typeProperties: {
          url: 'http://${virtualMachinePrivateIPAddress}/'
          connectVia: {
            referenceName: dataFactory::integrationRuntime.name
            type: 'IntegrationRuntimeReference'
          }
          method: 'GET'
          disableCertValidation: true
        }
      }
    ] 
  }
}

resource pipeline2 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: pipelineName2
  properties: {
  activities: [
    {
      name: 'Wait for IR'
      type: 'Until'
      dependsOn: [
        {
          activity: 'Start ACI'
          dependencyConditions: [
            'Succeeded'
          ]
        }
      ]
      userProperties: []
      typeProperties: {
        expression: {
          value: '@equals(activity(\'Get IR status\').output.properties.state, \'Online\')'
          type: 'Expression'
        }
        activities: [
          {
            name: 'Get IR status'
            type: 'WebActivity'
            dependsOn: [
              {
                activity: 'Wait'
                dependencyConditions: [
                  'Succeeded'
                ]
              }
            ]
            policy: {
              timeout: '0.12:00:00'
              retry: 0
              retryIntervalInSeconds: 30
              secureOutput: false
              secureInput: false
            }
            userProperties: []
            typeProperties: {
              url: {
                #disable-next-line  no-hardcoded-env-urls
                value: '@concat(\'https://management.azure.com\',pipeline().globalParameters.adfId,\'/integrationRuntimes/self-hosted-runtime/getStatus?api-version=2018-06-01\')'
                type: 'Expression'
              }
              method: 'POST'
              headers: {}
              body: '""'
              authentication: {
                type: 'MSI'
                #disable-next-line  no-hardcoded-env-urls
                resource: 'https://management.azure.com/'
              }
            }
          }
          {
            name: 'Wait'
            type: 'Wait'
            dependsOn: []
            userProperties: []
            typeProperties: {
              waitTimeInSeconds: 30
            }
          }
        ]
        timeout: '0.12:00:00'
      }
    }
    {
      name: 'Start ACI'
      type: 'WebActivity'
      dependsOn: []
      policy: {
        timeout: '0.12:00:00'
        retry: 0
        retryIntervalInSeconds: 30
        secureOutput: false
        secureInput: false
      }
      userProperties: []
      typeProperties: {
        url: {
          #disable-next-line  no-hardcoded-env-urls
          value: '@concat(\'https://management.azure.com\',pipeline().globalParameters.aciId,\'/start?api-version=2022-09-01\')'
          type: 'Expression'
        }
        method: 'POST'
        headers: {}
        body: '""'
        authentication: {
          type: 'MSI'
          #disable-next-line  no-hardcoded-env-urls
          resource: 'https://management.azure.com/'
        }
      }
    }
  ]
  policy: {
    elapsedTimeMetric: {}
    // Data factory generated ARM/Bicep does not match with schemas
    #disable-next-line BCP037
    cancelAfter: {}
  }
  annotations: []
}
  dependsOn: []
}
