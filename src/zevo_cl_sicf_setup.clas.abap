*&---------------------------------------------------------------------*
*& Class ZEVO_CL_SICF_SETUP
*&---------------------------------------------------------------------*
*& Generic ICF / SICF administrator — standalone tool.
*&
*& Call from report ZEVO_SICF_SETUP, or from any project post-install:
*&   DATA(ls) = zevo_cl_sicf_setup=>ensure( is_def = … ).
*&
*& Configure defaults via include ZEVO_SICF_SETUP_CFG (not product code).
*& SICF is not covered by abapGit; this class closes that gap.
*& Requires S_ICF_ADM plus S_ADMI_FCD value NADM: the ICF API checks
*& NADM even though transaction SICF does not.
*&
*& Uses the released SAP APIs:
*&   CL_ICF_TREE=>IF_ICF_TREE~SERVICE_FROM_URL   locate node from a path
*&   CL_ICF_TREE=>IF_ICF_TREE~GET_INFO_FROM_SERV read node settings
*&   CL_ICF_TREE=>IF_ICF_TREE~INSERT_NODE        create node
*&   CL_ICF_TREE=>IF_ICF_TREE~CHANGE_NODE        update node
*&   HTTP_ACTIVATE_NODE / HTTP_INACTIVATE_NODE   activation state
*&---------------------------------------------------------------------*
CLASS zevo_cl_sicf_setup DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! ICFNAME is CHAR15, so a single path segment cannot be longer
    CONSTANTS gc_max_name_len TYPE i VALUE 15.

    TYPES: BEGIN OF ty_handler,
             classname TYPE seoclsname,
           END OF ty_handler.
    TYPES ty_handlers TYPE STANDARD TABLE OF ty_handler WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_service_def,
             url         TYPE string,
             description TYPE string,
             handlers    TYPE ty_handlers,
             activate    TYPE abap_bool,
             package     TYPE devclass,
             transport   TYPE trkorr,
           END OF ty_service_def.
    TYPES ty_service_defs TYPE STANDARD TABLE OF ty_service_def WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_status,
             url         TYPE string,
             exists      TYPE abap_bool,
             active      TYPE abap_bool,
             description TYPE string,
             handlers    TYPE string,
             message     TYPE string,
           END OF ty_status.

    TYPES: BEGIN OF ty_result,
             ok      TYPE abap_bool,
             created TYPE abap_bool,
             updated TYPE abap_bool,
             url     TYPE string,
             message TYPE string,
           END OF ty_result.

    CLASS-METHODS ensure
      IMPORTING
        is_def           TYPE ty_service_def
        iv_dry_run       TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(rs_result) TYPE ty_result.

    CLASS-METHODS activate
      IMPORTING
        iv_url           TYPE clike
        iv_dry_run       TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(rs_result) TYPE ty_result.

    CLASS-METHODS deactivate
      IMPORTING
        iv_url           TYPE clike
        iv_dry_run       TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(rs_result) TYPE ty_result.

    CLASS-METHODS get_status
      IMPORTING
        iv_url           TYPE clike
      RETURNING
        VALUE(rs_status) TYPE ty_status.

    "! Batch format per line: URL;HANDLER[;HANDLER…][;description]
    CLASS-METHODS parse_batch
      IMPORTING
        it_lines       TYPE string_table
      RETURNING
        VALUE(rt_defs) TYPE ty_service_defs.

    CLASS-METHODS normalize_url
      IMPORTING
        iv_url        TYPE clike
      RETURNING
        VALUE(rv_url) TYPE string.

    "! Report what the tool resolves and which authorizations it holds,
    "! for cases where the API refuses without leaving an SU53 record.
    CLASS-METHODS diagnose
      IMPORTING
        is_def       TYPE ty_service_def
      RETURNING
        VALUE(rt_log) TYPE string_table.

  PRIVATE SECTION.
    CONSTANTS gc_msg_probe TYPE c LENGTH 20 VALUE 'ZEVO_SICF_NO_MESSAGE'.

    TYPES ty_icfhandlers TYPE STANDARD TABLE OF icfhandler WITH DEFAULT KEY.

    "! SERVICE_FROM_URL returns the deepest node that exists on the path.
    "! ev_suffix holds the part of the path that does not exist yet, so
    "! ev_guid doubles as "the node" and "the parent of a missing node".
    CLASS-METHODS resolve
      IMPORTING
        iv_url     TYPE clike
      EXPORTING
        ev_guid    TYPE icfnodguid
        ev_exists  TYPE abap_bool
        ev_active  TYPE abap_bool
        ev_suffix  TYPE string
        ev_ok      TYPE abap_bool
        ev_message TYPE string.

    CLASS-METHODS read_node
      IMPORTING
        iv_guid     TYPE icfnodguid
      EXPORTING
        es_service  TYPE icfservice
        es_docu     TYPE icfdocu
        et_handlers TYPE ty_icfhandlers
        ev_ok       TYPE abap_bool
        ev_message  TYPE string.

    CLASS-METHODS create_node
      IMPORTING
        is_def         TYPE ty_service_def
        iv_parent_guid TYPE icfnodguid
        iv_name        TYPE icfname
        it_handlers    TYPE icfhndlist
        iv_description TYPE clike
      EXPORTING
        ev_guid        TYPE icfnodguid
        ev_ok          TYPE abap_bool
        ev_message     TYPE string.

    CLASS-METHODS update_node
      IMPORTING
        is_def         TYPE ty_service_def
        iv_guid        TYPE icfnodguid
        it_handlers    TYPE icfhndlist
        iv_description TYPE clike
        iv_active      TYPE abap_bool
      EXPORTING
        ev_ok          TYPE abap_bool
        ev_message     TYPE string.

    CLASS-METHODS set_active
      IMPORTING
        iv_guid    TYPE icfnodguid
        iv_active  TYPE abap_bool
      EXPORTING
        ev_ok      TYPE abap_bool
        ev_message TYPE string.

    CLASS-METHODS split_url
      IMPORTING
        iv_url     TYPE clike
      EXPORTING
        ev_parent  TYPE string
        ev_name    TYPE icfname
        ev_ok      TYPE abap_bool
        ev_message TYPE string.

    CLASS-METHODS build_handler_list
      IMPORTING
        it_handlers   TYPE ty_handlers
      RETURNING
        VALUE(rt_list) TYPE icfhndlist.

    "! SICF expects the description at the start of the ICFDOCU structure
    CLASS-METHODS build_docu
      IMPORTING
        iv_text        TYPE clike
      RETURNING
        VALUE(rs_docu) TYPE icfdocu.

    CLASS-METHODS segment_count
      IMPORTING
        iv_path         TYPE clike
      RETURNING
        VALUE(rv_count) TYPE i.

    "! A classic exception only fills SY-MSG* when it was raised with
    "! MESSAGE ... RAISING. Plain RAISE leaves the previous message in the
    "! buffer, so stamp a known one first and treat it as "API said nothing".
    CLASS-METHODS msg_probe.

    CLASS-METHODS api_message
      RETURNING
        VALUE(rv_text) TYPE string.

    "! Package a node under iv_guid would inherit when none is given
    CLASS-METHODS node_package
      IMPORTING
        iv_guid            TYPE icfnodguid
      RETURNING
        VALUE(rv_devclass) TYPE devclass.

    CLASS-METHODS check_icf_auth
      IMPORTING
        iv_guid         TYPE icfnodguid
        iv_actvt        TYPE clike
      RETURNING
        VALUE(rv_subrc) TYPE sysubrc.

    CLASS-METHODS check_develop_auth
      IMPORTING
        iv_devclass     TYPE devclass
        iv_actvt        TYPE clike
      RETURNING
        VALUE(rv_subrc) TYPE sysubrc.

    "! The HTTPTREE layer under INSERT_NODE guards itself with S_ADMI_FCD
    "! value NADM, which transaction SICF itself does not need.
    CLASS-METHODS check_admi_fcd
      IMPORTING
        iv_value        TYPE clike
      RETURNING
        VALUE(rv_subrc) TYPE sysubrc.

    CLASS-METHODS auth_text
      IMPORTING
        iv_subrc       TYPE sysubrc
      RETURNING
        VALUE(rv_text) TYPE string.

    "! An ICF node is a cross-client repository object, so the client
    "! setting (SCC4) can forbid it no matter what the role allows.
    CLASS-METHODS client_change_text
      RETURNING
        VALUE(rv_text) TYPE string.

    "! Name the object that refuses, so a NO_AUTHORITY exception is
    "! actionable even when the check left no SU53 record.
    CLASS-METHODS auth_hint
      IMPORTING
        iv_guid        TYPE icfnodguid
        iv_actvt       TYPE clike
        iv_package     TYPE devclass
      RETURNING
        VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zevo_cl_sicf_setup IMPLEMENTATION.

  METHOD normalize_url.
    DATA: lv     TYPE string,
          lv_len TYPE i,
          lv_low TYPE string,
          lv_off TYPE i.

    lv = iv_url.
    CONDENSE lv.
    REPLACE ALL OCCURRENCES OF '\' IN lv WITH '/'.
    IF lv IS INITIAL.
      rv_url = lv.
      RETURN.
    ENDIF.
    IF lv(1) <> '/'.
      CONCATENATE '/' lv INTO lv.
    ENDIF.

    lv_len = strlen( lv ).
    WHILE lv_len > 1.
      lv_off = lv_len - 1.
      IF lv+lv_off(1) <> '/'.
        EXIT.
      ENDIF.
      lv_len = lv_len - 1.
      lv     = lv(lv_len).
    ENDWHILE.

    lv_low = lv.
    TRANSLATE lv_low TO LOWER CASE.
    IF strlen( lv_low ) >= 13 AND lv_low(13) = '/default_host'.
      lv = lv+13.
      IF lv IS INITIAL.
        lv = '/'.
      ELSEIF lv(1) <> '/'.
        CONCATENATE '/' lv INTO lv.
      ENDIF.
    ENDIF.

    rv_url = lv.
  ENDMETHOD.


  METHOD segment_count.
    DATA: lv_path TYPE string,
          lt_part TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    lv_path = iv_path.
    SPLIT lv_path AT '/' INTO TABLE lt_part.
    DELETE lt_part WHERE table_line IS INITIAL.
    rv_count = lines( lt_part ).
  ENDMETHOD.


  METHOD msg_probe.
    DATA lv_dummy TYPE string.

    " 00 398 is the generic '&1&2&3&4' message, present in every system
    MESSAGE ID '00' TYPE 'S' NUMBER '398'
            WITH gc_msg_probe space space space
            INTO lv_dummy.
  ENDMETHOD.


  METHOD api_message.
    IF sy-msgid IS INITIAL OR sy-msgno IS INITIAL.
      CLEAR rv_text.
      RETURN.
    ENDIF.
    IF sy-msgid = '00' AND sy-msgno = '398' AND sy-msgv1 = gc_msg_probe.
      " The API raised its exception without a message of its own
      CLEAR rv_text.
      RETURN.
    ENDIF.
    MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
            INTO rv_text.
  ENDMETHOD.


  METHOD node_package.
    DATA: lv_name    TYPE icfname,
          lv_parguid TYPE icfparguid,
          lv_obj     TYPE tadir-obj_name.

    CLEAR rv_devclass.
    SELECT SINGLE icf_name icfparguid FROM icfservice
           INTO (lv_name, lv_parguid)
           WHERE icfnodguid = iv_guid.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " SICF objects are keyed in TADIR as ICF_NAME(15) + ICFPARGUID(25)
    lv_obj(15)   = lv_name.
    lv_obj+15(25) = lv_parguid.

    SELECT SINGLE devclass FROM tadir INTO rv_devclass
           WHERE pgmid = 'R3TR' AND object = 'SICF' AND obj_name = lv_obj.
    IF sy-subrc <> 0.
      CLEAR rv_devclass.
    ENDIF.
  ENDMETHOD.


  METHOD check_icf_auth.
    DATA lv_actvt TYPE char2.

    lv_actvt = iv_actvt.
    AUTHORITY-CHECK OBJECT 'S_ICF_ADM'
      ID 'ACTVT'    FIELD lv_actvt
      ID 'ICF_HOST' DUMMY
      ID 'ICF_NODE' FIELD iv_guid
      ID 'ICF_TYPE' DUMMY.
    rv_subrc = sy-subrc.
  ENDMETHOD.


  METHOD check_develop_auth.
    DATA lv_actvt TYPE char2.

    lv_actvt = iv_actvt.
    AUTHORITY-CHECK OBJECT 'S_DEVELOP'
      ID 'DEVCLASS' FIELD iv_devclass
      ID 'OBJTYPE'  FIELD 'SICF'
      ID 'OBJNAME'  DUMMY
      ID 'P_GROUP'  DUMMY
      ID 'ACTVT'    FIELD lv_actvt.
    rv_subrc = sy-subrc.
  ENDMETHOD.


  METHOD check_admi_fcd.
    DATA lv_value TYPE char4.

    lv_value = iv_value.
    AUTHORITY-CHECK OBJECT 'S_ADMI_FCD'
      ID 'S_ADMI_FCD' FIELD lv_value.
    rv_subrc = sy-subrc.
  ENDMETHOD.


  METHOD auth_text.
    DATA lv_reason TYPE string.

    CASE iv_subrc.
      WHEN 0.
        lv_reason = 'granted'.
      WHEN 4.
        lv_reason = 'refused, authorization exists but not for these values'.
      WHEN 12.
        lv_reason = 'refused, no authorization for this object at all'.
      WHEN OTHERS.
        lv_reason = 'refused'.
    ENDCASE.
    rv_text = |subrc { iv_subrc } - { lv_reason }|.
  ENDMETHOD.


  METHOD client_change_text.
    DATA lv_flag TYPE t000-ccnocliind.

    SELECT SINGLE ccnocliind FROM t000 CLIENT SPECIFIED
           INTO lv_flag
           WHERE mandt = sy-mandt.
    IF sy-subrc <> 0.
      rv_text = 'client setting not readable'.
      RETURN.
    ENDIF.

    CASE lv_flag.
      WHEN space.
        rv_text = 'changes to repository and cross-client objects allowed'.
      WHEN '1'.
        rv_text = 'no changes to cross-client customizing (repository still allowed)'.
      WHEN '2'.
        rv_text = 'NO CHANGES TO REPOSITORY OBJECTS - this blocks ICF nodes'.
      WHEN '3'.
        rv_text = 'NO CHANGES TO REPOSITORY OR CROSS-CLIENT OBJECTS - this blocks ICF nodes'.
      WHEN OTHERS.
        rv_text = |CCNOCLIIND = '{ lv_flag }'|.
    ENDCASE.
  ENDMETHOD.


  METHOD auth_hint.
    DATA: lv_subrc   TYPE sysubrc,
          lv_pkg     TYPE devclass,
          lv_dev_act TYPE char2.

    lv_subrc = check_admi_fcd( 'NADM' ).
    IF lv_subrc <> 0.
      rv_text = 'You are missing S_ADMI_FCD value NADM (network administration).'
             && ' The ICF API checks it, transaction SICF does not, which is why'
             && ' the same node can be created by hand.'.
      RETURN.
    ENDIF.

    lv_subrc = check_icf_auth( iv_guid = iv_guid iv_actvt = iv_actvt ).
    IF lv_subrc <> 0.
      rv_text = |You are missing S_ICF_ADM ACTVT { iv_actvt } for ICF_NODE { iv_guid }.|.
      RETURN.
    ENDIF.

    lv_pkg = iv_package.
    IF lv_pkg IS INITIAL.
      lv_pkg = node_package( iv_guid ).
    ENDIF.
    IF iv_actvt = '01'.
      lv_dev_act = '01'.
    ELSE.
      lv_dev_act = '02'.
    ENDIF.
    IF lv_pkg IS NOT INITIAL.
      lv_subrc = check_develop_auth( iv_devclass = lv_pkg iv_actvt = lv_dev_act ).
      IF lv_subrc <> 0.
        rv_text = |You are missing S_DEVELOP ACTVT { lv_dev_act } for OBJTYPE SICF |
               && |in package { lv_pkg }.|.
        RETURN.
      ENDIF.
    ENDIF.

    rv_text = 'S_ADMI_FCD NADM, S_ICF_ADM and S_DEVELOP are all granted, so this is'
           && ' not your role and no role change will fix it.'.
    IF iv_actvt = '01' AND iv_package IS INITIAL AND lv_pkg IS NOT INITIAL.
      rv_text = |{ rv_text } Package is blank, so the node lands in the parent package |
             && |{ lv_pkg }; set Package to $TMP or a Z package and retry first.|.
    ENDIF.
    rv_text = rv_text
           && ' Then confirm your profile is active in this session (SU56, or log on'
           && ' again if it was assigned recently), and record STAUTHTRACE while'
           && ' running this report to see the check the API itself makes.'.
  ENDMETHOD.


  METHOD diagnose.
    DATA: lv_url        TYPE string,
          lv_parent     TYPE string,
          lv_name       TYPE icfname,
          lv_guid       TYPE icfnodguid,
          lv_exists     TYPE abap_bool,
          lv_active     TYPE abap_bool,
          lv_suffix     TYPE string,
          lv_ok         TYPE abap_bool,
          lv_msg        TYPE string,
          lv_parent_pkg TYPE devclass,
          lv_eff_pkg    TYPE devclass,
          ls_h          TYPE ty_handler,
          lv_hand       TYPE string,
          lv_len        TYPE i,
          lv_subrc      TYPE sysubrc,
          lv_auth       TYPE string,
          lv_txt        TYPE string,
          lv_line       TYPE string.

    lv_line = '--- ZEVO_SICF_SETUP diagnosis ---'.
    APPEND lv_line TO rt_log.
    lv_line = |User / client      : { sy-uname } / { sy-mandt }|.
    APPEND lv_line TO rt_log.
    lv_line = |Input URL          : { is_def-url }|.
    APPEND lv_line TO rt_log.

    lv_url  = normalize_url( is_def-url ).
    lv_line = |Normalized URL     : { lv_url }|.
    APPEND lv_line TO rt_log.

    split_url(
      EXPORTING iv_url     = lv_url
      IMPORTING ev_parent  = lv_parent
                ev_name    = lv_name
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      lv_line = |Path               : REJECTED - { lv_msg }|.
      APPEND lv_line TO rt_log.
      RETURN.
    ENDIF.
    lv_len  = strlen( lv_name ).
    lv_line = |Node name          : { lv_name } ({ lv_len } of { gc_max_name_len } chars)|.
    APPEND lv_line TO rt_log.
    lv_line = |Parent path        : { lv_parent }|.
    APPEND lv_line TO rt_log.

    LOOP AT is_def-handlers INTO ls_h.
      IF lv_hand IS INITIAL.
        lv_hand = ls_h-classname.
      ELSE.
        CONCATENATE lv_hand ls_h-classname INTO lv_hand SEPARATED BY space.
      ENDIF.
    ENDLOOP.
    lv_line = |Handlers           : { lv_hand }|.
    APPEND lv_line TO rt_log.

    resolve(
      EXPORTING iv_url     = lv_url
      IMPORTING ev_guid    = lv_guid
                ev_exists  = lv_exists
                ev_active  = lv_active
                ev_suffix  = lv_suffix
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      lv_line = |Resolve            : FAILED - { lv_msg }|.
      APPEND lv_line TO rt_log.
      RETURN.
    ENDIF.

    IF lv_exists = abap_true.
      lv_line = |Node               : exists, active={ lv_active }|.
      APPEND lv_line TO rt_log.
      lv_line = |Node GUID          : { lv_guid }|.
    ELSE.
      lv_line = |Node               : does not exist yet (missing '{ lv_suffix }')|.
      APPEND lv_line TO rt_log.
      lv_line = |Parent GUID        : { lv_guid }|.
    ENDIF.
    APPEND lv_line TO rt_log.

    lv_parent_pkg = node_package( lv_guid ).
    IF lv_parent_pkg IS INITIAL.
      lv_line = 'Parent package     : not found in TADIR'.
    ELSE.
      lv_line = |Parent package     : { lv_parent_pkg }|.
      IF lv_parent_pkg(1) <> 'Z' AND lv_parent_pkg(1) <> 'Y' AND lv_parent_pkg(1) <> '$'.
        lv_line = |{ lv_line } (SAP-owned: creating here modifies SAP standard)|.
      ENDIF.
    ENDIF.
    APPEND lv_line TO rt_log.

    IF is_def-package IS INITIAL.
      lv_eff_pkg = lv_parent_pkg.
      lv_line    = |Package requested  : blank, so parent package '{ lv_parent_pkg }' is used|.
    ELSE.
      lv_eff_pkg = is_def-package.
      lv_line    = |Package requested  : { is_def-package }|.
    ENDIF.
    APPEND lv_line TO rt_log.

    IF is_def-transport IS INITIAL.
      lv_line = 'Transport request   : blank, SAP prompts if it needs one'.
    ELSE.
      lv_line = |Transport request  : { is_def-transport }|.
    ENDIF.
    APPEND lv_line TO rt_log.

    lv_txt  = client_change_text( ).
    lv_line = |Client change opt. : { lv_txt }|.
    APPEND lv_line TO rt_log.

    lv_subrc = check_admi_fcd( 'NADM' ).
    lv_auth  = auth_text( lv_subrc ).
    lv_line  = |S_ADMI_FCD NADM    : { lv_auth }|.
    APPEND lv_line TO rt_log.
    IF lv_subrc <> 0.
      lv_line = '  ^ this is the one SICF does not need but the ICF API does.'.
      APPEND lv_line TO rt_log.
    ENDIF.

    lv_subrc = check_icf_auth( iv_guid = lv_guid iv_actvt = '01' ).
    lv_auth  = auth_text( lv_subrc ).
    lv_line  = |S_ICF_ADM create   : { lv_auth }|.
    APPEND lv_line TO rt_log.

    lv_subrc = check_icf_auth( iv_guid = lv_guid iv_actvt = '02' ).
    lv_auth  = auth_text( lv_subrc ).
    lv_line  = |S_ICF_ADM change   : { lv_auth }|.
    APPEND lv_line TO rt_log.

    lv_subrc = check_icf_auth( iv_guid = lv_guid iv_actvt = '07' ).
    lv_auth  = auth_text( lv_subrc ).
    lv_line  = |S_ICF_ADM activate : { lv_auth }|.
    APPEND lv_line TO rt_log.

    IF lv_eff_pkg IS INITIAL.
      lv_line = 'S_DEVELOP SICF     : not checked, package unknown'.
    ELSE.
      lv_subrc = check_develop_auth( iv_devclass = lv_eff_pkg iv_actvt = '01' ).
      lv_auth  = auth_text( lv_subrc ).
      lv_line  = |S_DEVELOP SICF     : { lv_auth } on '{ lv_eff_pkg }'|.
    ENDIF.
    APPEND lv_line TO rt_log.

    lv_line = 'Read the refused line above: S_ADMI_FCD NADM means ask for that value in your role,'.
    APPEND lv_line TO rt_log.
    lv_line = 'S_DEVELOP alone means set Package, S_ICF_ADM means you lack ICF rights on this path.'.
    APPEND lv_line TO rt_log.
    lv_line = 'All granted but the call still refuses: it is not your role. Check the client option'.
    APPEND lv_line TO rt_log.
    lv_line = 'above and SU56, then record STAUTHTRACE to see the check the API itself makes.'.
    APPEND lv_line TO rt_log.
  ENDMETHOD.


  METHOD split_url.
    DATA: lv_url  TYPE string,
          lt_part TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
          lv_part TYPE string,
          lv_last TYPE string,
          lv_cnt  TYPE i.

    CLEAR: ev_parent, ev_name, ev_message.
    ev_ok = abap_false.

    lv_url = normalize_url( iv_url ).
    IF lv_url IS INITIAL OR lv_url = '/'.
      ev_message = 'URL is empty.'.
      RETURN.
    ENDIF.

    SPLIT lv_url AT '/' INTO TABLE lt_part.
    DELETE lt_part WHERE table_line IS INITIAL.
    lv_cnt = lines( lt_part ).
    IF lv_cnt < 2.
      ev_message = |URL '{ lv_url }' is too short — need at least /sap/<service>|.
      RETURN.
    ENDIF.

    READ TABLE lt_part INTO lv_last INDEX lv_cnt.
    IF strlen( lv_last ) > gc_max_name_len.
      ev_message = |Node name '{ lv_last }' is longer than { gc_max_name_len } characters (SICF ICFNAME).|.
      RETURN.
    ENDIF.
    " Keep the case as typed: ICF node names are conventionally lower case
    ev_name = lv_last.
    DELETE lt_part INDEX lv_cnt.

    CLEAR ev_parent.
    LOOP AT lt_part INTO lv_part.
      CONCATENATE ev_parent '/' lv_part INTO ev_parent.
    ENDLOOP.
    IF ev_parent IS INITIAL.
      ev_parent = '/'.
    ENDIF.
    ev_ok = abap_true.
  ENDMETHOD.


  METHOD build_handler_list.
    DATA: ls_in  TYPE ty_handler,
          lv_cls TYPE icfhandler-icfhandler.

    CLEAR rt_list.
    LOOP AT it_handlers INTO ls_in WHERE classname IS NOT INITIAL.
      lv_cls = ls_in-classname.
      TRANSLATE lv_cls TO UPPER CASE.
      READ TABLE rt_list FROM lv_cls TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        INSERT lv_cls INTO TABLE rt_list.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_docu.
    DATA ls_full TYPE icfdocu.

    ls_full-icf_docu = iv_text.
    rs_docu = ls_full-icf_docu.
  ENDMETHOD.


  METHOD resolve.
    DATA: lv_url    TYPE string,
          lv_guid   TYPE icfnodguid,
          lv_active TYPE icfactive,
          lv_suffix TYPE icfredurl,
          lv_subrc  TYPE sysubrc,
          lv_api    TYPE string.

    CLEAR: ev_guid, ev_exists, ev_active, ev_suffix, ev_message.
    ev_ok = abap_false.

    lv_url = normalize_url( iv_url ).
    IF lv_url IS INITIAL.
      ev_message = 'URL is empty.'.
      RETURN.
    ENDIF.

    msg_probe( ).
    cl_icf_tree=>if_icf_tree~service_from_url(
      EXPORTING
        url                   = lv_url
        hostnumber            = 0
      IMPORTING
        icfnodguid            = lv_guid
        icfactive             = lv_active
        urlsuffix             = lv_suffix
      EXCEPTIONS
        wrong_application     = 1
        no_application        = 2
        not_allow_application = 3
        wrong_url             = 4
        no_authority          = 5
        OTHERS                = 6 ).
    lv_subrc = sy-subrc.
    lv_api   = api_message( ).

    CASE lv_subrc.
      WHEN 0.
        ev_ok = abap_true.
      WHEN 4.
        ev_message = |SICF rejected the path '{ lv_url }' (wrong URL).|.
        RETURN.
      WHEN 5.
        ev_message = 'No authorization to read the ICF tree: need S_ICF_ADM ACTVT 03.'.
        RETURN.
      WHEN OTHERS.
        IF lv_api IS INITIAL.
          ev_message = |Cannot read ICF tree (SERVICE_FROM_URL subrc { lv_subrc }).|.
        ELSE.
          ev_message = |Cannot read ICF tree: { lv_api } (subrc { lv_subrc }).|.
        ENDIF.
        RETURN.
    ENDCASE.

    ev_guid   = lv_guid.
    ev_active = boolc( lv_active = abap_true ).
    ev_suffix = lv_suffix.
    ev_exists = boolc( lv_suffix IS INITIAL AND lv_guid IS NOT INITIAL ).
  ENDMETHOD.


  METHOD read_node.
    DATA: lv_name    TYPE icfname,
          lv_parguid TYPE icfparguid,
          lt_serv    TYPE icfservtbl,
          lv_url     TYPE string,
          lv_subrc   TYPE sysubrc,
          lv_api     TYPE string.
    DATA ls_serv LIKE LINE OF lt_serv.

    CLEAR: es_service, es_docu, et_handlers, ev_message.
    ev_ok = abap_false.

    SELECT SINGLE icf_name icfparguid FROM icfservice
           INTO (lv_name, lv_parguid)
           WHERE icfnodguid = iv_guid.
    IF sy-subrc <> 0.
      ev_message = 'ICF node not found in ICFSERVICE.'.
      RETURN.
    ENDIF.

    msg_probe( ).
    cl_icf_tree=>if_icf_tree~get_info_from_serv(
      EXPORTING
        icf_name          = lv_name
        icfparguid        = lv_parguid
        icf_langu         = sy-langu
      IMPORTING
        serv_info         = lt_serv
        icfdocu           = es_docu
        url               = lv_url
      EXCEPTIONS
        wrong_name        = 1
        wrong_parguid     = 2
        incorrect_service = 3
        no_authority      = 4
        OTHERS            = 5 ).
    lv_subrc = sy-subrc.
    lv_api   = api_message( ).
    IF lv_subrc <> 0.
      IF lv_api IS INITIAL.
        ev_message = |Cannot read ICF node (GET_INFO_FROM_SERV subrc { lv_subrc }).|.
      ELSE.
        ev_message = |Cannot read ICF node: { lv_api } (subrc { lv_subrc }).|.
      ENDIF.
      RETURN.
    ENDIF.

    READ TABLE lt_serv INTO ls_serv INDEX 1.
    IF sy-subrc <> 0.
      ev_message = 'ICF node returned no service data.'.
      RETURN.
    ENDIF.

    MOVE-CORRESPONDING ls_serv-service TO es_service.
    APPEND LINES OF ls_serv-handlertbl TO et_handlers.
    ev_ok = abap_true.
  ENDMETHOD.


  METHOD create_node.
    DATA: ls_serdesc   TYPE icfserdesc,
          ls_docu      TYPE icfdocu,
          lv_transport TYPE trkorr,
          lv_active    TYPE icfactive,
          lv_desc      TYPE string,
          lv_subrc     TYPE sysubrc,
          lv_api       TYPE string,
          lv_hint      TYPE string,
          lv_parent    TYPE icfparguid.

    " Copy before clearing the exporting parameters: a caller that passes one
    " variable for both iv_parent_guid and ev_guid would otherwise lose it,
    " and INSERT_NODE reads an empty parent as "create a virtual host"
    lv_parent = iv_parent_guid.

    CLEAR: ev_guid, ev_message.
    ev_ok = abap_false.

    IF lv_parent IS INITIAL.
      ev_message = 'Parent GUID is empty. Refusing to create a top-level node or virtual host.'.
      RETURN.
    ENDIF.

    lv_desc = iv_description.
    IF lv_desc IS INITIAL.
      lv_desc = iv_name.
    ENDIF.
    ls_docu      = build_docu( lv_desc ).
    lv_transport = is_def-transport.
    lv_active    = boolc( is_def-activate = abap_true ).

    msg_probe( ).
    cl_icf_tree=>if_icf_tree~insert_node(
      EXPORTING
        icf_name                  = iv_name
        icfparguid                = lv_parent
        icfdocu                   = ls_docu
        doculang                  = sy-langu
        icfhandlst                = it_handlers
        package                   = is_def-package
        application               = space
        icfserdesc                = ls_serdesc
        icfactive                 = lv_active
      IMPORTING
        icfnodguid                = ev_guid
      CHANGING
        transport                 = lv_transport
      EXCEPTIONS
        empty_icf_name            = 1
        no_new_virtual_host       = 2
        special_service_error     = 3
        parent_not_existing       = 4
        enqueue_error             = 5
        node_already_existing     = 6
        empty_docu                = 7
        doculang_not_installed    = 8
        security_info_error       = 9
        user_password_error       = 10
        password_encryption_error = 11
        invalid_url               = 12
        invalid_otr_concept       = 13
        formflg401_error          = 14
        handler_error             = 15
        transport_error           = 16
        tadir_error               = 17
        package_not_found         = 18
        wrong_application         = 19
        not_allow_application     = 20
        no_application            = 21
        invalid_icfparguid        = 22
        alt_name_invalid          = 23
        alternate_name_exist      = 24
        wrong_icf_name            = 25
        no_authority              = 26
        OTHERS                    = 27 ).
    lv_subrc = sy-subrc.
    lv_api   = api_message( ).

    CASE lv_subrc.
      WHEN 0.
        ev_ok = abap_true.
        RETURN.
      WHEN 15.
        ev_message = 'Handler class rejected — check that it exists and implements IF_HTTP_EXTENSION.'.
      WHEN 16 OR 17.
        ev_message = 'Transport check failed. Supply a request, or use a local package.'.
      WHEN 18.
        ev_message = |Package '{ is_def-package }' does not exist.|.
      WHEN 25.
        ev_message = |Node name '{ iv_name }' contains characters SICF does not allow.|.
      WHEN 26.
        lv_hint    = auth_hint( iv_guid    = lv_parent
                                iv_actvt   = '01'
                                iv_package = is_def-package ).
        ev_message = |No authorization to create. { lv_hint }|.
      WHEN OTHERS.
        ev_message = 'Cannot create ICF node.'.
    ENDCASE.

    ev_message = |{ ev_message } [INSERT_NODE subrc { lv_subrc }|.
    IF lv_api IS NOT INITIAL.
      ev_message = |{ ev_message }, SAP: { lv_api }|.
    ELSE.
      ev_message = |{ ev_message }, SAP left no message|.
    ENDIF.
    ev_message = |{ ev_message }, parent GUID { lv_parent }]|.
  ENDMETHOD.


  METHOD update_node.
    DATA: ls_service   TYPE icfservice,
          ls_docu_read TYPE icfdocu,
          lt_existing  TYPE ty_icfhandlers,
          ls_existing  TYPE icfhandler,
          lt_handlers  TYPE icfhndlist,
          ls_serdesc   TYPE icfserdesc,
          ls_docu      TYPE icfdocu,
          lv_transport TYPE trkorr,
          lv_active    TYPE icfactive,
          lv_desc      TYPE string,
          lv_ok        TYPE abap_bool,
          lv_msg       TYPE string,
          lv_subrc     TYPE sysubrc,
          lv_api       TYPE string,
          lv_hint      TYPE string.

    CLEAR ev_message.
    ev_ok = abap_false.

    read_node(
      EXPORTING iv_guid     = iv_guid
      IMPORTING es_service  = ls_service
                es_docu     = ls_docu_read
                et_handlers = lt_existing
                ev_ok       = lv_ok
                ev_message  = lv_msg ).
    IF lv_ok = abap_false.
      ev_message = lv_msg.
      RETURN.
    ENDIF.

    " Re-sending a handler that is already assigned makes CHANGE_NODE fail
    lt_handlers = it_handlers.
    LOOP AT lt_existing INTO ls_existing.
      DELETE TABLE lt_handlers FROM ls_existing-icfhandler.
    ENDLOOP.

    lv_desc = iv_description.
    IF lv_desc IS INITIAL.
      lv_desc = ls_docu_read-icf_docu.
    ENDIF.
    IF lv_desc IS INITIAL.
      lv_desc = ls_service-icf_name.
    ENDIF.

    MOVE-CORRESPONDING ls_service TO ls_serdesc.
    ls_docu      = build_docu( lv_desc ).
    lv_transport = is_def-transport.
    " The checkbox activates; it never deactivates a running service
    IF is_def-activate = abap_true OR iv_active = abap_true.
      lv_active = abap_true.
    ELSE.
      lv_active = space.
    ENDIF.

    msg_probe( ).
    cl_icf_tree=>if_icf_tree~change_node(
      EXPORTING
        icf_name                  = ls_service-icf_name
        icfaltnme                 = ls_service-icfaltnme
        icfparguid                = ls_service-icfparguid
        icfdocu                   = ls_docu
        doculang                  = sy-langu
        icfhandlst                = lt_handlers
        package                   = is_def-package
        application               = space
        icfserdesc                = ls_serdesc
        icfactive                 = lv_active
      CHANGING
        transport                 = lv_transport
      EXCEPTIONS
        empty_icf_name            = 1
        no_new_virtual_host       = 2
        special_service_error     = 3
        parent_not_existing       = 4
        enqueue_error             = 5
        node_already_existing     = 6
        empty_docu                = 7
        doculang_not_installed    = 8
        security_info_error       = 9
        user_password_error       = 10
        password_encryption_error = 11
        invalid_url               = 12
        invalid_otr_concept       = 13
        formflg401_error          = 14
        handler_error             = 15
        transport_error           = 16
        tadir_error               = 17
        package_not_found         = 18
        wrong_application         = 19
        not_allow_application     = 20
        no_application            = 21
        invalid_icfparguid        = 22
        alt_name_invalid          = 23
        alternate_name_exist      = 24
        wrong_icf_name            = 25
        no_authority              = 26
        OTHERS                    = 27 ).
    lv_subrc = sy-subrc.
    lv_api   = api_message( ).

    CASE lv_subrc.
      WHEN 0.
        ev_ok = abap_true.
        RETURN.
      WHEN 5.
        ev_message = 'ICF node is locked by another user (enqueue error).'.
      WHEN 15.
        ev_message = 'Handler class rejected — check that it exists and implements IF_HTTP_EXTENSION.'.
      WHEN 16 OR 17.
        ev_message = 'Transport check failed. Supply a request, or use a local package.'.
      WHEN 26.
        lv_hint    = auth_hint( iv_guid    = iv_guid
                                iv_actvt   = '02'
                                iv_package = is_def-package ).
        ev_message = |No authorization to change. { lv_hint }|.
      WHEN OTHERS.
        ev_message = 'Cannot update ICF node.'.
    ENDCASE.

    ev_message = |{ ev_message } [CHANGE_NODE subrc { lv_subrc }|.
    IF lv_api IS NOT INITIAL.
      ev_message = |{ ev_message }, SAP: { lv_api }|.
    ELSE.
      ev_message = |{ ev_message }, SAP left no message|.
    ENDIF.
    ev_message = |{ ev_message }, node GUID { iv_guid }]|.
  ENDMETHOD.


  METHOD set_active.
    DATA: lv_subrc TYPE sysubrc,
          lv_api   TYPE string,
          lv_hint  TYPE string.

    CLEAR ev_message.
    ev_ok = abap_false.

    msg_probe( ).
    IF iv_active = abap_true.
      CALL FUNCTION 'HTTP_ACTIVATE_NODE'
        EXPORTING
          nodeguid                 = iv_guid
          hostname                 = 'DEFAULT_HOST'
          expand                   = space
        EXCEPTIONS
          node_not_existing        = 1
          enqueue_error            = 2
          no_authority             = 3
          url_and_nodeguid_space   = 4
          url_and_nodeguid_fill_in = 5
          OTHERS                   = 6.
    ELSE.
      CALL FUNCTION 'HTTP_INACTIVATE_NODE'
        EXPORTING
          nodeguid                 = iv_guid
          hostname                 = 'DEFAULT_HOST'
          expand                   = space
          force_deactivation       = space
        EXCEPTIONS
          node_not_existing        = 1
          enqueue_error            = 2
          no_authority             = 3
          url_and_nodeguid_space   = 4
          url_and_nodeguid_fill_in = 5
          OTHERS                   = 6.
    ENDIF.

    lv_subrc = sy-subrc.
    lv_api   = api_message( ).

    CASE lv_subrc.
      WHEN 0.
        COMMIT WORK AND WAIT.
        ev_ok = abap_true.
        RETURN.
      WHEN 1.
        ev_message = 'ICF node does not exist.'.
      WHEN 2.
        ev_message = 'ICF node is locked by another user (enqueue error).'.
      WHEN 3.
        lv_hint    = auth_hint( iv_guid    = iv_guid
                                iv_actvt   = '07'
                                iv_package = space ).
        ev_message = |No authorization to activate. { lv_hint }|.
      WHEN OTHERS.
        ev_message = 'Activation call failed.'.
    ENDCASE.

    ev_message = |{ ev_message } [subrc { lv_subrc }|.
    IF lv_api IS NOT INITIAL.
      ev_message = |{ ev_message }, SAP: { lv_api }|.
    ELSE.
      ev_message = |{ ev_message }, SAP left no message|.
    ENDIF.
    ev_message = |{ ev_message }, node GUID { iv_guid }]|.
  ENDMETHOD.


  METHOD get_status.
    DATA: ls_docu     TYPE icfdocu,
          lt_handlers TYPE ty_icfhandlers,
          ls_handler  TYPE icfhandler,
          lv_guid     TYPE icfnodguid,
          lv_exists   TYPE abap_bool,
          lv_active   TYPE abap_bool,
          lv_suffix   TYPE string,
          lv_ok       TYPE abap_bool,
          lv_msg      TYPE string.

    CLEAR rs_status.
    rs_status-url = normalize_url( iv_url ).

    resolve(
      EXPORTING iv_url     = rs_status-url
      IMPORTING ev_guid    = lv_guid
                ev_exists  = lv_exists
                ev_active  = lv_active
                ev_suffix  = lv_suffix
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_status-message = lv_msg.
      RETURN.
    ENDIF.

    IF lv_exists = abap_false.
      rs_status-message = |Service not found. Missing path: '{ lv_suffix }'.|.
      RETURN.
    ENDIF.

    rs_status-exists = abap_true.
    rs_status-active = lv_active.

    read_node(
      EXPORTING iv_guid     = lv_guid
      IMPORTING es_docu     = ls_docu
                et_handlers = lt_handlers
                ev_ok       = lv_ok
                ev_message  = lv_msg ).
    IF lv_ok = abap_false.
      rs_status-message = lv_msg.
      RETURN.
    ENDIF.

    rs_status-description = ls_docu-icf_docu.

    SORT lt_handlers BY icforder.
    LOOP AT lt_handlers INTO ls_handler WHERE icfhandler IS NOT INITIAL.
      IF rs_status-handlers IS INITIAL.
        rs_status-handlers = ls_handler-icfhandler.
      ELSE.
        CONCATENATE rs_status-handlers ',' ls_handler-icfhandler
                    INTO rs_status-handlers SEPARATED BY space.
      ENDIF.
    ENDLOOP.

    rs_status-message = |OK (node GUID { lv_guid }).|.
  ENDMETHOD.


  METHOD ensure.
    DATA: lv_url      TYPE string,
          lv_parent   TYPE string,
          lv_name     TYPE icfname,
          lv_ok       TYPE abap_bool,
          lv_msg      TYPE string,
          lv_guid     TYPE icfnodguid,
          lv_exists   TYPE abap_bool,
          lv_active   TYPE abap_bool,
          lv_suffix   TYPE string,
          lt_handlers TYPE icfhndlist,
          lv_new_guid TYPE icfnodguid,
          lv_created  TYPE abap_bool.

    CLEAR rs_result.
    lv_url = normalize_url( is_def-url ).
    rs_result-url = lv_url.

    IF is_def-handlers IS INITIAL.
      rs_result-message = 'At least one handler class is required.'.
      RETURN.
    ENDIF.

    split_url(
      EXPORTING iv_url     = lv_url
      IMPORTING ev_parent  = lv_parent
                ev_name    = lv_name
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.

    lt_handlers = build_handler_list( is_def-handlers ).
    IF lt_handlers IS INITIAL.
      rs_result-message = 'Handler list empty after normalization.'.
      RETURN.
    ENDIF.

    resolve(
      EXPORTING iv_url     = lv_url
      IMPORTING ev_guid    = lv_guid
                ev_exists  = lv_exists
                ev_active  = lv_active
                ev_suffix  = lv_suffix
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.

    IF lv_exists = abap_false AND segment_count( lv_suffix ) > 1.
      rs_result-message =
        |Only the last path segment can be created. Missing in SICF: '{ lv_suffix }'.|.
      RETURN.
    ENDIF.

    IF iv_dry_run = abap_true.
      rs_result-ok = abap_true.
      IF lv_exists = abap_true.
        rs_result-updated = abap_true.
        rs_result-message = |DRY-RUN: would update '{ lv_url }' (active={ lv_active }).|.
      ELSE.
        rs_result-created = abap_true.
        rs_result-message =
          |DRY-RUN: would create '{ lv_name }' under '{ lv_parent }' (parent GUID { lv_guid }).|.
        IF is_def-package IS INITIAL.
          rs_result-message =
            |{ rs_result-message } Package is blank, so the node inherits the parent package.|.
        ENDIF.
      ENDIF.
      RETURN.
    ENDIF.

    IF lv_exists = abap_true.
      update_node(
        EXPORTING is_def         = is_def
                  iv_guid        = lv_guid
                  it_handlers    = lt_handlers
                  iv_description = is_def-description
                  iv_active      = lv_active
        IMPORTING ev_ok          = lv_ok
                  ev_message     = lv_msg ).
    ELSE.
      " Distinct variables: parameters are passed by reference, so sharing
      " one would let create_node clear the parent GUID before it uses it
      create_node(
        EXPORTING is_def         = is_def
                  iv_parent_guid = lv_guid
                  iv_name        = lv_name
                  it_handlers    = lt_handlers
                  iv_description = is_def-description
        IMPORTING ev_guid        = lv_new_guid
                  ev_ok          = lv_ok
                  ev_message     = lv_msg ).
      lv_created = lv_ok.
      IF lv_ok = abap_true.
        lv_guid = lv_new_guid.
      ENDIF.
    ENDIF.
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.

    rs_result-ok      = abap_true.
    rs_result-created = lv_created.
    rs_result-updated = boolc( lv_created = abap_false ).
    IF lv_created = abap_true.
      rs_result-message = |Created ICF service '{ lv_url }'.|.
    ELSE.
      rs_result-message = |Updated ICF service '{ lv_url }'.|.
    ENDIF.

    IF is_def-activate = abap_true.
      set_active(
        EXPORTING iv_guid    = lv_guid
                  iv_active  = abap_true
        IMPORTING ev_ok      = lv_ok
                  ev_message = lv_msg ).
      IF lv_ok = abap_false.
        rs_result-message =
          |{ rs_result-message } Activation failed: { lv_msg } Activate manually in SICF.|.
        RETURN.
      ENDIF.
      CONCATENATE rs_result-message 'Activated.'
                  INTO rs_result-message SEPARATED BY space.
    ENDIF.
  ENDMETHOD.


  METHOD activate.
    DATA: lv_guid   TYPE icfnodguid,
          lv_exists TYPE abap_bool,
          lv_suffix TYPE string,
          lv_ok     TYPE abap_bool,
          lv_msg    TYPE string.

    CLEAR rs_result.
    rs_result-url = normalize_url( iv_url ).

    resolve(
      EXPORTING iv_url     = rs_result-url
      IMPORTING ev_guid    = lv_guid
                ev_exists  = lv_exists
                ev_suffix  = lv_suffix
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.
    IF lv_exists = abap_false.
      rs_result-message = |Service '{ rs_result-url }' not found. Missing path: '{ lv_suffix }'.|.
      RETURN.
    ENDIF.

    IF iv_dry_run = abap_true.
      rs_result-ok = abap_true.
      rs_result-message = |DRY-RUN: would activate '{ rs_result-url }'.|.
      RETURN.
    ENDIF.

    set_active(
      EXPORTING iv_guid    = lv_guid
                iv_active  = abap_true
      IMPORTING ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.
    rs_result-ok = abap_true.
    rs_result-message = |Activated '{ rs_result-url }'.|.
  ENDMETHOD.


  METHOD deactivate.
    DATA: lv_guid   TYPE icfnodguid,
          lv_exists TYPE abap_bool,
          lv_suffix TYPE string,
          lv_ok     TYPE abap_bool,
          lv_msg    TYPE string.

    CLEAR rs_result.
    rs_result-url = normalize_url( iv_url ).

    resolve(
      EXPORTING iv_url     = rs_result-url
      IMPORTING ev_guid    = lv_guid
                ev_exists  = lv_exists
                ev_suffix  = lv_suffix
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.
    IF lv_exists = abap_false.
      rs_result-message = |Service '{ rs_result-url }' not found. Missing path: '{ lv_suffix }'.|.
      RETURN.
    ENDIF.

    IF iv_dry_run = abap_true.
      rs_result-ok = abap_true.
      rs_result-message = |DRY-RUN: would deactivate '{ rs_result-url }'.|.
      RETURN.
    ENDIF.

    set_active(
      EXPORTING iv_guid    = lv_guid
                iv_active  = abap_false
      IMPORTING ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.
    rs_result-ok = abap_true.
    rs_result-message = |Deactivated '{ rs_result-url }'.|.
  ENDMETHOD.


  METHOD parse_batch.
    DATA: lv_line TYPE string,
          lt_tok  TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
          lv_tok  TYPE string,
          ls_def  TYPE ty_service_def,
          ls_h    TYPE ty_handler,
          lv_idx  TYPE i,
          lv_up   TYPE string.

    CLEAR rt_defs.

    LOOP AT it_lines INTO lv_line.
      CONDENSE lv_line.
      IF lv_line IS INITIAL OR lv_line(1) = '#'.
        CONTINUE.
      ENDIF.

      CLEAR: ls_def, lt_tok.
      SPLIT lv_line AT ';' INTO TABLE lt_tok.

      lv_idx = 0.
      LOOP AT lt_tok INTO lv_tok.
        lv_idx = lv_idx + 1.
        CONDENSE lv_tok.
        IF lv_tok IS INITIAL.
          CONTINUE.
        ENDIF.
        CASE lv_idx.
          WHEN 1.
            ls_def-url = lv_tok.
          WHEN 2.
            CLEAR ls_h.
            ls_h-classname = lv_tok.
            TRANSLATE ls_h-classname TO UPPER CASE.
            APPEND ls_h TO ls_def-handlers.
          WHEN OTHERS.
            lv_up = lv_tok.
            TRANSLATE lv_up TO UPPER CASE.
            IF strlen( lv_up ) >= 3 AND ( lv_up(1) = 'Z' OR lv_up(1) = 'Y'
                OR lv_up(3) = 'CL_' OR lv_up CS '/' ).
              CLEAR ls_h.
              ls_h-classname = lv_up.
              APPEND ls_h TO ls_def-handlers.
            ELSEIF ls_def-description IS INITIAL.
              ls_def-description = lv_tok.
            ELSE.
              CONCATENATE ls_def-description lv_tok
                          INTO ls_def-description SEPARATED BY space.
            ENDIF.
        ENDCASE.
      ENDLOOP.

      IF ls_def-url IS INITIAL OR ls_def-handlers IS INITIAL.
        CONTINUE.
      ENDIF.
      ls_def-activate = abap_true.
      APPEND ls_def TO rt_defs.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
