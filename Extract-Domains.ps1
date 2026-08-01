<#
.SYNOPSIS
  Extract domain names from symlink listing lines (ls -l style).

.DESCRIPTION
  From lines like:
    lrwxrwxrwx  1 root root 25 Apr 4 2023 www.gollob-shop.at -> /webcms/gollob.web-cms.io

  Outputs:
    gollob-shop.at

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Extract-Domains.ps1 -Path domains.txt

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Extract-Domains.ps1 -Path domains.txt -OutFile hasil.txt
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string[]] $InputObject,

    [Parameter()]
    [string] $Path,

    [Parameter()]
    [string] $OutFile,

    [Parameter()]
    [switch] $KeepWww,

    [Parameter()]
    [switch] $Unique
)

$ErrorActionPreference = 'Stop'

function Get-DomainFromLine {
    param([string] $Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    # Buang bagian target symlink: "... -> /path"
    $left = ($Line -split '\s*->\s*', 2)[0].Trim()
    if (-not $left) { return $null }

    # Ambil token terakhir di kiri panah = nama symlink/domain
    $parts = $left -split '\s+'
    $name = $parts[-1].Trim().TrimEnd('/', '\')
    if (-not $name) { return $null }

    # Harus mirip domain (punya titik)
    if ($name -notmatch '\.') { return $null }

    if (-not $KeepWww) {
        $name = $name -replace '^www\.', ''
    }

    return $name.ToLowerInvariant()
}

$lines = New-Object System.Collections.Generic.List[string]

if ($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "File tidak ketemu: $Path" -ForegroundColor Red
        exit 1
    }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object { [void]$lines.Add($_) }
}

foreach ($item in $InputObject) {
    if ($null -ne $item -and "$item" -ne '') {
        [void]$lines.Add($item)
    }
}

if ($lines.Count -eq 0) {
    Write-Host "Paste isi ls, lalu Enter di baris kosong:" -ForegroundColor Cyan
    while ($true) {
        $line = Read-Host
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        [void]$lines.Add($line)
    }
}

$results = New-Object System.Collections.Generic.List[string]
foreach ($line in $lines) {
    $domain = Get-DomainFromLine -Line $line
    if ($domain) {
        [void]$results.Add($domain)
    }
}

if ($Unique) {
    $results = [System.Collections.Generic.List[string]]@($results | Select-Object -Unique)
}

if ($results.Count -eq 0) {
    Write-Host "Tidak ada domain yang terbaca." -ForegroundColor Yellow
    Write-Host "Cek isi domains.txt — contoh baris yang valid:" -ForegroundColor Yellow
    Write-Host 'lrwxrwxrwx  1 root root 25 Apr 4 2023 www.gollob-shop.at -> /webcms/gollob.web-cms.io'
    exit 2
}

Write-Host ("Ketemu {0} domain:" -f $results.Count) -ForegroundColor Green
$results | ForEach-Object { Write-Output $_ }

if ($OutFile) {
    $results | Set-Content -LiteralPath $OutFile -Encoding UTF8
    Write-Host ("Disimpan ke: {0}" -f (Resolve-Path -LiteralPath $OutFile)) -ForegroundColor Green
}
