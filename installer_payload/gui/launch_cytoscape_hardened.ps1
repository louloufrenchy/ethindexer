<#
    launch_cytoscape_hardened.ps1

    - Detects Java version
    - Ensures JVM fix for ZIP validation
    - Logs diagnostics (manifest-style)
    - Safely regenerates CytoscapeConfiguration
#>

$ErrorActionPreference = "Stop"

# -----------------------------
# Paths
# -----------------------------
$cytoRoot = "C:\Program Files\Cytoscape_v3.10.4"
$cytoExe  = Join-Path $cytoRoot "Cytoscape.exe"
$vmOptionsFile = Join-Path $cytoRoot "Cytoscape.vmoptions"

$userHome = [Environment]::GetFolderPath("UserProfile")
$configDir = Join-Path $userHome "CytoscapeConfiguration"

$logDir = Join-Path $cytoRoot "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir "cytoscape_launch_$(Get-Date -Format 'yyyyMMdd').log"

# Manifest-style log for dashboard
$fsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$fsManifestDir = Join-Path $fsRoot "manifests"
New-Item -ItemType Directory -Path $fsManifestDir -Force | Out-Null
$fsManifestFile = Join-Path $fsManifestDir "cytoscape_manifest_$(Get-Date -Format 'yyyyMMdd').log"

# -----------------------------
# Logging
# -----------------------------
function Write-Log {
    param([string]$Message)

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Write-Manifest {
    param(
        [string]$Status,
        [string]$Message
    )

    $entry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("s")
        Host      = $env:COMPUTERNAME
        Status    = $Status
        Message   = $Message
    }

    $entry | ConvertTo-Json -Compress | Add-Content -Path $fsManifestFile
}

Write-Log "=== Cytoscape Hardened Launcher Start ==="
Write-Log "Cytoscape root: $cytoRoot"
Write-Log "Config dir    : $configDir"
Write-Manifest -Status "Start" -Message "Cytoscape launcher started"

if (-not (Test-Path $cytoExe)) {
    Write-Log "ERROR: Cytoscape.exe not found at $cytoExe"
    Write-Manifest -Status "CytoscapeError" -Message "Cytoscape.exe not found"
    throw "Cytoscape executable not found."
}

# -----------------------------
# Detect Java Version
# -----------------------------
function Get-JavaVersion {
    try {
        $javaOutput = & "$cytoRoot\jre\bin\java.exe" -version 2>&1
    }
    catch {
        try {
            $javaOutput = & java -version 2>&1
        }
        catch {
            return $null
        }
    }

    $line = $javaOutput | Select-Object -First 1
    if ($line -match '"([\d\.]+)"') {
        return $Matches[1]
    }
    return $null
}

$javaVersion = Get-JavaVersion
if ($javaVersion) {
    Write-Log "Detected Java version: $javaVersion"
    Write-Manifest -Status "CytoscapeOK" -Message "Java version $javaVersion detected"
} else {
    Write-Log "WARNING: Unable to detect Java version."
    Write-Manifest -Status "CytoscapeWarning" -Message "Unable to detect Java version"
}

# -----------------------------
# Ensure JVM Fix in vmoptions
# -----------------------------
$zipFix = "-Djdk.util.zip.disableZip64ExtraFieldValidation=true"

if (-not (Test-Path $vmOptionsFile)) {
    Write-Log "Cytoscape.vmoptions not found, creating new file."
    Set-Content -Path $vmOptionsFile -Value $zipFix
    Write-Log "Added JVM fix to new vmoptions file: $zipFix"
    Write-Manifest -Status "CytoscapeOK" -Message "JVM fix added to new vmoptions"
} else {
    $vmContent = Get-Content $vmOptionsFile -ErrorAction SilentlyContinue
    if ($vmContent -notcontains $zipFix) {
        Write-Log "JVM fix not present in vmoptions, appending."
        Add-Content -Path $vmOptionsFile -Value $zipFix
        Write-Manifest -Status "CytoscapeOK" -Message "JVM fix appended to vmoptions"
    } else {
        Write-Log "JVM fix already present in vmoptions."
        Write-Manifest -Status "CytoscapeOK" -Message "JVM fix already present"
    }
}

# -----------------------------
# Safely Regenerate Config
# -----------------------------
if (Test-Path $configDir) {
    $backupDir = "${configDir}_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Log "Backing up existing config to: $backupDir"
    Rename-Item -Path $configDir -NewName (Split-Path $backupDir -Leaf)
    Write-Log "Config backup complete."
    Write-Manifest -Status "CytoscapeOK" -Message "Config backed up to $(Split-Path $backupDir -Leaf)"
} else {
    Write-Log "No existing CytoscapeConfiguration folder found."
    Write-Manifest -Status "CytoscapeWarning" -Message "No existing config folder"
}

Write-Log "Creating fresh CytoscapeConfiguration folder..."
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

$disableOpenCL = Join-Path $configDir "disable-opencl.dummy"
New-Item -ItemType File -Path $disableOpenCL -Force | Out-Null
Write-Log "Created disable-opencl.dummy to disable OpenCL."
Write-Manifest -Status "CytoscapeOK" -Message "Config regenerated with OpenCL disabled"

# -----------------------------
# Launch Cytoscape
# -----------------------------
Write-Log "Launching Cytoscape..."
try {
    Start-Process -FilePath $cytoExe
    Write-Log "Cytoscape process started."
    Write-Manifest -Status "CytoscapeOK" -Message "Cytoscape launched"
}
catch {
    Write-Log "ERROR: Failed to start Cytoscape: $($_.Exception.Message)"
    Write-Manifest -Status "CytoscapeError" -Message "Failed to start Cytoscape: $($_.Exception.Message)"
    throw
}

Write-Log "=== Cytoscape Hardened Launcher End ==="
Write-Manifest -Status "Complete" -Message "Cytoscape launcher finished"
