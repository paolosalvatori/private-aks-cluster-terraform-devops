output "name" {
  value       = azurerm_kubernetes_cluster.aks_cluster.name
  description = "Specifies the name of the AKS cluster."
}

output "id" {
  value       = azurerm_kubernetes_cluster.aks_cluster.id
  description = "Specifies the resource id of the AKS cluster."
}


output "principal_id" {
  value       = azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id
  description = "Specifies the principal id of the managed identity of the AKS cluster."
}

output "kube_config_raw" {
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config_raw
  description = "Contains the Kubernetes config to be used by kubectl and other compatible tools."
}

output "private_fqdn" {
  value       = azurerm_kubernetes_cluster.aks_cluster.private_fqdn
  description = "The FQDN for the Kubernetes Cluster when private link has been enabled, which is only resolvable inside the Virtual Network used by the Kubernetes Cluster."
}

output "node_resource_group" {
  value       = azurerm_kubernetes_cluster.aks_cluster.node_resource_group
  description = "Specifies the resource id of the auto-generated Resource Group which contains the resources for this Managed Kubernetes Cluster."
}