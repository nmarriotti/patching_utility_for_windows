# Patch Utility
# Author: Nick Marriotti
# Date: 2/13/2021

param (
    [switch]$Build = $false
)

$PATCHED_FILES_DIR = "$PSScriptRoot\files"
$MANIFEST_CONFIG = "$PSScriptRoot\manifest.cfg"
$MANIFEST = "$PSScriptRoot\manifest"

Function WriteManifestLine()
{
    param (
        [Parameter(Mandatory=$true)]
        [String]$Dest
    )

    Function BuildPath()
    {
        param (
            [Parameter(Mandatory=$true)]
            [String]$Path
        )

        $parts = $Path -split "\\"
        $output = $parts[1..$parts.Count] -join '\'

        # This is where the patch will be stored
        $patch_path = "$PATCHED_FILES_DIR\$output"

        return $patch_path
    }

    echo "adding $Dest to manifest"

    # calculate md5 hash
    $md5 = Get-FileHash -Algorithm MD5 -Path $Dest
    # get absolute path where data will be stored in patch
    $src = BuildPath -Path $Dest
    
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

    echo "Building manifest..."



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
            echo "scanning $dest"

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
    echo "added $num_files file(s)."
    echo "`nbuild complete."
}


Function ApplyPatches()
{
    $num_patched = 0
    echo "Checking files..."

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
                    echo "patching file $($item.Destination)"
                    Copy-Item -Path $item.Source -Destination $item.Destination -Force
                    $num_patched += 1
                }
            }
            else
            {
                # File is missing, replace it
                echo "adding $($item.Destination)"

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
        echo "no action taken. all files are intact."
    }
    else
    {
        echo "$num_patched file(s) patched."
    }
}


# Start here
if($Build)
{
    Build
}
else
{
    Add-Type -AssemblyName PresentationFramework
    $resp = [System.Windows.MessageBox]::Show('Proceed with patching? This action cannot be undone.','Patch Utility','YesNoCancel','Question')
    
    switch ($resp) 
    {
        'Yes' 
        {
            ApplyPatches
            read-host “`nPress ENTER to exit or close this window...”
            break
        }
    }
}