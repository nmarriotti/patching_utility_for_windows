# Patch Utility
# Author: Nick Marriotti
# Date: 2/13/2021

param (
    [switch]$Build = $false
)

$PATCHED_FILES_DIR = "$PSScriptRoot\files"
$MANIFEST_CONFIG = "$PSScriptRoot\manifest.cfg"
$MANIFEST = "$PSScriptRoot\manifest"
$BACKUP_DIR = "$PSScriptRoot\backup"

Function Menu()
{
    cls
    Write-Host "Patch Utility Main Menu"
    Write-Host "      1. Patch"
    Write-Host "      2. Restore"
    Write-Host "      3. Exit"
    $action = Read-Host -Prompt "Select one"
    return $action
}


Function BuildPath()
{
    param (
        [Parameter(Mandatory=$true)]
        [String]$Path,
        [Parameter(Mandatory=$true)]
        [String]$Base
    )

    $parts = $Path -split "\\"
    $output = $parts[1..$parts.Count] -join '\'

    # This is where the patch will be stored
    $patch_path = "$Base\$output"

    return $patch_path
}


Function WriteManifestLine()
{
    param (
        [Parameter(Mandatory=$true)]
        [String]$Dest
    )



    Write-Host "adding $Dest to manifest"

    # calculate md5 hash
    $md5 = Get-FileHash -Algorithm MD5 -Path $Dest
    # get absolute path where data will be stored in patch
    $src = BuildPath -Path $Dest -Base $PATCHED_FILES_DIR
    
    # copy files/folders to patch directory
    New-Item -Path $(Split-Path -Path $src) -ItemType directory -ErrorAction SilentlyContinue | Out-Null
    
    if(-Not (Test-Path -Path $Dest -PathType Container))
    {
        Copy-Item -Path $Dest -Destination $src
    }
    
    
    if(-Not $md5)
    {
        $md5 = "-" # Unable to get hash of directories
    }
    else
    {
        $md5 = $md5.Hash
    }

    # Write line to manifest
    Add-Content -Path $MANIFEST -Value "$md5,$src,$Dest"
}


Function Build()
{
    # remove backup directory
    Remove-Item -Path $BACKUP_DIR -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    # Count number of files included in this patch
    $num_files = 0

    Function AddFilesToManifest()
    {
        param (
            [Parameter(Mandatory=$true)]
            [String]$Path
        )
        # Find all files in a folder
        $files = Get-ChildItem -Path $Path -Recurse -File -Force
        foreach($file in $files)
        {
            WriteManifestLine -Dest $file.FullName
            $num_files += 1
        }
    }

    Write-Host "Building manifest..."



    # cleanup
    Remove-Item $MANIFEST -Force -ErrorAction SilentlyContinue
    Remove-Item $PATCHED_FILES_DIR -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $PATCHED_FILES_DIR -ItemType directory -Force | Out-Null

    # create empty manifest file
    New-Item -Path $MANIFEST -ItemType File | Out-Null
    # Add headers
    Add-Content -Path $MANIFEST -Value "Hash,Source,Destination"

    # Read each line in manifest.cfg
    foreach($dest in Get-Content $MANIFEST_CONFIG)
    {
        # Check if this line is a folder
        if(Test-Path -Path $dest -PathType Container)
        {
            Write-Host "scanning $dest"

            # Find subfolders
            $subfolders = Get-ChildItem -Path $dest -Recurse -Directory -Force

            # Add any files in this top-level directory
            AddFilesToManifest -Path $dest

            foreach($folder in $subfolders)
            {
                WriteManifestLine -Dest $folder.FullName
                #AddFilesToManifest -Path $folder.FullName
                $num_files += 1
            }
        }
        else
        {
            WriteManifestLine -Dest $dest
            $num_files += 1
        }
    }
    Write-Host "added $num_files file(s)."
    Write-Host "`nbuild complete."
}


