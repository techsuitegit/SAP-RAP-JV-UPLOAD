CLASS lhc_upload DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    CONSTANTS: c_updated TYPE c LENGTH 12 VALUE 'UPDATED',
               c_error   TYPE c LENGTH 12 VALUE 'ERROR',
               c_partial TYPE c LENGTH 12 VALUE 'PARTIAL'.

    TYPES tt_read TYPE TABLE FOR READ IMPORT zi_je_ref_upl_hdr.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Upload
      RESULT    result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Upload
      RESULT    result.

    METHODS earlynumbering_create FOR NUMBERING
      IMPORTING entities FOR CREATE Upload.

    METHODS earlynumbering_cba_Items FOR NUMBERING
      IMPORTING entities FOR CREATE Upload\_Items.

    METHODS initFlags FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Upload~initFlags.

    METHODS loadExcel FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Upload~loadExcel.

    METHODS parseExcel FOR MODIFY
      IMPORTING keys FOR ACTION Upload~parseExcel RESULT result.

    METHODS Execute FOR MODIFY
      IMPORTING keys FOR ACTION Upload~Execute RESULT result.

    METHODS load_excel IMPORTING it_tky TYPE tt_read.
ENDCLASS.

CLASS lhc_upload IMPLEMENTATION.

  METHOD get_global_authorizations.
    result-%create = if_abap_behv=>auth-allowed.
    result-%update = if_abap_behv=>auth-allowed.
    result-%delete = if_abap_behv=>auth-allowed.

    IF requested_authorizations-%action-Edit = if_abap_behv=>mk-on.
      result-%action-Edit = if_abap_behv=>auth-allowed.
    ENDIF.
    IF requested_authorizations-%action-Execute = if_abap_behv=>mk-on.
      result-%action-Execute = if_abap_behv=>auth-allowed.
    ENDIF.
    IF requested_authorizations-%action-parseExcel = if_abap_behv=>mk-on.
      result-%action-parseExcel = if_abap_behv=>auth-allowed.
    ENDIF.
  ENDMETHOD.

  METHOD get_instance_features.
    READ ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload
      FIELDS ( Status )
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_up).

    " Execute stays enabled for PARTIAL / ERROR so failed rows can be retried
    result = VALUE #( FOR u IN lt_up
      ( %tky = u-%tky
        %action-Execute = COND #(
          WHEN u-%is_draft = if_abap_behv=>mk-on
            OR u-Status = c_updated
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled )
        %action-parseExcel = COND #(
          WHEN u-%is_draft = if_abap_behv=>mk-on
          THEN if_abap_behv=>fc-o-enabled
          ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  METHOD earlynumbering_create.
    DATA lv_uuid TYPE sysuuid_x16.

    LOOP AT entities INTO DATA(entity).
      CLEAR lv_uuid.
      TRY.
          lv_uuid = cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ).
        CATCH cx_uuid_error.
          APPEND VALUE #( %cid = entity-%cid %is_draft = entity-%is_draft )
            TO failed-upload.
          CONTINUE.
      ENDTRY.

      APPEND VALUE #(
        %cid       = entity-%cid
        %is_draft  = entity-%is_draft
        UploadUUID = lv_uuid
      ) TO mapped-upload.
    ENDLOOP.
  ENDMETHOD.

  METHOD earlynumbering_cba_Items.
    DATA lv_uuid TYPE sysuuid_x16.

    LOOP AT entities INTO DATA(entity).
      LOOP AT entity-%target INTO DATA(target).
        CLEAR lv_uuid.
        TRY.
            lv_uuid = cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ).
          CATCH cx_uuid_error.
            APPEND VALUE #( %cid = target-%cid %is_draft = target-%is_draft )
              TO failed-item.
            CONTINUE.
        ENDTRY.

        APPEND VALUE #(
          %cid      = target-%cid
          %is_draft = target-%is_draft
          ItemUUID  = lv_uuid
        ) TO mapped-item.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD initFlags.
    MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload
      UPDATE FIELDS ( HideExcel HideResult )
      WITH VALUE #( FOR k IN keys
                    ( %tky = k-%tky HideExcel = abap_false HideResult = abap_true ) ).
  ENDMETHOD.

  METHOD loadExcel.
    load_excel( CORRESPONDING #( keys ) ).
  ENDMETHOD.

  METHOD parseExcel.
    load_excel( CORRESPONDING #( keys ) ).

    READ ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload ALL FIELDS
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR a IN lt_after ( %tky = a-%tky %param = a ) ).
  ENDMETHOD.

  METHOD load_excel.
    TYPES: BEGIN OF ty_xlsx,
             doc TYPE string,
             fy  TYPE string,
             cc  TYPE string,
             ref TYPE string,
           END OF ty_xlsx.
    DATA lt_xlsx    TYPE STANDARD TABLE OF ty_xlsx WITH EMPTY KEY.
    DATA lt_create  TYPE TABLE FOR CREATE zi_je_ref_upl_hdr\_Items.
    DATA lv_skipped TYPE i.
    DATA lv_count   TYPE i.

    READ ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload
      FIELDS ( ExcelAttachment )
      WITH CORRESPONDING #( it_tky )
      RESULT DATA(lt_up).

    " remove rows loaded earlier (re-upload or Clear)
    READ ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload BY \_Items
      FIELDS ( ItemUUID )
      WITH CORRESPONDING #( it_tky )
      RESULT DATA(lt_old).

    IF lt_old IS NOT INITIAL.
      MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
        ENTITY Item
        DELETE FROM VALUE #( FOR o IN lt_old ( %tky = o-%tky ) ).
    ENDIF.

    LOOP AT lt_up INTO DATA(ls_up).

      IF ls_up-ExcelAttachment IS INITIAL.
        MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
          ENTITY Upload
          UPDATE FIELDS ( Status Message )
          WITH VALUE #( ( %tky = ls_up-%tky Status = '' Message = '' ) ).
        CONTINUE.
      ENDIF.

      CLEAR lt_xlsx.
      TRY.
          DATA(lo_ws) = xco_cp_xlsx=>document->for_file_content(
                          ls_up-ExcelAttachment
                        )->read_access( )->get_workbook( )->worksheet->at_position( 1 ).

          DATA(lo_pattern) = xco_cp_xlsx_selection=>pattern_builder->simple_from_to( )->from_row(
                               xco_cp_xlsx=>coordinate->for_numeric_value( 2 )
                             )->get_pattern( ).

          lo_ws->select( lo_pattern )->row_stream( )->operation->write_to(
            REF #( lt_xlsx )
          )->set_value_transformation(
            xco_cp_xlsx_read_access=>value_transformation->string_value
          )->if_xco_xlsx_ra_operation~execute( ).
        CATCH cx_root.
          MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
            ENTITY Upload
            UPDATE FIELDS ( Status Message )
            WITH VALUE #( ( %tky = ls_up-%tky Status = 'ERROR'
                            Message = 'The Excel file could not be read' ) ).
          CONTINUE.
      ENDTRY.

      CLEAR: lt_create, lv_skipped, lv_count.
      APPEND VALUE #( %tky = ls_up-%tky ) TO lt_create ASSIGNING FIELD-SYMBOL(<ls_create>).

      LOOP AT lt_xlsx INTO DATA(ls_x).
        DATA(lv_ref) = condense( ls_x-ref ).
        IF lv_ref IS INITIAL.
          lv_skipped += 1.
          CONTINUE.
        ENDIF.

        DATA(lv_doc) = condense( ls_x-doc ).
        IF lv_doc CO '0123456789' AND strlen( lv_doc ) < 10.
          lv_doc = |{ lv_doc WIDTH = 10 ALIGN = RIGHT PAD = '0' }|.
        ENDIF.

        " "1000 (TBDL)" -> "1000"
        DATA(lv_cc) = match( val = ls_x-cc regex = '^\w+' ).

        lv_count += 1.
        APPEND VALUE #(
          %cid           = |ITEM_{ lv_count }|
          %is_draft      = ls_up-%is_draft
          DocumentNumber = lv_doc
          FiscalYear     = condense( ls_x-fy )
          CompanyCode    = lv_cc
          ReferenceID    = lv_ref
          Status         = 'NEW'
        ) TO <ls_create>-%target.
      ENDLOOP.

      IF lv_count > 0.
        MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
          ENTITY Upload
          CREATE BY \_Items
          FIELDS ( DocumentNumber FiscalYear CompanyCode ReferenceID Status )
          WITH lt_create.
      ENDIF.

      DATA(lv_msg) = |{ lv_count } row(s) loaded|.
      IF lv_skipped > 0.
        lv_msg = |{ lv_msg }, { lv_skipped } row(s) without Reference ID left out|.
      ENDIF.

      MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
        ENTITY Upload
        UPDATE FIELDS ( Status Message HideExcel HideResult )
        WITH VALUE #( ( %tky = ls_up-%tky Status = 'LOADED' Message = lv_msg
                        HideExcel = abap_false HideResult = abap_true ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD Execute.
    READ ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload ALL FIELDS
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_up).

    READ ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload BY \_Items ALL FIELDS
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    " Rows already updated are not sent again (retry after PARTIAL / ERROR)
    DATA lt_todo TYPE zcl_je_ref_upl_api=>tt_record.
    LOOP AT lt_items INTO DATA(ls_item) WHERE Status <> c_updated.
      APPEND VALUE #( record_uuid     = ls_item-ItemUUID
                      document_number = ls_item-DocumentNumber
                      fiscal_year     = ls_item-FiscalYear
                      company_code    = ls_item-CompanyCode
                      reference_id    = ls_item-ReferenceID ) TO lt_todo.
    ENDLOOP.

    IF lt_todo IS INITIAL.
      DATA(lv_no_rows) = COND string( WHEN lt_items IS INITIAL
                                      THEN 'There are no rows to process'
                                      ELSE 'All rows are already updated' ).
      LOOP AT lt_up INTO DATA(ls_empty).
        APPEND VALUE #( %tky = ls_empty-%tky ) TO failed-upload.
        APPEND VALUE #(
          %tky = ls_empty-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = lv_no_rows )
        ) TO reported-upload.
      ENDLOOP.
      RETURN.
    ENDIF.

   " process( ) defaults to iv_commit = abap_false: no commit inside the RAP handler
