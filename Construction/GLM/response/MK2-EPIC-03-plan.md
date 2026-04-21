# MK2‑EPIC‑03 – ARC‑AGI Submission Orchestrator & CLI Design Document

**Author:** [Your Name]  
**Date:** 2026‑04‑21  
**Status:** Draft → Review → Approved → Implement  

---

## 1. Purpose & Scope

This document defines the architecture, data flow, component responsibilities, and implementation roadmap for the **ARC‑AGI end‑to‑end submission path**. The goal is to provide a **single, reproducible entry point** (CLI) that:

1. Accepts a user‑provided ARC task description (or a demo placeholder).  
2. Validates and normalises the input.  
3. Orchestrates the execution of the task via the **ARC‑AGI orchestrator**.  
4. Captures, formats, and returns the solution in the ARC‑AGI JSON schema.  
5. Supplies a **smoke‑test** harness, documentation, and automated tests to guarantee reliability.

The design is deliberately modular to allow future extensions (e.g., remote execution, multi‑model ensembles) without breaking the public CLI contract.

---

## 2. High‑Level Architecture

```
+-------------------+        +-------------------+        +-------------------+
|   CLI (arc-cli)   |  -->   |   Orchestrator    |  -->   |   Task Runner(s)  |
|   (Python entry) |        |   (core lib)      |        |   (model adapters)|
+-------------------+        +-------------------+        +-------------------+
          |                           |                           |
          |   1. Parse args / config   |   2. Validate & schedule   |
          |   2. Load task spec        |   3. Dispatch to runner   |
          |   3. Forward to orchestrator|   4. Collect results     |
          |                           |   5. Post‑process output  |
          v                           v                           v
+-------------------+        +-------------------+        +-------------------+
|   Documentation   |        |   Smoke Test      |        |   Unit / Integration|
|   (README, docs) |        |   (pytest)        |        |   (pytest)           |
+-------------------+        +-------------------+        +-------------------+
```

* **CLI** – thin wrapper that parses command‑line arguments, loads a task definition (JSON or demo), and invokes the orchestrator.  
* **Orchestrator** – core library responsible for validation, scheduling, and result aggregation. It is deliberately UI‑agnostic.  
* **Task Runner(s)** – adapters that execute a specific ARC‑AGI model (e.g., a transformer, a symbolic solver). For the MVP we ship a **demo runner** that returns a deterministic placeholder solution.  
* **Smoke Test** – a minimal end‑to‑end test that runs the CLI against the demo task and asserts a valid JSON response.  
* **Documentation & Tests** – ensure discoverability and regression safety.

---

## 3. Component Details

### 3.1 CLI (`arc_cli.py`)

| Responsibility | Implementation Notes |
|----------------|----------------------|
| Argument parsing (argparse) | `--task <path|demo>`; `--output <path>`; optional `--model <name>` |
| Load task spec | If `demo`, generate a built‑in demo JSON; else read file and validate JSON schema. |
| Initialise orchestrator | Pass a configuration object (model name, resource limits). |
| Execute & capture result | Call `orchestrator.run(task_spec)` and write the returned JSON to `stdout` or `--output`. |
| Exit codes | `0` on success, non‑zero on validation/orchestration failure. |
| Logging | Use `logging` with a `--verbose` flag. |

### 3.2 Orchestrator (`arc_orchestrator/__init__.py`)

| Responsibility | Implementation Notes |
|----------------|----------------------|
| Input validation | Verify required fields (`grid_size`, `input`, `output`) per ARC‑AGI spec. |
| Scheduler stub | For MVP, a simple synchronous call to the selected runner. Future versions may queue tasks. |
| Runner selection | Map `model` name to a concrete runner class (`DemoRunner`, `TransformerRunner`, …). |
| Execution wrapper | `run(task_spec) -> solution_json`. Handles exceptions and normalises error messages. |
| Post‑processing | Ensure the solution conforms to the ARC‑AGI output schema (e.g., correct dimensions, types). |
| Extensibility hooks | `register_runner(name, cls)` for third‑party plugins. |

### 3.3 Demo Task Runner (`arc_demo_runner.py`)

* Generates a **deterministic placeholder solution** (e.g., copies the input grid to output).  
* Implements the runner interface required by the orchestrator (`solve(task_spec) -> solution`).  
* Serves as a **smoke‑test target** and a reference implementation for developers.

### 3.4 Smoke Test (`tests/test_smoke.py`)

* Executes the CLI via `subprocess.run([...])` with the `demo` flag.  
* Asserts:
  * Exit code `0`.  
  * Output is valid JSON.  
  * JSON matches the expected demo schema (e.g., contains `solution` key).  

### 3.5 Documentation (`README.md`)

* Quick‑start guide (install, run demo).  
* CLI usage table.  
* Architecture overview (ASCII diagram).  
* Contribution guidelines (how to add new runners, tests).  

