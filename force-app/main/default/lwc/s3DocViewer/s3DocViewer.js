/* ============================================================================
 *  S3 Doc Viewer LWC 
 *  - Lists S3_File__c records linked to the current record (Account, Case…)
 *  - Inline edit of Description__c
 *  - Previews images / text / PDF / DOCX locally; .msg via AWS Lambda → HTML
 *  - Optional lookup columns toggled by “More / Less”
 *  - Filters, sorting, paging
 *  SECURITY NOTES:                                                     
 *  - Callouts ONLY through Named Credential (“MsgToEmlAPI”) in Apex.
 *  - All external URLs (attachments / blobs) use createObjectURL → _blank.
 *  - Inline HTML from Lambda is sanitised there; here we embed images only
 *    when cid ≤ 1 MB to avoid huge data-URIs.
 * --------------------------------------------------------------------------*/

import { LightningElement, api, wire, track } from 'lwc';
import getDocs   from '@salesforce/apex/S3DocService.getDocs';
import getFile   from '@salesforce/apex/S3DocService.getFile';
import getRelatedOpportunities from'@salesforce/apex/S3DocService.relatedOpportunities';
import getRelatedCases from '@salesforce/apex/S3DocService.relatedCases';
import getRelatedContacts from '@salesforce/apex/S3DocService.relatedContacts';
import updateDescriptions from'@salesforce/apex/S3DocService.updateDescriptions';
import createS3File from '@salesforce/apex/S3FileCreator.create';
import getPresignedUrl from '@salesforce/apex/S3PresignService.getPresignedUrl';
import getPresignedGetUrl from '@salesforce/apex/S3PresignService.getPresignedGetUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fetchMsg from '@salesforce/apex/MsgPreviewService.fetch';
import { refreshApex } from '@salesforce/apex';

/* ---------- i18n / Custom Labels ---------- */
import LABELS from './labels';

const {
    fileName:        LABEL_FILE_NAME,
    sizeLabel:       LABEL_SIZE_LABEL,
    typeLabel:       LABEL_TYPE_LABEL,
    creationDate:    LABEL_CREATION_DATE,
    descriptionLabel:LABEL_DESCRIPTION_LABEL
} = LABELS;

