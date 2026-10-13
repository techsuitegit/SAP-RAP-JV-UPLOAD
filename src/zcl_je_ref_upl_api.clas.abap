CLASS zcl_je_ref_upl_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CONSTANTS c_status_updated TYPE c LENGTH 12 VALUE 'UPDATED'.
    CONSTANTS c_status_error   TYPE c LENGTH 12 VALUE 'ERROR'.

    TYPES: BEGIN OF ty_record,
             record_uuid     TYPE sysuuid_x16,
             document_number TYPE c LENGTH 10,
             fiscal_year     TYPE n LENGTH 4,
             company_code    TYPE c LENGTH 4,
             reference_id    TYPE c LENGTH 16,
           END OF ty_record,
           tt_record TYPE STANDARD TABLE OF ty_record WITH EMPTY KEY,

           BEGIN OF ty_result,
             record_uuid   TYPE sysuuid_x16,
             document_date TYPE d,
             customer_name TYPE c LENGTH 80,
             batch_id      TYPE c LENGTH 10,
             message_id    TYPE c LENGTH 36,
             status        TYPE c LENGTH 12,
             message       TYPE c LENGTH 255,
           END OF ty_result,
           tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    " iv_commit = abap_false -> inside RAP handler (Execute); the RAP save commits
    " iv_commit = abap_true  -> ADT console (F9) / application job; commit per document
    METHODS process
      IMPORTING it_records        TYPE tt_record
                iv_commit         TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rt_results) TYPE tt_result.

  PRIVATE SECTION.
    METHODS lookup
      IMPORTING is_rec  TYPE ty_record
      EXPORTING ev_date TYPE d
                ev_name TYPE ty_result-customer_name.

    METHODS change_reference
      IMPORTING is_rec    TYPE ty_record
                iv_commit TYPE abap_bool
      CHANGING  cs_result TYPE ty_result.
ENDCLASS.


CLASS zcl_je_ref_upl_api IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    " F9 test only - the app passes the uploaded Excel rows through Execute.
    " >>> CHANGE: test documents. This REALLY updates the documents.
    DATA(lt_results) = process(
      it_records = VALUE #(
        ( document_number = '1500000173' company_code = '1000' fiscal_year = '2026' reference_id = 'TEST REF 01' )
        ( document_number = '1500'       company_code = '1000' fiscal_year = '2026' reference_id = 'MUST FAIL'   ) )
      iv_commit  = abap_true ).

    out->write( lt_results ).
  ENDMETHOD.


  METHOD process.
    LOOP AT it_records INTO DATA(ls_rec).
      DATA(ls_result) = VALUE ty_result(
        record_uuid = ls_rec-record_uuid
        batch_id    = |{ sy-tabix WIDTH = 5 ALIGN = RIGHT PAD = '0' }| ).

      " ---- Mandatory values ----
      IF ls_rec-document_number IS INITIAL
         OR ls_rec-company_code IS INITIAL
         OR ls_rec-fiscal_year  IS INITIAL
         OR ls_rec-reference_id IS INITIAL.
        ls_result-status  = c_status_error.
        ls_result-message = 'Mandatory value missing - not updated'.
        APPEND ls_result TO rt_results.
        CONTINUE.
      ENDIF.

      " 1500 -> 0000001500
      ls_rec-document_number = |{ ls_rec-document_number ALPHA = IN }|.

      " ---- Document must exist (also fills date / BP name) ----
      lookup( EXPORTING is_rec  = ls_rec
              IMPORTING ev_date = ls_result-document_date
                        ev_name = ls_result-customer_name ).

      IF ls_result-document_date IS INITIAL.
        ls_result-status  = c_status_error.
        ls_result-message = |Journal entry { ls_rec-document_number }/{ ls_rec-company_code }/{ ls_rec-fiscal_year } not found|.
        APPEND ls_result TO rt_results.
        CONTINUE.
      ENDIF.

      change_reference( EXPORTING is_rec    = ls_rec
                                  iv_commit = iv_commit
                        CHANGING  cs_result = ls_result ).

      APPEND ls_result TO rt_results.
    ENDLOOP.
  ENDMETHOD.


  METHOD lookup.
    CLEAR: ev_date, ev_name.

    SELECT SINGLE DocumentDate
      FROM i_journalentry
      WHERE CompanyCode        = @is_rec-company_code
        AND FiscalYear         = @is_rec-fiscal_year
        AND AccountingDocument = @is_rec-document_number
      INTO @ev_date.

    SELECT SINGLE Supplier, Customer
      FROM i_journalentryitem
      WHERE CompanyCode        = @is_rec-company_code
        AND FiscalYear         = @is_rec-fiscal_year
        AND AccountingDocument = @is_rec-document_number
        AND ( Supplier <> @space OR Customer <> @space )
      INTO @DATA(ls_bp).

    IF sy-subrc = 0.
      IF ls_bp-Supplier IS NOT INITIAL.
        SELECT SINGLE SupplierName
          FROM i_supplier
          WHERE Supplier = @ls_bp-Supplier
          INTO @ev_name.
      ELSE.
        SELECT SINGLE CustomerName
          FROM i_customer
          WHERE Customer = @ls_bp-Customer
          INTO @ev_name.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD change_reference.
    DATA lt_je  TYPE TABLE FOR ACTION IMPORT i_journalentrytp~change.
    DATA lv_msg TYPE string.

    APPEND INITIAL LINE TO lt_je ASSIGNING FIELD-SYMBOL(<je>).

    " Only DocumentReferenceID is changed; header text stays as it is
    DATA ls_header_control LIKE <je>-%param-%control.
    ls_header_control-documentreferenceid = if_abap_behv=>mk-on.

    <je>-accountingdocument = is_rec-document_number.
