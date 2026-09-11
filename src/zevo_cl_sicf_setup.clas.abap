*&---------------------------------------------------------------------*
*& Class ZEVO_CL_SICF_SETUP
*&---------------------------------------------------------------------*
*& Generic ICF / SICF administrator — standalone tool (own abapGit repo).
*&
*& Call from report ZEVO_SICF_SETUP, or from any project post-install:
*&   DATA(ls) = zevo_cl_sicf_setup=>ensure( is_def = … ).
*&
*& Configure defaults via include ZEVO_SICF_SETUP_CFG (not product code).
*& SICF is not covered by abapGit; this class closes that gap.
*& Requires ICF admin authorization (e.g. S_ICF_ADM).
*&
*& CL_ICF_TREE method names differ by BASIS release — methods are invoked
*& dynamically with common fallbacks; failures return a clear message.
*&---------------------------------------------------------------------*
CLASS zevo_cl_sicf_setup DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_handler,
             classname TYPE seoclsname,
           END OF ty_handler.
    TYPES ty_handlers TYPE STANDARD TABLE OF ty_handler WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_service_def,
             url         TYPE string,
             description TYPE string,
             handlers    TYPE ty_handlers,
             activate    TYPE abap_bool,
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

  PRIVATE SECTION.
    TYPES ty_icfhandlers TYPE STANDARD TABLE OF icfhandler WITH DEFAULT KEY.

    CLASS-METHODS split_url
      IMPORTING
        iv_url     TYPE clike
      EXPORTING
        ev_parent  TYPE string
        ev_name    TYPE icfname
        ev_ok      TYPE abap_bool
        ev_message TYPE string.

    CLASS-METHODS tree_from_url
      IMPORTING
        iv_url         TYPE clike
      RETURNING
        VALUE(ro_tree) TYPE REF TO object.

    CLASS-METHODS build_handler_tab
      IMPORTING
        it_handlers   TYPE ty_handlers
      RETURNING
        VALUE(rt_icf) TYPE ty_icfhandlers.

    CLASS-METHODS invoke
      IMPORTING
        io_obj     TYPE REF TO object
        iv_method  TYPE seocpdname
        it_params  TYPE abap_parmbind_tab OPTIONAL
      EXPORTING
        ev_ok      TYPE abap_bool
        ev_message TYPE string.

    CLASS-METHODS set_docu_fields
      IMPORTING
        iv_text TYPE clike
      CHANGING
        cs_docu TYPE icfdocu.

    CLASS-METHODS read_docu_text
      IMPORTING
        is_docu        TYPE icfdocu
      RETURNING
        VALUE(rv_text) TYPE string.

    CLASS-METHODS create_child
      IMPORTING
        io_parent      TYPE REF TO object
        iv_name        TYPE icfname
      EXPORTING
        eo_child       TYPE REF TO object
        ev_ok          TYPE abap_bool
        ev_message     TYPE string.

    CLASS-METHODS set_handlers
      IMPORTING
        io_svc         TYPE REF TO object
        it_hand        TYPE ty_icfhandlers
      EXPORTING
        ev_ok          TYPE abap_bool
        ev_message     TYPE string.

    CLASS-METHODS save_node
      IMPORTING
        io_svc         TYPE REF TO object
      EXPORTING
        ev_ok          TYPE abap_bool
        ev_message     TYPE string.
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
    ev_name = lv_last.
    TRANSLATE ev_name TO UPPER CASE.
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


  METHOD tree_from_url.
    DATA: lv_url  TYPE string,
          lt_parm TYPE abap_parmbind_tab,
          ls_parm TYPE abap_parmbind,
          lo_tree TYPE REF TO object,
          lv_meth TYPE seocpdname,
          lt_meth TYPE STANDARD TABLE OF seocpdname WITH DEFAULT KEY,
          lt_purl TYPE STANDARD TABLE OF abap_parmname WITH DEFAULT KEY,
          lt_ptree TYPE STANDARD TABLE OF abap_parmname WITH DEFAULT KEY,
          lv_purl TYPE abap_parmname,
          lv_ptree TYPE abap_parmname.

    CLEAR ro_tree.
    lv_url = normalize_url( iv_url ).
    IF lv_url IS INITIAL.
      RETURN.
    ENDIF.

    " Common static entry points / parameter names across BASIS releases
    APPEND 'IF_ICF_TREE~SERVICE_FROM_URL' TO lt_meth.
    APPEND 'SERVICE_FROM_URL' TO lt_meth.
    APPEND 'GET_NODE_BY_URL' TO lt_meth.

    APPEND 'URL' TO lt_purl.
    APPEND 'I_URL' TO lt_purl.
    APPEND 'IV_URL' TO lt_purl.

    APPEND 'TREE' TO lt_ptree.
    APPEND 'NODE' TO lt_ptree.
    APPEND 'E_ICF_TREE' TO lt_ptree.
    APPEND 'EO_TREE' TO lt_ptree.

    LOOP AT lt_meth INTO lv_meth.
      LOOP AT lt_purl INTO lv_purl.
        LOOP AT lt_ptree INTO lv_ptree.
          CLEAR: lt_parm, lo_tree.

          ls_parm-name = lv_purl.
          ls_parm-kind = cl_abap_objectdescr=>exporting.
          GET REFERENCE OF lv_url INTO ls_parm-value.
          INSERT ls_parm INTO TABLE lt_parm.

          ls_parm-name = lv_ptree.
          ls_parm-kind = cl_abap_objectdescr=>receiving.
          GET REFERENCE OF lo_tree INTO ls_parm-value.
          INSERT ls_parm INTO TABLE lt_parm.

          TRY.
              CALL METHOD cl_icf_tree=>(lv_meth)
                PARAMETER-TABLE lt_parm.
              IF lo_tree IS BOUND.
                ro_tree = lo_tree.
                RETURN.
              ENDIF.
            CATCH cx_sy_dyn_call_error cx_root.           "#EC NO_HANDLER
          ENDTRY.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_handler_tab.
    DATA: ls_in  TYPE ty_handler,
          ls_icf TYPE icfhandler,
          lv_pos TYPE i,
          lv_cls TYPE seoclsname.
    FIELD-SYMBOLS <fs> TYPE any.

    CLEAR rt_icf.
    LOOP AT it_handlers INTO ls_in WHERE classname IS NOT INITIAL.
      CLEAR ls_icf.
      lv_pos = lv_pos + 1.
      lv_cls = ls_in-classname.
      TRANSLATE lv_cls TO UPPER CASE.

      ASSIGN COMPONENT 'ICFORDER' OF STRUCTURE ls_icf TO <fs>.
      IF sy-subrc = 0.
        <fs> = lv_pos.
      ENDIF.

      ASSIGN COMPONENT 'ICFHANDLER' OF STRUCTURE ls_icf TO <fs>.
      IF sy-subrc = 0.
        <fs> = lv_cls.
      ENDIF.

      APPEND ls_icf TO rt_icf.
    ENDLOOP.
  ENDMETHOD.


  METHOD set_docu_fields.
    FIELD-SYMBOLS <fs> TYPE any.

    UNASSIGN <fs>.
    ASSIGN COMPONENT 'ICF_LANGU' OF STRUCTURE cs_docu TO <fs>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'LANGU' OF STRUCTURE cs_docu TO <fs>.
    ENDIF.
    IF <fs> IS ASSIGNED.
      <fs> = sy-langu.
    ENDIF.

    UNASSIGN <fs>.
    ASSIGN COMPONENT 'ICF_DOCU' OF STRUCTURE cs_docu TO <fs>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'ICFDOCU' OF STRUCTURE cs_docu TO <fs>.
    ENDIF.
    IF <fs> IS ASSIGNED.
      <fs> = iv_text.
    ENDIF.
  ENDMETHOD.


  METHOD read_docu_text.
    FIELD-SYMBOLS <fs> TYPE any.

    CLEAR rv_text.
    ASSIGN COMPONENT 'ICF_DOCU' OF STRUCTURE is_docu TO <fs>.
    IF sy-subrc <> 0.
      ASSIGN COMPONENT 'ICFDOCU' OF STRUCTURE is_docu TO <fs>.
    ENDIF.
    IF <fs> IS ASSIGNED.
      rv_text = <fs>.
    ENDIF.
  ENDMETHOD.


  METHOD invoke.
    DATA lx TYPE REF TO cx_root.
    CLEAR ev_message.
    ev_ok = abap_false.
    IF io_obj IS NOT BOUND OR iv_method IS INITIAL.
      ev_message = 'Object or method initial.'.
      RETURN.
    ENDIF.
    TRY.
        IF it_params IS SUPPLIED AND it_params IS NOT INITIAL.
          CALL METHOD io_obj->(iv_method) PARAMETER-TABLE it_params.
        ELSE.
          CALL METHOD io_obj->(iv_method).
        ENDIF.
        ev_ok = abap_true.
      CATCH cx_root INTO lx.
        ev_message = |{ iv_method }: { lx->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD create_child.
    DATA: lt_parm  TYPE abap_parmbind_tab,
          ls_parm  TYPE abap_parmbind,
          lo_child TYPE REF TO object,
          lv_meth  TYPE seocpdname,
          lt_meth  TYPE STANDARD TABLE OF seocpdname WITH DEFAULT KEY,
          lt_pname TYPE STANDARD TABLE OF abap_parmname WITH DEFAULT KEY,
          lt_rname TYPE STANDARD TABLE OF abap_parmname WITH DEFAULT KEY,
          lv_pname TYPE abap_parmname,
          lv_rname TYPE abap_parmname,
          lv_last  TYPE string.

    CLEAR: eo_child, ev_message.
    ev_ok = abap_false.

    APPEND 'INSERT_NODE' TO lt_meth.
    APPEND 'CREATE_NODE' TO lt_meth.
    APPEND 'ADD_NODE' TO lt_meth.

    APPEND 'ICFNAME' TO lt_pname.
    APPEND 'NAME' TO lt_pname.
    APPEND 'I_ICFNAME' TO lt_pname.

    APPEND 'NODE' TO lt_rname.
    APPEND 'TREE' TO lt_rname.
    APPEND 'SERVICE' TO lt_rname.

    LOOP AT lt_meth INTO lv_meth.
      LOOP AT lt_pname INTO lv_pname.
        LOOP AT lt_rname INTO lv_rname.
          CLEAR: lt_parm, lo_child.

          ls_parm-name = lv_pname.
          ls_parm-kind = cl_abap_objectdescr=>exporting.
          GET REFERENCE OF iv_name INTO ls_parm-value.
          INSERT ls_parm INTO TABLE lt_parm.

          ls_parm-name = lv_rname.
          ls_parm-kind = cl_abap_objectdescr=>receiving.
          GET REFERENCE OF lo_child INTO ls_parm-value.
          INSERT ls_parm INTO TABLE lt_parm.

          invoke(
            EXPORTING io_obj = io_parent iv_method = lv_meth it_params = lt_parm
            IMPORTING ev_ok = ev_ok ev_message = lv_last ).
          IF ev_ok = abap_true AND lo_child IS BOUND.
            eo_child = lo_child.
            CLEAR ev_message.
            RETURN.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    ev_ok = abap_false.
    ev_message = |Cannot create child node: { lv_last }|.
  ENDMETHOD.


  METHOD set_handlers.
    DATA: lt_parm TYPE abap_parmbind_tab,
          ls_parm TYPE abap_parmbind,
          lv_meth TYPE seocpdname,
          lv_pname TYPE abap_parmname,
          lt_meth TYPE STANDARD TABLE OF seocpdname WITH DEFAULT KEY,
          lt_pname TYPE STANDARD TABLE OF abap_parmname WITH DEFAULT KEY,
          lv_last TYPE string.

    CLEAR ev_message.
    ev_ok = abap_false.

    APPEND 'SET_HANDLERLIST' TO lt_meth.
    APPEND 'SET_HANDLER_LIST' TO lt_meth.

    APPEND 'HANDLERLIST' TO lt_pname.
    APPEND 'HANDLER_LIST' TO lt_pname.
    APPEND 'HANDLERS' TO lt_pname.

    LOOP AT lt_meth INTO lv_meth.
      LOOP AT lt_pname INTO lv_pname.
        CLEAR lt_parm.
        ls_parm-name = lv_pname.
        ls_parm-kind = cl_abap_objectdescr=>exporting.
        GET REFERENCE OF it_hand INTO ls_parm-value.
        INSERT ls_parm INTO TABLE lt_parm.

        invoke(
          EXPORTING io_obj = io_svc iv_method = lv_meth it_params = lt_parm
          IMPORTING ev_ok = ev_ok ev_message = lv_last ).
        IF ev_ok = abap_true.
          CLEAR ev_message.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    ev_ok = abap_false.
    ev_message = lv_last.
  ENDMETHOD.


  METHOD save_node.
    DATA lv_msg TYPE string.

    CLEAR ev_message.
    ev_ok = abap_false.

    invoke(
      EXPORTING io_obj = io_svc iv_method = 'ORDER_SAVE'
      IMPORTING ev_ok = ev_ok ev_message = lv_msg ).
    IF ev_ok = abap_true.
      RETURN.
    ENDIF.

    invoke(
      EXPORTING io_obj = io_svc iv_method = 'SAVE'
      IMPORTING ev_ok = ev_ok ev_message = lv_msg ).
    IF ev_ok = abap_true.
      RETURN.
    ENDIF.

    ev_message = lv_msg.
  ENDMETHOD.


  METHOD get_status.
    DATA: lo_tree    TYPE REF TO object,
          lt_handler TYPE ty_icfhandlers,
          ls_handler TYPE icfhandler,
          ls_docu    TYPE icfdocu,
          lv_active  TYPE abap_bool,
          lv_langu   TYPE sylangu,
          lt_parm    TYPE abap_parmbind_tab,
          ls_parm    TYPE abap_parmbind,
          lv_hand    TYPE string.
    FIELD-SYMBOLS <fs> TYPE any.

    CLEAR rs_status.
    rs_status-url = normalize_url( iv_url ).
    lo_tree = tree_from_url( rs_status-url ).
    IF lo_tree IS NOT BOUND.
      rs_status-exists  = abap_false.
      rs_status-message = 'Service not found.'.
      RETURN.
    ENDIF.
    rs_status-exists = abap_true.

    TRY.
        CALL METHOD lo_tree->('IS_ACTIVE')
          RECEIVING
            result = lv_active.
        rs_status-active = boolc( lv_active = abap_true ).
      CATCH cx_sy_dyn_call_error.
        TRY.
            CALL METHOD lo_tree->('GET_ACTIVE')
              RECEIVING
                result = lv_active.
            rs_status-active = boolc( lv_active = abap_true ).
          CATCH cx_sy_dyn_call_error cx_root.             "#EC NO_HANDLER
        ENDTRY.
      CATCH cx_root.                                      "#EC NO_HANDLER
    ENDTRY.

    TRY.
        CALL METHOD lo_tree->('GET_HANDLERLIST')
          RECEIVING
            result = lt_handler.
      CATCH cx_sy_dyn_call_error.
        TRY.
            CALL METHOD lo_tree->('GET_HANDLER_LIST')
              RECEIVING
                result = lt_handler.
          CATCH cx_sy_dyn_call_error cx_root.             "#EC NO_HANDLER
        ENDTRY.
      CATCH cx_root.                                      "#EC NO_HANDLER
    ENDTRY.

    LOOP AT lt_handler INTO ls_handler.
      CLEAR lv_hand.
      ASSIGN COMPONENT 'ICFHANDLER' OF STRUCTURE ls_handler TO <fs>.
      IF sy-subrc = 0.
        lv_hand = <fs>.
      ENDIF.
      IF lv_hand IS INITIAL.
        CONTINUE.
      ENDIF.
      IF rs_status-handlers IS INITIAL.
        rs_status-handlers = lv_hand.
      ELSE.
        CONCATENATE rs_status-handlers ',' lv_hand
                    INTO rs_status-handlers SEPARATED BY space.
      ENDIF.
    ENDLOOP.

    lv_langu = sy-langu.
    CLEAR lt_parm.
    ls_parm-name = 'LANGU'.
    ls_parm-kind = cl_abap_objectdescr=>exporting.
    GET REFERENCE OF lv_langu INTO ls_parm-value.
    INSERT ls_parm INTO TABLE lt_parm.
    ls_parm-name = 'RESULT'.
    ls_parm-kind = cl_abap_objectdescr=>receiving.
    GET REFERENCE OF ls_docu INTO ls_parm-value.
    INSERT ls_parm INTO TABLE lt_parm.
    TRY.
        CALL METHOD lo_tree->('GET_DOCU')
          PARAMETER-TABLE lt_parm.
        rs_status-description = read_docu_text( ls_docu ).
      CATCH cx_sy_dyn_call_error cx_root.                 "#EC NO_HANDLER
    ENDTRY.

    rs_status-message = 'OK'.
  ENDMETHOD.


  METHOD ensure.
    DATA: lv_url     TYPE string,
          lv_parent  TYPE string,
          lv_name    TYPE icfname,
          lv_ok      TYPE abap_bool,
          lv_msg     TYPE string,
          lo_parent  TYPE REF TO object,
          lo_svc     TYPE REF TO object,
          lt_hand    TYPE ty_icfhandlers,
          ls_docu    TYPE icfdocu,
          lt_parm    TYPE abap_parmbind_tab,
          ls_parm    TYPE abap_parmbind,
          ls_status  TYPE ty_status,
          lv_created TYPE abap_bool,
          lx         TYPE REF TO cx_root.

    CLEAR rs_result.
    lv_url = normalize_url( is_def-url ).
    rs_result-url = lv_url.

    IF is_def-handlers IS INITIAL.
      rs_result-message = 'At least one handler class is required.'.
      RETURN.
    ENDIF.

    split_url(
      EXPORTING iv_url = lv_url
      IMPORTING ev_parent  = lv_parent
                ev_name    = lv_name
                ev_ok      = lv_ok
                ev_message = lv_msg ).
    IF lv_ok = abap_false.
      rs_result-message = lv_msg.
      RETURN.
    ENDIF.

    lt_hand = build_handler_tab( is_def-handlers ).
    IF lt_hand IS INITIAL.
      rs_result-message = 'Handler list empty after normalization.'.
      RETURN.
    ENDIF.

    IF iv_dry_run = abap_true.
      ls_status = get_status( lv_url ).
      rs_result-ok = abap_true.
      IF ls_status-exists = abap_true.
        rs_result-updated = abap_true.
        rs_result-message =
          |DRY-RUN: would update '{ lv_url }' (active={ ls_status-active }).|.
      ELSE.
        rs_result-created = abap_true.
        rs_result-message =
          |DRY-RUN: would create '{ lv_url }' under '{ lv_parent }'.|.
      ENDIF.
      RETURN.
    ENDIF.

    TRY.
        lo_svc = tree_from_url( lv_url ).
        IF lo_svc IS BOUND.
          lv_created = abap_false.
        ELSE.
          lo_parent = tree_from_url( lv_parent ).
          IF lo_parent IS NOT BOUND.
            rs_result-message =
              |Parent ICF node '{ lv_parent }' not found. Create/activate it in SICF first.|.
            RETURN.
          ENDIF.

          create_child(
            EXPORTING io_parent = lo_parent iv_name = lv_name
            IMPORTING eo_child = lo_svc ev_ok = lv_ok ev_message = lv_msg ).
          IF lv_ok = abap_false OR lo_svc IS NOT BOUND.
            rs_result-message = lv_msg.
            RETURN.
          ENDIF.
          lv_created = abap_true.
        ENDIF.

        IF is_def-description IS NOT INITIAL.
          CLEAR ls_docu.
          set_docu_fields(
            EXPORTING iv_text = is_def-description
            CHANGING  cs_docu = ls_docu ).
          CLEAR lt_parm.
          ls_parm-name = 'DOCU'.
          ls_parm-kind = cl_abap_objectdescr=>exporting.
          GET REFERENCE OF ls_docu INTO ls_parm-value.
          INSERT ls_parm INTO TABLE lt_parm.
          invoke( io_obj = lo_svc iv_method = 'SET_DOCU' it_params = lt_parm ).
        ENDIF.

        set_handlers(
          EXPORTING io_svc = lo_svc it_hand = lt_hand
          IMPORTING ev_ok = lv_ok ev_message = lv_msg ).
        IF lv_ok = abap_false.
          rs_result-message = |Cannot set handlers: { lv_msg }|.
          RETURN.
        ENDIF.

        save_node(
          EXPORTING io_svc = lo_svc
          IMPORTING ev_ok = lv_ok ev_message = lv_msg ).
        IF lv_ok = abap_false.
          rs_result-message = |Cannot save ICF node: { lv_msg }|.
          RETURN.
        ENDIF.

        IF is_def-activate = abap_true.
          invoke(
            EXPORTING io_obj = lo_svc iv_method = 'ACTIVATE'
            IMPORTING ev_ok = lv_ok ev_message = lv_msg ).
          IF lv_ok = abap_false.
            rs_result-ok      = abap_true.
            rs_result-created = lv_created.
            rs_result-updated = boolc( lv_created = abap_false ).
            rs_result-message =
              |Saved but activate failed ({ lv_msg }). Activate manually in SICF.|.
            RETURN.
          ENDIF.
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
          CONCATENATE rs_result-message 'Activated.'
                      INTO rs_result-message SEPARATED BY space.
        ENDIF.

      CATCH cx_root INTO lx.
        rs_result-message = |Unexpected error: { lx->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD activate.
    DATA: lo_svc TYPE REF TO object,
          lv_ok  TYPE abap_bool,
          lv_msg TYPE string,
          lx     TYPE REF TO cx_root.

    CLEAR rs_result.
    rs_result-url = normalize_url( iv_url ).

    IF iv_dry_run = abap_true.
      rs_result-ok = abap_true.
      rs_result-message = |DRY-RUN: would activate '{ rs_result-url }'.|.
      RETURN.
    ENDIF.

    TRY.
        lo_svc = tree_from_url( rs_result-url ).
        IF lo_svc IS NOT BOUND.
          rs_result-message = |Service '{ rs_result-url }' not found.|.
          RETURN.
        ENDIF.
        invoke(
          EXPORTING io_obj = lo_svc iv_method = 'ACTIVATE'
          IMPORTING ev_ok = lv_ok ev_message = lv_msg ).
        IF lv_ok = abap_false.
          rs_result-message = lv_msg.
          RETURN.
        ENDIF.
        save_node( EXPORTING io_svc = lo_svc ).
        rs_result-ok = abap_true.
        rs_result-message = |Activated '{ rs_result-url }'.|.
      CATCH cx_root INTO lx.
        rs_result-message = lx->get_text( ).
    ENDTRY.
  ENDMETHOD.


  METHOD deactivate.
    DATA: lo_svc TYPE REF TO object,
          lv_ok  TYPE abap_bool,
          lv_msg TYPE string,
          lx     TYPE REF TO cx_root.

    CLEAR rs_result.
    rs_result-url = normalize_url( iv_url ).

    IF iv_dry_run = abap_true.
      rs_result-ok = abap_true.
      rs_result-message = |DRY-RUN: would deactivate '{ rs_result-url }'.|.
      RETURN.
    ENDIF.

    TRY.
        lo_svc = tree_from_url( rs_result-url ).
        IF lo_svc IS NOT BOUND.
          rs_result-message = |Service '{ rs_result-url }' not found.|.
          RETURN.
        ENDIF.
        invoke(
          EXPORTING io_obj = lo_svc iv_method = 'DEACTIVATE'
          IMPORTING ev_ok = lv_ok ev_message = lv_msg ).
        IF lv_ok = abap_false.
          rs_result-message = lv_msg.
          RETURN.
        ENDIF.
        save_node( EXPORTING io_svc = lo_svc ).
        rs_result-ok = abap_true.
        rs_result-message = |Deactivated '{ rs_result-url }'.|.
      CATCH cx_root INTO lx.
        rs_result-message = lx->get_text( ).
    ENDTRY.
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
