# Incident Response Scripts

This collection of scripts is used to automate forensic artifact collection
using Kroll's ["KAPE" (Kroll Artifact Parser & Extractor)"](https://www.kroll.com/en/services/cyber-risk/incident-response-litigation-support/kroll-artifact-parser-extractor-kape) and Crowdstrike RTR and Fusion Workflows.

## KAPE Collection

A CrowdStrike detection triggers a Fusion Workflow that places the KAPE files on the endpoint and then invokes `Start-KapeCollection.ps1`.

The parameters in this script will upload the ZIP file of collected artifacts to a modified [Skadi VM](https://github.com/tobraha/Skadi).
It performs these tasks:

- Script is optimized to run in the RTR environment
- Checks free disk space of the OS volume; does not proceed unless there is at least 10GB free
- Checks for existence of C:\Tmp\kape.exe (or kape.zip containing kape.exe)
- Sets password for collection zip file
- Defines KAPE Collection Targets
- Checks to see if the Windows Search Index DB is less than 1GB; adds to collection targets if so
- Starts KAPE as a background job due to CrowdStrike RTR time outs.

### NOTE
If KAPE cannot successfully connect to the SFTP server, then the script fails (silently if using RTR)

## Clean Uploads

Uploads are placed into a [restricted chroot jail](https://github.com/tobraha/docs/blob/master/sftp-chroot-jail/README.md) where the `clean_uploads.sh` script runs every 10 minutes via cron and moves them out of the chroot jail for processing. This script will wait until the file is finished uploading before trying to move it. Posts a message to a Teams WebHook when files are moved after each invocation of the script (I run the script every 10 minutes via cron).

## KAPE Ingest

Finally, the `kape_ingest.sh` script runs (also via cron) and processes the collected files. It performs these steps:

- Parses out hostname and collection date from the uploaded ZIP file.
- Creates all working directories
- Extracts the KAPE archive using 7-zip (must be installed on the server)
- Checks if KAPE encountered any "Long Files" (which it compacts into a folder in the ZIP root called "LongFileNames"). Restores them to their original path.
- Runs [Chainsaw](https://github.com/WithSecureLabs/chainsaw) on the Windows Event Logs (Chainsaw must be installed and configured according to its documentation. My script points directly to a self-compiled version in /opt)
- After Chainsaw completes, check for any collected files that are larger than 1GB (except the $MFT file, which is not parsed in PLASO by default). Large files are moved to a separate folder and are processed after the initial set due to long processing times.
- Starts a new tmux session for the host (tmux must be installed)
- Strings together docker commands to process artifacts using PLASO/Log2TimeLine for base files and large files. Docker commands perform the following for each set:
    - Run log2timeline/plaso version "20220428" (from Docker Hub) which is the last version that supports ElasticSearch (newer versions can only output to OpenSearch)
    - Run Plaso's 'psort' tool to perform "tagging" analysis, and then add artifacts to a new ElasticSearch Index
    - Run Plaso's 'pinfo' tool to output collection details to a text file.