<je>-fiscalyear         = is_rec-fiscal_year.
<je>-companycode        = is_rec-company_code.
<je>-%param = VALUE #( documentreferenceid = is_rec-reference_id
                           %control            = ls_header_control ).

    MODIFY ENTITIES OF i_journalentrytp
      ENTITY journalentry
      EXECUTE change FROM lt_je
      FAILED   DATA(ls_failed)
      REPORTED DATA(ls_reported).

    " ---- Rejected by I_JournalEntryTP ----
    IF ls_failed IS NOT INITIAL.
      LOOP AT ls_reported-journalentry INTO DATA(ls_rep).
        IF ls_rep-%msg IS BOUND.
          lv_msg = |{ lv_msg } { ls_rep-%msg->if_message~get_text( ) }|.
        ENDIF.
      ENDLOOP.

      " ROLLBACK ENTITIES is not allowed inside a RAP handler
      IF iv_commit = abap_true.
        ROLLBACK ENTITIES.
      ENDIF.

      cs_result-status  = c_status_error.
      cs_result-message = COND #( WHEN lv_msg IS INITIAL THEN 'Change rejected by I_JournalEntryTP'
                                  ELSE condense( lv_msg ) ).
      RETURN.
    ENDIF.

    " ---- Inside RAP: saved together with the upload ----
    IF iv_commit = abap_false.
      cs_result-status  = c_status_updated.
      cs_result-message = |Reference updated to { is_rec-reference_id }|.
      RETURN.
    ENDIF.

    " ---- Standalone: save this one document ----
    COMMIT ENTITIES BEGIN
      RESPONSE OF i_journalentrytp
      FAILED   DATA(ls_commit_failed)
      REPORTED DATA(ls_commit_reported).
    DATA(lv_rc) = sy-subrc.
    COMMIT ENTITIES END.

    IF lv_rc = 0 AND ls_commit_failed IS INITIAL.
      cs_result-status  = c_status_updated.
      cs_result-message = |Reference updated to { is_rec-reference_id }|.
    ELSE.
      LOOP AT ls_commit_reported-journalentry INTO DATA(ls_crep).
        IF ls_crep-%msg IS BOUND.
          lv_msg = |{ lv_msg } { ls_crep-%msg->if_message~get_text( ) }|.
        ENDIF.
      ENDLOOP.
      cs_result-status  = c_status_error.
      cs_result-message = COND #( WHEN lv_msg IS INITIAL THEN 'Save failed'
                                  ELSE condense( lv_msg ) ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
