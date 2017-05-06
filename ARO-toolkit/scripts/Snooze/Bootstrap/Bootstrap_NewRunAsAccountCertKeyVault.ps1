 <#
.SYNOPSIS  
 BootStrap script for creating Azure Run As Account
.DESCRIPTION  
 BootStrap script for creating Azure Run As Account
.EXAMPLE  
.\NewRunAsAccountCertKeyVault.ps1 -AzureLoginUserName "Value1" -AzureLoginPassword "Value2" -ResourceGroup "Value3" -AutomationAccountName "Value4" -SubscriptionId "Value5"
Version History  
v1.0   - redmond\balas - Initial Release  
#>
 Param (
    [String]$AzureLoginUserName = $(throw "Pass the value for AzureLoginUserName"),
 
    [String]$AzureLoginPassword = $(throw "Pass the value for AzureLoginPassword"),
 
    [String] $ResourceGroup = $(throw "Pass the value for ResourceGroup"),

    [String] $AutomationAccountName = $(throw "Pass the value for AutomationAccountName"),

    [String] $SubscriptionId = $(throw "Pass the value for SubscriptionId")
 )

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
    
    $RG = Get-AzureRmResourceGroup -Name $ResourceGroup 
    $KeyVaultLocation = $RG[0].Location
 
    # Create Run As Account using Service Principal
    $CertifcateAssetName = "AzureRunAsCertificate"
    $ConnectionAssetName = "AzureRunAsConnection"
    $ConnectionTypeName = "AzureServicePrincipal"
 
    Write-Output "Creating Keyvault for generating cert..."
    ValidateKeyVaultAndCreate $KeyVaultName $ResourceGroup $KeyVaultLocation

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
    CreateAutomationCertificateAsset $ResourceGroup $AutomationAccountName $CertifcateAssetName $PfxCertPathForRunAsAccount $PfxCertPlainPasswordForRunAsAccount $true

    # Populate the ConnectionFieldValues
    $SubscriptionInfo = Get-AzureRmSubscription -SubscriptionId $SubscriptionId
    $TenantID = $SubscriptionInfo | Select TenantId -First 1
    $Thumbprint = $PfxCert.Thumbprint
    $ConnectionFieldValues = @{"ApplicationId" = $ApplicationId; "TenantId" = $TenantID.TenantId; "CertificateThumbprint" = $Thumbprint; "SubscriptionId" = $SubscriptionId} 

    Write-Output "Creating Connection in the Asset..."
    # Create a Automation connection asset named AzureRunAsConnection in the Automation account. This connection uses the service principal.
    CreateAutomationConnectionAsset $ResourceGroup $AutomationAccountName $ConnectionAssetName $ConnectionTypeName $ConnectionFieldValues

    Write-Output "RunAsAccount Creation Completed..."
     
 }
 catch
 {
    Write-Output "Error Occurred..."   
    Write-Output $_.Exception

 }