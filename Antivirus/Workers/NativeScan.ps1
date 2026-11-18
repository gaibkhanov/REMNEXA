# SPDX-License-Identifier: GPL-2.0-or-later
# This optional worker is a separate libclamav-linked program. See COPYING.txt.
#Requires -Version 7.5
$ErrorActionPreference='Stop'
try {
    Add-Type -Path @((Join-Path $PSScriptRoot '../Private/WorkerTransport.cs'),(Join-Path $PSScriptRoot 'NativeEngine.cs')) -ErrorAction Stop
    [Remnexa.Worker.Server]::Run()
}
catch {
    # Never print PowerShell text into the binary result channel.
    [Console]::Error.WriteLine($_.Exception.GetBaseException().Message)
    exit 1
}
