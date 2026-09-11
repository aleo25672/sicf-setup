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
- [Authorizations](#authorizations)
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
| Package (blank = parent) | `ZEVO_SICF` |
| Transport request (optional) | `DEVK900123` |
| Activate after save | X |
| Dry-run (no changes) | optional |

Parent `/sap/bc` must already exist (standard). Save an SE38 variant per system if you do not want the include.

SICF nodes are transportable, so **fill in Package**. Blank means "inherit the parent's package", and under `/sap/bc` that is an SAP package, which turns the create into a modification of an SAP object and usually fails. Use your own `Z*` package, or `$TMP` for a local, non-transportable node. Leave **Transport request** blank to let SAP prompt; supply a request when running unattended.

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

Sample: [`examples/sample.batch`](./examples/sample.batch). Paste lines into the report; files under `examples/` are Git-only and are not pulled by abapGit.

### D) Class API (post-install)

Call `ensure` from your own post-install report after this package is on the system:

```abap
DATA ls_def TYPE zevo_cl_sicf_setup=>ty_service_def.
DATA ls_h   TYPE zevo_cl_sicf_setup=>ty_handler.
DATA ls_res TYPE zevo_cl_sicf_setup=>ty_result.

ls_def-url         = '/sap/bc/zmy_api'.
ls_def-description = 'My project API'.
ls_def-activate    = abap_true.
ls_def-package     = 'ZEVO_SICF'.   " optional, blank = parent's package
ls_def-transport   = 'DEVK900123'.  " optional, blank = SAP prompts
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
| Ensure (create/update) | Create the last path segment under the parent if missing; add handlers, set description; optionally activate |
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
- The last segment is the ICF node name and must be **15 characters or less** (`ICFNAME`). Case is kept as typed, so `/sap/bc/zmy_api` creates a lower-case node.

The path is resolved with `CL_ICF_TREE=>IF_ICF_TREE~SERVICE_FROM_URL`, which returns the deepest node that exists plus the unmatched remainder. So the tool knows both whether your node exists and which parent to create it under. Only the **last** segment is created; if more than one segment is missing, the message names the missing path and nothing is written.

## Class API

| Method | Purpose |
|--------|---------|
| `ensure` | Create or update node, handlers, description; optional activate |
| `activate` | Activate existing node |
| `deactivate` | Deactivate existing node |
| `get_status` | `exists`, `active`, `handlers` (comma-separated), `description`, `message` |
| `parse_batch` | Parse `string_table` of batch lines into `ty_service_defs` |
| `normalize_url` | Canonical ICF path (see [URL rules](#url-rules)) |

Definition (`ty_service_def`): `url`, `description`, `handlers`, `activate`, `package`, `transport`.

Result (`ty_result`): `ok`, `created`, `updated`, `url`, `message`. If the node is written but activation fails, `ok` is still true and the message tells you to activate in SICF.

The class calls released SAP APIs directly:

| Purpose | API |
|---------|-----|
| Locate node / parent from a path | `CL_ICF_TREE=>IF_ICF_TREE~SERVICE_FROM_URL` |
| Read handlers, description, settings | `CL_ICF_TREE=>IF_ICF_TREE~GET_INFO_FROM_SERV` |
| Create node | `CL_ICF_TREE=>IF_ICF_TREE~INSERT_NODE` |
| Update node | `CL_ICF_TREE=>IF_ICF_TREE~CHANGE_NODE` |
| Activate / deactivate | `HTTP_ACTIVATE_NODE` / `HTTP_INACTIVATE_NODE` |

Handlers are **added**, not replaced: on update, handlers already assigned to the node are skipped (passing them again makes `CHANGE_NODE` fail), and handlers you drop from the list stay on the node. Remove those in SICF.

If the description is empty, the existing one is kept; for a new node the node name is used, because SICF requires a description.

## After setup

This tool does **not** assign logon procedure, anonymous user, ICF alias, or caller authorizations. In transaction **SICF**, open the new node and set:

- Logon procedure / client / user (as required by the API)
- Handler list (should already match what you passed)
- Authorizations for callers (e.g. `S_ICF` / service-specific checks)

Then test the URL from a browser or HTTP client.

## Prerequisites

- Handler class exists and implements `IF_HTTP_EXTENSION` (or your release’s HTTP handler interface).
- Parent ICF path exists and is usable (usually `/sap/bc`).
- User can maintain ICF — see [Authorizations](#authorizations).

Typical failures:

| Message | What to do |
|---------|------------|
| Only the last path segment can be created. Missing in SICF: `…` | Create the intermediate nodes in SICF first |
| Node name `…` is longer than 15 characters | Shorten the last URL segment |
| At least one handler class is required | Fill handler on the screen, include, or batch line |
| URL is too short | Use at least `/sap/<name>` |
| Service not found. Missing path: `…` | Ensure/activate against a path that already exists |
| Handler class rejected | Check the class exists and implements `IF_HTTP_EXTENSION` |
| Transport check failed | Supply a transport request, or use a local package |
| No authorization to create … For S_DEVELOP set Package | Blank package inherits SAP's; use a `Z*` package or `$TMP` |
| No authorization … Run SU53 | See [Authorizations](#authorizations) |
| ICF node is locked by another user | Someone has the node open in SICF |

## Authorizations

Creating an ICF node is checked against **`S_ICF_ADM`**. Creating, changing, and activating are *separate* activities, so a user who can create a node may still fail to activate it.

| Field | Value for this tool |
|-------|---------------------|
| `ACTVT` | `01` create, `02` change, `03` display, `07` activation |
| `ICF_TYPE` | `Node` (service) |
| `ICF_HOST` | your virtual host, normally `DEFAULT_HOST` |
| `ICF_NODE` | GUID of the node the authorization applies to |

`ICF_NODE` is a **GUID, not a path**. For creating under `/sap/bc` it is the GUID of `bc`, because the new node has no GUID yet. Granting the GUID of a higher node covers everything beneath it, so the GUID of `sap` covers all of `/sap/*`. In PFCG you do not have to look the GUID up by hand: in the authorization field, choose the node from the ICF service hierarchy and PFCG fills the GUID in.

If the report says you have no authorization, run **SU53** right after the failure. It shows the exact object, activity, and node GUID that was refused — hand that screen to whoever maintains roles.

**If you can create the same node by hand in SICF but the report cannot**, check the **package** before suspecting your role. A blank package means "inherit the parent's package", and `/sap/bc` belongs to SAP, so creating there is a modification of an SAP object — which most developers are not allowed to do, and which can surface as a plain authorization failure. The SICF dialog does not hit this because it asks you for a package. Set **Package** to your own `Z*` package, or `$TMP` for a local, non-transportable node.

SU53 tells the two cases apart: `S_DEVELOP` points at the package, `S_ICF_ADM` at your ICF rights. The failure message also prints the parent GUID the tool passed as `ICF_NODE`, so you can compare it with SU53 and with the parent's GUID in SICF.

Because SICF nodes are transportable, creating one can additionally require rights for the package and the transport request. Using a **local package** (`$TMP`) avoids the transport entirely, at the cost of not being transportable to QA/production.

## Limits

- Does not create virtual hosts or SSL endpoints.
- Does not set anonymous users, logon data, or ICF aliases.
- Does not create more than one new path segment (parent must exist).
- Does not remove handlers, delete nodes, or set alternative service names.
- Node names are limited to 15 characters (`ICFNAME`).
- Batch UI is eight lines; call `parse_batch` + `ensure` in a loop for longer lists.

## Repository layout

```text
src/                      abapGit objects (PREFIX folder logic)
  zevo_cl_sicf_setup.*    API class
  zevo_sicf_setup.*       SE38 report
  zevo_sicf_setup_cfg.*   defaults include
  package.devc.xml        package ZEVO_SICF
examples/sample.batch     sample batch lines (Git only)
```
