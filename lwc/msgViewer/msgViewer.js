import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import MSGREADER_MIN from '@salesforce/resourceUrl/msgreader_bundle';

export default class MsgViewer extends LightningElement {
    /** blob:… URL provided by parent */
    @api src;

    @track error;
    @track attachments;
    rendered = false;

    renderedCallback() {
        if (this.rendered) return;
        this.rendered = true;

        loadScript(this, MSGREADER_MIN + '/msgreader.bundle.js')
        .then(() => {
            // PATCH: assign to window (Locker sometimes only lets you do this here)
            if (typeof window.MsgReader === 'undefined') {
                window.MsgReader = MsgReader;
            }
            this.renderMsg();
        })
        .catch(e => { this.error = 'Unable to load MSG reader'; });

    }

    async renderMsg() {
        try {
            const buf = await fetch(this.src).then(r => r.arrayBuffer());
            const u8 = new Uint8Array(buf);

            // SAFER: Use window.MsgReader
            if (!window.MsgReader) {
                this.error = 'Unable to load MSG reader.';
                return;
            }

            const reader = new window.MsgReader(u8);
            const { html, body, attachments } = reader.getFileData();

            /* body */
            const div = this.template.querySelector('#msgContainer');
            div.innerHTML = html || `<pre>${body}</pre>`;

            /* attachments */
            if (attachments?.length) {
                this.attachments = attachments.map((a, i) => {
                    const bytes = Uint8Array.from(atob(a.content), c => c.charCodeAt(0));
                    const blob  = new Blob([bytes], { type: a.mimeType || 'application/octet-stream' });
                    return { id: i, fileName: a.fileName, url: URL.createObjectURL(blob) };
                });
            }
        } catch (e) {
            // Corrected error logging
            // eslint-disable-next-line no-console
            console.error('[msgViewer] FULL ERROR:', e, JSON.stringify(e));
            this.error = 'Unable to display this .msg file.';
        }
    }

    disconnectedCallback() {
        this.attachments?.forEach(a => URL.revokeObjectURL(a.url));
    }
}
