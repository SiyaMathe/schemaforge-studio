// =============================================================================
// SchemaForge Studio — Azure Infrastructure
// Provisions: Azure SQL Server + Database, App Service Plan + Web App,
//             Application Insights, Log Analytics Workspace
// =============================================================================

targetScope = 'resourceGroup'

@description('Environment: dev | staging | production')
@allowed(['dev', 'staging', 'production'])
param environment string = 'dev'

@description('Azure region')
param location string = resourceGroup().location

@description('SQL Server admin password')
@secure()
param sqlAdminPassword string

@description('SQL Server admin login')
param sqlAdminLogin string = 'sqladmin'

var prefix       = 'schemaforge-${environment}'
var uniqueSuffix = uniqueString(resourceGroup().id)

// ── Log Analytics ─────────────────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name:     '${prefix}-logs'
  location: location
  properties: {
    sku:             { name: 'PerGB2018' }
    retentionInDays: environment == 'production' ? 90 : 30
  }
}

// ── Application Insights ──────────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name:     '${prefix}-insights'
  location: location
  kind:     'web'
  properties: {
    Application_Type:  'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ── Azure SQL Server ──────────────────────────────────────────────────────────
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name:     '${prefix}-sql-${uniqueSuffix}'
  location: location
  properties: {
    administratorLogin:         sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion:          '1.2'
  }
}

resource sqlFirewall 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  name:   'AllowAzureServices'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress:   '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  name:     'KhulisaCommerce'
  parent:   sqlServer
  location: location
  sku: {
    name: environment == 'production' ? 'S2' : 'S0'
    tier: 'Standard'
  }
  properties: {
    collation:     'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes:  environment == 'production' ? 53687091200 : 2147483648
    zoneRedundant: environment == 'production'
  }
}

// ── App Service Plan ──────────────────────────────────────────────────────────
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name:     '${prefix}-plan'
  location: location
  sku: {
    name: environment == 'production' ? 'P1v3' : 'B1'
    tier: environment == 'production' ? 'PremiumV3' : 'Basic'
  }
}

// ── Web App (KhulisaQuery REST API) ───────────────────────────────────────────
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name:     '${prefix}-api-${uniqueSuffix}'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name:  'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name:  'ConnectionStrings__KhulisaCommerce'
          value: 'Server=${sqlServer.properties.fullyQualifiedDomainName};Database=KhulisaCommerce;User Id=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;'
        }
        {
          name:  'ASPNETCORE_ENVIRONMENT'
          value: environment == 'production' ? 'Production' : 'Staging'
        }
      ]
      ftpsState:      'Disabled'
      minTlsVersion:  '1.2'
    }
    httpsOnly: true
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output webAppName       string = webApp.name
output webAppUrl        string = 'https://${webApp.properties.defaultHostName}'
output sqlServerFqdn    string = sqlServer.properties.fullyQualifiedDomainName
output appInsightsKey   string = appInsights.properties.InstrumentationKey
output swaggerUrl       string = 'https://${webApp.properties.defaultHostName}/swagger'
