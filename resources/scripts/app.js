/**
 * Waits for a specific element to appear inside the shadow DOM of a web component host,
 * and then invokes a callback with that element.
 *
 * @param {string} selector - CSS selector of the target element inside the shadow DOM.
 * @param {string} shadowHostSelector - CSS selector of the shadow host element.
 * @param {Function} callback - Function to be called once the element becomes available.
 *
 * This function can be called at any time — even before the DOM is fully loaded.
 * It automatically waits until the DOM is ready, then searches the shadow DOM for the given element.
 * If the element is not immediately available, it uses a MutationObserver to wait for it to be added.
 */
function waitForElementInShadow(selector, shadowHostSelector, callback) {
    const setup = () => {
        const host = document.querySelector(shadowHostSelector);
        if (!host || !host.shadowRoot) {
            console.warn("Shadow DOM not available: ", shadowHostSelector);
            return;
        }

        const element = host.shadowRoot.querySelector(selector);
        if (element) {
            callback(element);
        } else {
            const observer = new MutationObserver(() => {
                const element = host.shadowRoot.querySelector(selector);
                if (element) {
                    observer.disconnect();
                    callback(element);
                }
            });
            observer.observe(host.shadowRoot, { childList: true, subtree: true });
        }
    };

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => {
            requestAnimationFrame(() => requestAnimationFrame(setup));
        });
    } else {
        requestAnimationFrame(() => requestAnimationFrame(setup));
    }
}

/**
 * Synchronizes the checked state of multiple checkbox elements
 * whenever a custom event with a `detail.checked` property is fired.
 *
 * @param {string} eventName - The name of the custom event to listen for.
 * @param {HTMLInputElement[]} checkboxes - An array of checkbox elements to synchronize.
 */
function syncCheckboxesOnEvent(eventName, checkboxes) {
    window.addEventListener(eventName, function(e) {
        checkboxes.forEach(cb => {
            if (cb && cb.checked !== e.detail.checked) {
                cb.checked = e.detail.checked;
            }
        });
    });
}

