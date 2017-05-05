<#
.SYNOPSIS  
 Bootstrap script for creating webhook
.DESCRIPTION  
 Bootstrap script for creating webhook for stopvm runbook
.EXAMPLE  
.\Bootstrap_CreateStopVMWebhook.ps1 -AzureLoginUserName "Value1" -AzureLoginPassword "Value2" -ResourceGroupName "Value3" -AutomationAccountName "Value4" -RunbookName "Value5" -WebhookName "Value6" -SubscriptionId "Value7"
Version History  
v1.0   - redmond\balas - Initial Release  
#>
Param (
 [String]$AzureLoginUserName = $(throw "Value for AzureLoginUserName is missing"),
 
 [String]$AzureLoginPassword = $(throw "Value for AzureLoginPassword is missing"),
 
 [String] $ResourceGroupName = $(throw "Value for ResourceGroupName is missing"),

 [String] $AutomationAccountName = $(throw "Value for AutomationAccountName is missing"),

 [String] $RunbookName = $(throw "Value for RunbookName is missing"),

 [String] $WebhookName = $(throw "Value for WebhookName is missing"),

 [String] $SubscriptionId = $(throw "Value for SubscriptionId is missing")
)

try
{
    Write-Output "Webhook Creation started..."
    #-----L O G I N - A U T H E N T I C A T I O N-----
    <#
$connectionName = "AzureRunAsConnection"
    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

        "Logging in to Azure..."
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    catch 
    {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }#>
    Write-Output "Successfully logged into Azure Subscription..."

    [String] $WebhookUriVariableName ="Internal_MegaSnooze_WebhookUri"

    $ExpiryTime = (Get-Date).AddDays(730)

    Write-Output "Creating the Webhook ($($WebhookName)) for the Runbook ($($RunbookName))..."
    $Webhookdata = New-AzureRmAutomationWebhook -Name $WebhookName -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -RunbookName $RunbookName -IsEnabled $true -ExpiryTime $ExpiryTime -Force
    Write-Output "Successfully created the Webhook ($($WebhookName)) for the Runbook ($($RunbookName))..."
    
    $ServiceUri = $Webhookdata.WebhookURI

    Write-Output "Webhook Uri [$($ServiceUri)]"

    Write-Output "Creating the Assest Variable ($($WebhookUriVariableName)) in the Automation Account ($($AutomationAccountName)) to store the Webhook URI..."
    New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -Name $WebhookUriVariableName -Encrypted $False -Value $ServiceUri -ResourceGroupName $ResourceGroupName
    Write-Output "Successfully created the Assest Variable ($($WebhookUriVariableName)) in the Automation Account ($($AutomationAccountName)) and Webhook URI value updated..."

    Write-Output "Webhook Creation completed..."
}
catch
{
    Write-Output "Error Occurred..."   
    Write-Output $_.Exception
}