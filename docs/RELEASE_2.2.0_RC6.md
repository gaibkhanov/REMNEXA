[English](RELEASE_2.2.0_RC6.md) | [Deutsch](RELEASE_2.2.0_RC6.de.md)

# 2.2.0-rc.6 — worker validation and fixes

Development candidate on `fix/clamav-worker-validation`. This follow-up addresses the open validation work from [rc.5](PRIVATE_SCAN_ENGINE.md); it is not a stable release or REMNEXA 3.0.

## Corrected elevated launch

An actual UAC-elevated parent reproduced a worker handshake failure. A restricted token must retain access to its own process objects even when its creator is elevated. The launcher now explicitly grants the current user and SYSTEM access in the token's default DACL and in the new process/thread security descriptors. An Administrators-only inherited descriptor is not relied on. The three-handle inheritance allowlist, restricted medium-integrity token, elevation refusal and job limits remain.

Retesting passed from both ordinary and elevated parents. The elevated test included the real native library, harmless custom signatures, archive detection, reuse, idle shutdown, cancellation through the public scan API and private-directory ACL verification. The worker itself remained non-administrative. See the [host test record](benchmarks/rc6-worker-host.json).

## Memory and resource checks

The test host has approximately 16 GiB physical RAM and an SSD. It has no configured Windows Sandbox/Hyper-V test environment and no HDD. The following tests do not claim an 8 GiB VM or physical HDD result.

- Mocked available-memory snapshots exercise the cold 2 GiB and warm 512 MiB admission boundaries without exhausting host RAM.
- A real scan loads the full installed signature database in one thread under an actual **1.5 GiB Windows process-commit limit**. It completed and reused the same worker at the simulated warm boundary. Below the boundary, the scan was refused and the owned worker stopped.
- The observed post-scan private bytes were 1,103,081,472; peak working set was 1,178,931,200 bytes. Private commitment and working set are different counters.
- A child-process probe queries Windows kernel job state to verify memory limits, CPU hard caps, a one-process limit and kill-on-close. It also inspects the restricted token's default DACL. It does not allocate memory until failure.

See the [memory test record](benchmarks/rc6-worker-memory.json). The resource snapshot is simulated; actual scanning and Windows job enforcement are real. Low-memory system-wide contention, paging and HDD timing still require the missing test environments.

## Broader harmless scan corpus

Eleven fixtures cover ordinary clean text, Unicode, empty and random files, direct custom-signature detection, clean ZIP, matching ZIP, nested ZIP, GZip, TAR and an explicit size-limit warning. Both `clamscan` and the private engine produced the expected classifications. A sharing-locked file produced an error in both backends rather than a clean result.

The test also checks reuse with unchanged signatures and automatic reload after changing the isolated custom signature database. Installed signatures are not changed. Quarantine, EICAR and real malware are not used. This validates format/workflow behavior, not antivirus detection effectiveness against a real-world malware corpus. See the [corpus record](benchmarks/rc6-worker-corpus.json).

## CI and reproduction

The rc.5 GitHub run failed its worker tests. After the launch fix, GitHub passed the worker preflight, Pester tests and analyzer gate; the next failure was the source-packaging step. Test reports are now explicitly written to ignored `dist/`, independent of Git filename-case handling. A regression checks both Pester report spellings with strict-case Git configuration. Build failures now expose a bounded diagnostic annotation instead of only an exit code.

The package failure was traced to multiple `git` executables on the runner's PATH being treated as one command path. The builder now selects the first matching application; a regression reproduces multiple executable locations. CI retains host/Pester reports and cancels superseded runs on the same branch. Consult the [quality workflow](https://github.com/gaibkhanov/REMNEXA/actions/workflows/quality.yml) for the latest remote result.

The corrected code at `5b8f622` passed the [complete GitHub quality run](https://github.com/gaibkhanov/REMNEXA/actions/runs/44920947626), including tests, static analysis, source packaging, integrity verification and artifact upload. Locally, 181 tests passed before the last packaging regression was added; all eight packaging tests then passed separately. Ninety-four PowerShell files parsed without errors; analyzer 1.24.0 recorded zero errors, 492 warnings and 69 informational findings. The warning baseline remains open.

Run the focused local checks with an already configured ClamAV 1.5.4 installation:

```powershell
./tools/Test-ClamAVWorkerHost.ps1 -IncludeNativeEngine
./tools/Test-ClamAVMemoryPolicy.ps1
./tools/Test-ClamAVCorpus.ps1
```

Repeat the host test from an elevated PowerShell to validate that parent configuration; only these fixture tests need to be run there. It does not update ClamAV, change Windows security settings or scan personal directories.

Source packaging uses a clean commit, version `2.2.0-rc.6`, a per-file manifest and an archive SHA-256 sidecar. The ZIP excludes PowerShell, ClamAV binaries and databases. Existing candidates are not overwritten. Frontend/transport remain MIT; the optional native adapter remains GPL-2.0-or-later as documented in [third-party notices](THIRD_PARTY_NOTICES.md).

## Remaining boundaries

An actual 8 GiB Windows VM, HDD measurements and a controlled real-world malware laboratory remain unavailable. Native-engine exploit isolation is still not a complete sandbox. Automatic purging of extraction directories after an abrupt owner crash is not implemented. Existing static-analysis warnings are not presented as fixed. A stable release requires its own validation and approval.
