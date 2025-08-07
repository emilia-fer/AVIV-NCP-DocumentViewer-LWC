import { createElement } from 'lwc';
import Test_component from 'c/test_component';

describe('c-test-component', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders greeting', () => {
        const element = createElement('c-test-component', {
            is: Test_component
        });
        document.body.appendChild(element);

        const p = element.shadowRoot.querySelector('p');
        expect(p.textContent).toBe('This is my first Lightning Web Component.');
    });
});