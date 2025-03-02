<#
.SYNOPSIS
    Generates a digest for a project—either a local directory or a Git repository URL—by listing its directory structure and file contents (with optional Markdown stripping) and writes the result to multiple output files if needed.

.DESCRIPTION
    This script accepts a Source parameter that may be a local directory or a Git repository URL.
    If a Git URL is provided, the repository is cloned (optionally checking out a specified branch) into a temporary folder.
    The script then recursively scans the project using include/exclude patterns and processes file contents (even if large).
    A summary is generated (with file and directory counts plus an estimated token count) and the digest is written out.
    If the output file reaches a specified maximum size (set via -MaxOutputFileSize), the output rotates to a new file (with a _partN suffix).
    An optional ProjectName parameter allows you to specify a custom name that appears in the digest header.

.PARAMETER Source
    Required. A local directory path or a Git repository URL (http/https).

.PARAMETER OutputFile
    Required. The base file name where the digest is written (e.g. digest.txt).

.PARAMETER ProjectName
    Optional. A custom project name to display in the output header.

.PARAMETER MaxFileSize
    Optional. Maximum file size in bytes to use for summary statistics (default is 10MB). Big files are processed regardless.

.PARAMETER MaxOutputFileSize
    Optional. Maximum size (in bytes) for each output file before rotating. Default is 5MB.

.PARAMETER IncludePatterns
    Optional. An array of glob patterns (e.g. "*.ps1", "src/*") to include (if provided, only matching files are processed).

.PARAMETER ExcludePatterns
    Optional. An array of glob patterns to skip (default patterns are provided).

.PARAMETER Branch
    Optional. For Git URLs, specify a branch to clone (otherwise the default branch is used).

.EXAMPLE
    .\ImprovedDigest.ps1 -Source "C:\Projects\MyApp" -OutputFile "digest.txt" -ProjectName "MyApp Digest"

.EXAMPLE
    .\ImprovedDigest.ps1 -Source "https://github.com/cyclotruc/gitingest" -OutputFile "digest.txt" -Branch "main" -ProjectName "Gitingest Digest" -ExcludePatterns @("node_modules/*", "*.dll")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Source,

    [Parameter(Mandatory=$true)]
    [string]$OutputFile,

    [Parameter()]
    [string]$ProjectName,

    [Parameter()]
    [int]$MaxFileSize = 10MB,

    [Parameter()]
    [int]$MaxOutputFileSize = 5MB,

    [Parameter()]
    [string[]]$IncludePatterns,

    [Parameter()]
    [string[]]$ExcludePatterns = @(
        "bin/*", "obj/*", "debug/*", "release/*", "node_modules/*", "*.dll", "*.exe", "*.pdb", "*.cache"
    ),

    [Parameter()]
    [string]$Branch
)

#region Output Rotation Functions

# Global variables for output rotation
$global:FilePart = 1
$global:CurrentOutputFile = $OutputFile
$global:BaseOutputFile = [System.IO.Path]::GetFileNameWithoutExtension($OutputFile)
$global:OutputFileExtension = [System.IO.Path]::GetExtension($OutputFile)
$global:OutputFileDirectory = if ([string]::IsNullOrEmpty((Split-Path $OutputFile -Parent))) { Get-Location } else { Split-Path $OutputFile -Parent }

# Function: Writes a single line to the current output file and rotates file if necessary.
function Write-LineToOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Line
    )
    Add-Content -Path $global:CurrentOutputFile -Value $Line
    # Check file size
    $currentSize = (Get-Item $global:CurrentOutputFile).Length
    if ($currentSize -gt $MaxOutputFileSize) {
        $global:FilePart++
        $newFileName = "$global:BaseOutputFile" + "_part$global:FilePart" + "$global:OutputFileExtension"
        $global:CurrentOutputFile = Join-Path $global:OutputFileDirectory $newFileName
        # Write a header in the new file
        $headerCont = "# Project Digest Continued: $ProjectName (Part $global:FilePart)`nGenerated on: $(Get-Date)`n"
        Set-Content -Path $global:CurrentOutputFile -Value $headerCont
    }
}

