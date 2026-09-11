*&---------------------------------------------------------------------*
*& Report ZEVO_SICF_SETUP
*&---------------------------------------------------------------------*
*& Generic SICF / ICF setup utility (standalone tool repo).
*&
*& Defaults: edit include ZEVO_SICF_SETUP_CFG, or fill the screen / batch.
*&
*& Batch line format: URL;HANDLER[;HANDLER…][;description]
*& Lines starting with # are comments.
*&---------------------------------------------------------------------*
REPORT zevo_sicf_setup.

INCLUDE zevo_sicf_setup_cfg.

* Radios / checkboxes: COMMENT + INITIALIZATION so labels show even when
* only the .abap is pasted (no text-pool import).
SELECTION-SCREEN BEGIN OF BLOCK a WITH FRAME TITLE TEXT-001.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_ensur RADIOBUTTON GROUP act DEFAULT 'X'.
SELECTION-SCREEN COMMENT 3(40) c_ensur FOR FIELD p_ensur.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_act RADIOBUTTON GROUP act.
SELECTION-SCREEN COMMENT 3(40) c_act FOR FIELD p_act.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_deact RADIOBUTTON GROUP act.
SELECTION-SCREEN COMMENT 3(40) c_deact FOR FIELD p_deact.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_stat RADIOBUTTON GROUP act.
SELECTION-SCREEN COMMENT 3(40) c_stat FOR FIELD p_stat.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK a.

SELECTION-SCREEN BEGIN OF BLOCK m WITH FRAME TITLE TEXT-002.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_single RADIOBUTTON GROUP mod DEFAULT 'X' USER-COMMAND mod.
SELECTION-SCREEN COMMENT 3(40) c_sing FOR FIELD p_single.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_batch RADIOBUTTON GROUP mod.
SELECTION-SCREEN COMMENT 3(40) c_batch FOR FIELD p_batch.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK m.

SELECTION-SCREEN BEGIN OF BLOCK s WITH FRAME TITLE TEXT-003.
PARAMETERS:
  p_url  TYPE text100 LOWER CASE MODIF ID sng,
  p_hand TYPE seoclsname MODIF ID sng,
  p_desc TYPE text60 MODIF ID sng.
SELECTION-SCREEN END OF BLOCK s.

SELECTION-SCREEN BEGIN OF BLOCK b WITH FRAME TITLE TEXT-004.
SELECTION-SCREEN COMMENT /1(75) TEXT-005 MODIF ID bch.
SELECTION-SCREEN COMMENT /1(75) TEXT-006 MODIF ID bch.
PARAMETERS p_b1 TYPE text255 LOWER CASE MODIF ID bch.
PARAMETERS p_b2 TYPE text255 LOWER CASE MODIF ID bch.
PARAMETERS p_b3 TYPE text255 LOWER CASE MODIF ID bch.
PARAMETERS p_b4 TYPE text255 LOWER CASE MODIF ID bch.
PARAMETERS p_b5 TYPE text255 LOWER CASE MODIF ID bch.
PARAMETERS p_b6 TYPE text255 LOWER CASE MODIF ID bch.
PARAMETERS p_b7 TYPE text255 LOWER CASE MODIF ID bch.
PARAMETERS p_b8 TYPE text255 LOWER CASE MODIF ID bch.
SELECTION-SCREEN END OF BLOCK b.

SELECTION-SCREEN BEGIN OF BLOCK o WITH FRAME TITLE TEXT-007.
PARAMETERS:
  p_pack TYPE devclass,
  p_tr   TYPE trkorr.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_actv AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN COMMENT 3(40) c_actv FOR FIELD p_actv.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_dry AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN COMMENT 3(40) c_dry FOR FIELD p_dry.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK o.

INITIALIZATION.
  c_ensur = 'Ensure (create/update)'(010).
  c_act   = 'Activate only'(011).
  c_deact = 'Deactivate only'(012).
  c_stat  = 'Show status'(013).
  c_sing  = 'Single service'(014).
  c_batch = 'Batch (multi-project)'(015).
  c_actv  = 'Activate after save'(016).
  c_dry   = 'Dry-run (no changes)'(017).

  " Apply defaults from ZEVO_SICF_SETUP_CFG when set
  IF gc_sicf_cfg_url IS NOT INITIAL.
    p_url = gc_sicf_cfg_url.
  ENDIF.
  IF gc_sicf_cfg_hand IS NOT INITIAL.
    p_hand = gc_sicf_cfg_hand.
  ENDIF.
  IF gc_sicf_cfg_desc IS NOT INITIAL.
    p_desc = gc_sicf_cfg_desc.
  ENDIF.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-group1 = 'SNG'.
      IF p_single = abap_true.
        screen-active = '1'.
      ELSE.
        screen-active = '0'.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
    IF screen-group1 = 'BCH'.
      IF p_batch = abap_true.
        screen-active = '1'.
      ELSE.
        screen-active = '0'.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

