# Generic SICF / ICF setup (standalone abapGit repo)

Reusable ABAP utility to **create, update, activate, deactivate, and inspect** SICF HTTP services. SICF nodes are not shipped by abapGit — this tool closes that gap for any project.

| Object | Name | Role |
|--------|------|------|
| Package | `ZEVO_SICF` | Suggested package |
| Class | `ZEVO_CL_SICF_SETUP` | API |
| Report | `ZEVO_SICF_SETUP` | Selection-screen UI |
| Include | `ZEVO_SICF_SETUP_CFG` | **Project defaults** (edit here) |

## Why a separate repo?

Keep ICF wiring out of product packages (CTS extract, billing APIs, …). Pull this repo once per SAP system; configure URL + handler per consumer via:

1. **`ZEVO_SICF_SETUP_CFG`** constants (this repo / your fork), or  
2. Selection screen / batch lines / SE38 variants, or  
3. Direct calls to `ZEVO_CL_SICF_SETUP=>ensure( … )` from a product post-install report.

## Install (abapGit)

1. **New online** (or offline ZIP) → point at **this** repository (not a product repo).
2. Package **`ZEVO_SICF`** (or another `Z*` package).
3. Pull → activate.
4. Optional: edit include **`ZEVO_SICF_SETUP_CFG`** with your service defaults, activate, re-pull if you keep config in Git.
5. SE38 → **`ZEVO_SICF_SETUP`**.

## Configure

### A) Config include (repo-owned defaults)

Edit [`src/zevo_sicf_setup_cfg.prog.abap`](./src/zevo_sicf_setup_cfg.prog.abap):

```abap
CONSTANTS:
  gc_sicf_cfg_url  TYPE text100   VALUE '/sap/bc/zmy_api',
  gc_sicf_cfg_hand TYPE seoclsname VALUE 'ZCL_MY_HTTP_HANDLER',
  gc_sicf_cfg_desc TYPE text60    VALUE 'My HTTP API'.
```

### B) Selection screen (single)

| Field | Example |
|-------|---------|
| ICF URL path | `/sap/bc/zmy_api` |
| Handler class | `ZCL_MY_HTTP_HANDLER` |
| Description | My API |
| Activate after save | X |

Parent `/sap/bc` must already exist (standard).

### C) Batch mode

```text
# URL;HANDLER[;HANDLER…][;description]
/sap/bc/zmy_api;ZCL_MY_HTTP_HANDLER;My project API
/sap/bc/zbilling;ZCL_BILL_HANDLER;ZCL_BILL_AUTH;Billing API
```

Sample for CTS Extract: [`examples/cts-extract.batch`](./examples/cts-extract.batch).

### D) Class API

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

Other API methods: `activate`, `deactivate`, `get_status`, `parse_batch`, `normalize_url`.

## Actions

| Action | Effect |
|--------|--------|
| Ensure | Create under parent if missing; set handlers + description; optional activate |
| Activate only | Activate existing node |
| Deactivate only | Deactivate existing node |
| Show status | Exists / active / handlers / description |
| Dry-run | Print intended changes; write nothing |

## Prerequisites

- Handler class exists and implements `IF_HTTP_EXTENSION` (or your release’s HTTP handler IF).
- Parent path exists (usually `/sap/bc`).
- User can maintain ICF (e.g. `S_ICF_ADM`).
- After setup: assign logon procedure and authorizations for callers (not automated here).

## Origin repository

**Repo:** [`evolver/sicf-setup`](https://origin.cursor.com/evolver/sicf-setup)  
**Clone / abapGit URL:** `https://origin.cursor.com/evolver/sicf-setup.git`

Point abapGit at that URL (package `ZEVO_SICF`), not at the CTS extract product repo.

### How this tree was published

From the CTS monorepo:

```bash
git subtree split --prefix=sicf-setup -b sicf-setup-main
git push https://origin.cursor.com/evolver/sicf-setup.git sicf-setup-main:main
```

## Limits

- Does not create virtual hosts or SSL endpoints.
- Does not set anonymous users / ICF aliases.
- `CL_ICF_TREE` APIs vary by BASIS; the class tries common names and returns a clear error if your release differs.
