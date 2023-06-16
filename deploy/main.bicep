@description('The location into which the Azure resources should be deployed.')
param location string = resourceGroup().location

@description('The name of the container registry to create. This must be globally unique.')
param containerRegistryName string = 'shir${uniqueString(resourceGroup().id)}'

@description('The name of the virtual network to create.')
param vnetName string = 'shirdemo'

@description('The name of the data factory to create. This must be globally unique.')
param dataFactoryName string = 'shirdemo${uniqueString(resourceGroup().id)}'

@description('The port for nodes remote access.')
param irNodeRemoteAccessPort int = 8060

@description('The expiration time of the offline nodes in seconds. The value should not be less than 600.')
param irNodeExpirationTime int = 600

@description('The name of the SKU to use when creating the virtual machine.')
param vmSize string = 'Standard_DS1_v2'

@description('The type of disk and storage account to use for the virtual machine\'s OS disk.')
param vmOSDiskStorageAccountType string = 'StandardSSD_LRS'

@description('The administrator username to use for the virtual machine.')
param vmAdminUsername string = 'shirdemoadmin'

@description('The administrator password to use for the virtual machine.')
@secure()
param vmAdminPassword string

@description('The name of ACI to create. This must be globally unique.')
param aciName string = 'shir${uniqueString(resourceGroup().id)}'

@description('Trigger buildTask')
param triggerBuildTask bool = true

// Deploy the container registry and build the container image.
module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    name: containerRegistryName
    location: location
    triggerBuildTask: triggerBuildTask
  }
}

// Deploy a virtual network with the subnets required for this solution.
module vnet 'modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    name: vnetName
    location: location
  }
}

// Deploy a virtual machine with a private web server.
var vmImageReference = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2019-Datacenter'
  version: 'latest'
}

module vm 'modules/vm.bicep' = {
  name: 'vm'
  params: {
    location: location
    subnetResourceId: vnet.outputs.vmSubnetResourceId
    vmSize: vmSize
    vmImageReference: vmImageReference
    vmOSDiskStorageAccountType: vmOSDiskStorageAccountType
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
  }
}

// Deploy the data factory.
// ADF will be on non-working state until globals are being deployed
module adf 'modules/data-factory.bicep' = {
  name: 'adf'
  params: {
    dataFactoryName: dataFactoryName
    location: location
    virtualNetworkName: vnet.outputs.virtualNetworkName
    dataFactorySubnetResourceId: vnet.outputs.dataFactorySubnetResourceId
  }
}

// Deploy ADF globals
// ACR and ACI has dependencies to adf => Globals are missing during deployment
module dataFactoryGlobals 'modules/data-factory-globals.bicep' = {
  name: 'adf-globals'
  params: {
    aciId: aci.outputs.resourceId
    adfName: dataFactoryName
  }
}

// Deploy a Data Factory pipelines:
// * to start ACI
// * to connect to the private web server on the VM.
module dataFactoryPipeline 'modules/data-factory-pipeline.bicep' = {
  name: 'adf-pipeline'
  params: {
    dataFactoryName: adf.outputs.dataFactoryName
    integrationRuntimeName: adf.outputs.integrationRuntimeName
    virtualMachinePrivateIPAddress: vm.outputs.virtualMachinePrivateIPAddress
  }
}


var image = '${acr.outputs.containerRegistryName}.azurecr.io/${acr.outputs.containerImageName}:${acr.outputs.containerImageTag}'

// TODO: how to deploy without assigning ports twice?
module aci 'modules/aci.bicep' = {
  name: 'aci'
  params: {
    name: aciName
    location: location
    // Fails if enabled: 'Managed service identity is not supported for Windows container groups.'
    systemAssignedIdentity: false
    ipAddressType: 'Private'
    subnetId: vnet.outputs.aciSubnetResourceId
    ipAddressPorts: [
      {
        port: 80
        protocol: 'Tcp'
      }
      {
        port: 443
        protocol: 'Tcp'
      }
    ]
    osType: 'Windows'
    restartPolicy: 'OnFailure'
    sku: 'Standard'

    irNodeRemoteAccessPort: irNodeRemoteAccessPort
    irNodeExpirationTime: irNodeExpirationTime
    image: image
    ir: adf.outputs.ir
    acr: acr.outputs.acr
  }
}

module adfRoleAssignments 'modules/data-factory-role-assingments.bicep' = {
  name: 'adfRoleAssignments'
  params: {
    aciName:  aciName
    adfMsiId: adf.outputs.msiId
    adfName: dataFactoryName
  }
  dependsOn: [
    adf
    aci
  ]
}
