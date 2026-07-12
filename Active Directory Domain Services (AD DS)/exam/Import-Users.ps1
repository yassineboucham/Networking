$csvPath = "C:\Scripts\employes.csv"
$domain  = "ex-boucham.final"
$defaultPassword = ConvertTo-SecureString "P@ssw0rd2026" -AsPlainText -Force

$employes = Import-Csv -Path $csvPath -Encoding UTF8

foreach ($emp in $employes) {

    $service   = $emp.Service
    $login     = ("$($emp.Prenom).$($emp.Nom)").ToLower() -replace " ", ""
    $upn       = "$login@$domain"
    $ouPath    = "OU=Utilisateurs,OU=$service,DC=ex-boucham,DC=final"
    $groupName = "G_$service"

    if (Get-ADUser -Filter "SamAccountName -eq '$login'" -ErrorAction SilentlyContinue) {
        Write-Host "Utilisateur $login existe deja - ignore" -ForegroundColor Yellow
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

        Add-ADGroupMember -Identity $groupName -Members $login -ErrorAction Stop

        Write-Host "Utilisateur cree : $upn -> groupe $groupName" -ForegroundColor Green
    }
    catch {
        Write-Host "ECHEC pour $($emp.Prenom) $($emp.Nom) : $($_.Exception.Message)" -ForegroundColor Red
    }
}