### 3.6 Automated Tests (`tests/`)

| Test Type | Scope |
|-----------|-------|
| Unit tests | Validate orchestrator validation logic, runner registration, and error handling. |
| Integration tests | End‑to‑end CLI execution with real task files (sample ARC puzzles). |
| Coverage | Target ≥ 85 % for the orchestrator module. |

---

## 4. Data Flow Walk‑through

1. **User invokes CLI**  
   ```bash
   $ arc-cli --task demo --output solution.json
   ```
2. **CLI parses arguments** → builds `Config` object (`model="demo"`).  
3. **Task spec generation**  
   * `demo` flag → `DemoTaskFactory.create()` returns a JSON dict adhering to ARC‑AGI input schema.  
   * If a file path is supplied → read & JSON‑load → `SchemaValidator.validate(task_json)`.  
4. **Orchestrator receives** `(task_spec, config)`.  
5. **Runner lookup** → `DemoRunner` is instantiated.  
6. **Runner.solve(task_spec)** → returns a solution dict (`{ "output_grid": [...] }`).  
7. **Orchestrator post‑processes** → ensures dimensions match the original task, adds metadata (`"model": "demo"`).  
8. **Result is returned** to CLI.  
9. **CLI writes** JSON to `solution.json` (or `stdout`).  
10. **Smoke test** repeats steps 1‑9 and asserts the file contains a valid solution.

---

## 5. Implementation Steps & Milestones

| Milestone | Description | Owner | Estimated Effort |
|-----------|-------------|-------|-------------------|
| **M1 – Project scaffolding** | Create package layout (`arc_cli/`, `arc_orchestrator/`, `tests/`). Add `pyproject.toml`. | Lead Dev | 0.5 d |
| **M2 – CLI prototype** | Implement `arc_cli.py` with argparse, demo task generation, and stub orchestrator call. | Dev A | 1 d |
| **M3 – Orchestrator core** | Build validation, runner registry, synchronous scheduler, error handling. | Dev B | 2 d |
| **M4 – Demo Runner** | Implement deterministic placeholder solver, register as `"demo"` runner. | Dev A | 0.5 d |
| **M5 – End‑to‑end integration** | Wire CLI → Orchestrator → Demo Runner; ensure JSON output matches schema. | Dev B | 1 d |
| **M6 – Smoke test** | Write `tests/test_smoke.py`, configure CI to run on push. | QA Engineer | 0.5 d |
| **M7 – Documentation** | Draft `README.md`, usage examples, architecture diagram. | Tech Writer | 0.5 d |
| **M8 – Unit & integration tests** | Add coverage for validation, runner registration, error paths. | QA Engineer | 1 d |
| **M9 – CI/CD pipeline** | Add GitHub Actions workflow: lint → test → package. | DevOps | 0.5 d |
| **M10 – Release** | Tag v0.1.0, publish to PyPI (testpypi). | Lead Dev | 0.5 d |

**Total estimated effort:** ~ 8 person‑days.

---

## 6. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Schema drift** – ARC‑AGI spec changes. | Breaks validation & downstream runners. | Pin schema version in `requirements.txt`; add schema‑upgrade tests. |
| **CLI usability** – ambiguous flags. | Poor user adoption. | Provide clear help (`-h`) and examples in README. |
| **Runner performance** – demo runner trivial, real models may be heavy. | Long CI times. | Keep demo runner for CI; allow optional `--model` flag for heavy models, run them only in dedicated pipelines. |
| **Error propagation** – uncaught exceptions leak stack traces. | Bad UX, CI noise. | Centralised exception handling in orchestrator, map to user‑friendly messages and exit codes. |

---

## 7. Future Extensions (Post‑MVP)

1. **Remote Execution Service** – expose orchestrator via HTTP/GRPC for distributed workloads.  
2. **Model Registry** – plug‑in architecture for community‑contributed solvers.  
3. **Result Visualization** – optional `--viz` flag to render input/output grids in the terminal (using `rich`).  
4. **Benchmark Suite** – automated scoring against the full ARC‑AGI benchmark set.  

---

## 8. Glossary

| Term | Definition |
|------|------------|
| **ARC‑AGI** | Abstraction and Reasoning Corpus – a benchmark of visual reasoning tasks. |
| **Orchestrator** | Core library that validates tasks, selects runners, and aggregates results. |
| **Runner** | Adapter that implements a concrete solving strategy for a given task. |
| **Demo Runner** | Minimal placeholder runner used for smoke testing and documentation. |
| **CLI** | Command‑Line Interface (`arc-cli`) that provides the public entry point. |
| **Smoke Test** | Quick end‑to‑end test that verifies the whole pipeline works with the demo task. |

--- 

*Prepared for the ARC‑AGI development team. Feedback is welcome before the implementation sprint begins.*