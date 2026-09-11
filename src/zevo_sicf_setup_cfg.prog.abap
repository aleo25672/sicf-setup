*&---------------------------------------------------------------------*
*& Include ZEVO_SICF_SETUP_CFG
*&---------------------------------------------------------------------*
*& Project-specific defaults for report ZEVO_SICF_SETUP.
*&
*& How to configure (pick one):
*&   1. Edit the constants below in this repo, then abapGit pull
*&   2. Leave blank and fill URL / handler on the selection screen
*&   3. Use Batch mode or SE38 selection variants per system
*&   4. Call ZEVO_CL_SICF_SETUP=>ENSURE from your own post-install report
*&
*& The last URL segment is the ICF node name: max 15 characters.
*&
*& Example:
*&   gc_sicf_cfg_url  = '/sap/bc/zmy_api'
*&   gc_sicf_cfg_hand = 'ZCL_MY_HTTP_HANDLER'
*&   gc_sicf_cfg_desc = 'My HTTP API'
*&---------------------------------------------------------------------*

CONSTANTS:
  gc_sicf_cfg_url  TYPE text100   VALUE '',
  gc_sicf_cfg_hand TYPE seoclsname VALUE '',
  gc_sicf_cfg_desc TYPE text60    VALUE ''.
