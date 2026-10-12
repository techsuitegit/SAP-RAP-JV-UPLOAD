CLASS zcl_je_ref_upl_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_batch_size TYPE i VALUE 10.

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

    METHODS process
      IMPORTING it_records        TYPE tt_record
      RETURNING VALUE(rt_results) TYPE tt_result.

  PRIVATE SECTION.

    CONSTANTS c_sender TYPE string VALUE 'X1O'.

    CONSTANTS c_path TYPE string
      VALUE '/sap/bc/srt/scs_ext/sap/journalentrybulkchangerequest_'.

    CONSTANTS c_action TYPE string
      VALUE 'http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkChangeRequest_In/JournalEntryBulkChangeRequest_InRequest'.

    " outbound communication of the new package
    CONSTANTS c_comm_scenario  TYPE string VALUE 'ZJE_REF_UPL_CSCEN'.
    CONSTANTS c_service_id     TYPE string VALUE 'ZJE_REF_UPL_OS_REST'.
    CONSTANTS c_comm_system_id TYPE string VALUE 'JEU_SELF'.

    " abap_true only when this app runs in the same tenant as the documents
    CONSTANTS c_check_existing TYPE abap_bool VALUE abap_false.

    METHODS lookup
      IMPORTING is_rec  TYPE ty_record
      EXPORTING ev_date TYPE d
                ev_name TYPE ty_result-customer_name.

    METHODS build_xml
      IMPORTING it_batch      TYPE tt_record
                iv_msgid      TYPE string
                iv_hid        TYPE string
      RETURNING VALUE(rv_xml) TYPE string.

    METHODS send_batch
      IMPORTING it_batch          TYPE tt_record
                iv_batch_id       TYPE ty_result-batch_id
      RETURNING VALUE(rt_results) TYPE tt_result.

ENDCLASS.


