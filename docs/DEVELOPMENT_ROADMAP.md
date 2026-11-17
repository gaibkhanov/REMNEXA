[English](DEVELOPMENT_ROADMAP.md) | [Deutsch](DEVELOPMENT_ROADMAP.de.md)

# Development roadmap

The 2.2.0 development build is an incremental step from 2.1.3, not the completed REMNEXA 3.0 platform. Preserve functioning features while reducing risk. See [architecture audit](ARCHITECTURE_AUDIT.md).

## Phase status

| Phase | Status | Delivered | Remaining acceptance work |
| --- | --- | --- | --- |
| A: audit | Completed for available source scope | Architecture, risks, compatibility and plan | Independent audit and broader integration evidence. |
| B: stabilization | Partially implemented | Download/config/path safeguards, clearer outcomes, regression tests | Comprehensive recovery and interrupted-operation tests. |
| C: modularization | Partially implemented | Core modules, compatibility wrappers, external language resources | Smaller dispatcher and complete typed boundaries. |
| D: local AI | Not implemented beyond contracts | Bounded input and advisory-output schemas | Runtime, model selection, licensing, benchmarks, chat and offline tests. |
| E: system modules | Partially implemented | Read-only snapshot/UI plus existing maintenance tools | Advanced storage analysis and stronger uninstall attribution. |
| F: UI/UX | Partially implemented | Current console navigation, exit/pagination and permission explanations | Evaluated graphical UI, accessibility and responsive task/cancel support. |
| G: QA | Partially implemented | Local regression/self-test/error gate and CI definition | Verified CI, VM matrix, recovery, offline, performance and package tests. |
| H: release candidate | Partially implemented | Source-candidate builder, integrity checks and candidate notes | Installer, broader Windows/recovery validation and explicit publication approval. |

## Priority 1: safety and reliability

- Attribute leftovers using product IDs, publisher/path metadata and shared dependencies; unknown ownership must default to retention.
- Extend isolated tests for permission failures, shared files, malicious paths and interrupted operations.
- Design operation-level backups with verified recovery for supported Registry, startup, file, task and service changes.
- Reduce filesystem race exposure; do not describe ancestor checks as complete protection.
- Review analyzer warnings individually and reproduce the analyzer full-run crash.

## Priority 2: maintainability and usability

Continue extracting core logic without breaking command-line or localization compatibility. Define consistent outcomes, progress and safe cancellation. Keep language keys external and maintain paired English/German docs.

Measure console startup, inventory, residual scans, idle memory and system scans before setting performance targets. Compare a native Windows UI against actual memory/startup/packaging/accessibility needs before committing to migration.

## Priority 3: embedded offline AI

Evaluate `llama.cpp` with CPU-only Windows operation, bounded resource use, cancellation, isolation and idle shutdown. Compare at least three redistributable compact instruct models, including suitable Qwen candidates, using fixed German/English system-report prompts.

Record model/version/quantization, licenses, hashes, hardware, RAM, load time, tokens/second, instruction adherence and factual quality. No winner has been selected and no benchmark result is available.

The planned Standard edition may download a verified optional model; Complete must include all runtime/model dependencies and pass a disconnected-machine test. Neither package exists yet. Users must not need Python, Node.js, Docker, Ollama, cloud keys or paid APIs.

AI remains an advisory component without execution or elevation authority. Do not block useful classic functionality on model availability.

## Release gate

Maintain existing functions, pass meaningful safety/recovery and Windows compatibility tests, verify offline packaging and third-party licensing, and prepare checksummed artifacts with honest signing status. Obtain explicit maintainer approval before production publication. Do not rename an incomplete development build to 3.0 to imply completion.
