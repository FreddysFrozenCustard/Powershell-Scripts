# Hybrid-Aware User Provisioning Script
# Requires: RSAT:ActiveDirectory, Microsoft.Graph PowerShell SDK

# Import required modules
Import-Module ActiveDirectory
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Import-Module Microsoft.Graph.Licenses

# Authenticate to Microsoft Graph
Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All"

# Prompt for domain credentials
$UserCredential = $host.ui.PromptForCredential("Need credentials", "Please enter your Domain Admin user name and password.", "", "NetBiosUserName")

[int]$MainLoopA = 0

Do {
    # Basic user input
    $firstname = Read-Host 'First name?'
    $lastname = Read-Host 'Last name?'
    $title = Read-Host 'Title?'
    $password = Read-Host 'Password?'
    $username = $firstname.ToLower() + $lastname.Substring(0,1).ToLower()

    Write-Host "`n1. Set Username to $username `n2. Specify a new username `n"
    $UsernameMenu = Read-Host "Enter Selection"
    Switch ($UsernameMenu) {
        "1" { Write-Host "Username is set to $username" }
        "2" { $username = Read-Host 'Username? (NO @FREDDYSUSA.COM)' }
        default { Write-Host "Ok, I'll just set the username to $username" }
    }

    $upn = "$username@freddysusa.com"
    $displayname = "$firstname $lastname"
    $city = Read-Host 'City?'
    $mobile = Read-Host 'Mobile Phone?'
    $officephone = Read-Host 'Office Phone?'

    # OU Selection
    [int]$ffcemp = 0
    [int]$gm = 0
    $company = ""
    $path = ""

    Write-Host "Select OU:"
    Write-Host "1. Catering"
    Write-Host "2. Corporate Office"
    Write-Host "3. Out of Office"
    Write-Host "4. Stores"
    Write-Host "5. GMs"
    Write-Host "6. Resources"
    Write-Host "7. Service Accounts"
    Write-Host "Any Key for Default OU"
    $xMenuChoiceA = Read-Host "Please enter an option 1 to 7..."

    Switch ($xMenuChoiceA) {
        1 { $path = 'OU=Catering,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
        2 {
            $company = "Freddy's Frozen Custard & Steakburgers"
            $ffcemp = 1
            Write-Host "1. 1st Floor (Training)"
            Write-Host "2. 2nd Floor - East"
            Write-Host "3. 2nd Floor - West"
            $xMenuChoiceOU = Read-Host "Please enter an option 1 to 3..."
            Switch ($xMenuChoiceOU) {
                1 { $path = 'OU=1st Floor,OU=Corporate Office,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
                2 { $path = 'OU=2nd Floor East,OU=Corporate Office,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
                3 { $path = 'OU=2nd Floor West,OU=Corporate Office,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
                default { $path = 'OU=Corporate Office,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
            }
        }
        3 { $path = 'OU=Out of Office,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local'; $ffcemp = 1 }
        4 { $path = 'OU=Stores,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
        5 { $path = 'OU=GMs,OU=Stores,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local'; $gm = 1 }
        6 { $path = 'OU=Resources,OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
        7 { $path = 'OU=Service Accounts,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
        default { $path = 'OU=SBSUsers,OU=Users,OU=MyBusiness,DC=ffc,DC=local' }
    }

    # Confirm
    Write-Host "Creating user $displayname with username $username and UPN $upn"
    Write-Host "OU Path: $path"
    Write-Host "Password: $password"
    Pause

    # Create user in local AD
    New-ADUser -SamAccountName $username -Name $displayname -GivenName $firstname -Surname $lastname `
        -UserPrincipalName $upn -Title $title -Enabled $true -DisplayName $displayname `
        -Description $title -OfficePhone $officephone -Company $company -MobilePhone $mobile `
        -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) -Path $path

    # Add to standard groups
    Write-Host "1. Add to standard groups (All Users, Folder Redirection, SharePoint, VPN)"
    Write-Host "2. Skip"
    $xMenuChoiceGroupStandard = Read-Host "Enter option 1 or 2..."
    if ($xMenuChoiceGroupStandard -eq 1) {
        Add-ADGroupMember 'All Users!' $username
        Add-ADGroupMember 'Windows SBS Folder Redirection Accounts' $username
        Add-ADGroupMember 'Windows SBS SharePoint_MembersGroup' $username
        Add-ADGroupMember 'Windows SBS Virtual Private Network Users' $username
    }

    if ($ffcemp -eq 1) { Add-ADGroupMember 'FFC Employees!' $username }
    if ($gm -eq 1) { Add-ADGroupMember 'General Managers' $username }

    # Sync AD
    Write-Host "Syncing AD..."
    (Get-ADDomainController -Filter *).Name | ForEach-Object { repadmin /syncall $_ (Get-ADDomain).DistinguishedName /e /A | Out-Null }
    Start-Sleep 10

    # Wait for sync to Entra ID
    Write-Host "Waiting for Azure AD sync..."
    Start-Sleep -Seconds 60

    # Assign license via Microsoft Graph
    $user = Get-MgUser -UserId $upn
    if ($user) {
        Set-MgUser -UserId $user.Id -UsageLocation "US"
        $sku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPACK" }
        if ($sku) {
            Set-MgUserLicense -UserId $user.Id -AddLicenses @{ SkuId = $sku.SkuId } -RemoveLicenses @()
        }
    }

    # Loop again?
    Write-Host "`n1. Add another user `n2. Exit `n"
    $anotherusermenuresponse = Read-Host "Enter Selection"
    Switch ($anotherusermenuresponse) {
        "1" { $MainLoopA = 0 }
        "2" { $MainLoopA = 1 }
    }

} While ($MainLoopA -eq 0)
