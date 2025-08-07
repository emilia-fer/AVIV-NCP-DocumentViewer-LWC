/* ============================================================================
 *  labels.js – centralises every CustomLabel import for S3DocViewer
 * ----------------------------------------------------------------------------
 *  – Keeps the main component lean
 *  – Easy to maintain / extend (only touch this file when you add a label)
 * ========================================================================== */

import LABEL_DOCUMENTS              from '@salesforce/label/c.Documents';
import LABEL_UPLOAD_FILE            from '@salesforce/label/c.Upload_File';
import LABEL_UPLOAD_S3_DOCUMENT     from '@salesforce/label/c.Upload_S3_Document';
import LABEL_PREVIEW                from '@salesforce/label/c.Preview';
import LABEL_REMOVE_SELECTED_FILE   from '@salesforce/label/c.Remove_Selected_File';
import LABEL_REMOVE                 from '@salesforce/label/c.Remove';
import LABEL_FILE_NAME              from '@salesforce/label/c.File_Name';
import LABEL_TYPE_LABEL             from '@salesforce/label/c.Type_Label';
import LABEL_SIZE_LABEL             from '@salesforce/label/c.Size_Label';
import LABEL_DESCRIPTION_LABEL      from '@salesforce/label/c.Description_Label';
import LABEL_CREATION_DATE          from '@salesforce/label/c.Creation_Date';
import LABEL_LINK_OPPORTUNITY       from '@salesforce/label/c.Link_Opportunity';
import LABEL_LINK_CASE              from '@salesforce/label/c.Link_Case';
import LABEL_LINK_CONTACT           from '@salesforce/label/c.Link_Contact';
import LABEL_LINK_TASK              from '@salesforce/label/c.Link_Task';
import LABEL_CANCEL                 from '@salesforce/label/c.Cancel';
import LABEL_UPLOAD                 from '@salesforce/label/c.Upload';
import LABEL_ADVANCED_FILTERS       from '@salesforce/label/c.Advanced_Filters';
import LABEL_SEARCH_FILE_NAME       from '@salesforce/label/c.Search_File_Name';
import LABEL_SEARCH_DESCRIPTION     from '@salesforce/label/c.Search_Description';
import LABEL_DATE_GREATER_EQUAL     from '@salesforce/label/c.Date_GreaterEqual';
import LABEL_DATE_LESS_EQUAL        from '@salesforce/label/c.Date_LessEqual';
import LABEL_SIZE_GREATER_EQUAL     from '@salesforce/label/c.Size_GreaterEqual';
import LABEL_SIZE_LESS_EQUAL        from '@salesforce/label/c.Size_LessEqual';
import LABEL_ROWS                   from '@salesforce/label/c.Rows';
import LABEL_PREVIOUS               from '@salesforce/label/c.Previous';
import LABEL_NEXT                   from '@salesforce/label/c.Next';
import LABEL_BACK                   from '@salesforce/label/c.Back';
import LABEL_DOWNLOAD               from '@salesforce/label/c.Download';
import LABEL_LOADING                from '@salesforce/label/c.Loading';
import LABEL_PREVIEW_NOT_SUPPORTED  from '@salesforce/label/c.Preview_Not_Supported';
import LABEL_ATTACHMENTS            from '@salesforce/label/c.Attachments';
import LABEL_CLOSE                  from '@salesforce/label/c.Close';
import LABEL_CONTAINS               from '@salesforce/label/c.Contains';
import LABEL_STARTS_WITH            from '@salesforce/label/c.Starts_With';
import LABEL_MORE_COLUMNS           from '@salesforce/label/c.More_Columns';
import LABEL_LESS_COLUMNS           from '@salesforce/label/c.Less_Columns';
import LABEL_ALL_TYPES              from '@salesforce/label/c.All_Types';
import LABEL_SAVED                  from '@salesforce/label/c.Saved';
import LABEL_SAVE_FAILED            from '@salesforce/label/c.Save_Failed';
import LABEL_UPLOADED_TITLE         from '@salesforce/label/c.Uploaded_Title';
import LABEL_UPLOAD_FAILED          from '@salesforce/label/c.Upload_Failed';
import LABEL_LOAD_ERROR             from '@salesforce/label/c.Load_Error';
import LABEL_DOWNLOAD_FAILED        from '@salesforce/label/c.Download_Failed';
import LABEL_NO_FILE_SELECTED       from '@salesforce/label/c.No_File_Selected';
import LABEL_ACCOUNT_COL            from '@salesforce/label/c.Account_Col';
import LABEL_CASE_COL               from '@salesforce/label/c.Case_Col';
import LABEL_CONTACT_COL            from '@salesforce/label/c.Contact_Col';
import LABEL_FILE_NOT_FOUND         from '@salesforce/label/c.File_Not_Found';
import LABEL_OPPORTUNITY_COL        from '@salesforce/label/c.Opportunity_Col';

