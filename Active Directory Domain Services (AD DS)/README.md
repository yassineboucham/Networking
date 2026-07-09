# Active Directory Domain Services (AD DS) — Complete Mastery Guide
## Practical Case Study: Riad des Bijoux

> **Note on language**: This guide is written entirely in English. Wherever a Windows Server UI path is given, the **French Windows menu label** is also shown in brackets `[FR: ...]`, because in real environments (especially in Morocco/France) you will often click through a French-language Windows Server, and the menu wording does *not* match the English documentation word-for-word. That is the only place two languages appear — everything else (explanations, concepts, tips) is English only.

---

## 📌 Table of Contents
1. [What is Active Directory?](#1-what-is-active-directory)
2. [Key Concepts (Expanded Glossary)](#2-key-concepts-expanded-glossary)
3. [AD DS Architecture](#3-ad-ds-architecture)
4. [Roles vs Features](#4-roles-vs-features)
5. [How Authentication Actually Works (Kerberos & LDAP)](#5-how-authentication-actually-works-kerberos--ldap)
6. [Scenario: Riad des Bijoux](#6-scenario-riad-des-bijoux)
7. [Step-by-Step Implementation](#7-step-by-step-implementation)
8. [FSMO Roles in Depth](#8-fsmo-roles-in-depth)
9. [Group Policy Deep Dive](#9-group-policy-deep-dive)
10. [Password Policies & Fine-Grained Password Policies](#10-password-policies--fine-grained-password-policies)
11. [Backup, Recovery & AD Recycle Bin](#11-backup-recovery--ad-recycle-bin)
12. [Security Hardening Essentials](#12-security-hardening-essentials)
13. [Essential PowerShell Cmdlet Reference](#13-essential-powershell-cmdlet-reference)
14. [Troubleshooting](#14-troubleshooting)
15. [Practice Exercises (Test Yourself)](#15-practice-exercises-test-yourself)
16. [Summary](#16-summary)

---

## 1. What is Active Directory?

**Active Directory Domain Services (AD DS)** is Microsoft's directory service. It runs on a server called a **Domain Controller (DC)** and centralizes:

- Management of **users** and **groups**
- Management of **computers** joined to the network
- **Single Sign-On (SSO)** authentication — one login grants access to every authorized resource
- Enforcement of **security and configuration rules** through Group Policy Objects (GPOs)

**Why use it?**
Without AD DS, every workstation manages its own local accounts — unmanageable once a company grows past a handful of employees. With AD DS:
- Each employee has **one single account** valid on every machine in the network
- Administrators can **apply rules at scale** (block Control Panel, force a wallpaper, restrict USB access, etc.)
- **Security** is centralized (passwords, account lockout policies, permissions, auditing)
- IT staff can **delegate specific administrative tasks** without granting full admin rights

**Deeper context — what AD actually *is* under the hood:**
AD DS is, technically, an **LDAP-compliant hierarchical database** (a directory, not a relational database like SQL). Every object — user, computer, group, OU, printer — is stored as an entry with a unique **Distinguished Name (DN)**, e.g.:

```
CN=Yassine Alaoui,OU=OU_IT,DC=riaddesbijoux,DC=com
```

This is why AD scales so well: lookups are optimized for read-heavy, hierarchical, attribute-based queries (find all users in this OU, find this group's members), not for transactional writes like a financial database.

---

## 2. Key Concepts (Expanded Glossary)

| Term | Explanation |
|---|---|
| **Domain** | A logical management boundary (e.g. `riaddesbijoux.com`) grouping users, computers, and policies under one security authority. |
| **Forest** | The top-level container: one or more domains sharing a common schema, configuration partition, and Global Catalog. A forest is the actual security boundary in AD — not the domain. |
| **Tree** | A group of domains within a forest that share a contiguous DNS namespace (e.g. `riaddesbijoux.com` and `europe.riaddesbijoux.com`). |
| **Domain Controller (DC)** | A server hosting AD DS, handling authentication (Kerberos/NTLM) and replication of the directory database. |
| **OU (Organizational Unit)** | A logical "folder" to organize objects and target GPOs precisely. Unlike a plain container, GPOs and delegated permissions can be linked to an OU. |
| **GPO (Group Policy Object)** | A set of rules automatically applied to users/computers in an OU, domain, or site. |
| **Schema** | The blueprint defining every object class and attribute AD can store, shared forest-wide. Extending the schema (e.g. for Exchange) is a forest-wide, largely irreversible operation. |
| **Global Catalog (GC)** | A partial, searchable copy of all objects in the *entire forest* (not just the local domain), used for fast cross-domain lookups and for UPN logon. |
| **FSMO Roles** | Five special roles held by specific DCs to avoid write conflicts on data that can't be multi-mastered. Covered in detail in Section 8. |
| **SYSVOL** | A shared folder (`\\domain\SYSVOL`) replicated across all DCs via DFS-R (or the legacy FRS), storing GPO files and logon scripts. |
| **NTDS.dit** | The actual AD database file (ESE/JET database engine), stored locally at `%SystemRoot%\NTDS\ntds.dit` on every DC. |
| **Trust** | A relationship allowing users in one domain/forest to authenticate and access resources in another. Can be one-way or two-way, transitive or non-transitive. |
| **DNS integration** | AD DS is entirely dependent on DNS for locating DCs and services via **SRV records** (e.g. `_ldap._tcp.riaddesbijoux.com`, `_kerberos._tcp.riaddesbijoux.com`). If DNS breaks, AD effectively breaks. |
| **SID (Security Identifier)** | A unique value assigned to every security principal (user, group, computer). Permissions are actually stored against the SID, not the name — this is why renaming an account doesn't break its permissions. |
| **RODC (Read-Only Domain Controller)** | A DC that holds a read-only copy of the database — used in branch offices with weak physical security, since a stolen RODC can't be used to push malicious changes back. |
| **Site** | A physical/network location (defined by IP subnets) used to control replication traffic and help clients find the nearest DC. |
| **AGDLP / AGUDLP** | A best-practice model for nesting: put **A**ccounts into **G**lobal groups, Global groups into **D**omain **L**ocal groups, and assign **P**ermissions to the Domain Local group. This keeps permission management scalable across domains. |
| **Tombstone lifetime** | How long a deleted AD object is retained (marked as deleted, not purged) before permanent removal — default 180 days on modern forests, relevant for disaster recovery windows. |

---

## 3. AD DS Architecture

A typical AD DS environment includes:
- **One or more Domain Controllers** replicating data with each other (**multi-master replication** — any writable DC can accept changes, which then propagate to the others)
- **DNS Server role**, usually installed on the same server, since AD DS registers itself in DNS via SRV records
- **NTDS.dit** — the AD database file stored locally on each DC
- **Sites and Subnets** — used in larger networks to control replication traffic between physical locations
- **KCC (Knowledge Consistency Checker)** — an automatic process on every DC that builds the replication topology (who replicates with whom) so admins don't have to configure it manually
- **Replication protocol** — intra-site replication uses RPC over IP and triggers quickly (within seconds, change-notification driven); inter-site replication uses a schedule (default every 180 minutes) and can use RPC or SMTP for certain partitions

For a small lab like Riad des Bijoux, one DC hosting both AD DS and DNS is enough. In production, Microsoft recommends **at least two DCs** per domain for redundancy — if the only DC dies, authentication for the entire network stops.

**Partitions inside the AD database (worth knowing for interviews and exams):**
| Partition | Replicates to | Contains |
|---|---|---|
| Domain (Naming Context) | All DCs in the same domain | Users, groups, computers, OUs |
| Configuration | All DCs in the forest | Sites, services, replication topology |
| Schema | All DCs in the forest | Class and attribute definitions |
| Application (optional) | Only DCs you specify | DNS zones (`ForestDnsZones`, `DomainDnsZones`), custom app data |

---

## 4. Roles vs Features

Windows Server ships as a bare OS by default — nothing is enabled unless you explicitly add it. This modular design has three benefits:
1. **Security** — fewer active services means a smaller attack surface
2. **Performance** — no wasted RAM/CPU on unused services
3. **Clarity** — a server with one clear purpose is easier to maintain and troubleshoot

- A **Role** turns the server into something specific on the network (e.g. Domain Controller, DNS Server, File Server, Web Server/IIS)
- A **Feature** is a supporting component that complements a role or works independently (e.g. .NET Framework, Windows Backup, BitLocker, RSAT tools)

**Rule of thumb for exams and real deployments:** if it's something the server *does* for the network (serves files, resolves DNS, authenticates users) → Role. If it's something that *supports or manages* the server itself → Feature.

---

## 5. How Authentication Actually Works (Kerberos & LDAP)

This section wasn't in the original notes but is essential to actually *master* AD rather than just click through wizards.

**Kerberos, in plain terms:**
1. You log on → your workstation sends your hashed credentials to a DC's **Key Distribution Center (KDC)** service.
2. The KDC verifies you and issues a **Ticket Granting Ticket (TGT)**, valid by default for 10 hours.
3. When you try to access a resource (e.g. a file share), your machine presents the TGT to the KDC and receives a **service ticket** specific to that resource.
4. The service ticket is presented to the target server, which trusts it without contacting the DC again.

This is why **time synchronization matters so much**: Kerberos tickets are time-stamped, and by default any client whose clock drifts more than **5 minutes** from the DC will fail to authenticate — this is the #1 cause of "random" login failures in AD environments.

**LDAP, in plain terms:**
LDAP (Lightweight Directory Access Protocol) is the query language/protocol used to *read and write* objects in AD — port **389** (plain) or **636** (LDAPS, encrypted). Tools like ADUC, PowerShell's AD module, and third-party apps (e.g. VPN appliances doing "AD authentication") all talk LDAP or Kerberos under the hood.

| Port | Protocol | Purpose |
|---|---|---|
| 53 | DNS | Locating DCs/services |
| 88 | Kerberos | Authentication |
| 389 | LDAP | Directory queries (unencrypted) |
| 636 | LDAPS | Directory queries (TLS encrypted) |
| 445 | SMB | SYSVOL/NETLOGON share access, file access |
| 3268 / 3269 | Global Catalog | Forest-wide searches (plain / TLS) |

---

## 6. Scenario: Riad des Bijoux

**Context**: Riad des Bijoux is a jewelry shop / e-commerce business with several departments (Management, Sales, Accounting, IT). We want to centralize account and computer management through an Active Directory domain.

**Domain name**: `riaddesbijoux.com`

**Lab infrastructure**:
- `SRV-ADDS` — Windows Server 2022/2025 → future Domain Controller
- `PC-CLIENT` — Windows 11 → workstation that will join the domain

**Minimum lab specs worth noting:**
- DC: 2 vCPU, 4 GB RAM minimum (8 GB more comfortable), 60 GB disk
- Client: 2 vCPU, 4 GB RAM
- Both VMs on the same **internal/private virtual network** (not bridged to your home Wi-Fi, to avoid IP conflicts or accidentally broadcasting a rogue DNS server on your real network)

---

## 7. Step-by-Step Implementation

### Step 1 — Network Preparation

Create two VMs (VirtualBox or Hyper-V) on the same internal network:
- `SRV-ADDS`: static IP `192.168.10.10`
- `PC-CLIENT`: DHCP or static IP on the same subnet

On the server, configure:
```
IP: 192.168.10.10
Subnet mask: 255.255.255.0
Gateway: 192.168.10.1
DNS: 127.0.0.1
```

**Why DNS = 127.0.0.1 on the DC?** Once you install the DNS role (Step 3), the server becomes its own DNS server. Pointing it to itself ensures it can resolve its own SRV records immediately and doesn't depend on an external resolver that knows nothing about your domain.

📸 *Screenshot placeholder: static IP configuration window — English: "Internet Protocol Version 4 (TCP/IPv4) Properties" — French Windows: "Propriétés de Protocole Internet version 4 (TCP/IPv4)"*

---

### Step 2 — Add the AD DS Role

Path (English Windows): `Server Manager → Manage → Add Roles and Features → Role-based or feature-based installation → Select server → check "Active Directory Domain Services" → Add Features (when prompted) → Install`

`[FR: Gestionnaire de serveur → Gérer → Ajouter des rôles et fonctionnalités → Installation basée sur un rôle ou une fonctionnalité → Sélectionner le serveur → cocher "Services AD DS" → Ajouter des fonctionnalités → Installer]`

📸 *Screenshot placeholder: "Add Roles and Features Wizard" — AD DS selection*
📸 *Screenshot placeholder: installation completion confirmation*

PowerShell equivalent:
```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
```

**Extra detail:** `-IncludeManagementTools` pulls in RSAT (ADUC, ADAC, GPMC, DNS console) automatically — skip it only if you plan to manage the server exclusively through PowerShell/remote tools.

---

### Step 3 — Promote the Server to Domain Controller

Path: `Server Manager → (yellow flag notification) → Promote this server to a domain controller → Add a new forest → Root domain name: riaddesbijoux.com`

`[FR: Gestionnaire de serveur → (notification drapeau jaune) → Promouvoir ce serveur en contrôleur de domaine → Ajouter une nouvelle forêt → Nom de domaine racine : riaddesbijoux.com]`

📸 *Screenshot placeholder: "Add a new forest" wizard step*

Next, set:
- Forest/domain functional level: Windows Server 2016 or higher (higher functional levels unlock features like fine-grained password policies, AD Recycle Bin, but drop support for older DCs — pick the highest level your environment allows)
- DSRM (Directory Services Restore Mode) password — **this is a separate local admin-style password used only to boot into recovery mode; write it down somewhere safe, it's easy to forget since it's never used day-to-day**
- Ignore the "DNS delegation not created" warning (normal in a lab — it only matters if this domain needs to be discoverable from a parent public DNS zone)
- Verify the auto-generated NetBIOS name (`RIADDESBIJOUX`)
- Run prerequisite checks → Install

📸 *Screenshot placeholder: "Domain Controller Options" step — DSRM password*
📸 *Screenshot placeholder: "Prerequisites Check passed" final screen*

The server restarts and becomes **DC01.riaddesbijoux.com**.

PowerShell equivalent:
```powershell
Install-ADDSForest `
  -DomainName "riaddesbijoux.com" `
  -DomainNetbiosName "RIADDESBIJOUX" `
  -InstallDns:$true `
  -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force)
```

---

### Step 4 — Create Organizational Units (OUs)

Open `Active Directory Users and Computers` (`dsa.msc`)

`[FR: "Utilisateurs et ordinateurs Active Directory", même commande dsa.msc]`

Structure to create:
```
riaddesbijoux.com
├── OU_Management
├── OU_Sales
├── OU_Accounting
├── OU_IT
├── OU_Groups
└── OU_Computers
```

Path: `Right-click domain → New → Organizational Unit → enter name → OK`

`[FR: Clic droit sur le domaine → Nouveau → Unité d'organisation → saisir le nom → OK]`

📸 *Screenshot placeholder: ADUC window with created OUs*

**Design tip:** avoid mirroring the org chart too literally as you scale — many admins split OU structure by **object type first** (Users / Computers / Groups / Service Accounts) and then by department underneath, because GPOs almost never need to apply identically to users and their computers.

**Protect from accidental deletion:** every OU has a checkbox "Protect object from accidental deletion" — leave it checked in production; it just adds a deny-ACE against delete, easily removed by an admin who really means it.

---

### Step 5 — Create Security Groups

Inside `OU_Groups`, create:
```
GRP_Sales
GRP_Accounting
GRP_Management
GRP_IT_Admins
```
Type: **Security** — Scope: **Global**

Path: `Right-click OU → New → Group → enter name → Group scope: Global → Group type: Security → OK`

`[FR: Clic droit sur l'OU → Nouveau → Groupe → saisir le nom → Étendue du groupe : Globale → Type de groupe : Sécurité → OK]`

📸 *Screenshot placeholder: "New Object - Group" window*

**Security vs Distribution groups:** Security groups can be used both for permissions *and* email distribution (if mail-enabled later); Distribution groups are email-only and carry no security token — never use a Distribution group to grant file/folder access, it simply won't work.

**Group scope cheat sheet:**
| Scope | Can contain members from | Can be used for permissions in |
|---|---|---|
| Domain Local | Any domain in the forest (or trusted forest) | Only its own domain |
| Global | Only its own domain | Any domain in the forest (or trusted forest) |
| Universal | Any domain in the forest | Any domain in the forest |

---

### Step 6 — Create Users

| Name | Login (UPN) | OU | Group |
|---|---|---|---|
| Yassine Alaoui | y.alaoui@riaddesbijoux.com | OU_IT | GRP_IT_Admins |
| Fatima Zahra | f.zahra@riaddesbijoux.com | OU_Sales | GRP_Sales |
| Karim Idrissi | k.idrissi@riaddesbijoux.com | OU_Accounting | GRP_Accounting |

Path: `Right-click OU → New → User → fill in first/last name and logon name → Next → set password → check "User must change password at next logon" → Next → Finish`

`[FR: Clic droit sur l'OU → Nouveau → Utilisateur → remplir prénom/nom et nom d'ouverture de session → Suivant → définir le mot de passe → cocher "L'utilisateur doit changer le mot de passe à la prochaine ouverture de session" → Suivant → Terminer]`

📸 *Screenshot placeholder: "New Object - User" wizard*

Then add each user to their group:
`Right-click user → Properties → Member Of tab → Add → type group name → Check Names → OK`

`[FR: Clic droit sur l'utilisateur → Propriétés → onglet "Membre de" → Ajouter → saisir le nom du groupe → Vérifier les noms → OK]`

📸 *Screenshot placeholder: "Member Of" tab of a user's properties*

**Faster alternative for many users:** bulk-create with PowerShell instead of clicking through the wizard 50 times:
```powershell
New-ADUser -Name "Fatima Zahra" -GivenName "Fatima" -Surname "Zahra" `
  -SamAccountName "f.zahra" -UserPrincipalName "f.zahra@riaddesbijoux.com" `
  -Path "OU=OU_Sales,DC=riaddesbijoux,DC=com" `
  -AccountPassword (ConvertTo-SecureString "Temp@1234" -AsPlainText -Force) `
  -Enabled $true -ChangePasswordAtLogon $true

Add-ADGroupMember -Identity "GRP_Sales" -Members "f.zahra"
```
Or import a whole department from CSV — this is the realistic way large onboarding batches are handled in production.

---

### Step 7 — NTFS Permissions and Shares

Create a shared folder `D:\Shares\Sales`:

Path: `Right-click folder → Properties → Security tab → Edit → Add → GRP_Sales → check "Modify" → OK`
Then: `Sharing tab → Advanced Sharing → check "Share this folder" → Permissions → GRP_Sales → check Change/Read → OK`

`[FR: Clic droit sur le dossier → Propriétés → onglet "Sécurité" → Modifier → Ajouter → GRP_Sales → cocher "Modification" → OK, puis onglet "Partage" → "Partage avancé" → cocher "Partager ce dossier" → Autorisations → GRP_Sales → cocher Modifier/Lecture → OK]`

📸 *Screenshot placeholder: "Security" tab of the shared folder with permissions*

**Why set permissions in two places (NTFS *and* Share)?** The *effective* permission a user ends up with is always the **most restrictive** of the two. Best practice: set the **Share** permission loosely (Everyone: Change) and control the real restriction entirely through **NTFS** permissions — this avoids confusion when troubleshooting "why can't they access this" later.

---

### Step 8 — Delegation of Control

**Goal:** allow `GRP_IT_Admins` to reset passwords for `OU_Sales` users without full Domain Admin rights.

Path: `Right-click OU_Sales → Delegate Control → Next → Add GRP_IT_Admins → Next → check "Reset user passwords and force password change at next logon" → Next → Finish`

`[FR: Clic droit sur OU_Vente → Délégation de contrôle → Suivant → Ajouter GRP_Informatique_Admins → Suivant → cocher "Réinitialiser les mots de passe utilisateur et forcer le changement à la prochaine ouverture de session" → Suivant → Terminer]`

📸 *Screenshot placeholder: "Delegation of Control Wizard"*

**Why this matters:** delegation is the core tool for implementing **least privilege** in AD. A help-desk team should almost never be a member of Domain Admins — delegated, scoped rights on specific OUs achieve the same day-to-day capability with far less blast radius if an account is compromised.

---

### Step 9 — Domain Join (Windows 11 Client)

1. Set the client's network adapter DNS to `192.168.10.10`
2. Open `System Properties` (`sysdm.cpl`)
3. Path: `Computer Name tab → Change → Member of: Domain → type riaddesbijoux.com → OK`

`[FR: Onglet "Nom de l'ordinateur" → Modifier → Membre de : Domaine → taper riaddesbijoux.com → OK]`

4. Enter domain admin credentials when prompted
5. Restart the workstation

📸 *Screenshot placeholder: "Computer Name/Domain Changes" window*
📸 *Screenshot placeholder: "Welcome to the riaddesbijoux.com domain" message*

PowerShell equivalent:
```powershell
Add-Computer -DomainName "riaddesbijoux.com" -Credential (Get-Credential) -Restart
```

⚠️ **Common bug:** infinite password-change loop at first logon → check time synchronization (NTP) between client and DC, and password complexity requirements.

**Extra detail:** once joined, the computer object lands in the default `Computers` container, *not* `OU_Computers`. Move it manually (or pre-provision the computer account in the right OU first with `New-ADComputer`) so it inherits the correct GPOs immediately.

---

### Step 10 — Group Policy Objects (GPO)

Open `Group Policy Management` (`gpmc.msc`)

Example: block Control Panel access for the Sales staff.

Path: `Right-click OU_Sales → Create a GPO in this domain, and Link it here → name: GPO_Restrict_Sales → right-click GPO → Edit → User Configuration → Administrative Templates → Control Panel → enable "Prohibit access to Control Panel and PC settings"`

`[FR: Clic droit sur OU_Vente → Créer un objet GPO dans ce domaine, et le lier ici → nom : GPO_Restriction_Vente → clic droit sur la GPO → Modifier → Configuration utilisateur → Modèles d'administration → Panneau de configuration → activer "Interdire l'accès au Panneau de configuration et aux paramètres PC"]`

📸 *Screenshot placeholder: Group Policy Management Editor*

**GPO Best Practices:**
- One GPO = one clear purpose
- Use clear names (never `GPO1`, `GPO2`...)
- Always test on a dedicated test OU before production
- Use **Security Filtering** to target specific groups instead of the whole OU when needed
- Use `gpupdate /force` sparingly in production — schedule instead of forcing on every machine at once

**Verification on the client:**
```cmd
gpupdate /force
gpresult /r
```

📸 *Screenshot placeholder: `gpresult /r` command output*

**Debugging a GPO that doesn't apply:**
```cmd
gpresult /h report.html
```
Check: computer/user is in the correct OU, the GPO is linked and enabled (not disabled), no security filtering is blocking the group, no WMI filter excluding the target, and replication has completed across DCs (in multi-DC environments).

See Section 9 for a much deeper GPO breakdown.

---

## 8. FSMO Roles in Depth

FSMO (Flexible Single Master Operations) exists because a handful of operations in AD can't safely be multi-mastered — if two DCs made conflicting changes simultaneously, the directory could become inconsistent. Instead, one DC at a time "owns" each role.

| Role | Scope | What breaks if it's offline |
|---|---|---|
| **Schema Master** | Forest-wide (1 per forest) | Can't extend the schema (e.g. installing Exchange, upgrading DC OS version in some cases) |
| **Domain Naming Master** | Forest-wide (1 per forest) | Can't add/remove domains from the forest |
| **RID Master** | Per domain | New DCs run out of RID pools and can't create new security principals (users/groups/computers) once exhausted |
| **PDC Emulator** | Per domain | Time sync source breaks, password change urgency breaks, GPO "last writer wins" reference breaks, legacy NT4 clients fail |
| **Infrastructure Master** | Per domain | Cross-domain group membership references (in multi-domain forests) can go stale |

**Checking role holders:**
```powershell
netdom query fsmo
```

**Transferring a role (graceful, when the current holder is healthy):**
```powershell
Move-ADDirectoryServerOperationMasterRole -Identity "DC02" -OperationMasterRole SchemaMaster,RIDMaster
```

**Seizing a role (emergency only, when the current holder is dead and won't come back):**
```powershell
Move-ADDirectoryServerOperationMasterRole -Identity "DC02" -OperationMasterRole PDCEmulator -Force
```
⚠️ Never bring the old role holder back online after a seizure without wiping/rebuilding it — you risk USN rollback corruption.

---

## 9. Group Policy Deep Dive

**Processing order (mnemonic: LSDOU):**
1. **L**ocal Group Policy (on the machine itself)
2. **S**ite-linked GPOs
3. **D**omain-linked GPOs
4. **O**U-linked GPOs (closest OU applied last, so it wins conflicts)

Later-applied settings **win** over earlier ones by default, unless a GPO is marked **Enforced** (forces it to win even against a closer OU) or a parent OU is set to **Block Inheritance** (rejected unless the parent GPO is Enforced).

**Computer vs User settings:** Computer Configuration applies at boot (before logon); User Configuration applies at logon. If you need a setting to apply regardless of who logs in, put it under Computer Configuration.

**Loopback processing:** a special mode (`Enabled` under Computer Config → Admin Templates → System → Group Policy) used for shared machines (e.g. a reception kiosk PC) so that the *computer's* OU dictates user settings, not the logged-on user's own OU — critical for terminal-server/kiosk scenarios.

**Common real-world GPO use cases beyond blocking Control Panel:**
- Mapping network drives per department
- Deploying printers automatically
- Enforcing a desktop wallpaper/branding
- Disabling USB storage devices
- Redirecting `Documents`/`Desktop` folders to a network share (Folder Redirection)
- Pushing Windows Update deferral policies
- Deploying software (older method — mostly replaced today by Intune/SCCM, but still seen in smaller shops)

---

## 10. Password Policies & Fine-Grained Password Policies

By default, AD has **one** password/lockout policy per domain, defined in the **Default Domain Policy** GPO:
- Minimum length, complexity, history, max/min password age, account lockout threshold/duration

**Limitation:** you cannot give the IT department a stricter policy than the Sales department using only the Default Domain Policy — it's domain-wide.

**Solution — Fine-Grained Password Policies (FGPP):** available since Windows Server 2008, lets you create multiple **Password Settings Objects (PSOs)** and apply different policies to different security groups.

```powershell
New-ADFineGrainedPasswordPolicy -Name "PSO_ITAdmins" `
  -Precedence 10 -MinPasswordLength 14 -PasswordHistoryCount 24 `
  -LockoutThreshold 3 -ComplexityEnabled $true

Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_ITAdmins" -Subjects "GRP_IT_Admins"
```

Lower `Precedence` number = higher priority when a user is covered by more than one PSO.

---

## 11. Backup, Recovery & AD Recycle Bin

**Enable AD Recycle Bin (huge time-saver, off by default):**
```powershell
Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' `
  -Scope ForestOrConfigurationSet -Target 'riaddesbijoux.com'
```
Once enabled, deleted objects can be restored with all their attributes intact instead of doing a full authoritative restore:
```powershell
Get-ADObject -Filter {displayName -eq "Fatima Zahra"} -IncludeDeletedObjects | Restore-ADObject
```

**System State backup** (covers NTDS.dit, SYSVOL, registry, boot files):
```powershell
wbadmin start systemstatebackup -backupTarget:E:
```

**Authoritative vs non-authoritative restore:** a non-authoritative restore brings a DC back and lets replication catch it up from peers (used for a single failed DC). An authoritative restore (via `ntdsutil`) forces the restored data to overwrite what's on other DCs — used when you need to undo a bad forest-wide change (e.g. accidental mass deletion) that has already replicated everywhere.

---

## 12. Security Hardening Essentials

A few things every AD admin should know beyond the basic lab setup:

- **Tiered administration model**: separate Tier 0 (domain controllers, AD admin accounts), Tier 1 (servers), and Tier 2 (workstations/helpdesk) — never log a Domain Admin account into a regular workstation, since credential theft (e.g. via Mimikatz-style attacks) from that workstation could compromise the entire domain.
- **LAPS (Local Administrator Password Solution)**: randomizes and rotates the local Administrator password on every domain-joined machine, storing it securely in AD — prevents "pass-the-hash" lateral movement using a shared local admin password.
- **Protected Users group**: membership disables NTLM, DES/RC4 Kerberos encryption, and credential caching for that account — use for high-privilege accounts.
- **Disable/rename the built-in Administrator account** where policy allows, or at minimum ensure it has a very strong, unique password and isn't used day-to-day.
- **Least privilege everywhere**: prefer delegation (Section 7, Step 8) over adding people to Domain Admins.
- **Monitor Event ID 4625** (failed logon) and **4768/4769** (Kerberos ticket requests) for signs of brute-force or Kerberoasting attempts.

---

## 13. Essential PowerShell Cmdlet Reference

| Task | Cmdlet |
|---|---|
| Create a user | `New-ADUser` |
| Create a group | `New-ADGroup` |
| Create an OU | `New-ADOrganizationalUnit` |
| Add member to group | `Add-ADGroupMember` |
| Find a user | `Get-ADUser -Filter {Name -like "*zahra*"}` |
| Find locked-out accounts | `Search-ADAccount -LockedOut` |
| Unlock an account | `Unlock-ADAccount -Identity f.zahra` |
| Reset a password | `Set-ADAccountPassword -Identity f.zahra -Reset -NewPassword (ConvertTo-SecureString "New@Pass1" -AsPlainText -Force)` |
| Check FSMO holders | `netdom query fsmo` |
| Check domain/forest functional level | `Get-ADDomain`, `Get-ADForest` |
| Check replication health | `repadmin /replsummary` |
| Force replication | `repadmin /syncall /AdeP` |
| List all GPOs | `Get-GPO -All` |
| Generate GPO report | `Get-GPOReport -All -ReportType Html -Path C:\gpo-report.html` |

---

## 14. Troubleshooting

| Issue | Explanation & Fix |
|---|---|
| **"Domain not found" error** | Check the client's DNS points to the DC's IP, not a public DNS server (like 8.8.8.8). |
| **Password change loop** | Check NTP time sync between client and DC — Kerberos allows a max ~5 minute clock drift. |
| **GPO not applying** | Run `gpresult /r`, check OU placement, GPO link status, security filtering, and WMI filters. |
| **Settings app frozen on "About"** | Use `sysdm.cpl` (System Properties) instead — more reliable for domain join on some Windows 11 builds. |
| **Can't reach the DC** | Test with `ping riaddesbijoux.com` and `nslookup riaddesbijoux.com` from the client. |
| **"Trust relationship between workstation and domain failed"** | Usually means the computer's AD password (yes, computers have passwords too, rotated every 30 days) is out of sync — fix with `Test-ComputerSecureChannel -Repair` or by rejoining the domain. |
| **Replication errors between DCs** | Run `repadmin /replsummary` and `dcdiag /v` — most common causes are DNS misconfiguration or a firewall blocking RPC/AD ports. |
| **Slow logons across sites** | Check Site & Subnet configuration — a client authenticating against a DC in the wrong physical site (because subnets weren't mapped) causes major slowness. |

---

## 15. Practice Exercises (Test Yourself)

To go from "followed the steps" to "actually understands AD," try these without looking back at the guide:

1. Create a 5th OU called `OU_Marketing` and a matching `GRP_Marketing` security group using only PowerShell.
2. Deliberately break Kerberos by setting the client's clock 10 minutes ahead, and observe/document the exact error.
3. Create a Fine-Grained Password Policy that requires 16-character passwords for `GRP_IT_Admins` only, and confirm with `Get-ADUserResultantPasswordPolicy`.
4. Delete a test user, then restore them using the AD Recycle Bin without recreating the account manually.
5. Add a second DC (`DC02`) to the domain, then run `repadmin /replsummary` to confirm replication is healthy.
6. Seize (don't just transfer) a FSMO role from a deliberately powered-off DC in a lab, and understand why this is dangerous in production.
7. Build a GPO that maps a network drive only for `GRP_Sales`, using Security Filtering rather than linking it to `OU_Sales` directly.

---

## 16. Summary

```
Network preparation
   ↓
Add AD DS role
   ↓
Promote to Domain Controller (riaddesbijoux.com)
   ↓
Create OUs
   ↓
Create groups
   ↓
Create users
   ↓
NTFS permissions & shares
   ↓
Delegation of control
   ↓
Join Windows 11 client to domain
   ↓
Configure and verify GPOs
   ↓
(Mastery layer) FSMO awareness → Fine-grained password policies →
Backup/Recycle Bin → Security hardening → PowerShell fluency
```

---

*Document prepared for the Windows Server Administration module — ISGA Marrakech, ISI program.*