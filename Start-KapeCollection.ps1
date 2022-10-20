"[*] Checking free disk space..." | Out-String
$OsDisk = Get-CimInstance Win32_LogicalDisk -Filter drivetype=3 | ? { $_.DeviceID -eq "$env:SYSTEMDRIVE" }
$free = [math]::round($OsDisk.FreeSpace / 1GB, 0)
If ($free -lt 10) {
    "[!] Free space on OS drive is less than 10GB!! Aborting script..." | Out-String
    Throw
}

"Free space on $env:SYSTEMDRIVE is $free GB" | Out-String

"[*] Setting up working folders and paths..." | Out-String
$workingDir = "$env:SYSTEMDRIVE\Tmp"
$kapeExe = "$workingDir\kape.exe"
$RunDate = (Get-Date -UFormat "%d%b%Y").ToUpper()

If (-not (Test-Path $kapeExe)) {
    # if exe is not found, check for zip. failures here will halt the script
    If (Test-Path "$workingDir\kape.zip") {
        # extract the kape zip file into c:\tmp
        Try {
            "Found kape.zip, trying to extract..." | Out-String
            Add-Type -A 'System.IO.Compression.FileSystem'
            [IO.Compression.ZipFile]::ExtractToDirectory("$workingDir\kape.zip", $workingDir)
        } Catch {
            "[!] Failed to extract kape.zip - Aborting script!" | Out-String
            Throw
        }
    } Else {
        "[!] Unable to locate the kape binary or zip file" | Out-String
        Throw
    }
}

$zipPassword = "infected"

# define base collection targets
$CollectionTargets = "EventLogs,EvidenceOfExecution,FileSystem,LNKFilesAndJumpLists,PowerShellConsole,RecycleBin_InfoFiles"
$CollectionTargets += ",RegistryHives,ScheduledTasks,SRUM,Thumbcache,USBDevicesLogs,WebBrowsers,WindowsTimeline"

# add Windows search index if the file is smaller than 1GB
$SearchIndexFile = "$env:SYSTEMDRIVE\ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb"
If (Test-Path $SearchIndexFile) {
    If ((Get-ItemProperty -Path $SearchIndexFile).Length -lt "1GB") {
        "[+] Windows search database is less than 1GB in size and will be collected" | Out-String
        $CollectionTargets += ",WindowsIndexSearch"
    } Else {
        "[!] Windows search database exceeds 1GB and will not be collected" | Out-String
    }
} Else {
    "[!] Unable to locate Index Search Database!" | Out-String
}

# run we pre-defined collection parameters.
" --> Running kape with defined collection targets..." | Out-String
$kapeArgs = "--tsource", "$env:SYSTEMDRIVE", `
            "--tdest", "$workingDir\kape-%m-$RunDate", `
            "--tflush", `
            "--debug", `
            "--target", "$CollectionTargets", `
            "--scs", "0.0.0.0", `
            "--scp", "22", `
            "--scu", "sftpuser", `
            "--scpw", "WouldntYouLikeToKnow", `
            "--scd", "upload", `
            "--zip", "%m", `
            "--zpw", "$zipPassword"

"[*] Starting kape as a background job..." | out-string

Start-Process -NoNewWindow -WorkingDirectory $workingDir "$kapeExe" -ArgumentList "$kapeArgs"
