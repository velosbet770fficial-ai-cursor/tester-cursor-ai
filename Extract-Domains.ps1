<#
.SYNOPSIS
  Extract domain names from symlink listing lines (ls -l style).

.DESCRIPTION
  From lines like:
    lrwxrwxrwx  1 root root 25 Apr 4 2023 www.gollob-shop.at -> /webcms/gollob.web-cms.io

  Outputs:
    gollob-shop.at
    gollob-shop.com
    gollob-shop.eu

.EXAMPLE
  Get-Content domains.txt | .\Extract-Domains.ps1

.EXAMPLE
  .\Extract-Domains.ps1 -Path domains.txt

.EXAMPLE
  .\Extract-Domains.ps1 -Path domains.txt -KeepWww

.EXAMPLE
  # paste multi-line text when prompted
  .\Extract-Domains.ps1
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string[]] $InputObject,

    [Parameter()]
    [string] $Path,

    [Parameter()]
    [switch] $KeepWww,

    [Parameter()]
    [switch] $Unique
)

begin {
    $lines = New-Object System.Collections.Generic.List[string]
}

process {
    foreach ($item in $InputObject) {
        if ($null -ne $item -and $item -ne '') {
            [void]$lines.Add($item)
        }
    }
}

end {
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "File not found: $Path"
        }
        Get-Content -LiteralPath $Path | ForEach-Object { [void]$lines.Add($_) }
    }

    if ($lines.Count -eq 0 -and -not $Path) {
        Write-Host "Paste ls output, then press Enter on an empty line:" -ForegroundColor Cyan
        while ($true) {
            $line = Read-Host
            if ([string]::IsNullOrWhiteSpace($line)) { break }
            [void]$lines.Add($line)
        }
    }

    # Match symlink name before "->"  e.g. www.gollob-shop.at
    # Also accept a bare hostname on its own line.
    $pattern = '(?:^|\s)((?:www\.)?(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})(?:\s*$|\s*->)'

    $results = foreach ($line in $lines) {
        if ($line -match $pattern) {
            $domain = $Matches[1]
            if (-not $KeepWww) {
                $domain = $domain -replace '^www\.', ''
            }
            $domain.ToLowerInvariant()
        }
    }

    if ($Unique) {
        $results = $results | Select-Object -Unique
    }

    $results
}
