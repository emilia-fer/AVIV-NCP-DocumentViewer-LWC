import { LightningElement, api } from 'lwc';
import mammothLib from '@salesforce/resourceUrl/mammoth';
import { loadScript } from 'lightning/platformResourceLoader';

export default class DocxViewer extends LightningElement {
    rendered = false;
    _src;   // blob URL from parent

    @api
    set src(val) {
        this._src = val;
        this.renderDoc();
    }
    get src() { return this._src; }

    connectedCallback() {
        // load mammoth once
        loadScript(this, mammothLib + '/mammoth.browser.min.js')
            .then(() => { this.rendered = true; this.renderDoc(); })
            .catch(e => console.error('[docxViewer] load error', e));
    }

    async renderDoc() {
        if (!this.rendered || !this._src) return;

        const container = this.template.querySelector('.docxContainer');
        container.innerHTML = '<em>Loading DOCX…</em>';

        try {
            const buf  = await fetch(this._src).then(r => r.arrayBuffer());
            const res  = await window.mammoth.convertToHtml({ arrayBuffer: buf });
            container.innerHTML = res.value;
        } catch (e) {
            console.error('[docxViewer] error', e);
            container.innerHTML =
            `<p style="color:red">DOCX preview failed: ${e.message}</p>`;
        }
    }

}
