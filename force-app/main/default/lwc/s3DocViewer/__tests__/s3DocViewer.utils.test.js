import S3DocViewer, { mapMime, embedImages, parseEml, hostKey, resolveContext } from 'c/s3DocViewer';
import { Buffer } from 'buffer';
import { TextDecoder } from 'util';

// Polyfill TextDecoder for environments where it's not defined
if (typeof global.TextDecoder === 'undefined') {
    global.TextDecoder = TextDecoder;
}

// Polyfill atob for Node environment if needed
if (typeof atob === 'undefined') {
    global.atob = (input) => Buffer.from(input, 'base64').toString('binary');
}

describe('s3DocViewer utility functions', () => {
    it('mapMime returns expected categories', () => {
        expect(mapMime()).toBe('');
        expect(mapMime('image/png')).toBe('image');
        expect(mapMime('jpg')).toBe('image');
        expect(mapMime('application/pdf')).toBe('pdf');
        expect(mapMime('message/rfc822')).toBe('eml');
        expect(mapMime('application/vnd.ms-outlook')).toBe('msg');
        expect(mapMime('application/vnd.openxmlformats-officedocument.wordprocessingml.document')).toBe('docx');
        expect(mapMime('application/vnd.custom')).toBe('office doc');
        expect(mapMime('text/plain')).toBe('text');
        expect(mapMime('unknown/type')).toBe('unknown/type');
    });

    it('hostKey and resolveContext derive context object', () => {
        expect(hostKey('001ABC')).toBe('001');
        expect(hostKey('')).toBe('');
        expect(resolveContext('001ABC')).toBe('Account');
        expect(resolveContext('006XYZ')).toBe('Opportunity');
        expect(resolveContext('999XYZ')).toBe('Other');
    });

    it('embedImages replaces cid links with data URIs', () => {
        const html = '<img src="cid:img1">';
        const attachments = [{ contentId: 'img1', contentType: 'image/png', data: 'ZmFrZQ==' }];
        expect(embedImages(html, attachments)).toBe('<img src="data:image/png;base64,ZmFrZQ==">');
    });

    it('parseEml handles html, inline and regular attachments', () => {
        const eml = [
            'Content-Type: multipart/related; boundary="M"',
            '',
            '--M',
            'Content-Type: text/html',
            'Content-Transfer-Encoding: quoted-printable',
            '',
            '<html><head><style>.x{}</style></head><body>Hello</body></html>',
            '--M',
            'Content-Type: image/png',
            'Content-ID: <img1>',
            'Content-Disposition: inline; filename*=utf-8\'\'inline.png',
            'Content-Transfer-Encoding: base64',
            '',
            'ZmFrZQ==',
            '--M--'
        ].join('\r\n');
        const base64 = Buffer.from(eml, 'utf-8').toString('base64');
        const result = parseEml(base64);
        expect(result.html).toContain('<body>Hello</body>');
        expect(result.attachments.length).toBe(1);
        expect(result.attachments[0].filename).toBe('inline.png');
        expect(result.attachments[0].contentId).toBe('img1');
    });

        it('parseEml decodes base64 text bodies', () => {
        const text = Buffer.from('Plain', 'utf-8').toString('base64');
        const eml = [
            'Content-Type: text/plain',
            'Content-Transfer-Encoding: base64',
            '',
            text
        ].join('\r\n');
        const base64 = Buffer.from(eml, 'utf-8').toString('base64');
        const result = parseEml(base64);
        expect(result.html).toContain('Plain');
    });
});

