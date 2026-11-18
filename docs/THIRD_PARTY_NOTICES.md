[English](THIRD_PARTY_NOTICES.md) | [Deutsch](THIRD_PARTY_NOTICES.de.md)

# Third-party components and licensing

The [MIT license](../LICENSE) covers the REMNEXA frontend and IPC transport. The separate optional native adapter described below has explicit GPL notices. The MIT license does not relicense dependencies, upstream binaries, databases, models or other bundled materials. Keep original legal notices unchanged.

| Component | Role | Distribution and obligations |
| --- | --- | --- |
| PowerShell | Required application runtime, 7.5+ | Source checkout does not bundle it. PowerShell's MIT license and package-specific third-party notices remain applicable when redistributed. |
| ClamAV | Optional on-demand scanner and updater | Source checkout excludes binaries/signatures. Upstream ClamAV is GPLv2; preserve the supplied license/third-party notices and review source/provision obligations for the exact package. |
| REMNEXA native scan adapter | Optional separate-process libclamav integration | `Antivirus/Workers/NativeEngine.cs` and `NativeScan.ps1` are GPL-2.0-or-later; [GPL text](../Antivirus/Workers/COPYING.txt) is included. `WorkerTransport.cs` remains MIT and is GPL-compatible when compiled into the worker. Preserve these source notices; distributed linked workers must meet GPL source/license obligations. |
| Pester | Development tests | Not an end-user runtime requirement. Review the exact upstream version's license/notices before bundling. |
| PSScriptAnalyzer | Development analysis | Not an end-user runtime requirement. Review the exact upstream version's license/notices before bundling. |
| AI runtime/model | Planned only | Nothing selected or shipped. License/redistribution review is an acceptance requirement, not a completed clearance. |

This is an inventory and review guide, not legal advice or a declaration that every future bundle is compliant. A license identifier alone does not cover all included third-party assets or databases.

## Maintainer checklist

1. Identify exact upstream version, source, hash and included files.
2. Read that package's license and all accompanying notices, including transitive components.
3. Check modification, redistribution, source-availability and attribution requirements.
4. Preserve notices with the package and document included components.
5. Validate download integrity and keep security updates trackable.
6. Do not ship unreviewed model weights or imply REMNEXA's MIT license covers them.

## Official sources

- [PowerShell](https://github.com/PowerShell/PowerShell)
- [ClamAV](https://github.com/Cisco-Talos/clamav)
- [Pester](https://github.com/pester/Pester)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)

If evaluating `llama.cpp` or a Qwen model, inspect the exact revision/model license before choosing or distributing it. See the [roadmap](DEVELOPMENT_ROADMAP.md).
