(function () {
  /* eslint-disable no-restricted-globals, @lwc/lwc/no-document-query, @lwc/lwc/no-inner-html, no-undef */
  /* Read ?b64=… */
  const params = new URLSearchParams(location.search);
  const b64 = params.get('b64');
  if (!b64) {
    document.getElementById('subject').innerText =
      'No file data received.';
    return;
  }

  /* Convert to Uint8Array */
  const bin = atob(b64);
  const u8  = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);

  try {
    const reader = new MsgReader(u8);
    const data   = reader.getFileData();

    /* Subject / body */
    document.title =
      document.getElementById('subject').innerText =
        data.subject || '(no subject)';
    document.getElementById('body').innerHTML =
        data.htmlBody || `<pre>${data.body || ''}</pre>`;

    /* Attachments */
    if (data.attachments && data.attachments.length) {
      const tmpl = document.getElementById('att-template').content.cloneNode(true);
      const list = tmpl.querySelector('ul');
      data.attachments.forEach((att, i) => {
        const bytes = Uint8Array.from(atob(att.content), c => c.charCodeAt(0));
        const blob  = new Blob([bytes], {type: att.mimeType || 'application/octet-stream'});
        const url   = URL.createObjectURL(blob);

        const li = document.createElement('li');
        const a  = document.createElement('a');
        a.href   = url;
        a.download = att.fileName || `attachment_${i}`;
        a.innerText = att.fileName || `attachment_${i}`;
        a.target = '_blank';
        li.appendChild(a);
        list.appendChild(li);
      });
      document.querySelector('.container').appendChild(tmpl);
    }
  } catch (e) {
    document.getElementById('subject').innerText =
      'Unable to display this MSG file.';
    console.error('[MsgPreview] error:', e);
  }
})();
