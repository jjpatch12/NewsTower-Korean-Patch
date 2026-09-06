param(
    [ValidateSet("Menu", "Install", "Restore")]
    [string]$Action = "Menu",
    [string]$GamePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$PayloadRoot = $PSScriptRoot
$PackageRoot = Split-Path -Parent $PayloadRoot
$ManifestPath = Join-Path $PayloadRoot "manifest.json"
$BackupFolderName = ".NewsTower_KR_Backup_1.1.165.r"

$nativeSource = @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class NewsTowerMsDelta
{
    [DllImport("msdelta.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "ApplyDeltaW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ApplyDeltaW(
        long applyFlags,
        string sourceName,
        string deltaName,
        string targetName);

    public static void Apply(string sourceName, string deltaName, string targetName)
    {
        if (!ApplyDeltaW(0, sourceName, deltaName, targetName))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "MSDelta 패치 적용에 실패했습니다.");
        }
    }
}
"@

function Write-Title {
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor DarkCyan
    Write-Host " News Tower 한국어 패치 v1.0.0" -ForegroundColor Cyan
    Write-Host " 대상 게임: News Tower v1.1.165.r (Windows)" -ForegroundColor Gray
    Write-Host "==============================================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Get-Sha256([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $digest = $sha.ComputeHash($stream)
            return ([System.BitConverter]::ToString($digest).Replace("-", "").ToLowerInvariant())
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Resolve-GameRoot([string]$RequestedPath) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates.Add($RequestedPath.Trim().Trim('"'))
    }
    $candidates.Add($PackageRoot)
    $candidates.Add((Join-Path ([Environment]::GetFolderPath("Desktop")) "News.Tower.v1.1.165.r"))
    $candidates.Add((Join-Path ([Environment]::GetFolderPath("Desktop")) "News Tower"))
    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\News Tower"))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles "Steam\steamapps\common\News Tower"))
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($candidate)
        }
        catch { continue }
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        if (Test-Path -LiteralPath (Join-Path $full "News Tower.exe") -PathType Leaf) {
            return $full
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        throw "지정한 폴더에서 'News Tower.exe'를 찾지 못했습니다: $RequestedPath"
    }

    Write-Host "게임 폴더를 자동으로 찾지 못했습니다." -ForegroundColor Yellow
    $typed = (Read-Host "'News Tower.exe'가 들어 있는 폴더 경로를 붙여 넣으세요").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($typed)) {
        throw "게임 폴더가 입력되지 않았습니다."
    }
    $fullTyped = [System.IO.Path]::GetFullPath($typed)
    if (-not (Test-Path -LiteralPath (Join-Path $fullTyped "News Tower.exe") -PathType Leaf)) {
        throw "해당 폴더에서 'News Tower.exe'를 찾지 못했습니다: $fullTyped"
    }
    return $fullTyped
}

function Assert-GameClosed([string]$Root) {
    $gameExe = [System.IO.Path]::GetFullPath((Join-Path $Root "News Tower.exe"))
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -eq $gameExe) } catch { $false }
    })
    if ($running.Count -gt 0) {
        throw "News Tower가 실행 중입니다. 게임을 완전히 종료한 뒤 다시 실행해 주세요."
    }
}

function Get-FileStates([string]$Root, $Manifest) {
    $states = @()
    foreach ($entry in $Manifest.files) {
        $relative = [string]$entry.relative_path
        $target = Join-Path $Root ($relative.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $states += [pscustomobject]@{ Entry = $entry; Target = $target; State = "missing"; Hash = "" }
            continue
        }
        $hash = Get-Sha256 $target
        if ($hash -eq ([string]$entry.original_sha256).ToLowerInvariant()) {
            $state = "original"
        }
        elseif ($hash -eq ([string]$entry.patched_sha256).ToLowerInvariant()) {
            $state = "patched"
        }
        else {
            $state = "unknown"
        }
        $states += [pscustomobject]@{ Entry = $entry; Target = $target; State = $state; Hash = $hash }
    }
    return $states
}

function Assert-DeltaPayload($Manifest) {
    foreach ($entry in $Manifest.files) {
        $delta = Join-Path $PayloadRoot (([string]$entry.delta_file).Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $delta -PathType Leaf)) {
            throw "패치 데이터가 없습니다: $([string]$entry.delta_file)"
        }
        $actual = Get-Sha256 $delta
        if ($actual -ne ([string]$entry.delta_sha256).ToLowerInvariant()) {
            throw "패치 데이터가 손상되었습니다: $([string]$entry.delta_file)"
        }
    }
}

