@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'JE Upload - Header'
@Metadata.allowExtensions: true
define root view entity ZC_JE_REF_UPL_HDR
  provider contract transactional_query
  as projection on ZI_JE_REF_UPL_HDR
{
  key UploadUUID,
      Status,
      Message,
      HideExcel,
      HideResult,

      @Semantics.largeObject: {
        mimeType                    : 'MimeType',
        fileName                    : 'FileName',
        contentDispositionPreference: #ATTACHMENT,
        acceptableMimeTypes         : [ 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ]
      }
      ExcelAttachment,
      @Semantics.mimeType: true
      MimeType,
      FileName,

      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LocalLastChangedAt,
      LastChangedAt,

       _Items : redirected to composition child ZC_JE_REF_UPL_ITM
}
