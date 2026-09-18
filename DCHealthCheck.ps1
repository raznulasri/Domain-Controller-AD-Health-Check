
echo "Domain Controller Health"
Get-Service -Name NTDS, DNS, KDC, Netlogon, W32Time | Select-Object Name, DisplayName, Status, StartType

echo "Replication"
repadmin /showrepl
redamin /replsummary

echo "SYSVOL Synchronization"
dfsrmig /getglobalstate

echo "Diagnostic test across all core DC roles, services, security, and DNS configurations."
dcdiag /v

echo "FSMO Roles"
netdom query fsmo









Manual
## echo "Forces immediate Active Directory (AD) replication"
# repadmin /syncall /AeD