/* ---------- bundle & export ---------- */
const LABELS = {
    documents          : LABEL_DOCUMENTS,
    uploadFile         : LABEL_UPLOAD_FILE,
    uploadS3Document   : LABEL_UPLOAD_S3_DOCUMENT,
    preview            : LABEL_PREVIEW,
    removeSelectedFile : LABEL_REMOVE_SELECTED_FILE,
    remove             : LABEL_REMOVE,
    fileName           : LABEL_FILE_NAME,
    typeLabel          : LABEL_TYPE_LABEL,
    sizeLabel          : LABEL_SIZE_LABEL,
    descriptionLabel   : LABEL_DESCRIPTION_LABEL,
    creationDate       : LABEL_CREATION_DATE,
    linkOpportunity    : LABEL_LINK_OPPORTUNITY,
    linkCase           : LABEL_LINK_CASE,
    linkContact        : LABEL_LINK_CONTACT,
    linkTask           : LABEL_LINK_TASK,
    cancel             : LABEL_CANCEL,
    upload             : LABEL_UPLOAD,
    advancedFilters    : LABEL_ADVANCED_FILTERS,
    searchFileName     : LABEL_SEARCH_FILE_NAME,
    searchDescription  : LABEL_SEARCH_DESCRIPTION,
    dateGE             : LABEL_DATE_GREATER_EQUAL,
    dateLE             : LABEL_DATE_LESS_EQUAL,
    sizeGE             : LABEL_SIZE_GREATER_EQUAL,
    sizeLE             : LABEL_SIZE_LESS_EQUAL,
    rows               : LABEL_ROWS,
    previous           : LABEL_PREVIOUS,
    next               : LABEL_NEXT,
    back               : LABEL_BACK,
    download           : LABEL_DOWNLOAD,
    loading            : LABEL_LOADING,
    previewNotSupported: LABEL_PREVIEW_NOT_SUPPORTED,
    attachments        : LABEL_ATTACHMENTS,
    close              : LABEL_CLOSE,
    contains           : LABEL_CONTAINS,
    startsWith         : LABEL_STARTS_WITH,
    moreColumns        : LABEL_MORE_COLUMNS,
    lessColumns        : LABEL_LESS_COLUMNS,
    allTypes           : LABEL_ALL_TYPES,
    saved              : LABEL_SAVED,
    saveFailed         : LABEL_SAVE_FAILED,
    uploadedTitle      : LABEL_UPLOADED_TITLE,
    uploadFailed       : LABEL_UPLOAD_FAILED,
    loadError          : LABEL_LOAD_ERROR,
    downloadFailed     : LABEL_DOWNLOAD_FAILED,
    noFileSelected     : LABEL_NO_FILE_SELECTED,
    accountCol         : LABEL_ACCOUNT_COL,
    opportunityCol     : LABEL_OPPORTUNITY_COL,
    contactCol         : LABEL_CONTACT_COL,
    caseCol            : LABEL_CASE_COL,
    fileNotFound       : LABEL_FILE_NOT_FOUND
};

export default LABELS;