# Function: Writes a block of text (multiple lines) by splitting on newlines.
function Write-BlockToOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Block
    )
    $lines = $Block -split "`n"
    foreach ($line in $lines) {
        if (-not [string]::IsNullOrEmpty($line)) {
            Write-LineToOutput -Line $line
        }
    }
}
#endregion

#region Core Functions

# Function: Clone a Git repository to a temporary folder.
function Clone-Repository {
    param (
        [Parameter(Mandatory=$true)]
        [string]$RepoUrl,
        [string]$Branch = $null
    )
    $tempPath = Join-Path $env:TEMP ("repo_" + [System.Guid]::NewGuid().ToString())
    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    $cloneArgs = @("clone")
    if ($Branch) {
        $cloneArgs += @("--single-branch", "--branch", $Branch)
    } else {
        $cloneArgs += @("--depth=1")
    }
    $cloneArgs += @($RepoUrl, $tempPath)
    Write-Host "Cloning repository $RepoUrl into $tempPath ..." -ForegroundColor Cyan
    $process = Start-Process -FilePath "git" -ArgumentList $cloneArgs -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Git clone failed with exit code $($process.ExitCode)."
    }
    return $tempPath
}

# Function: Strip basic markdown formatting.
function Strip-Markdown {
    param (
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Content
    )
    # Return immediately if content is empty.
    if ([string]::IsNullOrEmpty($Content)) { return $Content }
    $Content = $Content -replace '(?m)^#+\s*', ''
    $Content = $Content -replace '\*\*(.*?)\*\*', '$1'
    $Content = $Content -replace '\*(.*?)\*', '$1'
    $Content = $Content -replace '_([^_]+)_', '$1'
    $Content = $Content -replace '\[(.*?)\]\(.*?\)', '$1'
    $Content = $Content -replace '```[\s\S]*?```', ''
    $Content = $Content -replace '`(.*?)`', '$1'
    return $Content
}

# Function: Check if a file/directory should be ignored.
function Should-Ignore {
    param(
        [string]$RelativePath,
        [string[]]$IncludePatterns,
        [string[]]$ExcludePatterns
    )
    if ($IncludePatterns -and ($IncludePatterns | ForEach-Object { if ($RelativePath -like $_) { return $true } } | Where-Object { $_ })) {
        return $false
    }
    if ($ExcludePatterns | ForEach-Object { if ($RelativePath -like $_) { return $true } } | Where-Object { $_ }) {
        return $true
    }
    return $false
}

# Function: Recursively process the directory structure.
function Process-Directory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CurrentDir,
        [string]$Indent = ""
    )
    $outputLines = @()
    if ($Indent -eq "") {
        $outputLines += "[DIR] ."
    } else {
        $dirName = Split-Path $CurrentDir -Leaf
        $outputLines += "$Indent[DIR] $dirName"
    }
    Get-ChildItem -LiteralPath $CurrentDir | Sort-Object -Property PSIsContainer, Name | ForEach-Object {
        $itemRel = (Resolve-Path -Relative $_.FullName)
        if ($_.Name -eq (Split-Path $OutputFile -Leaf)) { return }
        if (Should-Ignore -RelativePath $itemRel -IncludePatterns $IncludePatterns -ExcludePatterns $ExcludePatterns) { return }
        if ($_.PSIsContainer) {
            $outputLines += Process-Directory -CurrentDir $_.FullName -Indent ("$Indent  ")
        }
        else {
            if ($_.Extension -match '\.(ps1|cs|sln|md|txt|json|xml|yaml|yml|py|js)$') {
                $outputLines += "$Indent  [FILE] $($_.Name)"
            }
        }
    }
    return $outputLines
}

# Function: Process file contents (big files are processed regardless).
function Process-FileContents {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    $fileInfo = Get-Item $FilePath
    $allowedExtensions = @(".ps1",".cs",".sln",".md",".txt",".json",".xml",".yaml",".yml",".py",".js")
    if ($allowedExtensions -contains $fileInfo.Extension.ToLower()) {
        $content = Get-Content -Path $FilePath -Raw
        if ($fileInfo.Extension -eq ".md") {
            $content = Strip-Markdown -Content $content
        }
        $relPath = (Resolve-Path -Relative $FilePath) -replace '\\','/'
        $header = "`n## $relPath`n"
        return $header + $content
    }
    return ""
}

