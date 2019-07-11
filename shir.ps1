# Entrypoint for the SHIR container
# Written by jack.latrobe@servian.com
$mountPath = "C:\mount\"
$installLog = "$($mountPath)logs\install-shir.log"
$installErrorsLog = "$($mountPath)logs\install-shir-errors.log"
$setKeyLog = "$($mountPath)logs\set-adf-key.log"
$setKeyErrorsLog = "$($mountPath)logs\set-adf-key-errors.log"

$diaCMDPath = "C:\Program Files\Microsoft Integration Runtime\3.0\Shared\diacmd.exe"
$diaCMDMachineIDPath = "HKLM:SOFTWARE\Microsoft\DataTransfer\DataManagementGateway\"

$maxFailCount = 3
$processCheckTimeSecs = 5

$exitOnFail = $FALSE

# Define a meaningful logging function
function Write-SHIR-Log([string]$lineIn)
{
    Write-Host "$(Get-Date -Format '') - $($lineIn)"
}

# Define a check function for diacmd.exe -cgc to confirm gateway is connected
function Check-GatewayConnection([boolean]$LogVerbose = $FALSE)
{
    # Run the diacmd connection check - are we "connected"?
    Start-Process $diaCMDPath -Wait -ArgumentList "-cgc" -RedirectStandardOutput "$($mountPath)status-check.txt"
    $checkResult = Get-Content "$($mountPath)status-check.txt"
    Remove-Item -Force "$($mountPath)status-check.txt"

    if($checkResult -like "Connected")
    {
        if($LogVerbose)
        {
            Write-SHIR-Log "Diacmd.exe reports gateway connected successfully"
        }
        return $TRUE
    }
    else
    {
        Write-SHIR-Log "Diacmd.exe reports error in gateway connected state"
        return $FALSE    
    }
}

# Define a check function for diahost.exe to confirm it's running with a WMI query
function Check-HostService([boolean]$LogVerbose = $FALSE)
{
    $processInfo = $NULL
    try 
    {
        # Is the host process running?
        $processInfo = Get-WmiObject Win32_Process -Filter "name = 'diahost.exe'"
        
        if($processInfo)
        {
            if($LogVerbose)
            {
                Write-SHIR-Log "Diahost.exe is running"
            }
            return $TRUE
        }
        else 
        {
            throw "Process not found"   
        }
    }
    catch 
    {
        Write-SHIR-Log "Diahost.exe is not running"
        return $FALSE
    }
}

# Define a check function to ensure log directory is present
function Check-LogDirectory()
{
    if(Test-Path $mountPath)
    {
        if(-not (Test-Path "$($mountPath)logs"))
        {
            Write-SHIR-Log "Mount location confirmed, but we need to create a log directory"
            New-Item -ItemType Directory "$($mountPath)logs"
        }
        return $TRUE
    }
    else 
    {
        Write-SHIR-Log "Unable to find mount path"
        return $FALSE
    }
} 

# This function updates the registry key for the data factory IR node "MachineID" which allows HA registration
function Set-RegMachineID([string]$MachineId)
{
    if(Test-Path $diaCMDMachineIDPath)
    {
        Write-SHIR-Log "Setting MachineID to: $($MachineId)"
        New-ItemProperty -Path $diaCMDMachineIDPath -Name "MachineId" -Value $MachineId -Force | Out-Null
    }
    else 
    {
        Write-SHIR-Log "Unable to set registry key for SHIR MachineID - will exit instead of deregistering other nodes"
        exit 1
    }
}

##
## CONTAINER ENTRY
##
Write-SHIR-Log "Launching Containerised Azure Data Factory SHIR"

# Check to ensure the "mount" directory is present
if(-not (Check-LogDirectory))
{
    exit 1
}

# Install the included SHIR MSI binary
Write-SHIR-Log "Commencing install of Integration Runtime MSI"
try {
    Start-Process msiexec.exe -Wait -ArgumentList '/I C:\IntegrationRuntime.msi' -RedirectStandardError $installErrorsLog -RedirectStandardOutput $installLog
    if($?) 
    {
        Write-SHIR-Log "Successfully installed SHIR MSI"
    } else 
    {
        throw "SHIR MSI install failed"
    }
}
catch {
    Write-SHIR-Log "SHIR MSI install failed - check $($installLog) for more details"
    exit 1
}

# Before we register, update the MachineID to the hostname
Set-RegMachineID $(hostname)

# Register SHIR with key from Env Variable: ADFKey
if(Test-Path Env:ADFKey)
{
    Write-SHIR-Log "Registering SHIR with key: $((Get-Item Env:ADFKey).Value)"
    # This is the bundled registration wrapper script, but it forces a gateway registration (-rng) whereas we only want node registration (-rn)
    #Start-Process -FilePath "powershell" -Wait -ArgumentList "-File","`"C:\Program Files\Microsoft Integration Runtime\3.0\PowerShellScript\RegisterIntegrationRuntime.ps1`"","`"$((Get-Item Env:ADFKey).Value)`"" -RedirectStandardOutput $setKeyLog -RedirectStandardError $setKeyErrorsLog
    
    # This is the our updated script. It contains more logging and updates the diacmd.exe commands from -rng to -rn
    Start-Process -FilePath "powershell" -Wait -ArgumentList "-File","`"C:\RegisterIntegrationRuntimeNode.ps1`"","`"$((Get-Item Env:ADFKey).Value)`"" -RedirectStandardOutput $setKeyLog -RedirectStandardError $setKeyErrorsLog
    Get-Content $setKeyLog | ForEach-Object {Write-SHIR-Log "$($_)"}
}
else 
{
    Write-SHIR-Log "Env Variable ADFKey is not set - unable to register SHIR and will exit"
    exit 1
}

# Before we start monitoring, it takes some time for the services to start and register
Write-SHIR-Log "Waiting 30 seconds for services to register and become stable before entering monitoring loop"
Start-Sleep -Seconds 30

# Now, we enter into the monitoring loop, that keeps the container alive while the app is healthy
$processInfo = $NULL
$failCount = 0
while ($TRUE)
{
    if((Check-HostService) -and (Check-GatewayConnection))
    {   
        $failCount = 0
        Write-SHIR-Log "Container health check pass"
        Start-Sleep -Seconds $processCheckTimeSecs
        continue
    }
    else 
    {
        $failCount += 1
        Write-SHIR-Log "Container health check fail - $($failCount)/$($maxFailCount) failures"
        Start-Sleep -Seconds $processCheckTimeSecs
    }

    if($failCount -ge $maxFailCount)
    {
        Write-SHIR-log "Maximum failure count exceeded ($maxFailCount) - container will exit"
        break
    }
}

# Once we exit the above main loop, we choose if we want to exit or "hang" so the container and its filesystem can be inspected after it has completed
if($exitOnFail)
{
    Write-SHIR-Log "Container is set to exit on exit - will now, surprisingly, exit"
    exit 1
}
else 
{
    Write-SHIR-Log "Container is set to pause on exit - will now run endless ping"
    ping -t localhost
}