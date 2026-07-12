# Guide Complet — Examen Final Administration des Services Windows
## Windows Server 2025 — Active Directory (GUI + scripts requis)

> Remplacez **`<prenom>`** partout par votre prénom réel (hostnames, domaine, comptes, chemins).
> Domaine à créer : **ex-<prenom>.final**

---

## Vue d'ensemble de l'infrastructure

| Machine | Hostname | LAN | Interface | Adresse IP |
|---|---|---|---|---|
| SRV2025 | EX01\<prenom\> | LAN-RH | vNIC1 | 172.16.100.254/24 |
| SRV2025 | EX01\<prenom\> | LAN-IT | vNIC2 | 50.50.5.254/24 |
| Client RH | RH01\<prenom\> | LAN-RH | vNIC1 | 172.16.100.111/24 |
| Client IT | IT02\<prenom\> | LAN-IT | vNIC1 | 50.50.5.222/24 |

Passerelle des clients = IP du serveur sur leur LAN respectif. Dans VMware, créez **2 réseaux internes isolés** (Edit → Virtual Network Editor → Add Network, type "Host-only" ou "Custom", sans DHCP).

---

## PARTIE 1 — Configuration réseau du serveur (2 pts)

### Étape 1.1 — Créer les 2 cartes réseau dans VMware
Dans les paramètres de la VM `SRV2025` : `VM → Settings → Add → Network Adapter` (ajoutez une 2e carte). Reliez `vNIC1` au réseau LAN-RH et `vNIC2` au réseau LAN-IT.

