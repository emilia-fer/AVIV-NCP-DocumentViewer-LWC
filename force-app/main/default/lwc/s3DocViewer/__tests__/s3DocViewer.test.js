import { createElement } from 'lwc';
import S3DocViewer from 'c/s3DocViewer';

describe('c-s3-doc-viewer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders a card titled "Documents"', () => {
        const element = createElement('c-s3-doc-viewer', {
            is: S3DocViewer
        });
        document.body.appendChild(element);

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();

        // The title is rendered in the .slds-card__header element
        const header = card.shadowRoot
            ? card.shadowRoot.querySelector('.slds-card__header')
            : card.querySelector('.slds-card__header');

        // If using LWC test utils, might need to look up text another way.
        expect(card.title).toBe('c.Documents');
    });
});
