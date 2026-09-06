param(
    [Parameter(Mandatory = $true)]
    [string]$OriginalRoot,
    [Parameter(Mandatory = $true)]
    [string]$PatchedRoot,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$nativeSource = @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct DeltaInput
{
    public IntPtr Start;
    public UIntPtr Size;
    [MarshalAs(UnmanagedType.Bool)] public bool Editable;
}

public static class NewsTowerDeltaBuilder
{
    private const long DeltaFileTypeRaw = 0x00000001;
    private const long IgnoreFileSizeLimit = 0x00020000;
    private const long IgnoreOptionsSizeLimit = 0x00040000;
    private const uint DeltaCrc32 = 32;

    [DllImport("msdelta.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateDeltaW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateDeltaW(
        long fileTypeSet,
        long setFlags,
        long resetFlags,
        string sourceName,
        string targetName,
        string sourceOptionsName,
        string targetOptionsName,
        DeltaInput globalOptions,
        IntPtr targetFileTime,
        uint hashAlgId,
        string deltaName);

    public static void Create(string sourceName, string targetName, string deltaName)
    {
        var options = new DeltaInput();
        bool ok = CreateDeltaW(
            DeltaFileTypeRaw,
            IgnoreFileSizeLimit | IgnoreOptionsSizeLimit,
            0,
            sourceName,
            targetName,
            null,
            null,
            options,
            IntPtr.Zero,
            DeltaCrc32,
            deltaName);
        if (!ok)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "MSDelta 생성에 실패했습니다.");
        }
    }
}
"@

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

$relativeFiles = @(
    "News Tower_Data/Managed/NewsTower.dll",
    "News Tower_Data/StreamingAssets/aa/catalog.json",
    "News Tower_Data/StreamingAssets/aa/StandaloneWindows64/employees_assets_all_7358c2e7a2d3a41713a98574bf4ae475.bundle",
    "News Tower_Data/StreamingAssets/aa/StandaloneWindows64/fonts_assets_all_f0fb231c54bba8ba2b9e2497806f8eb5.bundle",
    "News Tower_Data/StreamingAssets/aa/StandaloneWindows64/localization-locales_assets_all.bundle",
    "News Tower_Data/StreamingAssets/aa/StandaloneWindows64/localization-string-tables-english(en)_assets_all.bundle"
)

$payloadRoot = Join-Path $RepositoryRoot "package\.patch_data"
$deltaRoot = Join-Path $payloadRoot "deltas"
$licenseRoot = Join-Path $payloadRoot "licenses"
[void](New-Item -ItemType Directory -Path $deltaRoot -Force)
[void](New-Item -ItemType Directory -Path $licenseRoot -Force)

if (-not ("NewsTowerDeltaBuilder" -as [type])) {
    Add-Type -TypeDefinition $nativeSource -Language CSharp
}

$entries = @()
for ($index = 0; $index -lt $relativeFiles.Count; $index++) {
    $relative = $relativeFiles[$index]
    $windowsRelative = $relative.Replace('/', '\')
    $source = Join-Path $OriginalRoot $windowsRelative
    $target = Join-Path $PatchedRoot $windowsRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "원본 파일 없음: $source" }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "패치 파일 없음: $target" }

    $baseName = [System.IO.Path]::GetFileName($relative)
    $safeName = ($baseName -replace '[^A-Za-z0-9._()-]', '_')
    $deltaName = ("{0:D2}-{1}.msdelta" -f ($index + 1), $safeName)
    $deltaPath = Join-Path $deltaRoot $deltaName
    if (Test-Path -LiteralPath $deltaPath) {
        Remove-Item -LiteralPath $deltaPath -Force
    }

    Write-Host "Creating $deltaName"
    [NewsTowerDeltaBuilder]::Create($source, $target, $deltaPath)
    $sourceItem = Get-Item -LiteralPath $source
    $targetItem = Get-Item -LiteralPath $target
    $deltaItem = Get-Item -LiteralPath $deltaPath
    $entries += [ordered]@{
        relative_path = $relative
        delta_file = "deltas/$deltaName"
        original_size = $sourceItem.Length
        original_sha256 = Get-Sha256 $source
        patched_size = $targetItem.Length
        patched_sha256 = Get-Sha256 $target
        delta_size = $deltaItem.Length
        delta_sha256 = Get-Sha256 $deltaPath
    }
}

$manifest = [ordered]@{
    format = "News Tower Korean Patch / MSDelta v1"
    patch_version = "1.0.0"
    target_game = "News Tower v1.1.165.r (Windows x64)"
    created_at = [DateTimeOffset]::Now.ToString("o")
    requires_pristine_source = $true
    bep_in_ex_used = $false
    image_assets_included = $false
    changed_file_count = $entries.Count
    files = $entries
}
$manifestJson = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText((Join-Path $payloadRoot "manifest.json"), $manifestJson + "`n", [System.Text.UTF8Encoding]::new($false))

foreach ($licenseName in @("OFL-Hahmlet.txt", "OFL-NotoSerifKR.txt")) {
    if (-not (Test-Path -LiteralPath (Join-Path $licenseRoot $licenseName) -PathType Leaf)) {
        throw "필수 폰트 라이선스 파일이 없습니다: package/.patch_data/licenses/$licenseName"
    }
}

$payloadItem = Get-Item -LiteralPath $payloadRoot -Force
$payloadItem.Attributes = $payloadItem.Attributes -bor [System.IO.FileAttributes]::Hidden

$totalDelta = ($entries | ForEach-Object { [int64]$_['delta_size'] } | Measure-Object -Sum).Sum
Write-Host "Created $($entries.Count) deltas ($totalDelta bytes total)."
