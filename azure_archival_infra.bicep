targetScope = 'resourceGroup'

@description('Name of the Cosmos DB account')
param cosmosDbAccountName string = 'billing-cosmosdb'

@description('Name of the Cosmos DB database')
param cosmosDbDatabaseName string = 'BillingDB'

@description('Name of the Cosmos DB container')
param cosmosDbContainerName string = 'BillingRecords'

@description('Name of the storage account for archived records')
param storageAccountName string = 'billingarchive${uniqueString(resourceGroup().id)}'

@description('Name of the blob container')
param blobContainerName string = 'billing-archive'

@description('Name of the Azure Function app')
param functionAppName string = 'billing-archive-fn'

@description('Location for all resources')
param location string = resourceGroup().location

// Cosmos DB Account
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDbAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

// Cosmos DB Database
resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  name: '${cosmosDbAccount.name}/${cosmosDbDatabaseName}'
  properties: {
    resource: {
      id: cosmosDbDatabaseName
    }
  }
  dependsOn: [cosmosDbAccount]
}

// Cosmos DB Container
resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  name: '${cosmosDbAccount.name}/${cosmosDbDatabase.name}/${cosmosDbContainerName}'
  properties: {
    resource: {
      id: cosmosDbContainerName
      partitionKey: {
        paths: ['/partitionKey']
        kind: 'Hash'
      }
    }
  }
  dependsOn: [cosmosDbDatabase]
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

// Blob Container
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/${blobContainerName}'
  dependsOn: [storageAccount]
}

// Azure Function App Hosting Plan (Consumption)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

// Azure Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageAccount.properties.primaryEndpoints.blob
        }
        {
          name: 'COSMOS_URL'
          value: cosmosDbAccount.properties.documentEndpoint
        }
        // Additional keys like COSMOS_KEY, etc., should be added via Key Vault or manually
      ]
    }
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [hostingPlan, storageAccount]
}
