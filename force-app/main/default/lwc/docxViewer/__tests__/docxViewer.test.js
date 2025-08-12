import { createElement } from 'lwc';
import DocxViewer from 'c/docxViewer';
import { loadScript } from 'lightning/platformResourceLoader';

jest.mock('lightning/platformResourceLoader', () => ({
    loadScript: jest.fn()
}));

jest.mock('@salesforce/resourceUrl/mammoth', () => '/mammoth', { virtual: true });

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

describe('c-docx-viewer', () => {
    let fetchMock;
    beforeEach(() => {
        fetchMock = jest.fn();
        global.fetch = fetchMock;
        window.mammoth = { convertToHtml: jest.fn() };
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.resetAllMocks();
        delete global.fetch;
        delete window.mammoth;
    });

    it('renders content once script is loaded', async () => {
        loadScript.mockResolvedValue(undefined);
        fetchMock.mockResolvedValue({
            arrayBuffer: () => Promise.resolve(new ArrayBuffer(0))
        });
        const htmlResult = { value: '<p>hello</p>' };
        window.mammoth.convertToHtml.mockResolvedValue(htmlResult);

        const element = createElement('c-docx-viewer', { is: DocxViewer });
        document.body.appendChild(element);
        element.src = 'test-url';
        await flushPromises();

        expect(loadScript).toHaveBeenCalled();
        expect(fetchMock).toHaveBeenCalledWith('test-url');
        const container = element.shadowRoot.querySelector('.docxContainer');
        expect(container.innerHTML).toBe(htmlResult.value);
        expect(element.src).toBe('test-url');
    });

    it('defers rendering until script load resolves', async () => {
        let resolveScript;
        loadScript.mockReturnValue(new Promise(resolve => {
            resolveScript = resolve;
        }));
        fetchMock.mockResolvedValue({
            arrayBuffer: () => Promise.resolve(new ArrayBuffer(0))
        });
        window.mammoth.convertToHtml.mockResolvedValue({ value: '<p>done</p>' });

        const element = createElement('c-docx-viewer', { is: DocxViewer });
        document.body.appendChild(element);

        element.src = 'early';
        await flushPromises();
        expect(fetchMock).not.toHaveBeenCalled();

        resolveScript();
        await flushPromises();

        expect(fetchMock).toHaveBeenCalledWith('early');
        const container = element.shadowRoot.querySelector('.docxContainer');
        expect(container.innerHTML).toBe('<p>done</p>');
    });

    it('handles errors from mammoth conversion', async () => {
        loadScript.mockResolvedValue(undefined);
        fetchMock.mockResolvedValue({
            arrayBuffer: () => Promise.resolve(new ArrayBuffer(0))
        });
        window.mammoth.convertToHtml.mockRejectedValue(new Error('boom'));
        const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

        const element = createElement('c-docx-viewer', { is: DocxViewer });
        document.body.appendChild(element);
        element.src = 'url';
        await flushPromises();

        expect(errorSpy).toHaveBeenCalled();
        const container = element.shadowRoot.querySelector('.docxContainer');
        expect(container.innerHTML).toContain('DOCX preview failed');
        errorSpy.mockRestore();
    });

    it('logs loadScript errors', async () => {
        const err = new Error('no script');
        loadScript.mockRejectedValue(err);
        const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

        const element = createElement('c-docx-viewer', { is: DocxViewer });
        document.body.appendChild(element);
        await flushPromises();

        expect(errorSpy).toHaveBeenCalledWith('[docxViewer] load error', err);
        errorSpy.mockRestore();
    });
});