### Étape 1.2 — Configurer l'IP statique de vNIC1 (LAN-RH) via l'interface graphique
1. `Panneau de configuration → Réseau et Internet → Centre Réseau et partage → Modifier les paramètres de la carte` (ou `ncpa.cpl`)
2. Repérez la carte correspondant à `vNIC1`, clic droit → **Propriétés**
3. Double-cliquez sur **Protocole Internet version 4 (TCP/IPv4)**
4. Sélectionnez **Utiliser l'adresse IP suivante** :
   - Adresse IP : `172.16.100.254`
   - Masque de sous-réseau : `255.255.255.0`
   - Passerelle par défaut : laisser vide (le serveur est la passerelle des clients, il n'a pas besoin de sa propre passerelle sur ce LAN)
5. **Serveur DNS préféré** : `127.0.0.1` (le serveur sera son propre DNS une fois le rôle installé)
6. OK → OK

### Étape 1.3 — Configurer l'IP statique de vNIC2 (LAN-IT)
Répétez la même procédure pour la carte `vNIC2` :
- Adresse IP : `50.50.5.254`
- Masque : `255.255.255.0`
- DNS préféré : `127.0.0.1`

📸 **CAPTURE 1** : ouvrez `ncpa.cpl`, faites une capture montrant les deux cartes avec leurs noms, puis une capture des propriétés IPv4 de chacune.

### Étape 1.4 — Renommer le serveur en EX01\<prenom\>
1. `Poste de travail → clic droit → Propriétés` (ou `sysdm.cpl`)
2. Dans l'onglet **Nom de l'ordinateur**, cliquez sur **Modifier**
3. Nom de l'ordinateur : `EX01<prenom>`
4. OK → un redémarrage sera demandé **(faites-le avant l'installation du rôle AD DS)**

### Étape 1.5 — Configurer l'IP des clients
Même procédure sur `RH01<prenom>` :
- IP : `172.16.100.111` / masque `255.255.255.0` / passerelle : `172.16.100.254` / DNS préféré : `172.16.100.254`

Et sur `IT02<prenom>` :
- IP : `50.50.5.222` / masque `255.255.255.0` / passerelle : `50.50.5.254` / DNS préféré : `50.50.5.254`

### Étape 1.6 — Tester la connectivité
Depuis chaque client, ouvrez `cmd` et lancez :
```cmd
ping 172.16.100.254
ping 50.50.5.254
```
📸 **CAPTURE 2** : capture du ping réussi depuis chaque client vers le serveur (les deux LANs).

📸 **CAPTURE 3** : sur le serveur, lancez `ipconfig /all` et faites une capture montrant les deux interfaces avec leurs IP.

📸 **CAPTURE 4** : capture des pings clients → serveur (RH et IT).

### Réponses aux questions théoriques — Partie 1

**Q1.1 — Commande PowerShell pour attribuer une IP statique (exemple LAN-RH) :**
```powershell
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 172.16.100.254 -PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 127.0.0.1
```
(`Ethernet0` doit être remplacé par le nom réel de l'interface, visible avec `Get-NetAdapter`)

**Q1.2 — Commande pour renommer le serveur :**
```powershell
Rename-Computer -NewName "EX01<prenom>" -Restart
```
Oui, un redémarrage est **obligatoire** : le nom NetBIOS et le nom DNS de la machine sont utilisés dans de nombreux processus système (SPNs Kerberos, inscription DNS, cache local) qui ne sont relus qu'au démarrage — sans redémarrage le nom affiché changerait mais des services continueraient à référencer l'ancien nom.

**Q1.3 — Impact du changement de nom sur Active Directory (si déjà promu) :**
Renommer un contrôleur de domaine **après** promotion est une opération supportée mais lourde : AD doit republier de nouveaux enregistrements DNS et SPN (Service Principal Names) pour le nouveau nom, mettre à jour les références dans `msDS-AdditionalDnsHostName`, et la réplication doit propager ce changement à tous les autres DC. C'est pourquoi il vaut toujours mieux renommer le serveur **avant** de le promouvoir, comme fait ici à l'étape 1.4.

---

## PARTIE 2 — Installation du contrôleur de domaine AD DS (5 pts)

### Étape 2.1 — Ajouter le rôle AD DS via le Gestionnaire de serveur
1. Ouvrez **Gestionnaire de serveur** (`Server Manager`)
2. `Gérer → Ajouter des rôles et fonctionnalités`
3. `Installation basée sur un rôle ou une fonctionnalité → Suivant`
4. Sélectionnez le serveur local → `Suivant`
5. Cochez **Services AD DS (Active Directory Domain Services)** → cliquez **Ajouter des fonctionnalités** quand demandé → `Suivant` jusqu'à `Installer`

📸 **CAPTURE 5** : capture du Gestionnaire de serveur montrant le rôle AD DS installé (page de résumé finale).

### Étape 2.2 — Promouvoir le serveur en contrôleur de domaine
1. Dans le Gestionnaire de serveur, cliquez sur le **drapeau jaune** (notification) en haut
2. `Promouvoir ce serveur en contrôleur de domaine`
3. Sélectionnez **Ajouter une nouvelle forêt**
4. Nom de domaine racine : `ex-<prenom>.final`
5. `Suivant` → Niveau fonctionnel de la forêt et du domaine : **Windows Server 2025** (ou le plus haut niveau disponible)
6. Définissez le **mot de passe DSRM** (notez-le, il sert uniquement en cas de restauration)
7. Ignorez l'avertissement "délégation DNS non créée" (normal en labo isolé)
8. Vérifiez le nom NetBIOS auto-généré
9. Lancez la **vérification des prérequis** → `Installer`
10. Le serveur redémarre automatiquement

📸 **CAPTURE 6** : après redémarrage, ouvrez `sysdm.cpl` (Propriétés système) et montrez que le domaine `ex-<prenom>.final` est visible en tant que membre.

📸 **CAPTURE 7** : ouvrez **Utilisateurs et ordinateurs Active Directory** (`dsa.msc`) et montrez le domaine créé avec les conteneurs par défaut.

### Équivalent PowerShell (pour Q2.1)
```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Install-ADDSForest `
  -DomainName "ex-<prenom>.final" `
  -DomainNetbiosName "EX<PRENOM>" `
  -InstallDns:$true `
  -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force) `
  -Force
```

### Réponses aux questions théoriques — Partie 2

**Q2.2 — Les 5 rôles FSMO et leur emplacement par défaut :**
| Rôle | Portée |
|---|---|
| Schema Master | 1 par forêt |
| Domain Naming Master | 1 par forêt |
| RID Master | 1 par domaine |
| PDC Emulator | 1 par domaine |
| Infrastructure Master | 1 par domaine |

Par défaut, **le premier contrôleur de domaine créé dans la forêt reçoit automatiquement les 5 rôles**. Ici, `EX01<prenom>` étant le premier (et seul) DC, il détient les cinq rôles. Vérification :
```powershell
netdom query fsmo
```

**Q2.3 — Le Global Catalog :**
C'est une copie **partielle mais indexée** de tous les objets de **toute la forêt** (pas seulement du domaine local), stockée sur certains DC désignés "serveurs de catalogue global". Il sert aux recherches rapides inter-domaines, à l'authentification via UPN, et à la résolution de l'appartenance aux groupes universels. Le premier DC d'une forêt est automatiquement Global Catalog.

**Q2.4 — Pourquoi au moins 2 contrôleurs de domaine :**
Redondance : si l'unique DC tombe en panne, plus aucune authentification n'est possible sur tout le réseau (aucun login, aucun accès aux ressources partagées). Deux DC permettent aussi de répartir la charge d'authentification et assurent la continuité de service pendant la maintenance de l'un des deux.

**Q2.5 — Le DSRM et son usage :**
Le **Directory Services Restore Mode** est un mode de démarrage spécial protégé par un mot de passe local distinct (défini à la promotion). Il est utilisé lorsqu'un contrôleur de domaine ne peut plus démarrer normalement, ou lors d'une **restauration autoritaire** de la base AD (`ntdsutil`) après une suppression massive accidentelle qu'il faut forcer à re-répliquer vers les autres DC.

---

## PARTIE 3 — Script PowerShell : OUs + import 50 utilisateurs (6 pts)

> ⚠️ L'énoncé exige explicitement un **script PowerShell** pour cette partie (import automatisé de 50 utilisateurs) — ce n'est pas faisable manuellement en 4h via l'interface graphique. Ci-dessous : la structure d'OU créée en GUI (pour bien la visualiser/vérifier), puis le script complet requis.

### Étape 3.1 — Créer la structure des OUs via l'interface graphique (dsa.msc)
1. Ouvrez `dsa.msc` (Utilisateurs et ordinateurs Active Directory)
2. Clic droit sur le domaine `ex-<prenom>.final` → `Nouveau → Unité d'organisation`
3. Créez, à la racine : `RH`, `IT`, `Finance`, `Marketing`, `DG`, `Groupes`
4. Dans **chacune** des 5 OU de service (`RH`, `IT`, `Finance`, `Marketing`, `DG`), créez 3 sous-OU : `Utilisateurs`, `Ordinateurs`, `Groupes`
5. Dans l'OU `Groupes` (racine), créez les groupes globaux de sécurité : `G_RH`, `G_IT`, `G_Finance`, `G_Marketing`, `G_DG`
   - `Nouveau → Groupe → Étendue : Globale → Type : Sécurité`

Cette étape en GUI vous permet de **vérifier visuellement** que l'arborescence attendue par le script existe bien avant de lancer l'import.

📸 **CAPTURE 8** : capture de `dsa.msc` montrant l'arborescence complète des OUs et sous-OUs.

### Étape 3.2 — Préparer le fichier CSV
Créez `C:\Scripts\employes.csv` (via le Bloc-notes ou Excel) avec l'en-tête :
```csv
Prenom,Nom,Service,Fonction,Telephone
Fatima,Zahra,RH,Responsable RH,0600000001
Karim,Idrissi,IT,Technicien,0600000002
...
```
Remplissez jusqu'à **50 lignes**, avec `Service` correspondant exactement à l'un de : `RH`, `IT`, `Finance`, `Marketing`, `DG`.

### Étape 3.3 — Le script PowerShell complet (Q3.1)
Ouvrez **Windows PowerShell ISE** (icône bleue, pour voir le code — requis en capture 10), créez `C:\Scripts\Import-Users.ps1` :

```powershell
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
```

Exécutez-le :
```powershell
cd C:\Scripts
.\Import-Users.ps1
```
```
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
📸 **CAPTURE 9** : `dsa.msc`, montrez les 50 utilisateurs répartis dans leurs OUs respectives.
📸 **CAPTURE 10** : le script ouvert dans **PowerShell ISE**, code visible.
📸 **CAPTURE 11** : sur `RH01<prenom>`, connectez-vous avec un compte RH créé (ex. `fatima.zahra`), montrez l'écran de changement de mot de passe obligatoire puis la session ouverte.

### Réponses aux questions théoriques — Partie 3

**Q3.2 — Stratégie AGDLP et son application ici :**
AGDLP signifie : mettre les **A**ccounts (utilisateurs) dans des groupes **G**lobaux, puis (si multi-domaine) les groupes globaux dans des groupes **D**omain **L**ocal, et attribuer les **P**ermissions au groupe Domain Local. Dans ce script, chaque utilisateur est ajouté à son groupe global de service (`G_RH`, `G_IT`, etc.) — c'est l'étape "A→G". Ces groupes globaux serviraient ensuite à recevoir les permissions NTFS sur les partages (Partie 4), ce qui complète le modèle.

**Q3.3 — Attribut du CSV qui détermine l'OU de destination :**
La colonne **`Service`** — elle sert à construire dynamiquement le chemin `$ouPath` (`OU=Utilisateurs,OU=$service,...`) et à choisir le groupe global correspondant.

**Q3.4 — Exécution du script deux fois :**
Sans protection, `New-ADUser` échouerait avec une erreur (le `SamAccountName` existe déjà) ou, pire, créerait un doublon avec un nom légèrement différent. Le script ci-dessus l'évite via un test `Get-ADUser -Filter "SamAccountName -eq '$login'"` avant création : si l'utilisateur existe déjà, il est simplement ignoré (`continue`).

---

## PARTIE 4 — Profils itinérants et dossiers de base (3 pts)

### Étape 4.1 — Créer les dossiers partagés sur le serveur (GUI)
1. Sur `EX01<prenom>`, créez `D:\Profiles` et `D:\HomeFolders` (Explorateur de fichiers)
2. Clic droit sur `D:\Profiles → Propriétés → onglet Partage → Partage avancé`
3. Cochez **Partager ce dossier**, dans **Nom du partage** tapez `Profiles$` (le `$` le rend invisible dans l'explorateur réseau — voir Q4.2)
4. `Autorisations → Tout le monde : Modifier` (le contrôle fin se fait via NTFS, pas ici)
5. Répétez pour `D:\HomeFolders` → nom de partage `HomeFolders$`

### Étape 4.2 — Configurer les permissions NTFS (GUI)
1. Clic droit sur `D:\Profiles → Propriétés → onglet Sécurité → Modifier`
2. Ajoutez **Administrateurs** → cochez **Contrôle total**
3. Ajoutez **Utilisateurs authentifiés** (ou le groupe concerné) → cochez **Modification**
4. Répétez exactement pour `D:\HomeFolders`

📸 **CAPTURE 12** : Explorateur montrant les deux partages `Profiles$` et `HomeFolders$` accessibles depuis un client (`\\EX01<prenom>\Profiles$`).

### Étape 4.3 — Configurer le profil itinérant et le lecteur Z: pour un utilisateur (GUI)
1. `dsa.msc → clic droit sur l'utilisateur → Propriétés → onglet Profil`
2. **Chemin du profil (profil itinérant)** : `\\EX01<prenom>\Profiles$\%username%`
3. **Dossier de base → Connecter** : lecteur `Z:` → `\\EX01<prenom>\HomeFolders$\%username%`
4. OK

📸 **CAPTURE 13** : capture de l'onglet Profil montrant le chemin de profil et le lecteur Z: configurés.

### Étape 4.4 — Vérification côté client
Connectez-vous avec un utilisateur RH sur `RH01<prenom>` et vérifiez dans l'explorateur que le lecteur `Z:` est bien mappé, puis rouvrez une session pour confirmer que le profil se recharge.

📸 **CAPTURE 14** : session ouverte montrant le lecteur `Z:` mappé et le profil itinérant chargé.

### Automatiser pour les 50 utilisateurs (script requis, complète le Q4.1)
```powershell
$server = "EX01<prenom>"
Get-ADUser -Filter * -SearchBase "DC=ex-<prenom>,DC=final" | ForEach-Object {
    $u = $_.SamAccountName
    Set-ADUser -Identity $u `
        -ProfilePath "\\$server\Profiles$\$u" `
        -HomeDirectory "\\$server\HomeFolders$\$u" `
        -HomeDrive "Z:"
}
```

### Réponses aux questions théoriques — Partie 4

**Q4.1 — Commande PowerShell pour attribuer un profil itinérant :**
```powershell
Set-ADUser -Identity "fatima.zahra" -ProfilePath "\\EX01<prenom>\Profiles$\fatima.zahra"
```

**Q4.2 — Pourquoi le symbole `$` dans `Profiles$` :**
Le `$` rend le partage **caché** : il n'apparaît pas dans la liste des dossiers partagés visibles quand un utilisateur parcourt `\\EX01<prenom>\` dans l'explorateur réseau. Il reste néanmoins accessible si on tape le chemin complet manuellement — cela évite que les utilisateurs naviguent par curiosité dans les profils des autres.

**Q4.3 — Le profil obligatoire (`ntuser.man`) :**
Un profil obligatoire est un profil itinérant **en lecture seule** : les modifications faites pendant la session (fond d'écran, raccourcis, etc.) ne sont **jamais sauvegardées**. Pour le configurer : renommez le fichier `ntuser.dat` du profil modèle en **`ntuser.man`** dans le dossier de profil partagé. À la prochaine connexion, Windows charge ce profil mais ne peut pas y écrire les changements.

**Q4.4 — Problèmes si un profil itinérant devient trop volumineux :**
- Temps de connexion/déconnexion très longs (le profil entier est copié sur le réseau à chaque login/logout)
- Saturation de l'espace disque du partage `Profiles$` si de nombreux utilisateurs ont des profils lourds
- Risque de corruption si la connexion réseau est coupée pendant la synchronisation
- Solution habituelle : combiner avec la **redirection de dossiers** (GPO 6, Partie 5) pour que les gros dossiers (Documents, Bureau) restent sur le réseau en permanence au lieu d'être copiés à chaque session.

---

## PARTIE 5 — Les 10 GPO indispensables en entreprise (4 pts)

> L'énoncé demande d'en **implémenter au moins 3** réellement sur l'infrastructure. Voici comment créer chacune via **GPMC** (`gpmc.msc`), en GUI.

### Méthode générale (à répéter pour chaque GPO)
1. Ouvrez `gpmc.msc` (Gestion des stratégies de groupe)
2. Clic droit sur l'OU cible → **Créer une GPO dans ce domaine, et la lier ici**
3. Donnez un nom explicite (voir tableau ci-dessous)
4. Clic droit sur la GPO créée → **Modifier**, puis naviguez vers le bon paramètre

### GPO 1 — Politique de mots de passe (liée à la racine du domaine)
`Configuration ordinateur → Stratégies → Paramètres Windows → Paramètres de sécurité → Stratégies de compte → Stratégie de mot de passe`
- Longueur minimale : `10`
- Complexité activée
- Historique : `10` mots de passe mémorisés
- Durée de vie maximale : `90` jours
`→ Verrouillage de compte` : seuil `5` tentatives

### GPO 2 — Pare-feu Windows activé (racine du domaine ou OU Ordinateurs)
`Configuration ordinateur → Modèles d'administration → Réseau → Connexions réseau → Pare-feu Windows Defender`, ou directement `Paramètres de sécurité → Pare-feu Windows Defender avec fonctions avancées de sécurité` → activer sur les 3 profils (Domaine, Privé, Public)

### GPO 3 — Restriction des supports USB (OU Utilisateurs non-IT)
`Configuration ordinateur → Modèles d'administration → Système → Accès au stockage amovible` → activer **"Disques amovibles : refuser l'accès en lecture"** et **"...en écriture"**

### GPO 4 — Mapping automatique du lecteur Z: (OUs Utilisateurs)
`Configuration utilisateur → Préférences → Paramètres Windows → Mappages de lecteurs → Nouveau → Lecteur mappé`
- Action : **Mettre à jour**
- Emplacement : `\\EX01<prenom>\HomeFolders$\%username%`
- Lettre : `Z:`

### GPO 5 — Fond d'écran d'entreprise (OUs Utilisateurs)
`Configuration utilisateur → Stratégies → Modèles d'administration → Panneau de configuration → Personnalisation → Fond d'écran du Bureau` → activer et indiquer un chemin réseau vers l'image

### GPO 6 — Redirection des dossiers (OUs Utilisateurs)
`Configuration utilisateur → Stratégies → Paramètres Windows → Redirection de dossiers → Documents` (et `Bureau`) → clic droit → Propriétés → **Basique** → cible : `\\EX01<prenom>\Profiles$\%username%\Dossiers`

### GPO 7 — Script de démarrage (OUs Ordinateurs)
`Configuration ordinateur → Stratégies → Paramètres Windows → Scripts → Démarrage` → Ajouter un script PowerShell de nettoyage placé dans le SYSVOL

### GPO 8 — Déploiement MSI (OU=IT\Ordinateurs)
`Configuration ordinateur → Stratégies → Paramètres du logiciel → Installation de logiciel → Nouveau → Package` → sélectionnez le `.msi` sur `\\EX01<prenom>\Deploy$` → mode **Attribué**

### GPO 9 — Journalisation des événements (racine du domaine)
`Configuration ordinateur → Stratégies → Paramètres Windows → Paramètres de sécurité → Stratégies d'audit avancées` → activer l'audit des connexions, de la gestion des comptes, et de l'accès aux objets AD DS

### GPO 10 — Politique de verrouillage renforcée (OU=Groupes ou selon besoin)
Durée de verrouillage : `30` minutes ; seuil d'alerte ; historique `10` mots de passe (peut être combinée avec une **Fine-Grained Password Policy** si elle ne doit s'appliquer qu'à un groupe précis — voir le guide AD DS précédent, Section 10)

📸 **CAPTURE 15** : `gpmc.msc`, liste des GPO créées et liées.

### Vérification (obligatoire, au moins 5 GPO doivent être vérifiées)
Sur chaque client :
```cmd
gpupdate /force
gpresult /r
```

📸 **CAPTURE 16** : sortie de `gpresult /r` sur `RH01<prenom>` montrant les GPO appliquées.
📸 **CAPTURE 17** : sur `IT02<prenom>`, montrez le lecteur `Z:` mappé automatiquement via GPO (preuve que GPO 4 fonctionne).

### Réponses aux questions théoriques — Partie 5

**Q5.1 — GPO liée à une OU vs GPO liée au domaine :**
Une GPO liée au **domaine** s'applique à **tous** les utilisateurs/ordinateurs du domaine, quelle que soit leur OU. Une GPO liée à une **OU précise** ne s'applique qu'aux objets contenus dans cette OU (et ses sous-OU par héritage). On lie au domaine les règles universelles (ex. mot de passe), et à une OU les règles ciblées (ex. restriction USB pour non-IT seulement).

**Q5.2 — L'héritage de GPO et comment le bloquer :**
Par défaut, une OU enfant hérite de toutes les GPO liées à ses parents (domaine, OU parentes). On peut bloquer cet héritage sur une OU via `clic droit sur l'OU → Bloquer l'héritage` dans GPMC — mais une GPO marquée **Appliquée (Enforced)** au niveau parent continue de s'imposer malgré le blocage.

**Q5.3 — Principe LSDOU (de la moins prioritaire à la plus prioritaire) :**
1. **L**ocal (stratégie de groupe locale de la machine)
2. **S**ite (GPO liée au site AD)
3. **D**omaine (GPO liée au domaine)
4. **O**U (GPO liée à l'OU, la plus proche de l'objet gagnant en dernier)
Les paramètres appliqués en dernier (OU la plus proche) l'emportent en cas de conflit, sauf usage d'**Enforced** ou de **Bloquer l'héritage**.

**Q5.4 — Filtre WMI, avec un exemple concret ici :**
Un filtre WMI permet de restreindre l'application d'une GPO selon des critères techniques de la machine (OS, quantité de RAM, modèle...), évalués via une requête WQL. Exemple concret utilisable ici : n'appliquer **GPO 8 (déploiement MSI)** qu'aux machines exécutant Windows 11 :
```sql
SELECT * FROM Win32_OperatingSystem WHERE Version LIKE "10.0.22%"
```

**Q5.5 — Commande PowerShell pour forcer la mise à jour des GPO sur un client :**
```powershell
Invoke-GPUpdate -Computer "RH01<prenom>" -Force
```
(ou directement en local sur le client, en ligne de commande classique : `gpupdate /force`)

**Q5.6 — Différence entre stratégies (Policies) et préférences (Preferences) :**
Les **Policies** sont **imposées** : l'utilisateur ne peut pas les modifier, et le paramètre disparaît/se remet en place si la GPO est retirée. Les **Preferences** (comme le mapping de lecteur en GPO 4) **définissent une valeur par défaut modifiable** : l'utilisateur peut la changer, et si la GPO est retirée, la dernière valeur appliquée reste en place (pas de "retour en arrière" automatique) — sauf si l'option "Supprimer cet élément lorsqu'il n'est plus appliqué" est cochée.

---

## Checklist finale avant remise

- [ ] Domaine `ex-<prenom>.final` accessible depuis les 2 clients
- [ ] 50 utilisateurs créés et répartis dans les bonnes OUs
- [ ] Chaque utilisateur dans son groupe de service (AGDLP)
- [ ] Profil itinérant + lecteur Z: fonctionnels
- [ ] Au moins 5 GPO appliquées (vérifié par `gpresult /r`)
- [ ] 17 captures d'écran intégrées dans le document
- [ ] Scripts PowerShell dans `C:\Scripts` sur le bureau du serveur
- [ ] `employes.csv` contient 50 entrées valides
- [ ] Dépôt effectué sur ISGA-Elearning avant le délai