/* ---------- MIME type mapping ---------- */
const mapMime = (mime) => {
    if (!mime) return '';
    if (mime.startsWith('image/') || mime.startsWith('img/'))  return 'image';
    if (['png', 'jpg', 'jpeg', 'gif', 'bmp', 'tif', 'tiff'].includes(mime)) return 'image';
    if (mime === 'application/pdf') return 'pdf';
    if (mime === 'message/rfc822') return 'eml'
    if (mime.startsWith('text/'))   return 'text';
    if (mime === 'application/vnd.ms-outlook') return 'msg';
    if (mime === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') return 'docx';
    if (mime.startsWith('application/vnd')) return 'office doc';
    return mime; // fallback
};



/* ---------- Constants ---------- */
const currentYear   = new Date().getFullYear();
const firstYear     = 2015;

/* ---------- Helpers ---------- */

/** replace cid: images in HTML with data URIs */
function embedImages(html, attachments){
    attachments.forEach(att => {
        if (!att.contentId) return;
        html = html.replace(
            new RegExp(`cid:${att.contentId}`, 'gi'),
            `data:${att.contentType};base64,${att.data}`
        );
    });
    return html;
}


/**
 * Robust .eml → { html, attachments[] }
 *  – keeps <style> tags
 *  – resolves cid:… images
 *  – understands base64 *and* quoted-printable
 *  – supports RFC-2231 encoded filenames  (name*=utf-8''…)
 */
function parseEml(base64Source) {

    /* ------------ helpers ------------------------------------------------ */
    const qpDecode = s => s
        .replace(/=(\r?\n)/g, '')                         // soft break
        .replace(/=([A-Fa-f0-9]{2})/g,
                 (_,h)=>String.fromCharCode(parseInt(h,16)));

    const bodyDecode = (enc, raw) => {
        enc = (enc||'').toLowerCase();
        if (enc === 'base64') {
            const txt   = raw.replace(/\s+/g,'');
            const pad   = txt.length % 4;
            const fixed = pad ? txt + '='.repeat(4-pad) : txt;
            const bytes = Uint8Array.from(atob(fixed), c => c.charCodeAt(0));
            return new TextDecoder('utf-8').decode(bytes);
        }
        if (enc === 'quoted-printable') return qpDecode(raw);
        return raw;
    };

    /* RFC-2231 filename*= → decode UTF-8 and %XX */
    const decode2231 = str => {
        // filename* may look like:  utf-8''some%20file.pdf
        const match = str.match(/^[^']*'[^']*'(.+)/);
        return match ? decodeURIComponent(match[1]) : str.replace(/["']/g,'');
    };

    /* ------------- recursive multipart parser --------------------------- */
    function walk(raw) {

        const [hdrRaw, ...rest] = raw.split(/\r?\n\r?\n/);
        if (!rest.length) return { html:'', styles:'', text:'', attachments:[] };

        const body      = rest.join('\r\n\r\n').trim();
        const cType     = (hdrRaw.match(/Content-Type:\s*([^;\r\n]+)/i)||[, ''])[1];
        const boundary  = (hdrRaw.match(/boundary="*([^"\r\n;]+)"*/i)||[, ''])[1];
        const cte       = (hdrRaw.match(/Content-Transfer-Encoding:\s*([^\r\n]+)/i)||[, ''])[1];
        const cid       = (hdrRaw.match(/Content-ID:\s*<([^>]+)>/i)||[, ''])[1];
        const dispo     = (hdrRaw.match(/Content-Disposition:\s*([^;\r\n]+)/i)||[, ''])[1];

        /* ----- filename / name (RFC-2231 aware) ------------------------- */
        let fname =  (hdrRaw.match(/name\*=\s*([^;\r\n]+)/i) ||
                      hdrRaw.match(/filename\*=\s*([^;\r\n]+)/i) );
        fname   =  fname ? decode2231(fname[1])
               : (hdrRaw.match(/name="([^"]+)"/i) ||
                  hdrRaw.match(/filename="([^"]+)"/i) || [, ''])[1];

        /* ----- multipart: recurse into sub-parts ------------------------ */
        if (/multipart\//i.test(cType) && boundary) {
            let html='', styles='', text='', atts=[];
            body.split(new RegExp(`--${boundary}(--)?(?:\r?\n|$)`,'g'))
                .filter(Boolean).forEach(p=>{
                    if (p.startsWith('--')) return;          // closing boundary
                    const sub = walk(p.trim());
                    if (sub.html)   html   = sub.html;
                    if (sub.styles) styles = sub.styles;
                    if (sub.text)   text   = sub.text;
                    atts = atts.concat(sub.attachments);
                });
            return { html, styles, text, attachments:atts };
        }

        /* ----- leaf ------------------------------------------------------ */
        if (/text\/html/i.test(cType)){
            const decoded = bodyDecode(cte, body);
            const styles  = (decoded.match(/<style[\s\S]*?<\/style>/gi)||[])
                                .join('\n');
            const clean   = decoded.replace(/<style[\s\S]*?<\/style>/gi,'');
            return { html:clean, styles, text:'', attachments:[] };
        }

        if (/text\/plain/i.test(cType)){
            return { text:bodyDecode(cte, body), html:'', styles:'', attachments:[] };
        }

        /* ----- attachment (inline or regular) --------------------------- */
        if (fname || cid || /attachment/i.test(dispo)){
            return { html:'', styles:'', text:'',
                     attachments:[{
                         filename   : fname || cid || 'unnamed',
                         contentId  : cid   || null,
                         contentType: cType || 'application/octet-stream',
                         data       : body.replace(/\s+/g,'')
                     }] };
        }

        return { html:'', styles:'', text:'', attachments:[] };
    }

    /* ------------- drive the parser & assemble result ------------------- */
    const emlText = atob(base64Source);
    const root    = walk(emlText);

    const htmlOut = root.html
        ? `${root.styles}\n${root.html}`
        : `<pre>${(root.text || emlText).replace(/[&<>]/g,
            ch=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[ch]))}</pre>`;

    return { html: htmlOut, attachments: root.attachments };
}


/** Extract object prefix, e.g. '001' for Account, '500' Case */
function hostKey(id) {
    return (id && id.length >= 3) ? id.substr(0, 3) : '';
}
const PREFIX_MAP = {
    '001':'Account', '006':'Opportunity', '003':'Contact', '500':'Case'
};

/* ---------- Column Definitions (fixed always shown) ---------- */
const nameCol = {
    label: LABEL_FILE_NAME,
    fieldName:'Name',
    type:'button',
    sortable:true,
    typeAttributes:{ label:{ fieldName:'Name' }, name:'preview', variant:'base' },
    initialWidth:300
};
const sizeCol = { label: LABEL_SIZE_LABEL, fieldName:'Size__c', type:'number', sortable:true, initialWidth:130 };
const typeCol = { label: LABEL_TYPE_LABEL, fieldName:'DisplayType', type:'text', sortable:true, initialWidth:90 };
const yearCol = { label: LABEL_CREATION_DATE, fieldName:'Creation_Date__c', type:'date', sortable:true, initialWidth:80 };

/* ---------- Context Helper ---------- */
function resolveContext(id){ return PREFIX_MAP[id?.substr(0,3)] || 'Other'; }

export default class S3DocViewer extends LightningElement {
    @api recordId;

    labels = LABELS;

    /* ---------------- State / Tracked Vars ---------------- */
    @track docs;
    @track error;
    @track isLoading = true;
    @track sortBy        = 'Name';     // default sort column
    @track sortDirection = 'asc';
    @track searchKey   = '';
    @track typeFilter  = 'all';
    @track yearFrom;
    @track yearTo;
    @track dateFrom;   // yyyy‑mm‑dd strings
    @track dateTo;
    @track sizeMin;
    @track sizeMax;
    @track typeOptions = [{ label: this.labels.allTypes, value: 'all' }];
    @track showFilters = false;
    @track draftValues = [];
    @track pageSize   = 20;
    @track pageNumber = 1;
    @track nameKey  = '';
    @track nameMode = 'contains';   // default
    @track descKey  = '';
    @track descMode = 'contains';
    @track previewError; 
    @track previewHtml;           
    @track previewAttachments = []; 
    @track dynamicColumns = [];     // generated based on data
    @track showExtended   = false;   // More / Less toggle
    @track optionalCols   = [];      // lookup columns for this context
    @track contextObject;   

    /* ------------- preview state ------------- */
    @track previewName;
    @track previewText;
    @track previewSrc;
    @track previewMime;

     /* ------------- input -------- */

    @track showModal = false;
    @track selectedFile;
    @track newDescription = '';
    @track newCreationYear = (new Date()).getFullYear();
    @track newCreationDate = new Date().toISOString().slice(0,10);
    @track newOpportunityId;
    @track newCaseId;
    @track newContactId;
    @track newTaskId; 
    @track isUploading = false;
    @track uploadMessage = '';

    @track opportunityOptions = [];
    @track caseOptions = [];
    @track contactOptions = [];
    @track isUploading = false;
    @track uploadMessage = '';
    @track editFileName = '';
    @track previewImageUrl = null;
    @track previewFileUrl = null;
    @track selectedFile    = null;
    @track iconTone = 'slds-text-color_inverse'; // default to white

    /* ---------- upload-preview (modal) ---------- */
    @track showUploadPreview   = false;
    @track upMime              = '';       // mime of the file being previewed
    @track upSrc               = '';       // Blob-URL for pdf / docx …
    @track upHtml              = '';       // HTML for eml / msg
    @track upText              = '';       // plain-text fallback
    @track upError             = '';       // user-friendly error
    @track upAttachments       = [];       // [{name,url,type}, …] – for eml/msg
    
    
    /* ---------------- Non-reactive (used for revoking Blob URLs) ---------------- */
    pageRecordId = this.recordId;
    _blobUrl = undefined;

    /* ---------------- Options ---------------- */
    modeOptions = [
        { label: this.labels.contains,   value: 'contains' },
        { label: this.labels.startsWith, value: 'starts'   }
    ];


    yearOptions = Array.from(
        { length: currentYear - firstYear + 1 },
        (_, i) => {
            const y = firstYear + i;
            return { label: String(y), value: y };
        }
    );
    pageSizeOptions = [
        { label: '20',  value: 20 },
        { label: '50',  value: 50 },
        { label: '100', value: 100 }
    ];

    /* ---------- Lookups: column definitions (built once) ---------- */
    connectedCallback(){
        this.contextObject = resolveContext(this.recordId);

        // Define optional lookup columns only once (do NOT change key names)
        this.accountCol = {
            label:this.labels.accountCol,
            fieldName:'AccountUrl',
            type:'url',
            typeAttributes:{ label:{ fieldName:'AccountName' }, target:'_self' }
        };
        this.oppCol = {
            label: this.labels.opportunityCol,
            fieldName:'OpportunityUrl',
            type:'url',
            typeAttributes:{ label:{ fieldName:'OpportunityName' }, target:'_self' }
        };
        this.contactCol = {
            label: this.labels.contactCol,
            fieldName:'ContactUrl',
            type:'url',
            typeAttributes:{ label:{ fieldName:'ContactName' }, target:'_self' }
        };
        this.caseCol = {
            label: this.labels.caseCol,
            fieldName:'CaseUrl',
            type:'url',
            typeAttributes:{ label:{ fieldName:'CaseNumber' }, target:'_self' }
        };

        this.taskCol = {
            label        : 'Task',
            fieldName    : 'TaskUrl',
            type         : 'url',
            typeAttributes : { label  : { fieldName : 'TaskName' }, target : '_self' }
        };


        // Lookup logic based on context
        switch(this.contextObject){
            case 'Account':
                this.optionalCols = [ this.oppCol, this.contactCol, this.caseCol, this.taskCol ];
                break;
            case 'Opportunity':
            case 'Contact':
                this.optionalCols = [ this.caseCol ];
                break;
            case 'Case':
                this.optionalCols = [ this.oppCol ];
                break;
            default:
                this.optionalCols = [];
        }
    }

    /* ========================================================================
     * --------------------------- GETTERS / COMPUTED -------------------------
     * ===================================================================== */

    /** Is there data for any optional column in this page? */
    get hasVisibleOptionals() {
        if (!this.optionalCols?.length) return false;
        const start = (this.pageNumber - 1) * this.pageSize;
        const page  = this.filteredRows.slice(start, start + this.pageSize);

        return page.some(r =>
            this.optionalCols.some(c => {
                const base = c.fieldName.replace('Url','Name') || c.fieldName;
                return !!r[base];
            })
        );
    }

    get columns(){
        const descColDynamic = {
            label       : LABEL_DESCRIPTION_LABEL,
            fieldName   : 'Description__c',
            type        : 'text',
            editable    : true,
            initialWidth: this.showExtended ? 260 : 530
        };
        return this.showExtended
            ? [nameCol, sizeCol, typeCol, yearCol, descColDynamic, ...this.optionalCols]
            : [nameCol, sizeCol, typeCol, yearCol, descColDynamic];
    }
    get hasOptionals(){ return this.optionalCols.length > 0; }
    get buttonLabel() {
        return this.showExtended
            ? this.labels.lessColumns
            : this.labels.moreColumns;
    }
    get descWidth() { return this.hasVisibleOptionals ? 260 : 530; }

    get sortedDocs() {
        if (!this.docs) return [];
        return [...this.docs].sort(this.sortFunc(this.sortBy, this.sortDirection));
    }
    get hasDraftValues() { return this.draftValues.length > 0; }
    get pageCount() { return Math.max(1, Math.ceil(this.filteredRows.length / this.pageSize)); }
    get disablePrev() { return this.pageNumber <= 1; }
    get disableNext() { return this.pageNumber >= this.pageCount; }

    /** True when button should be beside filters (cosmetic) */
    get placeButtonBesideFilters() { return this.showFilters; }

    /** Filter and sort docs for current page, also (re)build columns */
    get filteredAndSortedDocs() {
        const start = (this.pageNumber - 1) * this.pageSize;
        const pageSlice = this.filteredRows
           .sort(this.sortFunc(this.sortBy, this.sortDirection))
           .slice(start, start + this.pageSize);

        this.dynamicColumns = this.buildColumns(pageSlice);
        return pageSlice;
    }

    get showList()    { return !this.previewName && !this.error; }
    get showPreview() { return  this.previewName && !this.error; }
    get isImage()     { return this.previewMime?.startsWith('image/'); }
    get isText()      { return this.previewMime?.startsWith('text/'); }
    get isPdf()       { return this.previewMime === 'application/pdf'; }
    get isDocx()      { return this.previewMime?.startsWith('application/vnd.openxmlformats-officedocument.wordprocessingml.document'); }
    get isMsg()       { return this.previewMime === 'application/vnd.ms-outlook'; }
    get isEml() { return this.previewMime === 'message/rfc822'; }
    get isOther()     { return this.showPreview && !this.previewError &&!this.isImage && !this.isText && !this.isPdf && !this.isDocx &&!this.isMsg &&!this.isEml; }
    get showOppLookup() { return this.contextObject === 'Account' || this.contextObject === 'Case'; }
    get showCaseLookup() { return ['Account','Opportunity','Contact'].includes(this.contextObject); }
    get showContactLookup() { return this.contextObject === 'Account';}
    get isImageUpload()       { return this.isImageSelected; }

    get upIsImage() {           // <img>
        return this.upMime?.startsWith('image/');
    }
    get upIsPdf() {             // <c-pdf-viewer>
        return this.upMime === 'application/pdf';
    }
    get upIsDocx() {            // <c-docx-viewer>
        return this.upMime?.includes(
            'officedocument.wordprocessingml.document');
    }

    

    /* ========================================================================
     * ------------------------- UI / FILTER HANDLERS -------------------------
     * ===================================================================== */
    toggleColumns(){ this.showExtended = !this.showExtended; }
    toggleFilters() { this.showFilters = !this.showFilters; }

    handleSort(event) {
        this.sortBy        = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
    }
    handleSearchChange(e) { this.searchKey  = e.target.value;  this.pageNumber = 1; }
    handleTypeChange(e)   { this.typeFilter = e.detail.value;  this.pageNumber = 1; }
    handleYearFrom(e)     { this.yearFrom = +e.detail.value || undefined; }
    handleYearTo(e)       { this.yearTo   = +e.detail.value || undefined; }
    handleDateFrom(e){ this.dateFrom = e.target.value; this.pageNumber = 1; }
    handleDateTo  (e){ this.dateTo   = e.target.value; this.pageNumber = 1; }
    handleSizeMin(e)      { this.sizeMin    = +e.target.value || undefined; }
    handleSizeMax(e)      { this.sizeMax    = +e.target.value || undefined; }
    handlePageSize(e)     { this.pageSize   = +e.detail.value; this.pageNumber = 1; }
    handleNameKey(e)      { this.nameKey  = e.target.value;    this.pageNumber = 1; }
    handleDescKey(e)      { this.descKey  = e.target.value;    this.pageNumber = 1; }
    handleNameMode(e)     { this.nameMode = e.detail.value;    this.pageNumber = 1; }
    handleDescMode(e)     { this.descMode = e.detail.value;    this.pageNumber = 1; }
    nextPage()            { if (!this.disableNext)  this.pageNumber++; }
    prevPage()            { if (!this.disablePrev)  this.pageNumber--; }
    handleDraft(e)        { this.draftValues = e.detail.draftValues; }    
    handleNewDescriptionChange(event) { this.newDescription = event.target.value;}
    handleNewDate(e){ this.newCreationDate = e.target.value; }
    handleNewYearChange(event) { this.newCreationYear = event.target.value; }
    handleOpportunityChange(event) { this.newOpportunityId = event.detail.value; }
    handleCaseChange(event) { this.newCaseId = event.detail.value; }
    handleContactChange(event) { this.newContactId = event.detail.value;}
    handleTaskChange(event) { this.newTaskId = event.detail.value; }
    openModal() { this.showModal = true; }
    closeModal() { 
        this.showModal = false; 
        this.selectedFile = null;
        this.uploadMessage = '';
        // Optionally reset form fields here
    }
    handleNewDescriptionChange(event) { this.newDescription = event.target.value; }
    handleNewYearChange(event) { this.newCreationYear = event.detail.value; }
    handleNewDate(e){ this.newCreationDate = e.target.value; }
    handleOpportunityChange(event) { this.newOpportunityId = event.detail.value; }
    handleCaseChange(event) { this.newCaseId = event.detail.value; }
    handleContactChange(event) { this.newContactId = event.detail.value; }


    /* ========================================================================
     * ------------------------------ FILTER LOGIC ----------------------------
     * ===================================================================== */
    get filteredRows() {
        if (!this.docs) return [];
        let rows = [...this.docs];

        // Name filter (starts / contains)
        if (this.nameKey) {
            const key = this.nameKey.toLowerCase();
            rows = rows.filter(r => {
                const n = (r.Name || '').toLowerCase();
                return this.nameMode === 'starts' ? n.startsWith(key) : n.includes(key);
            });
        }
        // Description filter
        if (this.descKey) {
            const key = this.descKey.toLowerCase();
            rows = rows.filter(r => {
                const d = (r.Description__c || '').toLowerCase();
                return this.descMode === 'starts' ? d.startsWith(key) : d.includes(key);
            });
        }
        // Type filter (DisplayType, not MIME directly)
        if (this.typeFilter !== 'all') {
            rows = rows.filter(r => r.DisplayType === this.typeFilter);
        }
        // Year and size filters
        rows = rows.filter(r =>
            (this.yearFrom ? r.Creation_Year__c >= this.yearFrom : true) &&
            (this.yearTo   ? r.Creation_Year__c <= this.yearTo   : true)
        );
        rows = rows.filter(r =>
            (this.sizeMin ? r.Size__c >= this.sizeMin : true) &&
            (this.sizeMax ? r.Size__c <= this.sizeMax : true)
        );
        return rows;
    }

    /* ========================================================================
     * ------------------------------ TABLE COLUMNS ---------------------------
     * ===================================================================== */
    /**
     * Build the datatable column list *once* when docs arrive.
     * – Shows a lookup column *only* if at least one row has a value.
     * – Never shows the lookup that matches the current page (e.g. Case page ➜ hide Case).
     */
    buildColumns(rows) {
        const host = hostKey(this.recordId); // e.g. 001, 006, 003, 500

        const cols = [
            nameCol,
            sizeCol,
            typeCol,
            yearCol,
            {
                label: LABEL_DESCRIPTION_LABEL, fieldName:'Description__c',
                type:'text', editable:true, initialWidth: this.descWidth
            }
        ];

        if (rows.some(r => r.TaskId)) {
            cols.push(this.taskCol);
        }

        // Add lookup columns based on actual data and context
        const maybeAdd = (nameFld, englishKey, urlFld, keyPrefix) => {
            if (host === keyPrefix) return;                     // never show “self”

            // skip certain look-ups (same rules as before)
            const skip = {
                '001': [],                         // Account page
                '006': ['Account'],                // Opportunity page
                '003': ['Account'],                // Contact page
                '500': ['Account', 'Contact']      // Case page
            };
            if (skip[host]?.includes(englishKey)) return;

            if (rows.some(r => r[nameFld])) {
                /* map the English key -> proper label */
                const translated =
                    englishKey === 'Account'     ? this.labels.accountCol
                    : englishKey === 'Opportunity' ? this.labels.opportunityCol
                    : englishKey === 'Contact'     ? this.labels.contactCol
                    : englishKey === 'Case'        ? this.labels.caseCol
                    : englishKey;  // fallback (shouldn’t happen)

                cols.push({
                    label       : translated,
                    fieldName   : urlFld,
                    type        : 'url',
                    typeAttributes : {
                        label  : { fieldName: nameFld },
                        target : '_self'
                    }
                });
            }
        };
        
        maybeAdd('AccountName',     'Account',     'AccountUrl',     '001');
        maybeAdd('OpportunityName', 'Opportunity', 'OpportunityUrl', '006');
        maybeAdd('ContactName',     'Contact',     'ContactUrl',     '003');
        maybeAdd('CaseNumber',      'Case',        'CaseUrl',        '500');

        // Optionals for More/Less toggle
        this.optionalCols = cols.slice(5);
        return cols;
    }  

    /* ========================================================================
     * --------------------------- WIRED DOCS / DATA LOAD ---------------------
     * ===================================================================== */
    @wire(getDocs, { recordId:'$recordId' })
    wired(result) {
        this.wiredDocsResult = result;
        const { data, error } = result;
        this.isLoading = false;
        try {
            if (data) {
                this.docs  = data.map(r => ({
                    ...r,
                    DisplayType     : mapMime(r.Type__c),
                    AccountName     : r.Account_ID__r?.Name,
                    AccountUrl      : r.Account_ID__c     ? '/'+r.Account_ID__c     : null,
                    OpportunityName : r.Opportunity_ID__r?.Name,
                    OpportunityUrl  : r.Opportunity_ID__c ? '/'+r.Opportunity_ID__c : null,
                    ContactName     : r.Contact_ID__r?.Name,
                    ContactUrl      : r.Contact_ID__c     ? '/'+r.Contact_ID__c     : null,
                    CaseNumber      : r.Case_ID__r?.CaseNumber,
                    CaseUrl         : r.Case_ID__c        ? '/'+r.Case_ID__c        : null,
                    s3Key           : r.S3_Key__c, 
                    TaskId          : r.Task_ID__c,
                    TaskUrl         : r.Task_ID__c ? '/' + r.Task_ID__c : null,
                    TaskName        : r.TaskName
                }));

                // Optionals are those present in at least one row
                this.optionalCols = this.optionalCols.filter(c =>
                    this.docs.some(r => r[c.fieldName.replace('Url','Name')])
                );
                this.dynamicColumns = this.buildColumns(this.docs);

                // Types for filter dropdown
                const types = [...new Set(this.docs.map(r => r.DisplayType).filter(t => t))].sort();
                this.typeOptions = [{label: this.labels.allTypes, value: 'all'}, ...types.map(t => ({ label: t, value: t }))];
                this.error = undefined;
            } else if (error) {
                throw error;
            }
        } catch (e) {
            this.error = this.safeMessage(e);
            console.error('[s3DocViewer] wire error', e);
            this.dispatchEvent(new ShowToastEvent({
                title: this.labels.loadError,
                message: this.error,
                variant: 'error'
            }));
        }
    }

    // Use wire to get options
    @wire(getRelatedOpportunities, { hostId: '$recordId' })
    wiredOpps({ data }) {
        this.opportunityOptions = data
            ? data.map(o => ({ label: o.Name, value: o.Id }))
            : [];
    }
    @wire(getRelatedCases,        { hostId: '$recordId' })
    wiredCases({ data }) {
        this.caseOptions = data
            ? data.map(c => ({ label: c.CaseNumber, value: c.Id }))
            : [];
    }
    @wire(getRelatedContacts,     { hostId: '$recordId' })
    wiredContacts({ data }) {
        this.contactOptions = data
            ? data.map(ct => ({ label: ct.Name, value: ct.Id }))
            : [];
    }

    /* ========================================================================
     * --------------------------- TABLE EDITING/SAVING -----------------------
     * ===================================================================== */
    async handleSave(event) {
        const drafts = event.detail.draftValues;  
        if (!drafts.length) return;
        this.isLoading = true;
        try {
            await updateDescriptions({ files: drafts });

            // Update rows locally with saved drafts
            this.docs = this.docs.map(r => {
                const d = drafts.find(x => x.Id === r.Id);
                return d ? { ...r, Description__c: d.Description__c } : r;
            });

            const dt = this.template.querySelector('lightning-datatable');
            if (dt) { dt.draftValues = []; }

            this.dispatchEvent(
                new ShowToastEvent({ title: this.labels.saved, variant: 'success' })
            );
        } catch (err) {
            const msg = this.safeMessage(err);
            this.dispatchEvent(
                new ShowToastEvent({ title: this.labels.saveFailed, message: msg, variant: 'error' })
            );
            console.error('[s3DocViewer] save error', err);
        } finally {
            this.isLoading = false;
        }
    }

    /* ========================================================================
    *  When the user picks a file in the upload‑modal
    * ===================================================================== */
    handleFileChange(event) {
        this.selectedFile = event.target.files[0];

        /* nothing picked or user clicked “×” */
        if (!this.selectedFile) {
            this.previewImageUrl = this.previewFileUrl = null;
            this.isImageSelected = false;
            return;
        }

        /* auto‑populate “File Name” (strip extension) */
        this.editFileName = this.selectedFile.name.replace(/\.[^/.]+$/, '');

        /* decide if it is an image */
        this.isImageSelected = this.selectedFile.type &&
                            this.selectedFile.type.startsWith('image/');

        /* ── IMAGES ─────────────────────────────────────────── */
        if (this.isImageSelected) {
            this.previewImageUrl = URL.createObjectURL(this.selectedFile);
            this.previewFileUrl  = null;

            /* decide icon tone once the thumbnail loads */
            const img = new Image();
            img.onload = () => {
                const canvas = document.createElement('canvas');
                canvas.width = 32; canvas.height = 1;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0, 32, 1);
                const { data } = ctx.getImageData(0, 0, 32, 1);

                let lum = 0;
                for (let i = 0; i < data.length; i += 4) {
                    lum += 0.299*data[i] + 0.587*data[i+1] + 0.114*data[i+2];
                }
                lum = lum / 32;
                this.iconTone = lum < 140 ? 'slds-text-color_inverse'
                                        : 'slds-text-color_default';
            };
            img.src = this.previewImageUrl;
            return;
        }

        /* ── EVERY OTHER TYPE ───────────────────────────────── */
        this.previewImageUrl = null;
        this.previewFileUrl  = URL.createObjectURL(this.selectedFile);
    }


    /* decide tone based on average brightness */
    measureBrightness(event){
        const img = event.target;

        // tiny off‑screen canvas
        const canvas = document.createElement('canvas');
        const ctx    = canvas.getContext('2d');
        canvas.width = canvas.height = 8;          // 64 pixels is enough

        // draw the image shrunk to 8×8 and read back the pixels
        ctx.drawImage(img, 0, 0, 8, 8);
        const data = ctx.getImageData(0, 0, 8, 8).data;

        let total = 0;
        for (let i = 0; i < data.length; i += 4){
            // simple perceived luminance: 0.2126 R + 0.7152 G + 0.0722 B
            total += 0.2126 * data[i]     +   // R
                    0.7152 * data[i + 1] +   // G
                    0.0722 * data[i + 2];    // B
        }
        const avg = total / 64;                // 64 pixels

        // threshold‑pick: <128 → dark
        this.isDarkPreview = avg < 128;

        // tell LWC to recalc computed getters
        this.closeBtnClass;            // access to mark for re‑render
    }


    get closeBtnClass() {
        // base classes – keep on ONE logical line
        const base = 'slds-button slds-button_icon slds-button_icon-x-small slds-is-absolute';

        // decide which text‑colour utility to add
        const tone = this.isDarkPreview ? 'slds-text-color_inverse'
                                        : 'slds-text-color_default';

        return `${base} ${tone}`;       // no stray line‑breaks!
    }

    /* ========================================================================
    *  Local-file preview – now opens in a NEW TAB
    * ===================================================================== */
    openLocalPreview() {

        if (!this.selectedFile) { return; }

        /* ---------- infer a MIME type (fall back to extension) --------------- */
        const name = this.selectedFile.name;
        const ext  = name.split('.').pop().toLowerCase();
        const mime = this.selectedFile.type ||
                    (ext === 'eml' ? 'message/rfc822' :
                    ext === 'msg' ? 'application/vnd.ms-outlook' :
                    ext === 'docx'? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' :
                    ext === 'pdf' ? 'application/pdf' : '');

        const reader = new FileReader();

        /* ---------- once the file is read… ---------------------------------- */
        reader.onload = () => {

            /* a) IMAGES – reader.result is already a data:URI */
            if (mime.startsWith('image/')) {
                window.open(reader.result, '_blank');
                return;
            }

            /* b) PLAIN TEXT --------------------------------------------------- */
            if (mime.startsWith('text/')) {
                const win = window.open('', '_blank');
                win.document.write(`<pre style="white-space:pre-wrap;">${
                    reader.result.replace(/[&<>]/g,
                    ch=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[ch]))}</pre>`);
                win.document.title = name;
                return;
            }

            /* c) PDF or DOCX (or any binary) ---------------------------------- */
            if (mime === 'application/pdf' ||
                mime.startsWith('application/vnd')) {

                const blob   = new Blob([reader.result], { type: mime });
                const url    = URL.createObjectURL(blob);
                window.open(url, '_blank');

                /* Revoke after tab opens to free memory */
                setTimeout(()=>URL.revokeObjectURL(url), 30_000);
                return;
            }

            /* d) .EML --------------------------------------------------------- */
            if (mime === 'message/rfc822') {

                const bytes = new Uint8Array(reader.result);
                const b64   = btoa(String.fromCharCode.apply(null, bytes));
                const { html, attachments } = parseEml(b64);
                const htmlWithInline = embedImages(html, attachments);

                const win = window.open('', '_blank');
                win.document.write(`
                    <html><head><title>${name}</title></head><body>
                        <div style="padding:1rem; font:15px/1.4 system-ui, sans-serif;">
                            ${htmlWithInline}
                            ${attachments.filter(a=>!a.contentId).length ?
                                `<h3>Attachments</h3><ul>` +
                                attachments.filter(a=>!a.contentId).map((att,i)=>{
                                    const blob = new Blob(
                                        [Uint8Array.from(atob(att.data),c=>c.charCodeAt(0))],
                                        { type: att.contentType });
                                    const url  = URL.createObjectURL(blob);
                                    return `<li><a href="${url}" download="${att.filename}"
                                                target="_blank">${att.filename}</a></li>`;
                                }).join('') + `</ul>` : ''}
                        </div>
                    </body></html>`);
                return;
            }

            /* e) fallback ----------------------------------------------------- */
            const blob = new Blob([reader.result],
                                { type: mime || 'application/octet-stream' });
            const url  = URL.createObjectURL(blob);
            window.open(url, '_blank');
            setTimeout(()=>URL.revokeObjectURL(url), 30_000);
        };

        /* choose FileReader method ------------------------------------------- */
        if      (mime.startsWith('image/')) reader.readAsDataURL(this.selectedFile);
        else if (mime.startsWith('text/' )) reader.readAsText   (this.selectedFile);
        else                                reader.readAsArrayBuffer(this.selectedFile);
    }

    /* close button inside the inline preview */
    closeUploadPreview() {
        if (this.uploadPreviewSrc) URL.revokeObjectURL(this.uploadPreviewSrc);
        this.showUploadPreview  = false;
        this.uploadPreviewSrc   = null;
        this.uploadPreviewHtml  = null;
        this.uploadPreviewText  = null;
        this.uploadPreviewError = null;
    }

    clearSelectedFile() {

        /* ── 1. revoke any Blob‑URLs we created so the browser can free memory ── */
        if (this.previewImageUrl) {
            URL.revokeObjectURL(this.previewImageUrl);
        }
        if (this.previewFileUrl) {            // the generic‑file preview link
            URL.revokeObjectURL(this.previewFileUrl);
        }

        /* ── 2. wipe component‑level state ── */
        this.selectedFile     = null;
        this.previewImageUrl  = null;
        this.previewFileUrl   = null;         // make sure the button disappears
        this.editFileName     = '';
        this.newDescription   = '';
        this.iconTone         = 'slds-text-color_inverse';  // back to default

        /* ── 3. physically clear the <input type="file"> element ── */
        const inputEl = this.template.querySelector('[data-id="fileinput"]');
        if (inputEl) {
            inputEl.value = null;             // resets the control visually
        }
    }

    handleEditFileName(event) {
        this.editFileName = event.target.value;
    }


    /* ========================================================================
     * ------------------------------- SORTING --------------------------------
     * ===================================================================== */
    sortFunc(field, direction) {
        const multiplier = direction === 'asc' ? 1 : -1;
        return (a, b) => {
            let valA = a[field], valB = b[field];

            valA = valA === undefined || valA === null ? '' : valA;
            valB = valB === undefined || valB === null ? '' : valB;

            const cmp = typeof valA === 'number' && typeof valB === 'number'
                ? valA - valB
                : String(valA).localeCompare(String(valB), undefined, { numeric: true });

            return cmp * multiplier;
        };
    }

    /* ========================================================================
     * ------------------------------ PREVIEW / BLOB HELPERS ------------------
     * ===================================================================== */
    /** Safe error message extraction */
    safeMessage(err) {
        if (!err)            return 'Unknown error';
        if (err.body)        return err.body.message || err.body;
        if (err.message)     return err.message;
        return JSON.stringify(err);
    }
    /** Base64 to byte array */
    base64ToBytes(base64) {
        const bin = atob(base64);
        const len = bin.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
        return bytes;
    }
    /** Create Blob URL (workaround LWS restrictions) */
    makeBlobUrl(base64, mime) {
        const safeMime = mime && mime.startsWith('application/vnd') ? 'application/octet-stream' : mime || 'application/octet-stream';
        const bytes = this.base64ToBytes(base64);
        const url   = URL.createObjectURL(new Blob([bytes], { type: safeMime }));
        this._blobUrl = url;
        return url;
    }
    /** base64→UTF-8 string (for text preview) */
    decodeUtf8(base64) {
        const binary = atob(base64);
        const len    = binary.length;
        const bytes  = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        return new TextDecoder('utf-8').decode(bytes);
    }

    /* ---------- upload‑preview type helpers ---------- */
    get isUploadPreviewImage() {
        return this.uploadPreviewMime
            ? this.uploadPreviewMime.startsWith('image/')
            : false;
    }

    get isUploadPreviewPdf() {
        return this.uploadPreviewMime === 'application/pdf';
    }

    get isUploadPreviewDocx() {
        return this.uploadPreviewMime
            ? this.uploadPreviewMime.startsWith(
                'application/vnd.openxmlformats-officedocument'
            )
            : false;
    }


    /* ========================================================================
     * ------------------------------ ROW PREVIEW -----------------------------
     * ===================================================================== */
    /** Click on table row: preview file */
    async handleRowAction(e) {
        const row = e.detail.row;
        this.previewName = row.Name;
        this.isLoading   = true;
        this.previewHtml = undefined;
        this.previewAttachments = [];
        try {
            const file = await getFile({ s3Key: row.s3Key });
            this.previewName = row.Name;
            this.previewS3Key = row.s3Key;
            this.previewMime = file.contentType || 'application/octet-stream';
            if (this.previewMime === 'application/octet-stream') {
                const ext = row.Name.split('.').pop().toLowerCase();
                if (ext === 'gif') {                          // ← one-liner guess
                    this.previewMime = 'image/gif';
                }
            }
            const dataUrl = `data:${this.previewMime};base64,${file.base64Data}`;
            if (row.Name.toLowerCase().endsWith('.msg')) {
                this.previewMime = 'application/vnd.ms-outlook';
            }else if (row.Name.toLowerCase().endsWith('.eml')) {
                this.previewMime = 'message/rfc822';
            }
            if (this.isImage) {
                this.previewSrc  = dataUrl;
                this.previewText = undefined;
            } else if (this.isText) {
                this.previewText = this.decodeUtf8(file.base64Data);
                this.previewSrc  = undefined;
            } else if (this.isPdf || this.isDocx) {
                this.previewSrc  = this.makeBlobUrl(file.base64Data, this.previewMime);
                this.previewText = undefined;
            } else if (this.isMsg || this.isEml) {

                try {
                    // for .msg we still ask Lambda → returns { html, attachments } JSON
                    const parts = this.isMsg
                                ? JSON.parse(await fetchMsg({ key: row.Name }))
                                : parseEml(file.base64Data);          // local .eml

                    this.previewHtml = embedImages(parts.html, parts.attachments);

                    this.previewAttachments = parts.attachments
                    .filter(att => !att.contentId)                  // skip inline images
                    .map((att, i) => {
                        const isB64 = /^[A-Za-z0-9+/]+\s*={0,2}$/.test(att.data || '');
                        let blob;

                        if (isB64) {
                            const bytes = Uint8Array.from(atob(att.data.replace(/\s+/g,'')),
                                                        c => c.charCodeAt(0));
                            blob = new Blob([bytes], { type: att.contentType });
                        } else {
                            // quoted–printable or 7‑bit – just show a placeholder link.
                            blob = new Blob([att.data], { type: 'text/plain' });
                        }
                        return {
                            id  : i,
                            name: att.filename || `attachment‑${i+1}`,
                            url : URL.createObjectURL(blob),
                            type: att.contentType
                        };
                    });

                    this.previewSrc = this.previewText = undefined;
                    this.previewError = undefined;

                } catch(e) {
                    console.error(e);
                    this.previewError =
                        `Unable to display this ${this.isMsg?'.msg':'.eml'} file.`;
                } finally {
                    this.isLoading = false;
                }
                return;

            }else {
                this.previewSrc  = dataUrl;   // fallback for other types
                this.previewText = undefined;
            }
        } catch (err) {
            this.previewS3Key = row.s3Key;
            const msg = this.safeMessage(err);
            if (msg && msg.toLowerCase().includes('not found')) {
                this.previewError = this.labels.fileNotFound.replace('{0}', row.Name);
            } else {
                this.previewError = msg || 'Unknown error retrieving file.';
            }
        } finally {
            this.isLoading = false;
        }
    }

    /** Open attachment (MSG preview) in new tab */
    openAttachment(evt) {
        const url = evt.currentTarget.dataset.url;
        window.open(url, '_blank');
    }

    /** Back from preview */
    closePreview() {
        this.previewAttachments?.forEach(a => URL.revokeObjectURL(a.url));
        this.previewAttachments = [];
        if (this._blobUrl) {
            URL.revokeObjectURL(this._blobUrl);
            this._blobUrl = undefined;
        }
        this.previewName = this.previewText = this.previewSrc = this.previewMime = undefined;
        this.error = undefined;
        this.previewError = undefined;   // reset error state
    }

    /* ========================================================================
     * ------------------------------ DOWNLOAD -------------------------------
     * ===================================================================== */
    async downloadFile() {
        // Always allow download if a file is selected
        try {
            // Prefer base64 if available (small files, <= 6MB)
            if (this.previewSrc) {
                const a = document.createElement('a');
                a.href        = this.previewSrc;
                a.download    = this.previewName;
                a.style.display = 'none';
                this.template.appendChild(a);
                a.click();
                this.template.removeChild(a);
                return;
            }

            // If not, get presigned S3 GET URL and open/download
            const url = await getPresignedGetUrl({ s3Key: this.previewS3Key });
            if (!url) throw new Error("Could not get download link");

            // Open in new tab or force download (works for most file types)
            const a = document.createElement('a');
            a.href        = url;
            a.download    = this.previewName;
            a.target      = '_blank';
            a.style.display = 'none';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);

        } catch (err) {
            const msg = this.safeMessage(err);
            this.dispatchEvent(
                new ShowToastEvent({
                    title:'Download failed', message:msg, variant:'error'
                })
            );
        }
    }


    /* ========================================================================*/

    async uploadFile() {
        // reset UI state
        this.uploadMessage = '';
        if (!this.selectedFile) {
            this.uploadMessage = this.labels.noFileSelected;
            return;
        }

        this.isUploading = true;
        const file = this.selectedFile;

        try {

            //  choose a mime if the browser didn't 
            let mime = file.type || '';
            if (!mime) {
                const ext = (file.name.split('.').pop() || '').toLowerCase();
                mime = ext === 'png'  ? 'image/png'  :
                    ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' :
                    ext === 'gif'  ? 'image/gif'  :
                    ext === 'pdf'  ? 'application/pdf' :
                    ext === 'docx' ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' :
                    ext === 'msg'  ? 'application/vnd.ms-outlook' :
                    ext === 'eml'  ? 'message/rfc822' :
                    'application/octet-stream';
            }
            const ext  = (this.selectedFile.name.match(/\.[^/.]+$/) || [''])[0];
            const fileNameForLambda = this.editFileName + ext;

            const { uploadUrl, s3Key } = await getPresignedUrl({
                fileName   : fileNameForLambda,
                contentType: mime,      
                fileSize   : file.size
            });

            if (!uploadUrl) {
                throw new Error('Could not get presigned URL');
            }

            /* PUT to S3 */
            const s3Resp = await fetch(uploadUrl, {
                method : 'PUT',
                headers: { 'Content-Type': file.type },
                body   : file
            });
            if (!s3Resp.ok) {
                throw new Error('Failed to upload to S3');
            }

            /* create S3_File__c */
            await createS3File({
                name        : this.editFileName,
                type        : file.type,
                size        : file.size,
                s3Key,                                  
                description : this.newDescription,
                creationYear: this.newCreationYear,
                creationDate : this.newCreationDate,
                accountId   : this.contextObject === 'Account'     ? this.recordId : null,
                caseId      : this.contextObject === 'Case'        ? this.recordId : this.newCaseId,
                contactId   : this.contextObject === 'Contact'     ? this.recordId : this.newContactId,
                opportunityId: this.contextObject === 'Opportunity'? this.recordId : this.newOpportunityId,
                taskId : this.newTaskId
            });

            /* success toast */
            this.dispatchEvent(
                new ShowToastEvent({
                    title  : this.labels.uploadedTitle,
                    message: `${this.editFileName} has been added`,
                    variant: 'success',
                    mode   : 'dismissable'
                })
            );
            /* refresh list  */
            refreshApex(this.wiredDocsResult); 
            /* close the modal */
            this.closeModal();
        } catch (err) {
            // error toast 
            this.dispatchEvent(
                new ShowToastEvent({
                    title  : this.labels.uploadFailed,
                    message: err.body?.message || err.message,
                    variant: 'error',
                    mode   : 'sticky'
                })
            );
        } finally {
            this.isUploading = false;
        }
    }
}