@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'JE Reference Update - Projection'
@Metadata.allowExtensions: true
define root view entity ZC_JE_REF_UPL
  provider contract transactional_query
  as projection on ZI_JE_REF_UPL
{
  key RecordUUID,
      DocumentNumber,
      FiscalYear,
      CompanyCode,
      ReferenceID,
      DocumentDate,
      CustomerName,
      BatchID,
      MessageID,
      Status,
      Message,
      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      LastChangedAt
}
