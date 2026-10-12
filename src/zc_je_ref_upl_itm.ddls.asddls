@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'JE Upload - Rows'
@Metadata.allowExtensions: true
define view entity ZC_JE_REF_UPL_ITM
  as projection on ZI_JE_REF_UPL_ITM
{
  key ItemUUID,
      UploadUUID,
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
      LocalLastChangedAt,

      _Upload : redirected to parent ZC_JE_REF_UPL_HDR
}