Function ApplyPatches()
{
    # Make sure manifest exists
    if(-Not (Test-Path -Path $MANIFEST -PathType Leaf))
    {
        Write-Host "ERROR: Manifest file not found."
        return
    }
    # Create backup directory
    New-Item -Path $BACKUP_DIR -ItemType directory -ErrorAction SilentlyContinue | Out-Null

    $num_patched = 0
    Write-Host "Checking files..."

    # Read each line in manifest
    $_manifest = Import-CSV -Path $MANIFEST -ErrorAction Stop
    
    # Iterate over each item
    foreach($item in $_manifest)
    {
        # Check if this item is a directory
        if(Test-Path -Path $item.Source -PathType Container)
        {
            # Check if it exists on the file system
            if(Test-Path -Path $item.Destination -PathType Container)
            {
                # Directory exists
            }
            else
            {
                # Create the directory
                New-Item -Path $item.Destination -ItemType directory | Out-Null
            }
            
        }
        elseif(Test-Path $item.Source -PathType Leaf)
        {
            # This is a file, check if it exists on the file system
            if(Test-Path $item.Destination -PathType Leaf)
            {
                # File exists, compare hashes
                $currentHash = Get-FileHash -Algorithm MD5 -Path $item.Destination

                if(-Not ($item.Hash -match $currentHash.Hash))
                {
                    # Hash mismatch, replace the file
                    Backup -Dest $item.Destination     # first backup the file!
                    Write-Host "patching file $($item.Destination)"
                    Copy-Item -Path $item.Source -Destination $item.Destination -Force
                    $num_patched += 1
                }
            }
            else
            {
                # File is missing, replace it
                Write-Host "adding $($item.Destination)"

                # Check if the destination directory already exists
                $path_to_create = Split-Path -Path $item.Destination
                if(-Not (Test-Path $path_to_create -PathType Container)) 
                {
                    New-Item -Path $path_to_create -ItemType directory | Out-Null
                }
                
                Copy-Item -Path $item.Source $item.Destination -Force
                $num_patched += 1
            }
        }
    }
    if($num_patched -eq 0)
    {
        Write-Host "no action taken. all files are intact."
    }
    else
    {
        Write-Host "$num_patched file(s) patched."
    }
}


Function Backup()
{
        param (
            [Parameter(Mandatory=$true)]
            [String]$Dest
        )
        Write-Host "creating backup of $Dest"
        # This is where the back will be saved
        $backup_path = BuildPath -Path $Dest -Base $BACKUP_DIR
        # create the directory structure
        New-Item -Path $(Split-Path -Path $backup_path) -ItemType directory -ErrorAction SilentlyContinue | Out-Null
        # backup the file
        Copy-Item -Path $Dest -Destination $backup_path -Force | Out-Null
}


Function Restore()
{
    # Make sure manifest exists
    if(-Not (Test-Path -Path $MANIFEST -PathType Leaf))
    {
        Write-Host "ERROR: Manifest file not found."
        return
    }

    $num_restored = 0
    Write-Host "restoring..."

    # Read each line in manifest
    $_manifest = Import-CSV -Path $MANIFEST -ErrorAction Stop

    # Iterate over each item
    foreach($item in $_manifest)
    {
        $restoreFile = BuildPath -Path $item.Destination -Base $BACKUP_DIR

        # Check if restore file exists
        if(Test-Path -Path $restoreFile -PathType Leaf)
        {
            if(Test-Path -Path $item.Destination -PathType Leaf)
            {
                # Compare hashes
                $backup_md5 = $(Get-FileHash -Algorithm MD5 -Path $restoreFile).Hash
                if(-Not ($backup_md5 -match $(Get-FileHash -Algorithm MD5 -Path $item.Destination).Hash))
                {
                    Write-Host "restoring $($item.Destination)"
                    Copy-Item -Path $restoreFile -Destination $item.Destination -Force
                    $num_restored++
                }
            }
        }
    }

    if($num_restored -gt 0)
    {
        Write-Host "complete`n$num_restored file(s) restored."
    }
    else
    {
        Write-Host "no action taken. restore was not required"
    }
}

# Script will self-elevate to run as Administrator
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

# Start here
if($Build)
{
    Build
}
else
{
    while($true)
    {
        $action = Menu
        switch($action)
        {
            '1' 
            {
                $c = Read-Host -Prompt "Proceed with patching? (y/n)"
                switch($c)
                {
                    'y'
                    {
                        ApplyPatches
                        read-host “Press ENTER to continue...”
                        break
                    }
                    'n'
                    {
                        break
                    }
                    default
                    {
                        Write-Host "Invalid option!"
                        sleep 2
                    }
                }
                break
            }
            '2' 
            {
                $c = Read-Host -Prompt "Do you wish to undo all changes that were applied by the patch? (y/n)"
                switch($c)
                {
                    'y'
                    {
                        Restore
                        read-host “Press ENTER to continue...”
                        break
                    }
                    'n'
                    {
                        break
                    }
                    default
                    {
                        Write-Host "Invalid option!"
                        sleep 2
                    }
                }
                break
            }
            '3'
            {
                exit 0
            }
            default
            {
                Write-Host "Invalid option!"
            }
        }
    }

}