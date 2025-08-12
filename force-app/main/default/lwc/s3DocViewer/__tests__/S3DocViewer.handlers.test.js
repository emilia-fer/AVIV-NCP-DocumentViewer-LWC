jest.mock('@salesforce/apex/S3DocService.updateDescriptions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/S3DocService.getFile', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/S3PresignService.getPresignedUrl', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/S3FileCreator.create', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/MsgPreviewService.fetch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/S3PresignService.getPresignedGetUrl', () => ({ default: jest.fn() }), { virtual: true });

import S3DocViewer from 'c/s3DocViewer';
import updateDescriptions from '@salesforce/apex/S3DocService.updateDescriptions';
import getFile from '@salesforce/apex/S3DocService.getFile';
import getPresignedUrl from '@salesforce/apex/S3PresignService.getPresignedUrl';
import createS3File from '@salesforce/apex/S3FileCreator.create';
import getPresignedGetUrl from '@salesforce/apex/S3PresignService.getPresignedGetUrl';
import { Buffer } from 'buffer';

if (typeof global.atob === 'undefined') {
    global.atob = (input) => Buffer.from(input, 'base64').toString('binary');
}

describe('s3DocViewer handlers and wires', () => {
    afterEach(() => {
        jest.clearAllMocks();
    });

    it('handles filter and pagination events', () => {
        const ctx = { showExtended:false, showFilters:false, pageNumber:1 };
        S3DocViewer.prototype.toggleColumns.call(ctx);
        S3DocViewer.prototype.toggleFilters.call(ctx);
        S3DocViewer.prototype.handleSort.call(ctx,{detail:{fieldName:'Name',sortDirection:'asc'}});
        S3DocViewer.prototype.handleSearchChange.call(ctx,{target:{value:'s'}});
        S3DocViewer.prototype.handleTypeChange.call(ctx,{detail:{value:'img'}});
        S3DocViewer.prototype.handleYearFrom.call(ctx,{detail:{value:'2020'}});
        S3DocViewer.prototype.handleYearTo.call(ctx,{detail:{value:'2021'}});
        S3DocViewer.prototype.handleDateFrom.call(ctx,{target:{value:'2024-01-01'}});
        S3DocViewer.prototype.handleDateTo.call(ctx,{target:{value:'2024-01-02'}});
        S3DocViewer.prototype.handleSizeMin.call(ctx,{target:{value:'5'}});
        S3DocViewer.prototype.handleSizeMax.call(ctx,{target:{value:'10'}});
        S3DocViewer.prototype.handlePageSize.call(ctx,{detail:{value:'50'}});
        S3DocViewer.prototype.handleNameKey.call(ctx,{target:{value:'A'}});
        S3DocViewer.prototype.handleDescKey.call(ctx,{target:{value:'B'}});
        S3DocViewer.prototype.handleNameMode.call(ctx,{detail:{value:'starts'}});
        S3DocViewer.prototype.handleDescMode.call(ctx,{detail:{value:'contains'}});
        S3DocViewer.prototype.nextPage.call(ctx);
        S3DocViewer.prototype.prevPage.call(ctx);
        expect(ctx.showExtended).toBe(true);
        expect(ctx.showFilters).toBe(true);
        expect(ctx.sortBy).toBe('Name');
        expect(ctx.typeFilter).toBe('img');
        expect(ctx.yearFrom).toBe(2020);
        expect(ctx.pageSize).toBe(50);
        expect(ctx.descMode).toBe('contains');
        expect(ctx.pageNumber).toBe(1);
    });

    it('wired maps data and handles error', () => {
        const ctx = {
            labels:{ allTypes:'All', loadError:'err' },
            optionalCols:[{fieldName:'AccountUrl'},{fieldName:'ContactUrl'}],
            buildColumns: jest.fn().mockReturnValue(['col']),
            dispatchEvent: jest.fn(),
            safeMessage: (e)=>e.message
        };
        const data = [{
            Type__c:'image/png',
            Account_ID__r:{Name:'A'},
            Account_ID__c:'0011',
            s3Key:'key'
        }];
        S3DocViewer.prototype.wired.call(ctx,{ data, error: undefined });
        expect(ctx.docs.length).toBe(1);
        expect(ctx.dynamicColumns).toEqual(['col']);
        expect(ctx.optionalCols.length).toBe(1);

        const err = new Error('bad');
        S3DocViewer.prototype.wired.call(ctx,{ data: undefined, error: err });
        expect(ctx.error).toBe('bad');
        expect(ctx.dispatchEvent).toHaveBeenCalled();
    });

    it('wire option handlers map to picklist options', () => {
        const ctx = {};
        S3DocViewer.prototype.wiredOpps.call(ctx,{data:[{Name:'Opp',Id:'006'}]});
        S3DocViewer.prototype.wiredCases.call(ctx,{data:[{CaseNumber:'C1',Id:'500'}]});
        S3DocViewer.prototype.wiredContacts.call(ctx,{data:[{Name:'Bob',Id:'003'}]});
        expect(ctx.opportunityOptions[0].value).toBe('006');
        expect(ctx.caseOptions[0].label).toBe('C1');
        expect(ctx.contactOptions[0].label).toBe('Bob');
    });

    it('handleSave updates descriptions', async () => {
        updateDescriptions.mockResolvedValue();
        const ctx = {
            labels:{ saved:'saved', saveFailed:'fail' },
            docs:[{Id:'1', Description__c:'old'}],
            template:{ querySelector: jest.fn().mockReturnValue({ draftValues: [] }) },
            dispatchEvent: jest.fn(),
            isLoading:false
        };
        await S3DocViewer.prototype.handleSave.call(ctx,{detail:{draftValues:[{Id:'1', Description__c:'new'}]}});
        expect(updateDescriptions).toHaveBeenCalled();
        expect(ctx.docs[0].Description__c).toBe('new');
        expect(ctx.template.querySelector).toHaveBeenCalled();
    });

    it('handleFileChange sets preview for non-images', () => {
        const file = { name:'test.txt', type:'text/plain', size:4 };
        const ctx = { selectedFile:null, isImageSelected:false };
        global.URL.createObjectURL = jest.fn().mockReturnValue('blob:1');
        S3DocViewer.prototype.handleFileChange.call(ctx,{target:{files:[file]}});
        expect(ctx.editFileName).toBe('test');
        expect(ctx.previewFileUrl).toBe('blob:1');
    });

    it('clearSelectedFile revokes URLs and resets state', () => {
        global.URL.revokeObjectURL = jest.fn();
        const ctx = {
            previewImageUrl:'img',
            previewFileUrl:'file',
            template:{ querySelector: jest.fn() },
            selectedFile:'x', editFileName:'n', newDescription:'d', iconTone:'tone'
        };
        S3DocViewer.prototype.clearSelectedFile.call(ctx);
        expect(global.URL.revokeObjectURL).toHaveBeenCalledTimes(2);
        expect(ctx.selectedFile).toBeNull();
    });

    it('handleRowAction loads text files', async () => {
        const b64 = Buffer.from('hi').toString('base64');
        getFile.mockResolvedValue({ base64Data: b64, contentType: 'text/plain' });
        const ctx = {
            decodeUtf8: jest.fn().mockReturnValue('hi'),
            isImage: false,
            isText: true,
            isPdf: false,
            isDocx: false,
            isMsg: false,
            isEml: false,
            dispatchEvent: jest.fn(),
            labels: {}
        };
        await S3DocViewer.prototype.handleRowAction.call(ctx, { detail: { row: { Name: 'file.txt', s3Key: 'key' } } });
        expect(getFile).toHaveBeenCalled();
        expect(ctx.previewText).toBe('hi');
    });

    it('downloadFile uses base64 when available', async () => {
        const ctx = {
            previewSrc:'data:text/plain;base64,aGk=',
            previewName:'file.txt',
            template:{ appendChild: jest.fn(), removeChild: jest.fn() }
        };
        await S3DocViewer.prototype.downloadFile.call(ctx);
        expect(ctx.template.appendChild).toHaveBeenCalled();
    });

    it('downloadFile falls back to presigned URL', async () => {
        getPresignedGetUrl.mockResolvedValue('http://dl');
        const append = jest.fn();
        const remove = jest.fn();
        const origAppend = document.body.appendChild;
        const origRemove = document.body.removeChild;
        document.body.appendChild = append;
        document.body.removeChild = remove;
        const ctx = {
            previewSrc:null,
            previewS3Key:'key',
            previewName:'file.txt',
            dispatchEvent: jest.fn(),
            safeMessage: e=>e.message
        };
        await S3DocViewer.prototype.downloadFile.call(ctx);
        expect(getPresignedGetUrl).toHaveBeenCalled();
        document.body.appendChild = origAppend;
        document.body.removeChild = origRemove;
    });

    it('uploadFile sends file to server', async () => {
        getPresignedUrl.mockResolvedValue({ uploadUrl:'http://up', s3Key:'k' });
        global.fetch = jest.fn().mockResolvedValue({ ok:true });
        createS3File.mockResolvedValue();
        const file = { name:'test.txt', type:'text/plain', size:4 };
        const ctx = {
            labels:{ uploadedTitle:'up', uploadFailed:'fail', noFileSelected:'no' },
            selectedFile:file,
            editFileName:'test',
            newDescription:'d',
            newCreationYear:2024,
            newCreationDate:'2024-01-01',
            contextObject:'Account',
            recordId:'001',
            dispatchEvent: jest.fn(),
            closeModal: jest.fn()
        };
        await S3DocViewer.prototype.uploadFile.call(ctx);
        expect(getPresignedUrl).toHaveBeenCalled();
        expect(createS3File).toHaveBeenCalled();
        expect(ctx.isUploading).toBe(false);
    });
});