window.addEventListener('DOMContentLoaded', function() {
    const toggle = document.querySelector('[name=lang-toggle]');

    function applyLangColors () {
        const view = document.getElementById('view1')
        const usage = view.shadowRoot.querySelector('.lang-usage')
        // hide toggle if there is nothing to display
        if (!usage) {
            toggle.parentElement.style.display = 'none';
            return;
        }
        toggle.parentElement.style.display = 'inline-block';
        if (toggle.checked) {
            usage.style.display = 'block';
            view.style.setProperty("--lang-de-color", 'var(--bb-lang-de-color)');
            view.style.setProperty("--lang-el-color", 'var(--bb-lang-el-color)');
            view.style.setProperty("--lang-la-color", 'var(--bb-lang-la-color)');
            view.style.setProperty("--lang-he-color", 'var(--bb-lang-he-color)');
            view.style.setProperty("--lang-fr-color", 'var(--bb-lang-fr-color)');
            view.style.setProperty("--lang-it-color", 'var(--bb-lang-it-color)');
            view.style.setProperty("--lang-en-color", 'var(--bb-lang-en-color)');
        } else {
            usage.style.display = 'none';
            view.style.setProperty("--lang-la-color", 'transparent');
            view.style.setProperty("--lang-el-color", 'transparent');
            view.style.setProperty("--lang-de-color", 'transparent');
            view.style.setProperty("--lang-he-color", 'transparent');
            view.style.setProperty("--lang-fr-color", 'transparent');
            view.style.setProperty("--lang-it-color", 'transparent');
            view.style.setProperty("--lang-en-color", 'transparent');
        }
    }

    toggle.addEventListener('change', applyLangColors);

    pbEvents.subscribe('pb-update', 'transcription', ev => {
        applyLangColors()
    });

    pbEvents.subscribe('pb-update', 'facsimile', ev => {
        document.getElementById("facsimile-status").style.display ="none";
    });

    pbEvents.subscribe('pb-update', 'metadata', ev => {
        const shadowroot = ev.detail.root;
        const metaView = ev.target;
        if(!metaView) return;
        const expander = metaView.shadowRoot.querySelector('.overlength .expander');
        if(!expander) return;
        expander.addEventListener('click', ev =>  {
            const regest = shadowroot.querySelector('.regesttext');
            const icon = ev.target.nodeName === 'IRON-ICON' ? ev.target : ev.target.firstElementChild;
            if(regest.classList.contains('overlength')){
                regest.classList.remove('overlength');
                icon.setAttribute('icon','arrow-drop-up');
                expander.style.display="block";
            }else{
                regest.classList.add('overlength');
                icon.setAttribute('icon','arrow-drop-down');
                regest.scrollIntoView({behavior: "smooth", block: "end", inline: "nearest"});
            }
        });

        // Link regest divisions to letter text
         const links = shadowroot.querySelectorAll('a.link-regest');
         links.forEach(element => {
            element.addEventListener('click', ev => {
                ev.preventDefault();

                const textView = document.getElementById("view1");
                const allTargets = textView.shadowRoot.querySelectorAll('div.link-regest')
                allTargets.forEach(e => e.classList.remove("active"));
                const id = element.getAttribute("href").replace("#", "");
                const targetElement = textView.shadowRoot.getElementById(id);
                if(targetElement) {
                    targetElement.scrollIntoView({ behavior: "smooth" });
                    targetElement.classList.add("active");
                }
            })
         });
    });


    pbEvents.subscribe('pb-update', 'transcription', ev => {
        const view = document.getElementById('view1');

        // Collect the y positions of all pb-facs-link elements in the transcription
        let yPositions = [];

        const updatePositions = () => {
            yPositions = [];
            const teiLineBreaks = view.shadowRoot.querySelectorAll("pb-facs-link.facs-link-hidden");
            teiLineBreaks.forEach((teiLb) => {
                const y = teiLb.getBoundingClientRect().top + window.scrollY;
                yPositions.push({
                    y: y,
                    order: teiLb.getAttribute('order'),
                    coordinates: teiLb.getAttribute('coordinates')
                });
            });
        };

        updatePositions();

        // Update the y positions when the size of view1 changes
        const observer = new ResizeObserver(updatePositions);
        observer.observe(view);

        // When the mouse is moved over the transcription, trigger the pb-show-annotation event
        // of the closest pb-facs-link element based on the y position of the mouse
        view.shadowRoot.addEventListener('mousemove', (ev) => {
            if(!yPositions.length) return;
            const y = ev.clientY + window.scrollY;
            // Find the nearest element: the one with the highest y position that is still smaller than the mouse y position
            const closest = yPositions.reduce((prev, curr) => {
                if (curr.y <= y && (!prev || curr.y > prev.y)) {
                    return curr;
                }
                return prev;
            }, null);
            if (closest) {
                pbEvents.emit('pb-show-annotation', 'facsimile', { order: closest.order, coordinates: JSON.parse(closest.coordinates) });
            } else {
                pbEvents.emit('pb-show-annotation', 'facsimile', { coordinates: null });
            }
        });
    });

    /**
     * Waits for the shadow DOM checkbox inside <pb-view id="metadata"> to become available,
     * then synchronizes its state with the light DOM checkbox whenever the 'entities-toggled'
     * event is fired. Non-existent checkboxes are filtered out before binding.
     */
    waitForElementInShadow('input#entityCheckbox', 'pb-view#metadata', (entityCheckboxShadow) => {
        const entityCheckboxLight = document.querySelector('.js-toggle-entities');
        syncCheckboxesOnEvent('entities-toggled', [entityCheckboxShadow, entityCheckboxLight].filter(Boolean));
    });
});

/**
 * Listens for the custom 'toggle-entities' event, which is dispatched when a user
 * interacts with one of the entity checkboxes (to toggle named entity highlighting).
 *
 * - Toggles the CSS class 'colorize-named-entities' on the <body> element depending on the checkbox state.
 * - Emits a second custom event, 'entities-toggled', to notify all synchronized checkboxes to update
 *   their state accordingly.
 */
window.addEventListener('toggle-entities', (e) => {
    const isChecked = e.detail.checked;
    document.body.classList.toggle('colorize-named-entities', isChecked);

    window.dispatchEvent(new CustomEvent('entities-toggled', {
        detail: { checked: isChecked },
        bubbles: true,
        composed: true
    }));
});
