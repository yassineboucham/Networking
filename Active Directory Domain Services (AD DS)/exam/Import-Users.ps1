# Import-Users.ps1 (two-phase version)
$csvPath = "C:\Scripts\employes.csv"
$domain  = "ex-boucham.final"
$defaultPassword = ConvertTo-SecureString "P@ssw0rd2026" -AsPlainText -Force

$employes = Import-Csv -Path $csvPath -Encoding UTF8
$createdUsers = @()   # keep track of successfully created logins + their group

# PHASE 1 — create all users
foreach ($emp in $employes) {
    $service = $emp.Service
    $login   = ("$($emp.Prenom).$($emp.Nom)").ToLower() -replace " ", ""
    $upn     = "$login@$domain"
    $ouPath  = "OU=Utilisateurs,OU=$service,DC=ex-boucham,DC=final"

    if (Get-ADUser -Filter "SamAccountName -eq '$login'" -ErrorAction SilentlyContinue) {
        Write-Host "Utilisateur $login existe deja - ignore" -ForegroundColor Yellow
        $createdUsers += [PSCustomObject]@{ Login = $login; Group = "G_$service" }
        continue
    }

    try {
        New-ADUser `
            -Name "$($emp.Prenom) $($emp.Nom)" `
            -GivenName $emp.Prenom `
            -Surname $emp.Nom `
            -SamAccountName $login `
            -UserPrincipalName $upn `
            -Path $ouPath `
            -Description $emp.Fonction `
            -OfficePhone $emp.Telephone `
            -AccountPassword $defaultPassword `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -ErrorAction Stop

        Write-Host "Cree : $upn" -ForegroundColor Green
        $createdUsers += [PSCustomObject]@{ Login = $login; Group = "G_$service" }
    }
    catch {
        Write-Host "ECHEC creation pour $($emp.Prenom) $($emp.Nom) : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Give AD a moment to fully settle before group membership
Start-Sleep -Seconds 5

# PHASE 2 — add every successfully created user to their group
foreach ($u in $createdUsers) {
    try {
        Add-ADGroupMember -Identity $u.Group -Members $u.Login -ErrorAction Stop -Server $env:COMPUTERNAME
        Write-Host "Ajoute au groupe : $($u.Login) -> $($u.Group)" -ForegroundColor Green
    }
    catch {
        Write-Host "ECHEC groupe pour $($u.Login) : $($_.Exception.Message)" -ForegroundColor Red
    }
}