DATA(lt_res) = NEW zcl_je_ref_upl_api( )->process( it_records = lt_todo ).
    MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Item
      UPDATE FIELDS ( DocumentDate CustomerName BatchID MessageID Status Message )
      WITH VALUE #( FOR x IN lt_res
                    LET it = lt_items[ ItemUUID = x-record_uuid ] IN
                    ( %tky         = it-%tky
                      DocumentDate = x-document_date
                      CustomerName = x-customer_name
                      BatchID      = x-batch_id
                      MessageID    = x-message_id
                      Status       = x-status
                      Message      = x-message ) ).

    DATA(lv_total)   = lines( lt_items ).
    DATA(lv_errors)  = REDUCE i( INIT n = 0
                                 FOR r IN lt_res WHERE ( status = c_error )
                                 NEXT n = n + 1 ).
    DATA(lv_updated) = lv_total - lv_errors.

    DATA(lv_status) = COND string(
      WHEN lv_errors = 0  THEN c_updated
      WHEN lv_updated = 0 THEN c_error
      ELSE                     c_partial ).

    DATA(lv_first) = VALUE string( ).
    READ TABLE lt_res INTO DATA(ls_err) WITH KEY status = c_error.
    IF sy-subrc = 0.
      lv_first = substring( val = ls_err-message
                            len = nmin( val1 = strlen( ls_err-message ) val2 = 150 ) ).
    ENDIF.

    MODIFY ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload
      UPDATE FIELDS ( Status Message HideExcel HideResult )
      WITH VALUE #( FOR u IN lt_up
                    ( %tky       = u-%tky
                      Status     = lv_status
                      Message    = |{ lv_total } record(s): { lv_updated } updated, { lv_errors } with errors. { lv_first }|
                      HideExcel  = abap_true
                      HideResult = abap_false ) ).

    READ ENTITIES OF zi_je_ref_upl_hdr IN LOCAL MODE
      ENTITY Upload ALL FIELDS
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR a IN lt_after ( %tky = a-%tky %param = a ) ).
  ENDMETHOD.

ENDCLASS.
