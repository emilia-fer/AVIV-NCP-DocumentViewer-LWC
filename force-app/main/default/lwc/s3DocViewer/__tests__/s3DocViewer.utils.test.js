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

    it('parseEml parses text and attachments', () => {
        const eml = [
            'Content-Type: multipart/mixed; boundary="X"',
            '',
            '--X',
            'Content-Type: text/plain',
            '',
            'Hello World',
            '--X',
            'Content-Type: text/plain',
            'Content-Disposition: attachment; filename="file.txt"',
            'Content-Transfer-Encoding: base64',
            '',
            'SGVsbG8=',
            '--X--'
        ].join('\r\n');
        const base64 = Buffer.from(eml, 'utf-8').toString('base64');
        const result = parseEml(base64);
        expect(result.html).toContain('Hello');
        expect(Array.isArray(result.attachments)).toBe(true);
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
            optionalCols: []
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
            CaseUrl: '/500'
        }];
        const cols = S3DocViewer.prototype.buildColumns.call(mockThis, rows);
        const fieldNames = cols.map(c => c.fieldName);
        expect(fieldNames).toEqual(expect.arrayContaining(['OpportunityUrl','ContactUrl','CaseUrl']));
        expect(mockThis.optionalCols.length).toBe(cols.length - 5);
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
});