describe('s3DocViewer class helpers', () => {
    it('buildColumns adds lookup columns based on data', () => {
        const mockLabels = {
            accountCol: 'Account',
            opportunityCol: 'Opportunity',
            contactCol: 'Contact',
            caseCol: 'Case'
        };
        const mockThis = {
            recordId: '001XYZ',
            labels: mockLabels,
            optionalCols: [],
            taskCol: { fieldName: 'TaskUrl', label: 'Task' }
        };
        const rows = [{
            Name: 'Test',
            Size__c: 10,
            Type__c: 'text/plain',
            DisplayType: 'text',
            Creation_Date__c: '2024-01-01',
            Description__c: 'desc',
            OpportunityName: 'Opp',
            OpportunityUrl: '/006',
            ContactName: 'Con',
            ContactUrl: '/003',
            CaseNumber: 'C-0001',
            CaseUrl: '/500',
            TaskId: '00T1',
            TaskUrl: '/00T1',
            TaskName: 'Task'
        }];
        const cols = S3DocViewer.prototype.buildColumns.call(mockThis, rows);
        const fieldNames = cols.map(c => c.fieldName);
        expect(fieldNames).toEqual(expect.arrayContaining(['OpportunityUrl','ContactUrl','CaseUrl']));
        expect(mockThis.optionalCols.length).toBe(cols.length - 5);
    });

    it('connectedCallback assigns optional columns per context', () => {
        const labels = {
            accountCol: 'Account',
            opportunityCol: 'Opportunity',
            contactCol: 'Contact',
            caseCol: 'Case'
        };
        const call = (id) => {
            const ctx = { recordId: id, labels };
            S3DocViewer.prototype.connectedCallback.call(ctx);
            return ctx.optionalCols.length;
        };
        expect(call('001AAA')).toBe(4); // Account
        expect(call('006AAA')).toBe(1); // Opportunity
        expect(call('500AAA')).toBe(1); // Case
        expect(call('999AAA')).toBe(0); // Default
    });

    it('columns getter respects showExtended toggle', () => {
        const mockThis = {
            optionalCols: [{ fieldName: 'AccountUrl', label: 'Account', type: 'url' }],
            showExtended: true,
            filteredRows: [{ AccountName: 'Acme' }],
            pageNumber: 1,
            pageSize: 20
        };
        const columnsGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'columns').get;
        const hasOptionalsGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'hasOptionals').get;
        expect(columnsGetter.call(mockThis).length).toBe(6); // 5 base + 1 optional
        expect(hasOptionalsGetter.call(mockThis)).toBe(true);
        mockThis.showExtended = false;
        expect(columnsGetter.call(mockThis).length).toBe(5);
    });

    it('hasVisibleOptionals and button related getters work', () => {
        const ctx = {
            optionalCols: [{ fieldName: 'AccountUrl' }],
            pageNumber: 1,
            pageSize: 20,
            filteredRows: [{ AccountName: 'Acme' }],
            showExtended: false,
            labels: { moreColumns: 'More', lessColumns: 'Less' }
        };
        const hasVis = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'hasVisibleOptionals').get;
        const btn = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'buttonLabel').get;
        const descWidth = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'descWidth').get;
        expect(hasVis.call(ctx)).toBe(true);
        expect(btn.call(ctx)).toBe('More');
        ctx.showExtended = true;
        expect(btn.call(ctx)).toBe('Less');
        expect(descWidth.call({ hasVisibleOptionals: true })).toBe(260);
        expect(descWidth.call({ hasVisibleOptionals: false })).toBe(530);
    });

    it('sorting and paging helpers', () => {
        const sortedGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'sortedDocs').get;
        const hasDraftGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'hasDraftValues').get;
        const pageCountGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'pageCount').get;
        const disablePrevGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'disablePrev').get;
        const disableNextGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'disableNext').get;
        const placeBtnGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'placeButtonBesideFilters').get;
        const ctx = {
            docs: [{ Name: 'b' }, { Name: 'a' }],
            sortBy: 'Name',
            sortDirection: 'asc',
            sortFunc: S3DocViewer.prototype.sortFunc,
            draftValues: [{ Id: 1 }],
            filteredRows: [1, 2, 3, 4],
            pageSize: 2,
            pageNumber: 1,
            showFilters: true
        };
        Object.defineProperty(ctx, 'pageCount', {
            get: () => pageCountGetter.call(ctx)
        });
        expect(sortedGetter.call(ctx)[0].Name).toBe('a');
        expect(hasDraftGetter.call(ctx)).toBe(true);
        expect(pageCountGetter.call(ctx)).toBe(2);
        expect(disablePrevGetter.call(ctx)).toBe(true);
        ctx.pageNumber = 2;
        expect(disableNextGetter.call(ctx)).toBe(true);
        expect(placeBtnGetter.call(ctx)).toBe(true);
    });

    it('filteredAndSortedDocs sorts and updates columns', () => {
        const ctx = {
            filteredRows: [{ Name: 'b' }, { Name: 'a' }],
            sortBy: 'Name',
            sortDirection: 'asc',
            sortFunc: S3DocViewer.prototype.sortFunc,
            pageNumber: 1,
            pageSize: 20,
            buildColumns: jest.fn().mockReturnValue(['col'])
        };
        const getter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'filteredAndSortedDocs').get;
        const result = getter.call(ctx);
        expect(result[0].Name).toBe('a');
        expect(ctx.dynamicColumns).toEqual(['col']);
    });

    it('preview and lookup getters evaluate correctly', () => {
        const ctx = {
            previewName: 'file',
            previewMime: 'image/png',
            isLoading: false,
            error: null,
            contextObject: 'Account',
            isImageSelected: true,
            upMime: 'application/pdf'
        };
        const get = (prop) => Object.getOwnPropertyDescriptor(S3DocViewer.prototype, prop).get;
        expect(get('showList').call({ previewName: null, error: null })).toBe(true);
        expect(get('showPreview').call(ctx)).toBe(true);
        expect(get('isImage').call(ctx)).toBe(true);
        expect(get('isText').call(ctx)).toBe(false);
        expect(get('isPdf').call({ previewMime: 'application/pdf' })).toBe(true);
        expect(get('isDocx').call({ previewMime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' })).toBe(true);
        expect(get('isMsg').call({ previewMime: 'application/vnd.ms-outlook' })).toBe(true);
        expect(get('isEml').call({ previewMime: 'message/rfc822' })).toBe(true);
        expect(get('isOther').call({ showPreview: true, previewError: null, isImage: false, isText: false, isPdf: false, isDocx: false, isMsg: false, isEml: false })).toBe(true);
        expect(get('showOppLookup').call({ contextObject: 'Account' })).toBe(true);
        expect(get('showCaseLookup').call({ contextObject: 'Opportunity' })).toBe(true);
        expect(get('showContactLookup').call({ contextObject: 'Account' })).toBe(true);
        expect(get('isImageUpload').call({ isImageSelected: true })).toBe(true);
        expect(get('upIsImage').call({ upMime: 'image/png' })).toBe(true);
        expect(get('upIsPdf').call(ctx)).toBe(true);
        expect(get('upIsDocx').call({ upMime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' })).toBe(true);
    });

    it('safeMessage handles various error shapes', () => {
        const fn = S3DocViewer.prototype.safeMessage;
        expect(fn.call({})).toBe('Unknown error');
        expect(fn.call({}, { body: { message: 'oops' } })).toBe('oops');
        expect(fn.call({}, { body: 'raw' })).toBe('raw');
        expect(fn.call({}, { message: 'msg' })).toBe('msg');
        const obj = { foo: 'bar' };
        expect(fn.call({}, obj)).toBe(JSON.stringify(obj));
    });

    it('base64 helpers convert and decode correctly', () => {
        const base = Buffer.from('ABC').toString('base64');
        const bytes = S3DocViewer.prototype.base64ToBytes.call({}, base);
        expect(Array.from(bytes)).toEqual([65, 66, 67]);
        const utf = Buffer.from('Hello µWorld', 'utf8').toString('base64');
        const decoded = S3DocViewer.prototype.decodeUtf8.call({}, utf);
        expect(decoded).toBe('Hello µWorld');
    });

    it('makeBlobUrl creates blob URLs and stores reference', () => {
        const createSpy = jest.fn(() => 'blob:test');
        const revokeSpy = jest.fn();
        global.URL.createObjectURL = createSpy;
        global.URL.revokeObjectURL = revokeSpy;
        const ctx = { base64ToBytes: S3DocViewer.prototype.base64ToBytes };
        const b64 = Buffer.from('data').toString('base64');
        const url = S3DocViewer.prototype.makeBlobUrl.call(ctx, b64, 'text/plain');
        expect(createSpy).toHaveBeenCalled();
        expect(url).toBe('blob:test');
        expect(ctx._blobUrl).toBe('blob:test');
    });

    it('sortFunc sorts numeric and string fields', () => {
        const arr = [{ a: 2 }, { a: 1 }];
        arr.sort(S3DocViewer.prototype.sortFunc.call({}, 'a', 'asc'));
        expect(arr[0].a).toBe(1);
        const str = [{ a: 'b' }, { a: 'a' }];
        str.sort(S3DocViewer.prototype.sortFunc.call({}, 'a', 'desc'));
        expect(str[0].a).toBe('b');
    });

    it('upload preview mime getters detect types', () => {
        const imgCtx = { uploadPreviewMime: 'image/png' };
        const pdfCtx = { uploadPreviewMime: 'application/pdf' };
        const docxCtx = {
            uploadPreviewMime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        };
        const imgGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'isUploadPreviewImage').get;
        const pdfGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'isUploadPreviewPdf').get;
        const docxGetter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'isUploadPreviewDocx').get;
        expect(imgGetter.call(imgCtx)).toBe(true);
        expect(pdfGetter.call(pdfCtx)).toBe(true);
        expect(docxGetter.call(docxCtx)).toBe(true);
    });

    it('filteredRows applies all filters', () => {
        const ctx = {
            docs: [
                { Name: 'Alpha', Description__c: 'First', DisplayType: 'img', Creation_Year__c: 2023, Size__c: 50 },
                { Name: 'Beta', Description__c: 'Second', DisplayType: 'pdf', Creation_Year__c: 2024, Size__c: 200 }
            ],
            nameKey: 'a',
            nameMode: 'starts',
            descKey: 'first',
            descMode: 'contains',
            typeFilter: 'img',
            searchKey: '',
            yearFrom: 2023,
            yearTo: 2023,
            dateFrom: undefined,
            dateTo: undefined,
            sizeMin: 40,
            sizeMax: 60
        };
        const getter = Object.getOwnPropertyDescriptor(S3DocViewer.prototype, 'filteredRows').get;
        const result = getter.call(ctx);
        expect(result.length).toBe(1);
        expect(result[0].Name).toBe('Alpha');
    });
});