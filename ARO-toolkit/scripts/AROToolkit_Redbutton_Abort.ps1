<#
.SYNOPSIS  
 Disable the ARO Toolkit 
.DESCRIPTION  
 Disable the ARO Toolkit
.EXAMPLE  
.\AROToolkit_Redbutton_Abort.ps1 
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
    Write-Output "Performing AROToolkit Redbutton Abort..."

    Write-Output "Collecting all the schedule names for ScheduleSnooze and MegaSnooze..."

    #---------Read all the input variables---------------
    $SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
    $ResourceGroupNames = Get-AutomationVariable -Name 'External_ResourceGroupNames'
    $AutomationAccountName = Get-AutomationVariable -Name 'Internal_AROAutomationAccountName'
    $aroResourceGroupName = Get-AutomationVariable -Name 'Internal_AROResourceGroupName'

    #Schedules for ScheduleSnooze
    $scheduleStart = "ScheduleSnooze-StartVM"
    $scheduleStop = "ScheduleSnooze-StopVM"        

    Write-Output "Disabling the schedules for ScheduleSnooze..."

    #Disable the Schedules for ScheduleSnooze    
    Set-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleStart -ResourceGroupName $aroResourceGroupName -IsEnabled $false
    Set-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleStop -ResourceGroupName $aroResourceGroupName -IsEnabled $false

    Write-Output "Disabling the schedules & alerts for MegaSnooze..."

    #Disable the MegaSnooze by calling the MegaSnooze_Disable runbook
    Start-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName -Name 'MegaSnooze_Disable' -ResourceGroupName $aroResourceGroupName -Wait

    Write-Output "AROToolkit Redbutton Abort execution completed..."

}
catch
{
    Write-Output "Error Occurred on executing AROToolkit Redbutton Abort..."   
    Write-Output $_.Exception
}