CLASS zcl_je_ref_upl_api IMPLEMENTATION.

  METHOD process.
    DATA(lv_total) = lines( it_records ).
    DATA(lv_from)  = 1.
    DATA(lv_batch) = 0.

    WHILE lv_from <= lv_total.
      lv_batch += 1.
      DATA(lv_to) = nmin( val1 = lv_from + c_batch_size - 1
                          val2 = lv_total ).

      DATA(lt_batch) = VALUE tt_record(
        FOR i = lv_from THEN i + 1 UNTIL i > lv_to
          ( it_records[ i ] ) ).

      APPEND LINES OF send_batch(
        it_batch    = lt_batch
        iv_batch_id = |{ lv_batch WIDTH = 3 ALIGN = RIGHT PAD = '0' }|
      ) TO rt_results.

      lv_from = lv_to + 1.
    ENDWHILE.
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


  METHOD build_xml.
    GET TIME STAMP FIELD DATA(lv_ts).
    DATA(lv_now) = |{ lv_ts TIMESTAMP = ISO }Z|.

    rv_xml =
      |<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" | &&
      |xmlns:wsa="http://www.w3.org/2005/08/addressing">| &&
      |<soapenv:Header>| &&
      |<wsa:MessageID>uuid:{ iv_msgid }</wsa:MessageID>| &&
      |<wsa:Action>{ c_action }</wsa:Action>| &&
      |</soapenv:Header><soapenv:Body>| &&
      |<sfin:JournalEntryBulkChangeRequestMessage xmlns:sfin="http://sap.com/xi/SAPSCORE/SFIN">| &&
      |<MessageHeader><ID>{ iv_hid }</ID>| &&
      |<CreationDateTime>{ lv_now }</CreationDateTime>| &&
      |<SenderBusinessSystemID>{ c_sender }</SenderBusinessSystemID></MessageHeader>|.

    LOOP AT it_batch INTO DATA(ls_rec).
      DATA(lv_n) = sy-tabix.
      rv_xml = rv_xml &&
        |<JournalEntryHeader>| &&
        |<MessageHeader><ID>{ iv_hid }_{ lv_n WIDTH = 3 ALIGN = RIGHT PAD = '0' }</ID>| &&
        |<CreationDateTime>{ lv_now }</CreationDateTime></MessageHeader>| &&
        |<HeaderKey>| &&
        |<AccountingDocument>{ ls_rec-document_number }</AccountingDocument>| &&
        |<CompanyCode>{ ls_rec-company_code }</CompanyCode>| &&
        |<FiscalYear>{ ls_rec-fiscal_year }</FiscalYear>| &&
        |</HeaderKey>| &&
        |<DocumentReferenceIDChange>| &&
        |<DocumentReferenceID>{ escape( val = ls_rec-reference_id format = cl_abap_format=>e_xml_text ) }</DocumentReferenceID>| &&
        |<FieldValueChangeIsRequested>true</FieldValueChangeIsRequested>| &&
        |</DocumentReferenceIDChange>| &&
        |</JournalEntryHeader>|.
    ENDLOOP.

    rv_xml = rv_xml &&
      |</sfin:JournalEntryBulkChangeRequestMessage></soapenv:Body></soapenv:Envelope>|.
  ENDMETHOD.


  METHOD send_batch.
    DATA lv_status  TYPE ty_result-status.
    DATA lv_message TYPE ty_result-message.
    DATA lv_hid     TYPE string.
    DATA lt_valid   TYPE tt_record.

    rt_results = VALUE #( FOR r IN it_batch
                          ( record_uuid = r-record_uuid
                            batch_id    = iv_batch_id ) ).

    " ---- check before sending ----
    LOOP AT it_batch INTO DATA(ls_rec).
      DATA(lv_idx) = sy-tabix.
      lookup( EXPORTING is_rec  = ls_rec
              IMPORTING ev_date = DATA(lv_d)
                        ev_name = DATA(lv_name) ).
      rt_results[ lv_idx ]-document_date = lv_d.
      rt_results[ lv_idx ]-customer_name = lv_name.

      DATA(lv_err) = VALUE string( ).
      IF ls_rec-document_number IS INITIAL OR ls_rec-company_code IS INITIAL
         OR ls_rec-fiscal_year IS INITIAL OR ls_rec-fiscal_year = '0000'
         OR ls_rec-reference_id IS INITIAL.
        lv_err = 'Mandatory value missing - not sent'.
      ELSEIF c_check_existing = abap_true AND lv_d IS INITIAL.
        lv_err = 'Document not found - not sent'.
      ENDIF.

      IF lv_err IS NOT INITIAL.
        rt_results[ lv_idx ]-status  = 'ERROR'.
        rt_results[ lv_idx ]-message = lv_err.
      ELSE.
        APPEND ls_rec TO lt_valid.
      ENDIF.
    ENDLOOP.

    IF lt_valid IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        " ID of this request (the ID used in Message Dashboard)
        GET TIME STAMP FIELD DATA(lv_ts).
        lv_hid = |JE{ condense( |{ lv_ts }| ) }B{ iv_batch_id }|.

        " new unique WS-Addressing message id for every request
        DATA(lv_c32) = to_lower(
          cl_uuid_factory=>create_system_uuid( )->create_uuid_c32( ) ).
        DATA(lv_msgid) =
          |{ substring( val = lv_c32 off = 0  len = 8 ) }-| &&
          |{ substring( val = lv_c32 off = 8  len = 4 ) }-| &&
          |{ substring( val = lv_c32 off = 12 len = 4 ) }-| &&
          |{ substring( val = lv_c32 off = 16 len = 4 ) }-| &&
          |{ substring( val = lv_c32 off = 20 len = 12 ) }|.

        DATA(lv_xml) = build_xml( it_batch = lt_valid
                                  iv_msgid = lv_msgid
                                  iv_hid   = lv_hid ).

        DATA(lo_dest) = cl_http_destination_provider=>create_by_comm_arrangement(
                          comm_scenario  = CONV #( c_comm_scenario )
                          service_id     = CONV #( c_service_id )
                          comm_system_id = CONV #( c_comm_system_id ) ).

        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req)    = lo_client->get_http_request( ).
        lo_req->set_uri_path( i_uri_path = c_path ).
        lo_req->set_header_field( i_name = 'Content-Type' i_value = 'text/xml; charset=utf-8' ).
        lo_req->set_header_field( i_name = 'SOAPAction'   i_value = c_action ).
        lo_req->set_text( lv_xml ).

        DATA(lo_resp)   = lo_client->execute( if_web_http_client=>post ).
        DATA(ls_status) = lo_resp->get_status( ).
        DATA(lv_text)   = lo_resp->get_text( ).
        lo_client->close( ).

        DATA(lv_is_html) = xsdbool( to_lower( lv_text ) CS '<html' ).

        IF lv_is_html = abap_true.
          lv_status  = 'ERROR'.
          lv_message = |HTTP { ls_status-code }: login page returned - check user, password or path|.
        ELSEIF ls_status-code >= 200 AND ls_status-code < 300.
          lv_status  = 'SUBMITTED'.
          lv_message = |Accepted for processing. Result: Message Dashboard or check the document|.
        ELSE.
          lv_status  = 'ERROR'.
          lv_message = |HTTP { ls_status-code } { ls_status-reason }: { substring(
                         val = lv_text
                         len = nmin( val1 = strlen( lv_text ) val2 = 150 ) ) }|.
        ENDIF.

      CATCH cx_http_dest_provider_error
            cx_web_http_client_error
            cx_uuid_error INTO DATA(lx).
        lv_status  = 'ERROR'.
        lv_message = |{ cl_abap_typedescr=>describe_by_object_ref( lx )->get_relative_name( ) }: { lx->get_text( ) }|.
    ENDTRY.

    " rows that passed the check get the result of the call
    LOOP AT rt_results ASSIGNING FIELD-SYMBOL(<res>) WHERE status IS INITIAL.
      <res>-message_id = lv_hid.
      <res>-status     = lv_status.
      <res>-message    = lv_message.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
