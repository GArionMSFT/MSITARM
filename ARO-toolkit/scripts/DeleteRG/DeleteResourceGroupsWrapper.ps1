<#
.SYNOPSIS  
 Script for deleting the resource groups
.DESCRIPTION  
 Script for deleting the resource groups
.EXAMPLE  
.\DeleteResourceGroupsWrapper.ps1 
Version History  
v1.0   - redmond\balas - Initial Release  
#>

Param(
    [String]$RGNames
)
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
    [string[]] $VMRGList = $RGNames -split ","
    $AutomationAccountName = Get-AutomationVariable -Name 'Internal_AROAutomationAccountName'
    $aroResourceGroupName = Get-AutomationVariable -Name 'Internal_AROResourceGroupName'


    if($VMRGList -ne $null)
    {
        foreach($Resource in $VMRGList)
        {
            $checkRGname = Get-AzureRmResourceGroup  $Resource.Trim() -ev notPresent -ea 0  
            if ($checkRGname -eq $null)
            {
                Write-Warning "$($Resource) is not a valid Resource Group Name. Please Verify!"
            }
            else
            {  
                Write-Output "Calling the child runbook DeleteRG to delete the resource group $($Resource)..."
                $params = @{"RGName"=$Resource}                  
                Start-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $aroResourceGroupName -Name "DeleteRG" -Parameters $params
            }
        }
        write-output "Execution Completed"
    }
    else
    {
        Write-Output "Resource Group Name is empty..."
    } 
    
}
catch
{
    Write-Output "Error Occurred..."
    Write-Output $_.Exception
}
