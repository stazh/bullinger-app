window.addEventListener('WebComponentsReady', function () {
  // Main UI elements used for filtering, list updates and map interaction
  const registerList = document.querySelector('.register-list');
  const splitList = document.querySelector('pb-split-list');
  const viewAll = document.querySelector('input[name="view"][value="all"]');
  const viewCorrespondence = document.querySelector(
    'input[name="view"][value="correspondence"]',
  );
  const viewMentions = document.querySelector(
    'input[name="view"][value="mentions"]',
  );
  const sentCheckbox = document.querySelector('input[name="correspSent"]');
  const receivedCheckbox = document.querySelector(
    'input[name="correspReceived"]',
  );
  const subfilter = document.querySelector('.checkboxes--subfilter');
  const scrollTopButton = document.getElementById('register-scroll-top');

  // Abort if required elements for filtering are not available
  if (
    !registerList ||
    !splitList ||
    !viewAll ||
    !viewCorrespondence ||
    !viewMentions ||
    !sentCheckbox ||
    !receivedCheckbox ||
    !subfilter
  ) {
    return;
  }

  // Trigger a refresh of the locality list
  function submitFilter() {
    splitList.submit();
  }

  // Convenience helper to toggle both correspondence role filters
  function setBothCorrespCheckboxes(checked) {
    sentCheckbox.checked = checked;
    receivedCheckbox.checked = checked;
  }

  // Visually indicate whether the correspondence subfilter is active
  function updateSubfilterState() {
    subfilter.classList.toggle('is-inactive', !viewCorrespondence.checked);
  }

  // "Correspondence and mentions":
  // deactivate both correspondence subfilters and reload the list
  viewAll.addEventListener('change', function () {
    if (viewAll.checked) {
      setBothCorrespCheckboxes(false);
      updateSubfilterState();
      submitFilter();
    }
  });

  // "Correspondence":
  // activate both correspondence role filters by default
  viewCorrespondence.addEventListener('change', function () {
    if (viewCorrespondence.checked) {
      setBothCorrespCheckboxes(true);
      updateSubfilterState();
      submitFilter();
    }
  });

  // "Mentions":
  // deactivate both correspondence subfilters and reload the list
  viewMentions.addEventListener('change', function () {
    if (viewMentions.checked) {
      setBothCorrespCheckboxes(false);
      updateSubfilterState();
      submitFilter();
    }
  });

  // Switch to the correspondence view when selecting a correspondence role checkbox
  [sentCheckbox, receivedCheckbox].forEach(function (checkbox) {
    checkbox.addEventListener('change', function (ev) {
      viewAll.checked = false;
      viewMentions.checked = false;
      viewCorrespondence.checked = true;

      // Keep at least one correspondence role filter selected
      if (!sentCheckbox.checked && !receivedCheckbox.checked) {
        ev.target.checked = true;
        return;
      }

      updateSubfilterState();
      submitFilter();
    });
  });

  updateSubfilterState();

  // Scroll the result list back to the first item
  function scrollItemsToTop() {
    const items = splitList.shadowRoot?.querySelector('#items');

    if (items) {
      items.scrollTop = 0;
    }
  }

  // Shortcut button for scrolling back to the top of the list
  if (scrollTopButton) {
    scrollTopButton.addEventListener('click', scrollItemsToTop);
  }

  // Show a loading overlay while the locality list is being updated
  pbEvents.subscribe('pb-start-update', 'transcription', function () {
    registerList.classList.add('is-loading');
  });

  // Synchronize markers on the map after the update finished
  pbEvents.subscribe('pb-end-update', 'transcription', function () {
    // Hide the loading overlay and reset scroll position
    registerList.classList.remove('is-loading');
    scrollItemsToTop();

    pbEvents.emit('pb-update', 'map', {
      root: splitList,
    });
  });

  // Navigate to the locality detail page when a map marker is clicked
  pbEvents.subscribe('pb-leaflet-marker-click', 'map', function (ev) {
    const geo = ev.detail.element;
    const item = geo.closest('.js-place-item');
    const link = item ? item.querySelector('.js-place-link') : null;
    const href = link ? link.getAttribute('href') : null;

    if (href) {
      window.location = href;
    }
  });
});