START-OF-SELECTION.
  PERFORM run.

*&---------------------------------------------------------------------*
FORM run.
  DATA: lt_defs TYPE zevo_cl_sicf_setup=>ty_service_defs,
        ls_def  TYPE zevo_cl_sicf_setup=>ty_service_def,
        ls_h    TYPE zevo_cl_sicf_setup=>ty_handler,
        ls_res  TYPE zevo_cl_sicf_setup=>ty_result,
        ls_st   TYPE zevo_cl_sicf_setup=>ty_status,
        lt_line TYPE string_table,
        lv_ok   TYPE i,
        lv_fail TYPE i.

  IF p_batch = abap_true.
    PERFORM collect_batch CHANGING lt_line.
    lt_defs = zevo_cl_sicf_setup=>parse_batch( lt_line ).
    IF lt_defs IS INITIAL.
      MESSAGE 'No valid batch lines (URL;HANDLER[;…]).' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ELSE.
    IF p_url IS INITIAL OR p_hand IS INITIAL.
      MESSAGE 'Enter ICF URL path and handler class (or set ZEVO_SICF_SETUP_CFG).'
              TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    CLEAR ls_def.
    ls_def-url         = p_url.
    ls_def-description = p_desc.
    ls_def-activate    = boolc( p_actv = abap_true ).
    CLEAR ls_h.
    ls_h-classname = p_hand.
    APPEND ls_h TO ls_def-handlers.
    APPEND ls_def TO lt_defs.
  ENDIF.

  CASE abap_true.
    WHEN p_stat.
      LOOP AT lt_defs INTO ls_def.
        ls_st = zevo_cl_sicf_setup=>get_status( ls_def-url ).
        WRITE: / ls_st-url,
                 | exists={ ls_st-exists } active={ ls_st-active }|,
                 | handlers={ ls_st-handlers }|,
                 | { ls_st-description }|.
        IF ls_st-exists = abap_true.
          ADD 1 TO lv_ok.
        ELSE.
          ADD 1 TO lv_fail.
        ENDIF.
      ENDLOOP.

    WHEN p_act.
      LOOP AT lt_defs INTO ls_def.
        ls_res = zevo_cl_sicf_setup=>activate(
                   iv_url     = ls_def-url
                   iv_dry_run = boolc( p_dry = abap_true ) ).
        PERFORM write_result USING ls_res CHANGING lv_ok lv_fail.
      ENDLOOP.

    WHEN p_deact.
      LOOP AT lt_defs INTO ls_def.
        ls_res = zevo_cl_sicf_setup=>deactivate(
                   iv_url     = ls_def-url
                   iv_dry_run = boolc( p_dry = abap_true ) ).
        PERFORM write_result USING ls_res CHANGING lv_ok lv_fail.
      ENDLOOP.

    WHEN OTHERS. " ensure
      LOOP AT lt_defs INTO ls_def.
        ls_def-activate  = boolc( p_actv = abap_true ).
        ls_def-package   = p_pack.
        ls_def-transport = p_tr.
        ls_res = zevo_cl_sicf_setup=>ensure(
                   is_def     = ls_def
                   iv_dry_run = boolc( p_dry = abap_true ) ).
        PERFORM write_result USING ls_res CHANGING lv_ok lv_fail.
      ENDLOOP.
  ENDCASE.

  SKIP.
  WRITE: / |Done. ok={ lv_ok }, failed={ lv_fail }.|.
  IF p_dry = abap_true.
    WRITE: / 'Dry-run only — no changes were written.'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM collect_batch CHANGING ct_line TYPE string_table.
  CLEAR ct_line.
  IF p_b1 IS NOT INITIAL. APPEND p_b1 TO ct_line. ENDIF.
  IF p_b2 IS NOT INITIAL. APPEND p_b2 TO ct_line. ENDIF.
  IF p_b3 IS NOT INITIAL. APPEND p_b3 TO ct_line. ENDIF.
  IF p_b4 IS NOT INITIAL. APPEND p_b4 TO ct_line. ENDIF.
  IF p_b5 IS NOT INITIAL. APPEND p_b5 TO ct_line. ENDIF.
  IF p_b6 IS NOT INITIAL. APPEND p_b6 TO ct_line. ENDIF.
  IF p_b7 IS NOT INITIAL. APPEND p_b7 TO ct_line. ENDIF.
  IF p_b8 IS NOT INITIAL. APPEND p_b8 TO ct_line. ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM write_result USING    is_res  TYPE zevo_cl_sicf_setup=>ty_result
                  CHANGING cv_ok   TYPE i
                           cv_fail TYPE i.
  IF is_res-ok = abap_true.
    WRITE: / 'OK  ', is_res-url, is_res-message.
    ADD 1 TO cv_ok.
  ELSE.
    WRITE: / 'FAIL', is_res-url, is_res-message COLOR COL_NEGATIVE.
    ADD 1 TO cv_fail.
  ENDIF.
ENDFORM.
