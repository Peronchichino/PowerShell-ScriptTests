$thumb = "xxx"
Connect-AzureAD -TenantId xxx -ApplicationId  xxx -CertificateThumbprint $thumb
Connect-MgGraph -TenantId xxx -ClientID xxx -CertificateThumbprint $thumb
Connect-PnPOnline -url "xxx/sites/"


function WriteLog{    
    Param ([string]$logString)
    $dateTime = "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
    # If File not exists use Add-Content to create it and add content
    if (-not (Test-Path -Path $csvLogging)) {Add-Content -Path $csvLogging -Value "Start CAL Contacts Logging"}
    Add-content $csvLogging -value "$datetime $logString"
}

# function CompareContacts {
#     Param (
#         [hashtable]$existCont,
#         [hashtable]$newCont
#     )

#     foreach ($key in $newCont.Keys) {
#         if ($newCont[$key] -is [System.Array]) {
#             if (-not ($newCont[$key] -join "," -eq $existCont[$key] -join ",")) {
#                 return $true
#             }
#         } elseif ($newCont[$key] -ne $existCont[$key]) {
#             return $true
#         }
#     }
#     return $false
# }

function CompareContacts($existCont,$newCont){
    $properties = @(
        "givenName","surname","emailAddresses","businessPhone","categories","CompanyName","Department","OfficeLocation"
    )

    foreach($property in $properties){
        $existVal = $existCont.$property
        $newVal = $newCont.$property

        if($existVal -is [System.Collections.IEnumerable] -and $newVal -is [System.Collections.IEnumerable]){
            $existVal = @($existVal) -join ","
            $newVal = @($newVal) -join ","
        }

        if($existVal -ne $newVal){
            return $true
        }
    }

    return $false
} 

$benchmark = [System.Diagnostics.Stopwatch]::StartNew()

#contact folder display name 
$folder = "CAL Contacts"
$folderId

$groupId = "xxx"
#$group = Get-AzureADGroup -Filter "ObjectId eq '$groupId'"

$bla = @("Buchmayer Lukas")

$members = Get-AzureADGroupMember -ObjectId "xxx" | Where-Object { $_.DisplayName -in $bla }

$csvLogging = "C:\...\graphapilogfile.csv"

$items = Get-PnPListItem -list "TestContacts"

if($items.count -eq 0){
    WriteLog('[INFO] Problem with list or item retrieval. Either list is empty or items could not be retrievewd')
    return
}

if($members.count -eq 0){
    WriteLog('[INFO] Problem with retrieving group or gromp is empty')
    return
}

$itemsToExport = $items | ForEach-Object {
    [PSCustomObject]@{
        GivenName = $_.FieldValues.Title
        Surname = $_.FieldValues.Surname
        Initials = $_.FieldValues.Initials
        emailAddresses = $_.FieldValues.emailAddresses
        emailNames = $_.FieldValues.emailNames
        businessPhones = $_.FieldValues.businessPhones
        categories = $_.FieldValues.categories
        CompanyName = $_.FieldValues.CompanyName
        Department = $_.FieldValues.Department
        OfficeLocation = $_.FieldValues.OfficeLocation
    }
}

foreach($member in $members){
    $memberDets = Get-AzureADUser -ObjectId $member.ObjectId
    $memberId = $member.UserPrincipalName

    $exists = Get-MgUserContactFolder -userid $memberId | Where-Object { $_.DisplayName -eq "CAL Contacts" }

    if($null -eq $exists){
        $createFolder = New-MgUserContactFolder -userid $memberId -DisplayName "CAL Contacts"
        $folderId = $createFolder.Id
        WriteLog('[INFO] Folder didnt exist, created')
    } else {
        $folderId = $exists.Id

        $folderContacts = Get-MgUserContactFolderContact -userid $memberId -ContactFolderId $folderId 
        $folderContacts_Dict = @{}

        foreach($folderContact in $folderContacts){ #create keys
            $key = $folderContact.emailAddresses
            if($null -ne $key){
                $folderContacts_Dict[$key] = $folderContact
            }
        }
    }

    foreach($contact in $itemsToExport){
        $benchmark_cont = [System.Diagnostics.Stopwatch]::StartNew()

        $params = @{
            givenName = $contact.givenName
            surname = $contact.surname
            emailAddresses = @(
                @{
                    address = $contact.emailAddresses
                    name = $contact.emailNames
                }
            )
            businessPhones = @($contact.businessPhones)
            categories = @($contact.categories)
            CompanyName = $contact.CompanyName
            Department = $contact.Department
            OfficeLocation = $contact.OfficeLocation
        }

        $key = $contact.emailAddresses | Select-Object -First 1
        $existingContact = $folderContacts_Dict[$key]

        if($null -ne $existingContact){
            $oldParams = @{
                givenName = $existingContact.givenName
                surname = $existingContact.surname
                emailAddresses = @(
                    @{
                        address = $existingContact.emailAddresses
                        name = $existingContact.emailNames
                    }
                )
                businessPhones = @($existingContact.businessPhones)
                categories = @($existingContact.categories)
                CompanyName = $existingContact.CompanyName
                Department = $existingContact.Department
                OfficeLocation = $existingContact.OfficeLocation
            }

            # $update = $false
            # foreach($k in $params.Keys){
            #     if($params[$k] -is [System.Array]){
            #         if(-not ($params[$k] -join "," -eq $oldParams[$k] -join ",")){
            #             $update = $true
            #             break
            #         }
            #     } elseif ($params[$k] -ne $oldParams[$k]){
            #         $update = $true
            #         break
            #     }

            # }

            # if($update){
            #     Remove-MgUserContactFolderContact -userid $memberId -ContactFolderId $folderId -ContactId $existingContact.Id
            #     WriteLog('[CMD] Deleted changed contact')
            #     New-MgUserContactFolderContact -userid $memberId -ContactFolderId $folderId -BodyParameter $params
            #     # Update-MgUserContactFolderContact -userid $memberId -ContactFolderId $folderId -ContactId $existingContact.id -BodyParameter $params
            #     WriteLog('[CMD] Updated contact in folder')
            # } else {
            #     WriteLog('[INFO] Contact exists and is up to date')
            # }


            $differences = CompareContacts -existCont $oldParams -newCont $params

            if($differences){
                Remove-MgUserContactFolderContact -userid $memberId -ContactFolderId $folderId -ContactId $existingContact.Id
                WriteLog('[CMD] Deleted changed contact')
                New-MgUserContactFolderContact -userid $memberId -ContactFolderId $folderId -BodyParameter $params
                WriteLog('[CMD] Updated contact in folder')
            } else {
                WriteLog('[INFO] Contact exists and is up to date')
            }

        } else {
            New-MgUserContactFolderContact -userid $memberId -ContactFolderId $folderId -BodyParameter $params
            WriteLog('[CMD] Contact created')
        }

        $benchmark_cont.Stop()

        $time_cont = "[Contact Benchmark] $($benchmark_cont.ElapsedMilliseconds) ms"
        WriteLog($time_cont)
    }
    
}

$benchmark.Stop()

Write-Host "Benchmarking:`n-----------------------------"
Write-Host "Time elapsed: "$benchmark.Elapsed
Write-Host "Time elapsed (ms): "$benchmark.ElapsedMilliseconds"`n"
$time = "[Benchmark] $($benchmark.ElapsedMilliseconds) ms"
WriteLog($time)

