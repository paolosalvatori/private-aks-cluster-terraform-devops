---
services: aks, container-registry, azure-monitor, storage, virtual-network, virtual-machines, private-link, templates, terraform, devops
author: paolosalvatori
---

# Create a private Azure Kubernetes Service cluster using Terraform and Azure DevOps #

This sample shows how to create a [private AKS clusters](https://docs.microsoft.com/en-us/azure/aks/private-clusters) with using:

- [Terraform](https://www.terraform.io/intro/index.html) as an infrastructure as code (IaC) tool to build, change, and version the infrastructure on Azure in a safe, repeatable, and efficient way. 
- [Azure DevOps Pipelines](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/what-is-azure-pipelines?view=azure-devops) to automate the deployment and undeployment of the entire infrastructure on multiple environments on the Azure platform.

In a private AKS cluster the API server endpoint is not exposed via a public IP address. Hence, to manage the API server, you will need to use a virtual machine that has access to the AKS cluster's Azure Virtual Network (VNet). This sample deploys a jumpbox virtual machine in the a hub virtual network peered with the virtual network that hosts the private AKS cluster. There are several options for establishing network connectivity to the private cluster.

- Create a virtual machine in the same Azure Virtual Network (VNet) as the AKS cluster.
- Use a virtual machine in a separate network and set up Virtual network peering. See the section below for more information on this option.
- Use an Express Route or VPN connection.

Creating a virtual machine in the same virtual network as the AKS cluster or in a peered virtual network is the easiest option. Express Route and VPNs add costs and require additional networking complexity. Virtual network peering requires you to plan your network CIDR ranges to ensure there are no overlapping ranges. For more information, see [Create a private Azure Kubernetes Service cluster](https://docs.microsoft.com/en-us/azure/aks/private-clusters). For more information on Azure Private Links, see [What is Azure Private Link?](https://docs.microsoft.com/en-us/azure/private-link/private-link-overview).

In addition, the sample creates a private endpoint to access all the managed services deployed by the Terraform modules via a private IP address and disable the public network access to these services: 

- Azure Container Registry
- Azure Storage Account
- Azure Key Vault

> **NOTE**  
> If you want to deploy a [private AKS cluster using a public DNS zone](https://docs.microsoft.com/en-us/azure/aks/private-clusters#create-a-private-aks-cluster-with-a-public-dns-address) to simplify the DNS resolution of the API Server to the private IP address of the private endpoint,  you can use this project under my [GitHub](https://github.com/paolosalvatori/private-cluster-with-public-dns-zone) account or on [Azure Quickstart Templates](https://github.com/Azure/azure-quickstart-templates/tree/master/demos/private-aks-cluster-with-public-dns-zone).

## Architecture ##

The following picture shows the architecture created by the Terraform modules included in this sample:

![Architecture](images/architecture.png)

The architecture is composed of the following elements:

- A hub virtual neywork with three subnets:
  - AzureBastionSubnet used by Azure Bastion
  - AzureFirewallSubnet used by Azure Firewall
  - JumpboxSubnet used by the jumpbox virtual machine and private endpoints
- A new virtual network with three subnets:
  - SystemSubnet used by the AKS system node pool
  - UserSubnet used by the AKS user node pool
- The private AKS cluster uses a user-defined managed identity to create additional resources like load balancers and managed disks in Azure.
- The private AKS cluster is composed of a:
  - System node pool hosting only critical system pods and services. The worker nodes have node taint which prevents application pods from beings scheduled on this node pool.
  - User node pool hosting user workloads and artifacts.
- An Azurer Firewall used to control the egress traffic from the private AKS cluster. For more information on how to lock down your private AKS cluster and filter outbound traffic, see: 
   - [Control egress traffic for cluster nodes in Azure Kubernetes Service (AKS)](https://docs.microsoft.com/en-us/azure/aks/limit-egress-traffic)
   - [Use Azure Firewall to protect Azure Kubernetes Service (AKS) Deployments](https://docs.microsoft.com/en-us/azure/firewall/protect-azure-kubernetes-service)
- An AKS cluster with a private endpoint to the control plane / API server hosted by an AKS-managed Azure subscription. The cluster can communicate with the API server exposed via a Private Link Service using a private endpoint.
- An Azure Bastion resource that provides secure and seamless SSH connectivity to the Jumpbox virtual machine directly in the Azure portal over SSL
- An Azure Container Registry (ACR) to build, store, and manage container images and artifacts in a private registry for all types of container deployments.
- When the ACR sku is equal to Premium, a Private Endpoint is created to allow the private AKS cluster to access ACR via a private IP address. For more information, see [Connect privately to an Azure container registry using Azure Private Link](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-private-link).
- A Private DNS Zone for the name resolution of each private endpoint.
- A Virtual Network Link between each Private DNS Zone and both the hub and AKS virtual networks
- A jumpbox virtual machine to manage the private AKS cluster in the hub virtual network
- A Log Analytics workspace to collect the diagnostics logs and metrics of both the AKS cluster and Jumpbox virtual machine.

## Requirements ##
There are some requirements you need to complete before we can deploy Terraform modules using Azure DevOps. 

- Store the Terraform state file to an Azure storage account. For more information on how to create to use a storage account to store remote Terraform state, state locking, and encryption at rest, see [Store Terraform state in Azure Storage](https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli)
- Create an Azure DevOps Project. For more information, see [Create a project in Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/organizations/projects/create-project?view=azure-devops&tabs=preview-page)
- Create an [Azure DevOps Service Connection](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints?view=azure-devops&tabs=yaml) to your Azure subscription. No matter you use Service Principal Authentication (SPA) or an Azure-Managed Service Identity when creating the service connection, make sure that the service principal or managed identity used by Azure DevOps to connect to your Azure subscription is assigned the owner role on the entire subscription.

## Terraform State ##
In order to deploy Terraform modules to Azure you can use Azure DevOps CI/CD pipelines. [Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/user-guide/what-is-azure-devops?view=azure-devops) provides developer services for support teams to plan work, collaborate on code development, and build and deploy applications and infrastructure components using IaC technologies such as ARM Templates, Bicep, and Terraform.

Terraform stores [state](https://www.terraform.io/docs/language/state/index.html) about your managed infrastructure and configuration in a special file called state file. This state is used by Terraform to map real world resources to your configuration, keep track of metadata, and to improve performance for large infrastructures. Terraform state is used to reconcile deployed resources with Terraform configurations. When using Terraform to deploy Azure resources, the state allows Terraform to know what Azure resources to add, update, or delete. By default, Terraform state is stored in a local file named "terraform.tfstate", but it can also be stored remotely, which works better in a team environment. Storing the state in a local file isn't ideal for the following reasons:

- Local state doesn't work well in a team or collaborative environment.
- Terraform state can include sensitive information.
- Storing state locally increases the chance of inadvertent deletion.

Each Terraform configuration can specify a [backend](https://www.terraform.io/docs/language/settings/backends/index.html), which defines where and how operations are performed, where [state](https://www.terraform.io/docs/language/state/index.html) snapshots are stored. The [Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) or **azurerm** can be used to configure infrastructure in Microsoft Azure using the Azure Resource Manager API's. Terraform provides a [backend](https://www.terraform.io/docs/language/settings/backends/azurerm.html) for the Azure Provider that allows to store the state as a Blob with the given Key within a given Blob Container inside a Blob Storage Account. This backend also supports state locking and consistency checking via native capabilities of Azure Blob Storage. [](https://www.terraform.io/docs/language/settings/backends/azurerm.html) When using Azure DevOps to deploy services to a cloud environment, you should use this backend to store the state to a remote storage account. For more information on how to create to use a storage account to store remote Terraform state, state locking, and encryption at rest, see [Store Terraform state in Azure Storage](https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli). Under the [storage-account](./storage-account) folder in this sample you can find a Terraform module and bash script to deploy an Azure storage account where you can persist the Terraform state as a blob. 

## Variable Groups ##
The [key-vault](./key-vault) folder contains a bash script that uses Azure CLI to store the following data to an Azure Key Vault. This sensitive data will be used by Azure DevOps CD pipelines via [variable groups](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups?view=azure-devops&tabs=yaml). Variable groups store values and secrets that you want pass into a YAML pipeline or make available across multiple pipelines. You can share use variables groups in multiple pipelines in the same project. You can Link an existing Azure key vault to a variable group and map selective vault secrets to the variable group. You can link an existing Azure Key Vault to a variable group and select which secrets you want to expose as variables in the variable group. For more information, see [Link secrets from an Azure Key Vault](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups?view=azure-devops&tabs=yaml#link-secrets-from-an-azure-key-vault).

The YAML pipelines in this sample use a variable group shown in the following picture:

![Variable Group](images/variable-group.png)

The variable group is configured to use the following secrets from an existing Key Vault:

- **terraformBackendContainerName**: name of the blob container holding the Terraform remote state
- **terraformBackendResourceGroupName**: resource group name of the storage account that contains the Terraform remote state
- **terraformBackendStorageAccountKey**: key of the storage account that contains the Terraform remote state
- **terraformBackendStorageAccountName**: name of the storage account that contains the Terraform remote state
- **sshPublicKey**: key used by Terraform to configure the SSH public key for the administrator user of the virtual machine and AKS worker nodes

## Azure DevOps Pipelines ##
You can use Azure DevOps YAML pipelines to deploy resources to the target environment. Pipelines are part of the same Git repo that contains the artifacts such as Terraform modules and scripts and as such pipelines can be versioned as any other file in the Git reppsitory. You can follow a pull-request process to ensure changes are verified and approved before being merged. The following picture shows the key concepts of an Azure DevOps pipeline.

![Pipeline](images/pipeline.png)

- A [trigger](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#trigger) tells a Pipeline to run.
- A [pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#pipeline) is made up of one or more [stages](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#stage). A [pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#pipeline) can deploy to one or more [environments](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#environment).
- A [stage](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#stage) is a way of organizing [jobs](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#job) in a pipeline and each stage can have one or more jobs.
- Each [job](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#job) runs on one [agent](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#agent). A job can also be agentless.
- Each [agent](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#agent) runs a job that contains one or more [steps](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#step).
- A step[https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#step] can be a task[https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#task] or script[https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#script] and is the smallest building block of a pipeline.
- A [task](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#task) is a pre-packaged script that performs an action, such as invoking a REST API or publishing a build artifact.
- An [artifact](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops#artifact) is a collection of files or packages published by a run.

For more information on Azure DevOps pipelines, see: 

- [What is Azure Pipelines?](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started/what-is-azure-pipelines?view=azure-devops#:~:text=Azure%20Pipelines%20automatically%20builds%20and,ship%20it%20to%20any%20target.)
- [Add stages, dependencies, & conditions](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/stages?view=azure-devops&tabs=yaml)
- [Specify jobs in your pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/phases?view=azure-devops&tabs=yaml)

This sample provides three pipelines to deploy the infrastructure using Terraform modules, and one to undeploy the infrastructure. 

- **cd-validate-plan-apply-one-stage-tfvars**: in Terraform, to set a large number of variables, you can specify their values in a variable definitions file (with a filename ending in either `.tfvars` or `.tfvars.json`) and then specify that file on the command line with a `-var-file` parameter. For more information, see [Input Variables](https://www.terraform.io/docs/language/values/variables.html). The sample contains three different `.tfvars` files under the [tfvars](./tfvars) folder. Each file contains a different value for each variable and can be used to deploy the same infrastructure to three distinct environment: production, staging, and test.
- **cd-validate-plan-apply-one-stage-vars**: this pipeline specifies variable values for Terraform [plan](https://www.terraform.io/docs/cli/commands/plan.html) and [apply](https://www.terraform.io/docs/cli/commands/apply.html) commands with the `-var` command line option. For more information, see [Input Variables](https://www.terraform.io/docs/language/values/variables.html). 
- **cd-validate-plan-apply-separate-stages.yml**: this pipeline is composed of three distinct stages for [validate](https://www.terraform.io/docs/cli/commands/validate.html), [plan](https://www.terraform.io/docs/cli/commands/plan.html), and [apply](https://www.terraform.io/docs/cli/commands/apply.html). Each stage can be run separately.
- **destroy-deployment**: this pipeline uses the [destroy](https://www.terraform.io/docs/cli/commands/destroy.html) to fully remove the resource group and all the Azure resources.

## Terraform Extension for Azure DevOps ##
All the pipelines make use of the tasks of the [Terraform](https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks) extension. This extension provides the following components:

- A service connection for connecting to an Amazon Web Services(AWS) account
- A service connection for connecting to a Google Cloud Platform(GCP) account
- A task for installing a specific version of Terraform, if not already installed, on the agent
- A task for executing the core Terraform commands

The Terraform tool installer task acquires a specified version of [Terraform](https://www.terraform.io/) from the Internet or the tools cache and prepends it to the PATH of the Azure Pipelines Agent (hosted or private). This task can be used to change the version of Terraform used in subsequent tasks. Adding this task before the [Terraform task](https://github.com/microsoft/azure-pipelines-extensions/tree/master/Extensions/Terraform/Src/Tasks/TerraformTask/TerraformTaskV2) in a build definition ensures you are using that task with the right Terraform version.

The [Terraform task](https://github.com/microsoft/azure-pipelines-extensions/tree/master/Extensions/Terraform/Src/Tasks/TerraformTask/TerraformTaskV2) enables running Terraform commands as part of Azure Build and Release Pipelines providing support for the following Terraform commands

- [init](https://www.terraform.io/docs/cli/commands/init.html)
- [validate](https://www.terraform.io/docs/cli/commands/validate.html)
- [plan](https://www.terraform.io/docs/cli/commands/plan.html)
- [apply](https://www.terraform.io/docs/cli/commands/apply.html)
- [destroy](https://www.terraform.io/docs/cli/commands/destroy.html)

This extension is intended to run on Windows, Linux and MacOS agents. As an alternative, you can use the [Bash Task](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/utility/bash?view=azure-devops) or [PowerShell Task](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/utility/powershell?view=azure-devops) to install Terraform to the agent and run Terraform commands.

## Deployment ##
The following picture shows the resources deployed by the ARM template in the target resource group.

![Resource Group](images/resourcegroup.png)

The following picture shows the resources deployed by the ARM template in the MC resource group associated to the AKS cluster:

![MC Resource Group](images/mc_resourcegroup.png)

## Visio ##

In the [visio](./visio) folder you can find the Visio document which contains the above diagrams.

## Testing ##

If you open an ssh session to the Linux virtual machine via Azure Bastion and manually run the nslookup command using the FQND of the API server as a parameter, you should see an output like the the following:

![Architecture](images/nslookup.png)

**NOTE**: the Terraform module runs an [Azure Custom Script Extension](https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-linux) that installed the [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/) and [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/) on the jumpbox virtual machine.