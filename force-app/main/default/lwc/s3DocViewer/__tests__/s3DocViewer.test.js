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

        const header = card.querySelector('.slds-card__header');
        expect(header.textContent).toBe('Documents');
    });
});