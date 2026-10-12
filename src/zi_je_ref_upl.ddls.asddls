@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'JE Reference Update - Interface'
define root view entity ZI_JE_REF_UPL
  as select from zje_ref_upd
{
  key record_uuid     as RecordUUID,
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
      @Semantics.user.createdBy: true
      created_by      as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at      as CreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      changed_by      as ChangedBy,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      changed_at      as ChangedAt,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at as LastChangedAt
}
