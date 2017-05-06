<#
.SYNOPSIS  
 Bootstrap master script for pre-configuring Automation Account
.DESCRIPTION  
 Bootstrap master script for pre-configuring Automation Account
.EXAMPLE  
.\Bootstrap_Main.ps1 
Version History  
v1.0   - redmond\balas - Initial Release  
#>

function ValidateKeyVaultAndCreate([string] $keyVaultName, [string] $resourceGroup, [string] $KeyVaultLocation) 
{
   $GetKeyVault=Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
   if (!$GetKeyVault)
   {
     Write-Warning -Message "Key Vault $keyVaultName not found. Creating the Key Vault $keyVaultName"
     $keyValut=New-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroup -Location $keyVaultLocation
     if (!$keyValut) {
       Write-Error -Message "Key Vault $keyVaultName creation failed. Please fix and continue"
       return
     }
     $uri = New-Object System.Uri($keyValut.VaultUri, $true)
     $hostName = $uri.Host
     Start-Sleep -s 15     
     # Note: This script will not delete the KeyVault created. If required, please delete the same manually.
   }
 }

 function CreateSelfSignedCertificate([string] $keyVaultName, [string] $certificateName, [string] $selfSignedCertPlainPassword,[string] $certPath, [string] $certPathCer, [string] $noOfMonthsUntilExpired ) 
{
   $certSubjectName="cn="+$certificateName

   $Policy = New-AzureKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -SubjectName $certSubjectName  -IssuerName "Self" -ValidityInMonths $noOfMonthsUntilExpired -ReuseKeyOnRenewal
   $AddAzureKeyVaultCertificateStatus = Add-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -CertificatePolicy $Policy 
  
   While($AddAzureKeyVaultCertificateStatus.Status -eq "inProgress")
   {
     Start-Sleep -s 10
     $AddAzureKeyVaultCertificateStatus = Get-AzureKeyVaultCertificateOperation -VaultName $keyVaultName -Name $certificateName
   }
 
   if($AddAzureKeyVaultCertificateStatus.Status -ne "completed")
   {
     Write-Error -Message "Key vault cert creation is not sucessfull and its status is: $status.Status" 
   }

   $secretRetrieved = Get-AzureKeyVaultSecret -VaultName $keyVaultName -Name $certificateName
   $pfxBytes = [System.Convert]::FromBase64String($secretRetrieved.SecretValueText)
   $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
   $certCollection.Import($pfxBytes,$null,[System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
   
   #Export  the .pfx file 
   $protectedCertificateBytes = $certCollection.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12, $selfSignedCertPlainPassword)
   [System.IO.File]::WriteAllBytes($certPath, $protectedCertificateBytes)

   #Export the .cer file 
   $cert = Get-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName
   $certBytes = $cert.Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
   [System.IO.File]::WriteAllBytes($certPathCer, $certBytes)

   # Delete the cert after downloading
   $RemoveAzureKeyVaultCertificateStatus = Remove-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -PassThru -Force -ErrorAction SilentlyContinue -Confirm:$false
 }

 function CreateServicePrincipal([System.Security.Cryptography.X509Certificates.X509Certificate2] $PfxCert, [string] $applicationDisplayName) {  
   $CurrentDate = Get-Date
   $keyValue = [System.Convert]::ToBase64String($PfxCert.GetRawCertData())
   $KeyId = [Guid]::NewGuid() 

   $KeyCredential = New-Object  Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADKeyCredential
   $KeyCredential.StartDate = $CurrentDate
   $KeyCredential.EndDate= [DateTime]$PfxCert.GetExpirationDateString()
   $KeyCredential.KeyId = $KeyId
   $KeyCredential.CertValue  = $keyValue

   # Use Key credentials and create AAD Application
   $Application = New-AzureRmADApplication -DisplayName $ApplicationDisplayName -HomePage ("http://" + $applicationDisplayName) -IdentifierUris ("http://" + $KeyId) -KeyCredentials $KeyCredential

   $ServicePrincipal = New-AzureRMADServicePrincipal -ApplicationId $Application.ApplicationId 
   $GetServicePrincipal = Get-AzureRmADServicePrincipal -ObjectId $ServicePrincipal.Id

   # Sleep here for a few seconds to allow the service principal application to become active (should only take a couple of seconds normally)
   Sleep -s 15

   $NewRole = $null
   $Retries = 0;
   While ($NewRole -eq $null -and $Retries -le 6)
   {
      New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId | Write-Verbose -ErrorAction SilentlyContinue
      Sleep -s 10
      $NewRole = Get-AzureRMRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
      $Retries++;
   }

   return $Application.ApplicationId.ToString();
 }

 function CreateAutomationCertificateAsset ([string] $resourceGroup, [string] $automationAccountName, [string] $certifcateAssetName,[string] $certPath, [string] $certPlainPassword, [Boolean] $Exportable) {
   $CertPassword = ConvertTo-SecureString $certPlainPassword -AsPlainText -Force   
   Remove-AzureRmAutomationCertificate -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Name $certifcateAssetName -ErrorAction SilentlyContinue
   New-AzureRmAutomationCertificate -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Path $certPath -Name $certifcateAssetName -Password $CertPassword -Exportable:$Exportable  | write-verbose
 }

 function CreateAutomationConnectionAsset ([string] $resourceGroup, [string] $automationAccountName, [string] $connectionAssetName, [string] $connectionTypeName, [System.Collections.Hashtable] $connectionFieldValues ) {
   Remove-AzureRmAutomationConnection -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Name $connectionAssetName -Force -ErrorAction SilentlyContinue
   New-AzureRmAutomationConnection -ResourceGroupName $ResourceGroup -AutomationAccountName $automationAccountName -Name $connectionAssetName -ConnectionTypeName $connectionTypeName -ConnectionFieldValues $connectionFieldValues 
 }


try
{
    Write-Output "Bootstrap main script execution started..."

    Write-Output "Reading the credentials..."

    #---------Read the Credentials variable---------------
    $myCredential = Get-AutomationPSCredential -Name 'AzureCredentials'
    $AzureLoginUserName = $myCredential.UserName
    $securePassword = $myCredential.Password
    $AzureLoginPassword = $myCredential.GetNetworkCredential().Password

    #---------Inputs variables for NewRunAsAccountCertKeyVault.ps1 child bootstrap script--------------
    $AutomationAccountName = Get-AutomationVariable -Name 'Internal_AROAutomationAccountName'
    $SubscriptionId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
    $aroResourceGroupName = Get-AutomationVariable -Name 'Internal_AROResourceGroupName'
    
    #++++++++++++++++++++++++STEP 1 execution starts++++++++++++++++++++++++++
    
    #In Step 1 we are creating keyvault to generate cert and creating runas account...

    Write-Output "Executing Step-1 : Create the keyvault certificate and connection asset..."
    
    Write-Output "RunAsAccount Creation Started..."

    try
     {
        Write-Output "Logging into Azure Subscription..."
    
        #-----L O G I N - A U T H E N T I C A T I O N-----
        $secPassword = ConvertTo-SecureString $AzureLoginPassword -AsPlainText -Force
        $AzureOrgIdCredential = New-Object System.Management.Automation.PSCredential($AzureLoginUserName, $secPassword)
        Login-AzureRmAccount -Credential $AzureOrgIdCredential
        Get-AzureRmSubscription -SubscriptionId $SubscriptionId | Select-AzureRmSubscription
        Write-Output "Successfully logged into Azure Subscription..."

        $AzureRMProfileVersion= (Get-Module AzureRM.Profile).Version
        if (!(($AzureRMProfileVersion.Major -ge 2 -and $AzureRMProfileVersion.Minor -ge 1) -or ($AzureRMProfileVersion.Major -gt 2)))
        {
            Write-Error -Message "Please install the latest Azure PowerShell and retry. Relevant doc url : https://docs.microsoft.com/en-us/powershell/azureps-cmdlets-docs/ "
            return
        }
     
        [String] $ApplicationDisplayName="$($AutomationAccountName)App1"
        [Boolean] $CreateClassicRunAsAccount=$false
        [String] $SelfSignedCertPlainPassword = [Guid]::NewGuid().ToString().Substring(0,8)+"!" 
        [String] $KeyVaultName="KeyVault"+ [Guid]::NewGuid().ToString().Substring(0,5)        
        [int] $NoOfMonthsUntilExpired = 36
    
        $RG = Get-AzureRmResourceGroup -Name $aroResourceGroupName 
        $KeyVaultLocation = $RG[0].Location
 
        # Create Run As Account using Service Principal
        $CertifcateAssetName = "AzureRunAsCertificate"
        $ConnectionAssetName = "AzureRunAsConnection"
        $ConnectionTypeName = "AzureServicePrincipal"
 
        Write-Output "Creating Keyvault for generating cert..."
        ValidateKeyVaultAndCreate $KeyVaultName $aroResourceGroupName $KeyVaultLocation

        $CertificateName = $AutomationAccountName+$CertifcateAssetName
        $PfxCertPathForRunAsAccount = Join-Path $env:TEMP ($CertificateName + ".pfx")
        $PfxCertPlainPasswordForRunAsAccount = $SelfSignedCertPlainPassword
        $CerCertPathForRunAsAccount = Join-Path $env:TEMP ($CertificateName + ".cer")

        Write-Output "Generating the cert using Keyvault..."
        CreateSelfSignedCertificate $KeyVaultName $CertificateName $PfxCertPlainPasswordForRunAsAccount $PfxCertPathForRunAsAccount $CerCertPathForRunAsAccount $NoOfMonthsUntilExpired


        Write-Output "Creating service principal..."
        # Create Service Principal
        $PfxCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($PfxCertPathForRunAsAccount, $PfxCertPlainPasswordForRunAsAccount)
        $ApplicationId=CreateServicePrincipal $PfxCert $ApplicationDisplayName

        Write-Output "Creating Certificate in the Asset..."
        # Create the automation certificate asset
        CreateAutomationCertificateAsset $aroResourceGroupName $AutomationAccountName $CertifcateAssetName $PfxCertPathForRunAsAccount $PfxCertPlainPasswordForRunAsAccount $true

        # Populate the ConnectionFieldValues
        $SubscriptionInfo = Get-AzureRmSubscription -SubscriptionId $SubscriptionId
        $TenantID = $SubscriptionInfo | Select TenantId -First 1
        $Thumbprint = $PfxCert.Thumbprint
        $ConnectionFieldValues = @{"ApplicationId" = $ApplicationId; "TenantId" = $TenantID.TenantId; "CertificateThumbprint" = $Thumbprint; "SubscriptionId" = $SubscriptionId} 

        Write-Output "Creating Connection in the Asset..."
        # Create a Automation connection asset named AzureRunAsConnection in the Automation account. This connection uses the service principal.
        CreateAutomationConnectionAsset $aroResourceGroupName $AutomationAccountName $ConnectionAssetName $ConnectionTypeName $ConnectionFieldValues

        Write-Output "RunAsAccount Creation Completed..."

        Write-Output "Completed Step-1 ..."
     
     }
     catch
     {
        Write-Output "Error Occurred on Step-1..."   
        Write-Output $_.Exception

     }

    #++++++++++++++++++++++++STEP 1 execution ends++++++++++++++++++++++++++

    #=======================STEP 2 execution starts===========================

    #In Step 2 we are creating webhook for StopAzureRmVM runbook...

    #---------Inputs variables for Webhook creation--------------
    $runbookNameforStopVM = "MegaSnooze_StopAzureRmVM"
    $webhookNameforStopVM = "MegaSnooze_StopAzureRmVMWebhook"

    Write-Output "Executing Step-2 : Create the webhook for $($runbookNameforStopVM)..."
    
    try
    {
        [String] $WebhookUriVariableName ="Internal_MegaSnooze_WebhookUri"

        $ExpiryTime = (Get-Date).AddDays(730)

        Write-Output "Creating the Webhook ($($webhookNameforStopVM)) for the Runbook ($($runbookNameforStopVM))..."
        $Webhookdata = New-AzureRmAutomationWebhook -Name $webhookNameforStopVM -AutomationAccountName $AutomationAccountName -ResourceGroupName $aroResourceGroupName -RunbookName $runbookNameforStopVM -IsEnabled $true -ExpiryTime $ExpiryTime -Force
        Write-Output "Successfully created the Webhook ($($webhookNameforStopVM)) for the Runbook ($($runbookNameforStopVM))..."
    
        $ServiceUri = $Webhookdata.WebhookURI

        Write-Output "Webhook Uri [$($ServiceUri)]"

        Write-Output "Creating the Assest Variable ($($WebhookUriVariableName)) in the Automation Account ($($AutomationAccountName)) to store the Webhook URI..."
        New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -Name $WebhookUriVariableName -Encrypted $False -Value $ServiceUri -ResourceGroupName $aroResourceGroupName
        Write-Output "Successfully created the Assest Variable ($($WebhookUriVariableName)) in the Automation Account ($($AutomationAccountName)) and Webhook URI value updated..."

        Write-Output "Webhook Creation completed..."

       Write-Output "Completed Step-2 ..."
    }
    catch
    {
        Write-Output "Error Occurred in Step-2..."   
        Write-Output $_.Exception
    }    

    #=======================STEP 2 execution ends=============================

    #***********************STEP 3 execution starts**********************************

    #In Step 3 we are creating schedules for MegaSnooze and disable it...
    try
    {

        Write-Output "Executing Step-3 : Create schedule for MegaSnooze_CreateAlertsForAzureRmVMWrapper runbook ..."    
    
        #---------Inputs variables for CreateScheduleforAlert.ps1 child bootstrap script--------------
        $runbookNameforCreateAlert = "MegaSnooze_CreateAlertsForAzureRmVMWrapper"
        $scheduleNameforCreateAlert = "Schedule_MegaSnooze_CreateAlertsForAzureRmVMWrapper"

        #-----Configure the Start & End Time----
        $StartTime = (Get-Date).AddMinutes(10)
        $EndTime = $StartTime.AddYears(1)

        #----Set the schedule to run every 8 hours---
        $Hours = 8

        #---Create the schedule at the Automation Account level--- 
        Write-Output "Creating the Schedule ($($scheduleNameforCreateAlert)) in Automation Account ($($AutomationAccountName))..."
        New-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName -StartTime $StartTime -ExpiryTime $EndTime -HourInterval $Hours

        #Disable the schedule    
        Set-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName -IsEnabled $false
    
        Write-Output "Successfully created the Schedule ($($scheduleNameforCreateAlert)) in Automation Account ($($AutomationAccountName))..."

        #---Link the schedule to the runbook--- 
        Write-Output "Registering the Schedule ($($scheduleNameforCreateAlert)) in the Runbook ($($runbookNameforCreateAlert))..."
        Register-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -Name $runbookNameforCreateAlert -ScheduleName $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName
        Write-Output "Successfully Registered the Schedule ($($scheduleNameforCreateAlert)) in the Runbook ($($runbookNameforCreateAlert))..."
    
        Write-Output "Completed Step-3 ..."
    }
    catch
    {
        Write-Output "Error Occurred in Step-3..."   
        Write-Output $_.Exception
    }

    #***********************STEP 3 execution ends**********************************

    #-------------------STEP 4 (Bootstrap_CreateScheduleForARMVMOptimizationWrapper) execution starts---------------------

    #In Step 4 we are creating schedules for ScheduleSnooze and disable it...
    try
    {

        Write-Output "Executing Step-4 : Create schedule for ScheduleSnooze_ARMVMOptimizationWrapper runbook ..."

        $runbookNameforARMVMOptimization = "ScheduleSnooze_ARMVMOptimizationWrapper"
        $scheduleStart = "ScheduleSnooze-StartVM"
        $scheduleStop = "ScheduleSnooze-StopVM"
    
        #Starts everyday 6AM
        $StartVmUTCTime = (Get-Date "13:00:00").AddDays(1).ToUniversalTime()
        #Stops everyday 6PM
        $StopVmUTCTime = (Get-Date "01:00:00").AddDays(1).ToUniversalTime()
    
        Write-Output "Script 4 execution with resource group name is: $($aroResourceGroupName)"
    
        #---Create the schedule at the Automation Account level--- 
        Write-Output "Creating the Schedule in Automation Account ($($AutomationAccountName))..."
        New-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleStart -ResourceGroupName $aroResourceGroupName -StartTime $StartVmUTCTime -ExpiryTime $StartVmUTCTime.AddYears(1) -DayInterval 1
        New-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleStop -ResourceGroupName $aroResourceGroupName -StartTime $StopVmUTCTime -ExpiryTime $StopVmUTCTime.AddYears(1) -DayInterval 1
    
        #Disable the schedule   
        Set-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleStart -ResourceGroupName $aroResourceGroupName -IsEnabled $false
        Set-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $scheduleStop -ResourceGroupName $aroResourceGroupName -IsEnabled $false

        Write-Output "Successfully created the Schedule in Automation Account ($($AutomationAccountName))..."

        $paramsStopVM = @{"Action"="Stop"}
        $paramsStartVM = @{"Action"="Start"}
    
        #---Link the schedule to the runbook--- 
        Write-Output "Registering the Schedule in the Runbook ($($runbookNameforARMVMOptimization))..."
    
        Register-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -Name $runbookNameforARMVMOptimization -ScheduleName $scheduleStart -ResourceGroupName $aroResourceGroupName -Parameters $paramsStartVM
        Register-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -Name $runbookNameforARMVMOptimization -ScheduleName $scheduleStop -ResourceGroupName $aroResourceGroupName -Parameters $paramsStopVM
    
        Write-Output "Successfully Registered the Schedule in the Runbook ($($runbookNameforARMVMOptimization))..."

        Write-Output "Completed Step-4 ..."
    }
    catch
    {
        Write-Output "Error Occurred in Step-4..."        
        Write-Output $_.Exception
    }

    #-------------------STEP 4 (Bootstrap_CreateScheduleForARMVMOptimizationWrapper) execution ends---------------------

    #*******************STEP 5 execution starts********************************************

    #In Step 5 we are deleting the bootstrap script, Credential asset variable and Keyvault...
    try
    {

        Write-Output "Executing Step-5 : Performing clean up tasks (bootstrap scripts, Credential asset variable and Keyvalut) ..."

        Write-Output "Removing the Keyvault : ($($KeyVaultName))..."

        Remove-AzureRmKeyVault -VaultName $KeyVaultName -ResourceGroupName $aroResourceGroupName -Confirm:$False -Force

        Write-Output "Removing the Azure Credentials..."

        Remove-AzureRmAutomationCredential -Name "AzureCredentials" -AutomationAccountName $AutomationAccountName -ResourceGroupName $aroResourceGroupName 

        Write-Output "Removing the Bootstrap_Main Runbook..."

        Remove-AzureRmAutomationRunbook -Name "Bootstrap_Main" -ResourceGroupName $aroResourceGroupName -AutomationAccountName $AutomationAccountName -Force 

        Write-Output "Completed Step-5 ..."
    }
    catch
    {
        Write-Output "Error Occurred in Step-5..."   
        Write-Output $_.Exception
    }

    #*******************STEP 5 execution ends**********************************************
    
    Write-Output "Bootstrap wrapper script execution completed..."  

}
catch
{
    Write-Output "Error Occurred in Bootstrap Wrapper..."   
    Write-Output $_.Exception
}