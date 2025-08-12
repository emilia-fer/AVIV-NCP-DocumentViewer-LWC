import { createElement } from 'lwc';

jest.mock('@salesforce/resourceUrl/pdfjs', () => ({ default: '/pdfjs' }), { virtual: true });

import PdfViewer from 'c/pdfViewer';

// microtask-based flush (no setTimeout)
const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

describe('c-pdf-viewer', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('exposes undefined src before initialization', () => {
    const element = createElement('c-pdf-viewer', { is: PdfViewer });
    document.body.appendChild(element);

    const iframe = element.shadowRoot.querySelector('iframe');
    expect(iframe.getAttribute('src')).toBeNull();
    expect(element.src).toBeUndefined();
  });

  it('computes viewer URL from provided src', async () => {
    const element = createElement('c-pdf-viewer', { is: PdfViewer });
    document.body.appendChild(element);

    const testUrl = 'https://example.com/file name.pdf?foo=bar&baz=qux';
    element.src = testUrl;
    await flushPromises();

    const expected = `/pdfjs/web/viewer.html?file=${encodeURIComponent(testUrl)}`;
    const iframe = element.shadowRoot.querySelector('iframe');
    expect(iframe.getAttribute('src')).toBe(expected);
    expect(element.src).toBe(expected);

    const newUrl = 'blob://new';
    element.src = newUrl;
    await flushPromises();

    const expected2 = `/pdfjs/web/viewer.html?file=${encodeURIComponent(newUrl)}`;
    expect(iframe.getAttribute('src')).toBe(expected2);
    expect(element.src).toBe(expected2);
  });
});
