from __future__ import annotations

import base64
import hashlib
import io
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PAYLOAD_ROOT = REPOSITORY_ROOT / "package" / ".patch_data"
OUTPUT = REPOSITORY_ROOT / "dist" / "NewsTower_Korean_Patch_v1.0.0.bat"


HEADER = r'''@echo off
setlocal
set "NTKR_SELF=%~f0"
set "NTKR_ARG1=%~1"
set "NTKR_ARG2=%~2"
set "NTKR_ARG3=%~3"
set "NTKR_ARG4=%~4"
title News Tower Korean Patch v1.0.0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';$tmp=Join-Path ([IO.Path]::GetTempPath()) ('NewsTowerKR_'+[Guid]::NewGuid().ToString('N'));$forward=@($env:NTKR_ARG1,$env:NTKR_ARG2,$env:NTKR_ARG3,$env:NTKR_ARG4)|Where-Object{$_};try{[IO.Directory]::CreateDirectory($tmp)|Out-Null;$text=[IO.File]::ReadAllText($env:NTKR_SELF,[Text.Encoding]::ASCII);$marker='__NTKR_PAYLOAD__';$at=$text.LastIndexOf($marker,[StringComparison]::Ordinal);if($at -lt 0){throw 'Embedded payload not found.'};$payload=$text.Substring($at+$marker.Length);$zip=Join-Path $tmp 'payload.zip';[IO.File]::WriteAllBytes($zip,[Convert]::FromBase64String($payload));Add-Type -AssemblyName System.IO.Compression.FileSystem;[IO.Compression.ZipFile]::ExtractToDirectory($zip,$tmp);& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp 'install.ps1') @forward;$code=$LASTEXITCODE}catch{Write-Host ('Bootstrap error: '+$_.Exception.Message) -ForegroundColor Red;$code=1}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}};exit $code"
set "PATCH_EXIT=%ERRORLEVEL%"
echo.
if not "%PATCH_EXIT%"=="0" echo The patch did not complete. Check the error above.
pause
exit /b %PATCH_EXIT%
__NTKR_PAYLOAD__
'''


def make_payload() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
        files = sorted((path for path in PAYLOAD_ROOT.rglob("*") if path.is_file()), key=lambda path: path.as_posix().lower())
        for path in files:
            archive.write(path, path.relative_to(PAYLOAD_ROOT).as_posix())
    return buffer.getvalue()


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    payload = make_payload()
    encoded = base64.b64encode(payload).decode("ascii")
    wrapped = "\r\n".join(encoded[index : index + 76] for index in range(0, len(encoded), 76))
    OUTPUT.write_bytes((HEADER.replace("\n", "\r\n") + wrapped + "\r\n").encode("ascii"))

    raw = OUTPUT.read_bytes()
    marker = b"__NTKR_PAYLOAD__\r\n"
    marker_at = raw.find(marker)
    if marker_at < 0:
        raise RuntimeError("Payload marker not found in generated BAT")
    decoded = base64.b64decode(raw[marker_at + len(marker) :], validate=False)
    if decoded != payload:
        raise RuntimeError("Embedded payload round-trip mismatch")
    with zipfile.ZipFile(io.BytesIO(decoded)) as archive:
        names = set(archive.namelist())
        required = {"install.ps1", "manifest.json"}
        if not required.issubset(names):
            raise RuntimeError(f"Embedded archive is missing {sorted(required.difference(names))}")
        delta_count = sum(name.startswith("deltas/") and name.endswith(".msdelta") for name in names)
        if delta_count != 6:
            raise RuntimeError(f"Expected 6 delta files, found {delta_count}")

    print(f"file={OUTPUT}")
    print(f"bytes={len(raw)}")
    print(f"sha256={hashlib.sha256(raw).hexdigest()}")
    print(f"embedded_zip_bytes={len(payload)}")


if __name__ == "__main__":
    main()
