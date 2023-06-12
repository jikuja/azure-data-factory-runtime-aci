> :warning: :warning: :warning: :warning: :warning:
> 
> Before deploying this to any public or multi-user environment please read [Security](#Security) section.

# Azure Data Factory self-hosted integration runtime in Azure Container Instances(ACI) service

This sample illustrates how to host an [Azure Data Factory self-hosted integration runtime](https://docs.microsoft.com/azure/data-factory/concepts-integration-runtime) in Azure Container Instances service.

By using this approach, you can gain the benefits of 
* using a self-hosted integration runtime while avoiding having to manage virtual machines or other infrastructure
* orchestrating ACI up and down when needed

## Related work

* This sample is fork from [https://github.com/Azure-Samples/azure-data-factory-runtime-app-service](https://github.com/Azure-Samples/azure-data-factory-runtime-app-service)

## Approach and architecture

This sample runs the self-hosted integration in a Windows container on ACI. Azure Data Factory [supports running a self-hosted integration runtime on Windows containers](https://docs.microsoft.com/azure/data-factory/how-to-run-self-hosted-integration-runtime-in-windows-container), and [they provide a GitHub repository](https://github.com/Azure/Azure-Data-Factory-Integration-Runtime-in-Windows-Container) with a Dockerfile and associated scripts. Azure Container Registry builds the Dockerfile by using [ACR tasks](https://docs.microsoft.com/azure/container-registry/container-registry-tasks-overview).

The ACI uses [VNet integration](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-vnet) to connect to a virtual network. This means that the self-hosted integration runtime can [connect to Data Factory by using a private endpoint](https://docs.microsoft.com/azure/data-factory/data-factory-private-link), and it can also access servers and other resources that are accessible thorugh the virtual network.

To illustrate the end-to-end flow, the sample deploys an example Data Factory pipelines which
* starts ACI and polls integration runtime(IR) status until IR is available 
* connects to a web server on a virtual machine by using a private IP address.

### Architecture diagram

![Architecture diagram](architecture-diagram.png)

These are the data flows used by the solution:

1. When the ACI starts, ACI pulls the container image from the container registry.
    - The ACI ACR's admin credentials to pull the image. This has been selected to simplify the demo.
1. After the container is started, the self-hosted integration runtime loads. It connects to the data factory by using a private endpoint.
1. When the data factory's pipeline runs, the self-hosted integration runtime accesses the web server on the virtual machine.

## Deploy and test the sample

The entire deployment is defined as a Bicep file, with a series of modules to deploy each part of the solution.

To run the deployment, first create a resource group, such as by using the following Azure CLI command:

```azurecli
az group create \
  --name SHIR \
  --location australiaeast
```

Next, initiate the deployment of the Bicep file. The only mandatory parameter is `vmAdminPassword`, which must be set to a value that conforms to the password naming rules for virtual machines. The following Azure CLI command initiates the deployment:

```azurecli
az deployment group create \
  --resource-group SHIR \
  --template-file deploy/main.bicep \
  --parameters 'vmAdminPassword=<YOUR-VM-ADMIN-PASSWORD>' ['irNodeExpirationTime=<TIME-IN-SECONDS>']
```

where the optional parameter `irNodeExpirationTime` specifies the time in seconds when the offline nodes expire after App Service stops or restarts. The expired nodes will be removed automatically during next restarting. The minimum expiration time, as well as the default value, is 600 seconds (10 minutes).

The deployment takes approximately 30-45 minutes to complete. The majority of this time is the step to build the container image within Azure Container Registry.

After the deployment completes, wait about another 10-15 minutes for App Service to deploy the container image. You can monitor the progress of this step by using the Deployment Center page on the App Service app resource in the Azure portal.

To test the deployment when it's completed:

1. Open the Azure portal, navigate to the resource group (named *SHIR* by default), and open the data factory.
1. Select **Open Azure Data Factory Studio**. A separate page opens up in your browser.
1. On the left navigation bar, select **Manage**, and then select **Integration runtimes**. Look at the **self-hosted-runtime** item. The status should show as *Available*. If it says *Unavailable*, it probably means the container is still starting. Wait a few minutes and refresh the list.
1. On the left navigation bar, select **Author**.
1. TODO: refactor text for multiple pipelines:
  1. Under **Pipelines**, select **Start ACI**.
1. Under **Pipelines**, select **sample-pipeline**. The pipeline opens. There's a single task named *GetWebContent*.
1. On the toolbar, select **Debug** to start the pipeline running. The run appears in the bottom pane. Wait a few moments and select the refresh button on the bottom pane's toolbar.
1. The task shows the *Succeeded* status. This means the self-hosted integration runtime successfully connected to the web server on the virtual machine and accessed its data.

## Security

To simplify templating sensitive data is passed as module output values and in unsecured Bicep module inputs:
* Integration runtime key
* ACI admin username and password

To simplify templating ACI admin username and password are used instead instead of service principal:
* Linux container on ACI [support](https://learn.microsoft.com/en-us/azure/container-instances/using-azure-container-registry-mi)  ACI with MSI. Windows containers do not support MSI at all
* The recommended alternative login credentials for ACI is service principal:
  * [ACI documentation](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-using-azure-container-registry)
  * [ACR documentation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-auth-service-principal)
  * Conflicting [ACR documentation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-auth-aci) mentions usage of service principals only for ACI

Because of the template simplifications Azure deployment resource(s) will contain credentials on their outputs and therefore this template should not be used for production deployments.

### Proposed changes

To fix above-mentioned security related issues main.bicep and aci.bicep require some major refactoring.

**Template refactoring**
Templates should be refactored not to
* return sensitive data as module outputs
* not to pass sensitve data to unsecured module inputs

**ACI/ACR**
ACI/ACR has two potential fixes:
* Use recommended credential to pull images
  * service principals. This required refactoring to avoid unsecured module inputs
  * or wait for proper MSI support

Alternative approach is to continue using ACI admin username and password and refactor template not to pass credentials as module output and as unsecured module input.

Other alternative approach is to use [repository-scoped tokens](https://learn.microsoft.com/en-gb/azure/container-registry/container-registry-repository-scoped-permissions) with ACI

**ACI/ADF IR key**
This can be implemented with template refactoring. 

Implementation will be easier as soon as Bicep allows passing resources to/from modules.

## Note

In this sample, we use ACI to host the container because the other serverless/PaaS container hosting options in Azure don't support or support has limitations VNet integration with Windows containers (at least at the time of writing, June 2023).

App service is not really serverless: it is generating costs 24/7 as soon as `Microsoft.Web/serverfarms` is being deployed. Official app service [demo](https://github.com/Azure-Samples/azure-data-factory-runtime-app-service)

TODO: comments about AKS. New free tier allows running small Kubbernetes cluster with 24/7 cluster management cost. [(Released 02/2023)](https://techcommunity.microsoft.com/t5/apps-on-azure-blog/azure-kubernetes-service-free-tier-and-standard-tier/ba-p/3731432)

## TODO

* Test if ACI can pull images through a VNet-integrated container registry
* Refactor templating when Bicep support resources as module inputs and outputs