function Assert-BackupValid([string]$BackupRoot, $Manifest) {
    foreach ($entry in $Manifest.files) {
        $backupFile = Join-Path $BackupRoot (([string]$entry.relative_path).Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf)) {
            throw "백업 파일이 없습니다: $([string]$entry.relative_path)"
        }
        if ((Get-Sha256 $backupFile) -ne ([string]$entry.original_sha256).ToLowerInvariant()) {
            throw "백업 파일의 해시가 원본과 다릅니다: $([string]$entry.relative_path)"
        }
    }
}

function New-VerifiedBackup([string]$Root, [string]$BackupRoot, $Manifest) {
    if (Test-Path -LiteralPath $BackupRoot) {
        Assert-BackupValid $BackupRoot $Manifest
        Write-Host "기존 원본 백업을 확인했습니다." -ForegroundColor DarkGray
        return
    }

    $creating = "$BackupRoot.creating"
    if (Test-Path -LiteralPath $creating) {
        Remove-Item -LiteralPath $creating -Recurse -Force
    }
    [void](New-Item -ItemType Directory -Path $creating -Force)
    try {
        foreach ($entry in $Manifest.files) {
            $relativeWindows = ([string]$entry.relative_path).Replace('/', '\')
            $source = Join-Path $Root $relativeWindows
            $destination = Join-Path $creating $relativeWindows
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        Assert-BackupValid $creating $Manifest
        [System.IO.File]::WriteAllText(
            (Join-Path $creating "README.txt"),
            "News Tower v1.1.165.r 한국어 패치가 만든 원본 백업입니다.`r`n이 폴더는 원본 복원에 필요하므로 삭제하지 마세요.`r`n",
            [System.Text.UTF8Encoding]::new($true)
        )
        Move-Item -LiteralPath $creating -Destination $BackupRoot
        $backupItem = Get-Item -LiteralPath $BackupRoot -Force
        $backupItem.Attributes = $backupItem.Attributes -bor [System.IO.FileAttributes]::Hidden
    }
    catch {
        if (Test-Path -LiteralPath $creating) {
            Remove-Item -LiteralPath $creating -Recurse -Force
        }
        throw
    }
    Write-Host "원본 6개 파일을 숨김 백업 폴더에 보관했습니다." -ForegroundColor Green
}

function Install-Patch([string]$Root, $Manifest) {
    Assert-GameClosed $Root
    Assert-DeltaPayload $Manifest
    $states = @(Get-FileStates $Root $Manifest)
    $unknown = @($states | Where-Object { $_.State -in @("missing", "unknown") })
    if ($unknown.Count -gt 0) {
        $details = ($unknown | ForEach-Object { " - $([string]$_.Entry.relative_path) [$($_.State)]" }) -join "`n"
        throw "지원하지 않는 파일 상태입니다. v1.1.165.r 순정본에서 실행해 주세요.`n$details"
    }
    $patched = @($states | Where-Object { $_.State -eq "patched" })
    if ($patched.Count -eq $states.Count) {
        Write-Host "이미 동일한 한국어 패치가 적용되어 있습니다." -ForegroundColor Green
        return
    }
    if ($patched.Count -gt 0) {
        throw "일부 파일만 패치된 상태입니다. 안전을 위해 설치를 중단합니다. 원본을 복구한 뒤 다시 실행해 주세요."
    }

    $stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("NewsTowerKR_" + [Guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $stageRoot -Force)
    try {
        if (-not ("NewsTowerMsDelta" -as [type])) {
            Add-Type -TypeDefinition $nativeSource -Language CSharp
        }
        Write-Host "패치 데이터를 적용하고 검증하는 중입니다..." -ForegroundColor Cyan
        foreach ($state in $states) {
            $entry = $state.Entry
            $relativeWindows = ([string]$entry.relative_path).Replace('/', '\')
            $output = Join-Path $stageRoot $relativeWindows
            $delta = Join-Path $PayloadRoot (([string]$entry.delta_file).Replace('/', '\'))
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force)
            [NewsTowerMsDelta]::Apply($state.Target, $delta, $output)
            if ((Get-Sha256 $output) -ne ([string]$entry.patched_sha256).ToLowerInvariant()) {
                throw "생성된 파일 검증에 실패했습니다: $([string]$entry.relative_path)"
            }
            Write-Host "  확인: $([string]$entry.relative_path)" -ForegroundColor DarkGray
        }

        $backupRoot = Join-Path $Root $BackupFolderName
        New-VerifiedBackup $Root $backupRoot $Manifest

        try {
            foreach ($entry in $Manifest.files) {
                $relativeWindows = ([string]$entry.relative_path).Replace('/', '\')
                Copy-Item -LiteralPath (Join-Path $stageRoot $relativeWindows) -Destination (Join-Path $Root $relativeWindows) -Force
            }
            $after = @(Get-FileStates $Root $Manifest)
            if (@($after | Where-Object { $_.State -ne "patched" }).Count -ne 0) {
                throw "설치 후 파일 검증에 실패했습니다."
            }
        }
        catch {
            Write-Host "설치 도중 문제가 생겨 원본으로 되돌립니다..." -ForegroundColor Yellow
            foreach ($entry in $Manifest.files) {
                $relativeWindows = ([string]$entry.relative_path).Replace('/', '\')
                Copy-Item -LiteralPath (Join-Path $backupRoot $relativeWindows) -Destination (Join-Path $Root $relativeWindows) -Force
            }
            throw
        }

        [System.IO.File]::WriteAllText(
            (Join-Path $backupRoot "install.log"),
            "Installed: $([DateTimeOffset]::Now.ToString('o'))`r`nVersion: $([string]$Manifest.patch_version)`r`n",
            [System.Text.UTF8Encoding]::new($true)
        )
        Write-Host ""
        Write-Host "한국어 패치 설치가 완료되었습니다." -ForegroundColor Green
        Write-Host "이미지 리소스는 변경하지 않았습니다." -ForegroundColor Gray
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
    }
}

function Restore-Original([string]$Root, $Manifest) {
    Assert-GameClosed $Root
    $backupRoot = Join-Path $Root $BackupFolderName
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        throw "이 패치가 만든 원본 백업을 찾지 못했습니다: $backupRoot"
    }
    Assert-BackupValid $backupRoot $Manifest
    $states = @(Get-FileStates $Root $Manifest)
    $unknown = @($states | Where-Object { $_.State -in @("missing", "unknown") })
    if ($unknown.Count -gt 0) {
        throw "게임 파일이 설치 후 변경된 상태라 자동 복원을 중단했습니다. 게임 업데이트 또는 다른 모드를 확인해 주세요."
    }
    if (@($states | Where-Object { $_.State -eq "original" }).Count -eq $states.Count) {
        Write-Host "이미 원본 상태입니다." -ForegroundColor Green
        return
    }
    foreach ($entry in $Manifest.files) {
        $relativeWindows = ([string]$entry.relative_path).Replace('/', '\')
        Copy-Item -LiteralPath (Join-Path $backupRoot $relativeWindows) -Destination (Join-Path $Root $relativeWindows) -Force
    }
    $after = @(Get-FileStates $Root $Manifest)
    if (@($after | Where-Object { $_.State -ne "original" }).Count -ne 0) {
        throw "원본 복원 후 검증에 실패했습니다."
    }
    Write-Host "원본 6개 파일을 모두 복원했습니다." -ForegroundColor Green
}

try {
    Write-Title
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "manifest.json을 찾지 못했습니다. 패치 압축을 다시 풀어 주세요."
    }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($Action -eq "Menu") {
        Write-Host "[1] 한국어 패치 설치"
        Write-Host "[2] 원본 복원"
        Write-Host "[3] 종료"
        Write-Host ""
        $choice = Read-Host "번호를 입력하세요"
        switch ($choice.Trim()) {
            "1" { $Action = "Install" }
            "2" { $Action = "Restore" }
            default { Write-Host "종료합니다."; exit 0 }
        }
    }

    $root = Resolve-GameRoot $GamePath
    Write-Host "게임 폴더: $root" -ForegroundColor Gray
    if ($Action -eq "Install") {
        Install-Patch $root $manifest
    }
    else {
        Restore-Original $root $manifest
    }
    exit 0
}
catch {
    Write-Host ""
    Write-Host ("오류: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