# Function: Generate summary info.
function Generate-Summary {
    param(
        [int]$FileCount,
        [int]$DirCount,
        [int]$TotalBytes
    )
    $approxTokens = [math]::Round($TotalBytes / 4)
    $summary = "Repository Summary:`n"
    $summary += "Files analyzed: $FileCount`n"
    $summary += "Directories scanned: $DirCount`n"
    $summary += "Total size: $TotalBytes bytes`n"
    $summary += "Estimated tokens: $approxTokens`n"
    return $summary
}
#endregion

#region Main Execution
try {
    if ($Source -match "^https?://") {
        Write-Host "Source appears to be a URL." -ForegroundColor Cyan
        $global:ClonedRepoPath = Clone-Repository -RepoUrl $Source -Branch $Branch
        $ProjectDir = $global:ClonedRepoPath
    }
    else {
        if (-Not (Test-Path -LiteralPath $Source -PathType Container)) {
            throw "Directory '$Source' does not exist."
        }
        $ProjectDir = (Resolve-Path -LiteralPath $Source).Path
    }

    Write-Host "Processing project directory: $ProjectDir" -ForegroundColor Cyan
    Push-Location $ProjectDir

    # Prepare header text with optional custom project name.
    if ($ProjectName) {
        $titleLine = "# Project Digest: $ProjectName"
    }
    else {
        $titleLine = "# Project Digest"
    }
    $header = @"
$titleLine
Generated on: $(Get-Date)
Source: $Source
Project Directory: $ProjectDir

"@
    # Initialize the first output file.
    Set-Content -Path $global:CurrentOutputFile -Value $header

    # Write Directory Structure section.
    Write-BlockToOutput -Block "`n# Directory Structure`n"
    $structureLines = Process-Directory -CurrentDir $ProjectDir
    foreach ($line in $structureLines) {
        Write-LineToOutput -Line $line
    }

    # Write Files Content section.
    Write-BlockToOutput -Block "`n# Files Content`n"
    $fileCount = 0
    $dirCount = 0
    $totalBytes = 0

    Get-ChildItem -LiteralPath $ProjectDir -Recurse -File | ForEach-Object {
        $itemRel = (Resolve-Path -Relative $_.FullName)
        if ($_.Name -eq (Split-Path $OutputFile -Leaf)) { return }
        if (Should-Ignore -RelativePath $itemRel -IncludePatterns $IncludePatterns -ExcludePatterns $ExcludePatterns) { return }
        $allowedExtensions = @(".ps1",".cs",".sln",".md",".txt",".json",".xml",".yaml",".yml",".py",".js")
        if ($allowedExtensions -contains $_.Extension.ToLower()) {
            $fileCount++
            $totalBytes += $_.Length
            $contentBlock = Process-FileContents -FilePath $_.FullName
            if ($contentBlock) {
                Write-BlockToOutput -Block $contentBlock
            }
        }
    }

    # Count directories.
    $dirCount = (Get-ChildItem -LiteralPath $ProjectDir -Recurse -Directory).Count

    # Generate summary and prepend it.
    $summary = Generate-Summary -FileCount $fileCount -DirCount $dirCount -TotalBytes $totalBytes
    $existing = Get-Content -Path $global:CurrentOutputFile -Raw
    # Overwrite the first file with summary prepended.
    Set-Content -Path $OutputFile -Value ($summary + "`n" + $existing)

    Write-Host "Documentation has been generated (possibly across multiple files starting at '$OutputFile')." -ForegroundColor Green
}
finally {
    Pop-Location
    if ($global:ClonedRepoPath) {
        Write-Host "Cleaning up temporary repository at $global:ClonedRepoPath" -ForegroundColor Yellow
        Remove-Item -LiteralPath $global:ClonedRepoPath -Recurse -Force
    }
}
#endregion
