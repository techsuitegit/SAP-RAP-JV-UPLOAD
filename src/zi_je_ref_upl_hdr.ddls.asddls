@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'JE Upload - Header'
define root view entity ZI_JE_REF_UPL_HDR
  as select from zje_ref_upl_hdr
  composition [0..*] of ZI_JE_REF_UPL_ITM as _Items
{
  key upload_uuid      as UploadUUID,
      status           as Status,
      message          as Message,
      hide_excel       as HideExcel,
      hide_result      as HideResult,

      @Semantics.largeObject: {
        mimeType                    : 'MimeType',
        fileName                    : 'FileName',
        contentDispositionPreference: #ATTACHMENT,
        acceptableMimeTypes         : [ 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ]
      }
      excel_attachment as ExcelAttachment,
      @Semantics.mimeType: true
      mime_type        as MimeType,
      file_name        as FileName,

      @Semantics.user.createdBy: true
      created_by       as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at       as CreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      last_changed_by  as LastChangedBy,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      last_changed_at  as LocalLastChangedAt,
      @Semantics.systemDateTime.lastChangedAt: true
      lastchanged      as LastChangedAt,

      _Items
}
