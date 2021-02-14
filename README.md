# Patching Utility for Windows

PowerShell script to easily build and patch files and folders based on MD5 hash comparisons.

## How to Use

Edit _manifest.cfg_ and include a list of files and/or folders to include in the patch.

### Build the Manifest

The manifest file contains MD5 hash values and source/destinations locations such as where each file resides in the patch and where it belongs on the file system.

```
./patch.ps1 -Build
```

### Deploy

```
./patch.ps1
```

