##

<#
.SYNOPSIS
    Automated Active Directory Health Check Script
.DESCRIPTION
    Audits Core AD Services, Replication Status, FSMO Roles, Time Sync, and Event Logs.
#>

[CmdletBinding()]
param (
    [string]$LogPath = "C:\ADHealthCheck_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

# Initialize Output Buffer
$Report = [System.Collections.Generic.List[string]]::new()
function Write-Report {
    param([string]$Message)
    Write-Host $Message
    $Report.Add($Message)
}

Write-Report "===================================================="
Write-Report "   ACTIVE DIRECTORY HEALTH CHECK REPORT"
Write-Report "   Generated: $(Get-Date)"
Write-Report "====================================================`n"

# 1. Retrieve Domain Controllers
try {
    $DCs = Get-ADDomainController -Filter *
    Write-Report "[+] Found $($DCs.Count) Domain Controller(s) in domain."
} catch {
    Write-Report "[!] ERROR: Unable to query Active Directory Domain Controllers. Exiting."
    exit
}

# 2. Check FSMO Roles
Write-Report "`n--- [FSMO ROLE HOLDERS] ---"
try {
    $Domain = Get-ADDomain$Forest = Get-ADForest
    Write-Report "Schema Master:       $($Forest.SchemaMaster)"
    Write-Report "Domain Naming:       $($Forest.DomainNamingMaster)"
    Write-Report "PDC Emulator:        $($Domain.PDCEmulator)"
    Write-Report "RID Master:          $($Domain.RIDMaster)"
    Write-Report "Infrastructure:      $($Domain.InfrastructureMaster)"
} catch {
    Write-Report "[!] Error retrieving FSMO Role holders."
}

# 3. Domain Controller Health Checks
$RequiredServices = 'NTDS', 'DNS', 'KDC', 'Netlogon', 'W32Time'

foreach ($DC in $DCs) {
    $DCName =$DC.HostName
    Write-Report "`n===================================================="
    Write-Report " AUDITING DC: $DCName"
    Write-Report "===================================================="

    # Ping Connectivity Test
    if (-not (Test-Connection -ComputerName $DCName -Count 1 -Quiet)) {
        Write-Report "[!] CRITICAL: $DCName is Offline / Unreachable via ICMP."
        continue
    }

    # A. Core AD Services Status
    Write-Report "`n  [Services Status]"
    try {
        $Services = Get-Service -ComputerName $DCName -Name$RequiredServices -ErrorAction Stop
        foreach ($Svc in $Services) {
            $StatusStr = if ($Svc.Status -eq 'Running') { "PASS" } else { "FAIL" }
            Write-Report "  - [$StatusStr] $($Svc.Name) ($($Svc.DisplayName)): $($Svc.Status)"
        }
    } catch {
        Write-Report "  [!] Failed to query services via WinRM/RPC on $DCName"
    }

    # B. Time Synchronization
    Write-Report "`n  [Time Sync Check]"
    try {
        $TimeStatus = Invoke-Command -ComputerName $DCName -ScriptBlock { w32tm /query /status } -ErrorAction Stop
        $Source = ($TimeStatus | Select-String "Source:").ToString().Trim()
        Write-Report "  - $Source"
    } catch {
        Write-Report "  [!] Unable to query time status on $DCName"
    }

    # C. Critical Event Log Errors (Last 24 Hours)
    Write-Report "`n  [Critical Event Logs (Last 24 Hours)]"
    $LogNames = @('Directory Service', 'DNS Server', 'System'); $StartTime = (Get-Date).AddHours(-24)

    foreach ($Log in $LogNames) {
        try {
            $Errors = Get-WinEvent -ComputerName$DCName -FilterHashtable @{
                LogName   = $Log
                Level     = 1, 2 # Error, Critical
                StartTime = $StartTime
            } -ErrorAction SilentlyContinue

            if ($Errors) {
                Write-Report "  - [WARNING] $Log Log has $($Errors.Count) Error/Critical events."
            } else {
                Write-Report "  - [PASS] $Log Log is clear."
            }
        } catch {
            Write-Report "  - [!] Could not query $Log Log on$DCName"
        }
    }
}

# 4. Active Directory Replication Summary
Write-Report "`n===================================================="
Write-Report " AD REPLICATION HEALTH SUMMARY"
Write-Report "===================================================="
try {
    $ReplSummary = repadmin /replsummary
    foreach ($Line in $ReplSummary) {
        Write-Report $Line
    }
} catch {
    Write-Report "[!] Failed to execute repadmin /replsummary."
}

# Export Report to Text File
$Report | Out-File -FilePath $LogPath -Encoding utf8
Write-Host "`n[+] Audit Complete. Full report saved to: $LogPath" -ForegroundColor Green
