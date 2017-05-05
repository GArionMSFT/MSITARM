<#
.SYNOPSIS  
 Disable MegaSnooze feature
.DESCRIPTION  
 Disable MegaSnooze feature
.EXAMPLE  
.\MegaSnooze_Disable.ps1 
Version History  
v1.0   - redmond\balas - Initial Release  
#>

#-----L O G I N - A U T H E N T I C A T I O N-----
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
}
try
{
    #---------Read all the input variables---------------
    $SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
    $ResourceGroupNames = Get-AutomationVariable -Name 'External_ResourceGroupNames'
    $ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'
    $AutomationAccountName = Get-AutomationVariable -Name 'Internal_AROAutomationAccountName'
    $aroResourceGroupName = Get-AutomationVariable -Name 'Internal_AROResourceGroupName'

    $webhookUri = Get-AutomationVariable -Name 'Internal_MegaSnooze_WebhookUri'
    $scheduleNameforCreateAlert = "Schedule_MegaSnooze_CreateAlertsForAzureRmVMWrapper"

    #Disable the schedule    
    Set-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName -IsEnabled $false

    [string[]] $VMRGList = $ResourceGroupNames -split ","

    $AzureVMListTemp = $null
    $AzureVMList=@()
    ##Getting VM Details based on RG List or Subscription
    if($VMRGList -ne $null)
    {
        foreach($Resource in $VMRGList)
        {
            Write-Output "Validating the resource group name ($($Resource.Trim()))" 
            $checkRGname = Get-AzureRmResourceGroup  $Resource.Trim() -ev notPresent -ea 0  
            if ($checkRGname -eq $null)
            {
                Write-Warning "$($Resource) is not a valid Resource Group Name. Please Verify!"
            }
            else
            {                   
            $AzureVMListTemp = Get-AzureRmVM -ResourceGroupName $Resource -ErrorAction SilentlyContinue
            if($AzureVMListTemp -ne $null)
            {
                $AzureVMList+=$AzureVMListTemp
            }
            }
        }
    } 
    else
    {
        Write-Output "Getting all the VM's from the subscription..."  
        $AzureVMList=Get-AzureRmVM -ErrorAction SilentlyContinue
    }

    foreach($VM in $AzureVMList)
    {
        try
        {
            $params = @{"VMObject"=$VM;"AlertAction"="Disable";"WebhookUri"=$webhookUri}                    
            Start-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName -Name 'MegaSnooze_CreateOrDisableAlert' -ResourceGroupName $aroResourceGroupName –Parameters $params
        }
        catch
        {
            Write-Output "Error Occurred on Alert disable..."   
            Write-Output $_.Exception 
        }
    }

}
catch
{
    Write-Output "Error Occurred on MegaSnooze Disable Wrapper..."   
    Write-Output $_.Exception
}