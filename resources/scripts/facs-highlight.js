window.addEventListener('DOMContentLoaded', function () {
    function clearHighlight() {
        const facsimile = document.getElementById('facsimile');
        if (facsimile && facsimile.overlay && facsimile._tify?.viewer) {
            facsimile._tify.viewer.removeOverlay(facsimile.overlay);
            facsimile.overlay = null;
        }
        CSS.highlights?.delete('facs-text-highlight');
    }

    function highlightTextRange(targetPos, positions, contentDiv) {
        if (!CSS.highlights) return;
        CSS.highlights.delete('facs-text-highlight');
        if (!targetPos) return;

        const idx = positions.indexOf(targetPos);
        if (idx < 0) return;

        const range = new Range();
        range.setStartAfter(targetPos.element);
        if (idx + 1 < positions.length) {
            range.setEndBefore(positions[idx + 1].element);
        } else {
            range.setEnd(contentDiv, contentDiv.childNodes.length);
        }

        CSS.highlights.set('facs-text-highlight', new Highlight(range));
    }

    // Returns the text node at (x, y) inside shadowRoot, falling back to the element.
    // A text node sits precisely between its sibling facs-links, so compareDocumentPosition
    // works correctly even when multiple facs-links share the same parent element.
    function findNodeAtPoint(x, y, shadowRoot) {
        const element = shadowRoot.elementFromPoint(x, y);
        if (!element) return null;
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
            const range = document.createRange();
            range.selectNodeContents(node);
            for (const rect of range.getClientRects()) {
                if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
                    return node;
                }
            }
        }
        return element;
    }

    pbEvents.subscribe('pb-update', 'transcription', ev => {
        const view = document.getElementById('view1');

        const style = document.createElement('style');
        style.textContent = '::highlight(facs-text-highlight) { background-color: rgba(0, 0, 128, 0.08); }';
        view.shadowRoot.appendChild(style);

        let positions = [];
        let contentDiv = null;

        const updatePositions = () => {
            positions = [];
            contentDiv = view.shadowRoot.querySelector('#content');
            view.shadowRoot.querySelectorAll('pb-facs-link.facs-link-hidden').forEach(el => {
                positions.push({
                    element: el,
                    order: el.getAttribute('order'),
                    coordinates: el.getAttribute('coordinates')
                });
            });
        };

        updatePositions();

        // Re-collect if the transcription content is re-rendered
        const observer = new ResizeObserver(updatePositions);
        observer.observe(view);

        view.addEventListener('mouseleave', clearHighlight);

        view.shadowRoot.addEventListener('mousemove', (ev) => {
            if (!positions.length) return;

            // Resolve the precise node under the cursor. elementFromPoint returns an element,
            // but when two facs-links share the same parent element, comparing the parent via
            // compareDocumentPosition gives CONTAINS|PRECEDING — not FOLLOWING — and we break
            // too early. A text node between siblings is exact, so we look for one first.
            const target = findNodeAtPoint(ev.clientX, ev.clientY, view.shadowRoot);
            if (!target || target.nodeType !== Node.TEXT_NODE || !contentDiv?.contains(target)
                    || target.parentElement?.closest('.inline-remark')) {
                clearHighlight();
                return;
            }

            // Walk positions in DOM order; keep the last facs-link that precedes the target.
            // DOCUMENT_POSITION_FOLLOWING means target comes after pos.element in the DOM tree.
            let closest = null;
            for (const pos of positions) {
                if (pos.element.compareDocumentPosition(target) & Node.DOCUMENT_POSITION_FOLLOWING) {
                    closest = pos;
                } else {
                    break;
                }
            }

            if (!closest) {
                clearHighlight();
                return;
            }

            pbEvents.emit('pb-show-annotation', 'facsimile', { order: closest.order, coordinates: JSON.parse(closest.coordinates) });
            highlightTextRange(closest, positions, contentDiv);
        });
    });
});
