# SICF / ICF setup for ABAP

abapGit does not ship **SICF** (ICF HTTP service) nodes. This utility creates, updates, activates, deactivates, and inspects them.

Install **once per SAP system** via abapGit. Point each consumer at its URL and handler class through the config include, the selection screen, a batch list, or a direct class call.

| Object | Name | Role |
|--------|------|------|
| Package | `ZEVO_SICF` | Suggested package (`BC-MID-ICF`) |
| Class | `ZEVO_CL_SICF_SETUP` | Reusable API |
| Report | `ZEVO_SICF_SETUP` | SE38 selection-screen UI |
| Include | `ZEVO_SICF_SETUP_CFG` | Optional project defaults |

## Contents

- [Install (abapGit)](#install-abapgit)
- [Configure](#configure)
- [Report actions](#report-actions)
- [URL rules](#url-rules)
- [Class API](#class-api)
- [After setup](#after-setup)
- [Prerequisites](#prerequisites)
- [Limits](#limits)
- [Repository layout](#repository-layout)

## Install (abapGit)

1. In abapGit, **New online** (or offline ZIP) and point at this repository.
2. Use package **`ZEVO_SICF`** (or another `Z*` package).
3. Pull and activate.
4. Optional: set defaults in include **`ZEVO_SICF_SETUP_CFG`**, activate, and re-pull if you keep those constants in Git.
5. Run SE38 → **`ZEVO_SICF_SETUP`**.

`README.md`, `.gitignore`, and `examples/` are listed in `.abapgit.xml` **IGNORE**. They stay in Git only; they are not imported into the SAP system.

## Configure

Pick one path. They all end up in `ZEVO_CL_SICF_SETUP`.

### A) Config include (repo-owned defaults)

Edit [`src/zevo_sicf_setup_cfg.prog.abap`](./src/zevo_sicf_setup_cfg.prog.abap). Non-empty constants pre-fill the selection screen:

```abap
CONSTANTS:
  gc_sicf_cfg_url  TYPE text100   VALUE '/sap/bc/zmy_api',
  gc_sicf_cfg_hand TYPE seoclsname VALUE 'ZCL_MY_HTTP_HANDLER',
  gc_sicf_cfg_desc TYPE text60    VALUE 'My HTTP API'.
```

Leave them blank if you prefer the screen, batch lines, or a post-install report.

### B) Selection screen (single service)

SE38 → `ZEVO_SICF_SETUP` → **Single service**.

| Field | Example |
|-------|---------|
| ICF URL path | `/sap/bc/zmy_api` |
| Handler class | `ZCL_MY_HTTP_HANDLER` |
| Description | My API |
| Activate after save | X |
| Dry-run (no changes) | optional |

Parent `/sap/bc` must already exist (standard). Save an SE38 variant per system if you do not want the include.

Single mode accepts **one** handler class. For several handlers on one node, use batch mode or the class API.

### C) Batch mode

SE38 → **Batch (multi-project)**. Up to eight lines:

```text
# URL;HANDLER[;HANDLER…][;description]
/sap/bc/zmy_api;ZCL_MY_HTTP_HANDLER;My project API
/sap/bc/zbilling;ZCL_BILL_HANDLER;ZCL_BILL_AUTH;Billing API
```

- Blank lines and lines starting with `#` are skipped.
- First token is the URL; the second is the first handler.
- Later tokens that look like class names (`Z…`, `Y…`, `CL_…`, or containing `/` for namespaces) are extra handlers; anything else is description.
- Parsed lines always set **activate** to true; the screen checkbox **Activate after save** still applies when you run **Ensure**.

Paste lines into the report. Files under `examples/` are Git-only and are not pulled by abapGit.

### D) Class API (post-install)

Call `ensure` from your own post-install report after this package is on the system:

```abap
DATA ls_def TYPE zevo_cl_sicf_setup=>ty_service_def.
DATA ls_h   TYPE zevo_cl_sicf_setup=>ty_handler.
DATA ls_res TYPE zevo_cl_sicf_setup=>ty_result.

ls_def-url         = '/sap/bc/zmy_api'.
ls_def-description = 'My project API'.
ls_def-activate    = abap_true.
ls_h-classname     = 'ZCL_MY_HTTP_HANDLER'.
APPEND ls_h TO ls_def-handlers.

ls_res = zevo_cl_sicf_setup=>ensure( is_def = ls_def ).
IF ls_res-ok = abap_false.
  MESSAGE ls_res-message TYPE 'E'.
ENDIF.
```

`ensure` requires at least one handler. Pass `iv_dry_run = abap_true` to print intended create/update without writing.

## Report actions

| Action | Effect |
|--------|--------|
| Ensure (create/update) | Create the last path segment under the parent if missing; set handlers and description; optionally activate |
| Activate only | Activate an existing node |
| Deactivate only | Deactivate an existing node |
| Show status | Exists / active / handlers / description |
| Dry-run | Print intended changes; write nothing |

The list at the end of the spool is `ok=` / `failed=` counts. Dry-run still counts as OK when the plan is valid.

## URL rules

`normalize_url` is applied everywhere:

- Leading `/` is added if missing; trailing `/` is stripped.
- Backslashes become slashes.
- A leading `/default_host` prefix is removed (SICF virtual host).
- Paths must be at least two segments after split, e.g. `/sap/<service>`. A lone `/` is rejected.

The **parent** node (everything except the last segment) must already exist. This tool does not create intermediate folders. Typical parent: `/sap/bc`.

## Class API

| Method | Purpose |
|--------|---------|
| `ensure` | Create or update node, handlers, description; optional activate |
| `activate` | Activate existing node |
| `deactivate` | Deactivate existing node |
| `get_status` | `exists`, `active`, `handlers` (comma-separated), `description`, `message` |
| `parse_batch` | Parse `string_table` of batch lines into `ty_service_defs` |
| `normalize_url` | Canonical ICF path (see [URL rules](#url-rules)) |

Result (`ty_result`): `ok`, `created`, `updated`, `url`, `message`. If save succeeds but activate fails, `ok` is still true and the message tells you to activate in SICF.

`CL_ICF_TREE` method names differ by BASIS release. The class tries common names (`SERVICE_FROM_URL`, `INSERT_NODE`, `SET_HANDLERLIST`, `ORDER_SAVE`, …) and returns a clear error if none match.

## After setup

This tool does **not** assign logon procedure, anonymous user, ICF alias, or caller authorizations. In transaction **SICF**, open the new node and set:

- Logon procedure / client / user (as required by the API)
- Handler list (should already match what you passed)
- Authorizations for callers (e.g. `S_ICF` / service-specific checks)

Then test the URL from a browser or HTTP client.

## Prerequisites

- Handler class exists and implements `IF_HTTP_EXTENSION` (or your release’s HTTP handler interface).
- Parent ICF path exists and is usable (usually `/sap/bc`).
- User can maintain ICF (e.g. `S_ICF_ADM`).

Typical failures:

| Message | What to do |
|---------|------------|
| Parent ICF node `…` not found | Create/activate the parent in SICF first |
| At least one handler class is required | Fill handler on the screen, include, or batch line |
| URL is too short | Use at least `/sap/<name>` |
| Service not found | Ensure/activate against a path that already exists |
| Cannot create/set/save ICF node | BASIS `CL_ICF_TREE` mismatch or missing `S_ICF_ADM` |

## Limits

- Does not create virtual hosts or SSL endpoints.
- Does not set anonymous users or ICF aliases.
- Does not create more than one new path segment (parent must exist).
- Batch UI is eight lines; call `parse_batch` + `ensure` in a loop for longer lists.
- `CL_ICF_TREE` APIs vary by BASIS; unsupported releases get an error rather than a silent no-op.

## Repository layout

```text
src/                      abapGit objects (PREFIX folder logic)
  zevo_cl_sicf_setup.*    API class
  zevo_sicf_setup.*       SE38 report
  zevo_sicf_setup_cfg.*   defaults include
  package.devc.xml        package ZEVO_SICF
examples/                 sample batch lines (Git only)
```
