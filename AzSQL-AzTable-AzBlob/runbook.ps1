

#Use Get-AzAutomationVariable for non-encrypted variables
#Use Get-AutomationVariable for encrypted variable
#ref: https://docs.microsoft.com/en-us/azure/automation/shared-resources/variables?tabs=azure-powershell#powershell-cmdlets-to-access-variables

$AutomationAccountName = "automation-account"
$ResourceGroupName = "azAutomation-rg"
$SubscriptionName = "Visual Studio Enterprise Subscription"

try
{
    #to be read from Azure SQL database
    $country = ""
    $capital = ""
    
    #to be read from Azure Table storage 
    $language = ""

    #content to be written to Azure blob
    $blobContent = ""

    #get the system assigned identity context
    $azContext = (Connect-AzAccount -Identity).context
     
    #use the identity context and set the azure context. 
    $AzureContext = set-azcontext -Tenant $azContext.Tenant.Id -SubscriptionName $SubscriptionName

    #read the SQL Connection String Variable    
    $sqlConnStr = get-AzAutomationVariable -name sqlConnString -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
    
    #connect to database and query details 
    $sqlConn = New-Object System.Data.SqlClient.SQLConnection
    $sqlConn.ConnectionString = $sqlConnStr.Value

    #for reading from Azure SQL Database
    try
    {
        $sqlConn.Open()
        
        $sqlcmd = New-Object System.Data.SqlClient.SqlCommand
        $sqlcmd.Connection = $sqlConn

        $selectQuery = "select name, capital from country where name = 'France'"
        $sqlcmd.CommandText = $selectQuery
        
        $reader = $sqlcmd.ExecuteReader()

        $success = $reader.Read()
        if(! $success)
        {
            throw(New-object System.Exception("Reader failure"))
        }

        $country = $reader.GetValue(0)
        $capital = $reader.GetValue(1)

        #write-output "Country and capital read from Azure SQL database : $country, $capital"
        $blobContent =  "Country and capital read from Azure SQL database : $country, $capital"
    }
    catch
    {
        Write-Error "Error when conencting to SQL"
        Write-Error $_
        exit
    }

    #*****************************************
    #Context For reading from Azure storage
    $StorageConnStr = get-AzAutomationVariable -name stoarageConnString -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
    $AzStorageContext = New-AzStorageContext -ConnectionString $StorageConnStr.Value
    
    
    #*****************************************
    #The following snippet is to read value from Azure Table storage
    
    $AzTableName = "popularLanguages"
    $storageTable = (Get-AzStorageTable –Name $AzTableName –Context $AzStorageContext).CloudTable

    #get the popular language of the particular country from table
    $result = Get-AzTableRow -table $storageTable -PartitionKey "country" -RowKey $country
    $language = $result.language
    
    #write-output "Language returned from storage : $language"
    $blobContent += "`nLanguage returned from storage : $language"


    #*****************************************
    #For uploading stuff to azure blob

    #content to be uploaded to Azure Blob container (tmp.txt will be uploaded) which was read from Azure SQL and Azure Table storage
    $containerName = "samplecontainer"
    
    #write a local file with the contents read from AzSQL and Table Storage
    Add-Content -path .\tmp.txt -Value $blobContent
    
    $timestamp = get-date -Format o
    $blobName = "tmp_"+$timestamp+".txt"

    Set-AzStorageBlobContent -File .\tmp.txt -Container $containerName -Blob $blobName -Context $AzStorageContext

    #tmp file getting deleted
    Remove-Item -Path .\tmp.txt

}
catch
{
    Write-Output "Exception Caught..."
    Write-Output $_.Exception.Message
    Write-Output $_.ScriptStackTrace 

    throw($_)
}