# Import-Users.ps1
$csvPath = "C:\Scripts\employes.csv"
$domain  = "ex-<prenom>.final"
$defaultPassword = ConvertTo-SecureString "P@ssw0rd2026" -AsPlainText -Force

$employes = Import-Csv -Path $csvPath

foreach ($emp in $employes) {

    $service   = $emp.Service
    $login     = ("$($emp.Prenom).$($emp.Nom)").ToLower() -replace " ", ""
    $upn       = "$login@$domain"
    $ouPath    = "OU=Utilisateurs,OU=$service,DC=ex-<prenom>,DC=final"
    $groupName = "G_$service"

    # Q3.4 - éviter les doublons si le script est relancé
    if (Get-ADUser -Filter "SamAccountName -eq '$login'" -ErrorAction SilentlyContinue) {
        Write-Host "Utilisateur $login existe deja - ignore" -ForegroundColor Yellow
        continue
    }

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
        -Enabled $true

    # Ajout au groupe global du service (strategie AGDLP)
    Add-ADGroupMember -Identity $groupName -Members $login

    Write-Host "Utilisateur cree : $upn -> groupe $groupName" -ForegroundColor Green
}
