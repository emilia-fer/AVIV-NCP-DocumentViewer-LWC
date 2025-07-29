import { LightningElement, api } from 'lwc';
import pdfjsLib from '@salesforce/resourceUrl/pdfjs';

export default class PdfViewer extends LightningElement {
    viewerUrl;

    @api
    set src(blobUrl) {
        // Point built-in viewer at our blob
        this.viewerUrl =
            `${pdfjsLib}/web/viewer.html?file=${encodeURIComponent(blobUrl)}`;
    }
    get src() { return this.viewerUrl; }
}
