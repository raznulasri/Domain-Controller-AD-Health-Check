<#
.SYNOPSIS
    Automated Active Directory Health Check Script (HTML Output)
.DESCRIPTION
    Audits Core AD Services, Replication Status, FSMO Roles, Time Sync, and Event Logs,
    outputting a styled HTML report.
#>

[CmdletBinding()]
param (
    [string]$LogPath = "C:\ADHealthCheck_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
)

# 1. Retrieve Domain Controllers & FSMO
try {
    $DCs = Get-ADDomainController -Filter *
    $Domain = Get-ADDomain
    $Forest = Get-ADForest
} catch {
    Write-Host "[!] ERROR: Unable to query Active Directory. Exiting." -ForegroundColor Red
    exit
}

# 2. Build DC Audit Data
$RequiredServices = 'NTDS', 'DNS', 'KDC', 'Netlogon', 'W32Time'
$DCResults = [System.Collections.Generic.List[PSObject]]::new()

foreach ($DC in $DCs) {
    $DCName = $DC.HostName
    $Ping = Test-Connection -ComputerName $DCName -Count 1 -Quiet
    
    if (-not $Ping) {
        $DCResults.Add([PSCustomObject]@{
            DCName     = $DCName
            Status     = "Offline"
            Services   = "N/A"
            TimeSync   = "N/A"
            EventLogs  = "N/A"
        })
        continue
    }

    # Services Check
    $SvcSummary = try {
        $Services = Get-Service -ComputerName $DCName -Name $RequiredServices -ErrorAction Stop
        $Failed = $Services | Where-Object { $_.Status -ne 'Running' }
        if ($Failed) { "$($Failed.Count) Stopped" } else { "All Running" }
    } catch { "Query Failed" }

    # Time Sync Check
    $TimeSource = try {
        $TimeStatus = Invoke-Command -ComputerName $DCName -ScriptBlock { w32tm /query /status } -ErrorAction Stop
        ($TimeStatus | Select-String "Source:").ToString().Replace("Source:", "").Trim()
    } catch { "Query Failed" }

    # Event Logs Check
    $LogNames = @('Directory Service', 'DNS Server', 'System')
    $StartTime = (Get-Date).AddHours(-24)
    $LogSummary = try {
        $TotalErrors = 0
        foreach ($Log in $LogNames) {
            $Errors = Get-WinEvent -ComputerName $DCName -FilterHashtable @{
                LogName   = $Log
                Level     = 1, 2
                StartTime = $StartTime
            } -ErrorAction SilentlyContinue
            if ($Errors) { $TotalErrors += $Errors.Count }
        }
        if ($TotalErrors -gt 0) { "$TotalErrors Errors (24h)" } else { "Clean" }
    } catch { "Query Failed" }

    $DCResults.Add([PSCustomObject]@{
        DCName    = $DCName
        Status    = "Online"
        Services  = $SvcSummary
        TimeSync  = $TimeSource
        EventLogs = $LogSummary
    })
}

# 3. Replication Summary
$ReplOutput = try {
    (repadmin /replsummary) -join "`n"
} catch { "Failed to execute repadmin /replsummary." }

# 4. Generate HTML Content
$HTMLHeader = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f6f9; color: #333; margin: 20px; }
        h1 { color: #0056b3; border-bottom: 2px solid #0056b3; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #0056b3; color: white; }
        tr:hover { background-color: #f1f1f1; }
        .badge-pass { background-color: #28a745; color: white; padding: 4px 8px; border-radius: 4px; font-weight: bold; }
        .badge-fail { background-color: #dc3545; color: white; padding: 4px 8px; border-radius: 4px; font-weight: bold; }
        .badge-warn { background-color: #ffc107; color: #333; padding: 4px 8px; border-radius: 4px; font-weight: bold; }
        pre { background: #1e1e1e; color: #d4d4d4; padding: 15px; border-radius: 5px; overflow-x: auto; font-family: 'Consolas', monospace; }
    </style>
</head>
<body>
    <h1>Active Directory Health Check Report</h1>
    <p><strong>Generated:</strong> $(Get-Date)</p>

    <div class="card">
        <h2>FSMO Role Holders</h2>
        <table>
            <tr><th>Role</th><th>Server</th></tr>
            <tr><td>Schema Master</td><td>$($Forest.SchemaMaster)</td></tr>
            <tr><td>Domain Naming Master</td><td>$($Forest.DomainNamingMaster)</td></tr>
            <tr><td>PDC Emulator</td><td>$($Domain.PDCEmulator)</td></tr>
            <tr><td>RID Master</td><td>$($Domain.RIDMaster)</td></tr>
            <tr><td>Infrastructure Master</td><td>$($Domain.InfrastructureMaster)</td></tr>
        </table>
    </div>

    <div class="card">
        <h2>Domain Controllers Status</h2>
        <table>
            <tr>
                <th>DC Name</th>
                <th>Ping Status</th>
                <th>Services</th>
                <th>Time Source</th>
                <th>Event Logs (24h)</th>
            </tr>
"@

$HTMLRows = ""
foreach ($Res in $DCResults) {
    $StatusBadge = if ($Res.Status -eq "Online") { "<span class='badge-pass'>Online</span>" } else { "<span class='badge-fail'>Offline</span>" }
    $SvcBadge    = if ($Res.Services -eq "All Running") { "<span class='badge-pass'>All Running</span>" } else { "<span class='badge-fail'>$($Res.Services)</span>" }
    $LogBadge    = if ($Res.EventLogs -eq "Clean") { "<span class='badge-pass'>Clean</span>" } else { "<span class='badge-warn'>$($Res.EventLogs)</span>" }

    $HTMLRows += @"
            <tr>
                <td><strong>$($Res.DCName)</strong></td>
                <td>$StatusBadge</td>
                <td>$SvcBadge</td>
                <td>$($Res.TimeSync)</td>
                <td>$LogBadge</td>
            </tr>
"@
}

$HTMLFooter = @"
        </table>
    </div>

    <div class="card">
        <h2>AD Replication Summary</h2>
        <pre>$ReplOutput</pre>
    </div>
</body>
</html>
"@

# Output & Save
$FinalHTML = $HTMLHeader + $HTMLRows + $HTMLFooter
$FinalHTML | Out-File -FilePath $LogPath -Encoding utf8

Write-Host "[+] Health check complete! Report saved to: $LogPath" -ForegroundColor Green
Invoke-Item $LogPath