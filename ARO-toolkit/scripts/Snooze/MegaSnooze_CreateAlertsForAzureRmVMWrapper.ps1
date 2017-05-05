
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


#---------Read all the input variables---------------
$SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
$ResourceGroupNames = Get-AutomationVariable -Name 'External_ResourceGroupNames'
$ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'
$AutomationAccountName = Get-AutomationVariable -Name 'Internal_AROAutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_AROResourceGroupName'

#-----Prepare the inputs for alert attributes-----
$webhookUri = Get-AutomationVariable -Name 'Internal_MegaSnooze_WebhookUri'

try
    {  
            Write-Output "Runbook Execution Started..."
            [string[]] $VMfilterList = $ExcludeVMNames -split ","
            [string[]] $VMRGList = $ResourceGroupNames -split ","

            #Validate the Exclude List VM's and stop the execution if the list contains any invalid VM
            if([string]::IsNullOrEmpty($ExcludeVMNames) -ne $true)
            {
                Write-Output "Exclude VM's added so validating the resource(s)..."
                $AzureVM= Get-AzureRmVM -ErrorAction SilentlyContinue
                [boolean] $ISexists = $false
            
                [string[]] $invalidvm=@()
                $ExAzureVMList=@()

                foreach($filtervm in $VMfilterList)
                {
                    foreach($vmname in $AzureVM)
                    {
                        if($Vmname.Name.ToLower().Trim() -eq $filtervm.Tolower().Trim())
                        {                    
                            $ISexists = $true
                            $ExAzureVMList+=$vmname
                            break                    
                        }
                        else
                        {
                            $ISexists = $false
                        }
                    }
                 if($ISexists -eq $false)
                 {
                    $invalidvm = $invalidvm+$filtervm
                 }
               }

               if($invalidvm -ne $null)
               {
                Write-Output "Runbook Execution Stopped! Invalid VM Name(s) in the exclude list: $($invalidvm) "
                Write-Warning "Runbook Execution Stopped! Invalid VM Name(s) in the exclude list: $($invalidvm) "
                exit
               }
             } 

            foreach($VM in $ExAzureVMList)
            {
                try
                {
                    $params = @{"VMObject"=$VM;"AlertAction"="Disable";"WebhookUri"=$webhookUri}                    
                    Start-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName -Name 'MegaSnooze_CreateOrDisableAlert' -ResourceGroupName $aroResourceGroupName –Parameters $params
                }
                catch
                {
                   $ex = $_.Exception
                   Write-Output $_.Exception 
                }
            }

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
                ##Checking Vm in excluded list                         
                if($VMfilterList -notcontains ($($VM.Name)))
                {

                    $params = @{"VMObject"=$VM;"AlertAction"="Create";"WebhookUri"=$webhookUri}                    
                    Start-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName -Name 'MegaSnooze_CreateOrDisableAlert' -ResourceGroupName $aroResourceGroupName –Parameters $params

                }
            }
            Write-Output "Runbook Execution Completed..."
    }
    catch
    {
        $ex = $_.Exception
        Write-Output $_.Exception
        #throw $ex
    }
