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
| Diagnose | Print resolved values and authorization results; write nothing |
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
- User can maintain ICF: `S_ICF_ADM` **and** `S_ADMI_FCD` value `NADM` — see [Authorizations](#authorizations).

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
| No authorization … missing `S_ADMI_FCD` value `NADM` | Ask for that value in your role; SICF does not need it but the API does |
| No authorization … missing `S_ICF_ADM` | Grant the activity for the printed `ICF_NODE` GUID |
| No authorization … `S_DEVELOP` refused in Diagnose | Blank package inherits SAP's; use a `Z*` package or `$TMP` |
| No authorization … but Diagnose shows every check granted | Not your role. Set **Package** to `$TMP` or a `Z*` package; then check the system change option (`SE06`) |
| ICF node is locked by another user | Someone has the node open in SICF |

## Authorizations

Two objects have to be right, and they are checked by different layers:

| Object | Value | Checked by |
|--------|-------|-----------|
| `S_ADMI_FCD` | `S_ADMI_FCD` = `NADM` (network administration) | the `HTTPTREE` function layer under the ICF API |
| `S_ICF_ADM` | `ACTVT` `01`/`02`/`07`, `ICF_TYPE` `Node`, `ICF_HOST`, `ICF_NODE` | the ICF tree itself |

`S_ADMI_FCD` = `NADM` is the one people miss, because transaction SICF does not need it while the function layer under the ICF API does. If SAP message `00 150`, *"You are not authorized to use function Netzwerkadministration"*, comes back, that text is the description of function code `NADM` (often German even on an English logon, since it is the maintained text). Confirm it with **Diagnose** before asking for it, though — see below.

For `S_ICF_ADM`, creating, changing, and activating are *separate* activities, so a user who can create a node may still fail to activate it. `ICF_NODE` is a **GUID, not a path**. For creating under `/sap/bc` it is the GUID of `bc`, because the new node has no GUID yet. Granting the GUID of a higher node covers everything beneath it, so the GUID of `sap` covers all of `/sap/*`. In PFCG you do not have to look the GUID up by hand: in the authorization field, choose the node from the ICF service hierarchy and PFCG fills the GUID in.

### Diagnosing a refusal

Failure messages name the object themselves, so start by reading the message. Two cautions before you act on one:

- **`NO_AUTHORITY` does not prove an authorization is missing.** It is the exception the ICF API raises for several refusals, including ones that come from the change and transport layer rather than from your role. If you hold `SAP_ALL`, or Diagnose reports every check granted, then the cause is *not* your role, whatever the wording says — read the package angle below.
- **The quoted SAP message may be about something else.** A classic exception only carries a message when the API raised it with `MESSAGE … RAISING`; a plain `RAISE` leaves whatever was in the message buffer from earlier processing. The tool stamps a marker before each call and prints `SAP left no message` when the marker survives, so a message shown after `SAP:` is genuinely from that call — but older builds of this tool could quote a stale one.

The **Diagnose** action runs the checks itself and prints what it finds. It writes nothing, so it also works as a pre-flight check against a production system:

```text
--- ZEVO_SICF_SETUP diagnosis ---
User / client      : DEVELOPER / 100
Normalized URL     : /sap/bc/zsicf_setup
Node name          : zsicf_setup (11 of 15 chars)
Parent path        : /sap/bc
Node               : does not exist yet (missing '/zsicf_setup')
Parent GUID        : EEPI2GLFNOLHN7IW9R54I61RZ
Parent package     : SHTTP (SAP-owned: creating here modifies SAP standard)
Package requested  : blank, so parent package 'SHTTP' is used
Client change opt. : changes to repository and cross-client objects allowed
S_ADMI_FCD NADM    : subrc 12 - refused, no authorization for this object at all
  ^ this is the one SICF does not need but the ICF API does.
S_ICF_ADM create   : subrc 0 - granted
S_DEVELOP SICF     : subrc 12 - refused, no authorization for this object at all on 'SHTTP'
```

Read the refused lines in order:

- **`S_ADMI_FCD NADM` refused** — ask for that value in your role. Nothing else you change in the tool will help.
- **`S_ICF_ADM` refused** — it really is your ICF role, and the printed `ICF_NODE` GUID is the value the role has to cover.
- **`S_DEVELOP` refused, the rest granted** — the package is the problem, not ICF rights. Set **Package** to your own `Z*` package, or `$TMP` for a local, non-transportable node.
- **`Client change opt.` says repository changes are blocked** — an ICF node is a cross-client repository object, so this client (`SCC4`) forbids it and no profile can override that. Use a client that permits repository changes.
- **All granted, and the call still fails with no authorization** — believe Diagnose, not the wording. The usual cause is the **package**: blank means "inherit the parent's", and `/sap/bc` belongs to SAP, so the node is created as an SAP object. Creating there needs the SAP namespace to be modifiable in the **system change option** (`SE06`), which no profile can grant you — `SAP_ALL` does not help. The SICF dialog dodges this by asking you for a package. Set **Package** to `$TMP` or a `Z*` package and retry; that single change resolves most of these.

If you want certainty rather than inference, record an authorization trace with **`STAUTHTRACE`** (or `ST01`) while running the report. It logs every `AUTHORITY-CHECK` with its values and return code, including the ones that succeed. If the trace shows no failure, the refusal is not an authorization at all and the change and transport layer is where to look.

Holding `SAP_ALL` is not quite the same as the checks passing: a profile assigned during the current session only takes effect at the next logon. **`SU56`** shows what is actually in your user buffer right now, which is what `AUTHORITY-CHECK` reads.

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
