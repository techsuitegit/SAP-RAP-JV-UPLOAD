@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'JE Upload - Rows'
define view entity ZI_JE_REF_UPL_ITM
  as select from zje_ref_upl_itm
  association to parent ZI_JE_REF_UPL_HDR as _Upload
    on $projection.UploadUUID = _Upload.UploadUUID
{
  key item_uuid       as ItemUUID,
      upload_uuid     as UploadUUID,
      document_number as DocumentNumber,
      fiscal_year     as FiscalYear,
      company_code    as CompanyCode,
      reference_id    as ReferenceID,
      document_date   as DocumentDate,
      customer_name   as CustomerName,
      batch_id        as BatchID,
      message_id      as MessageID,
      status          as Status,
      message         as Message,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      last_changed_at as LocalLastChangedAt,

      _Upload
}
