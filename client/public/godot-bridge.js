window.initTutorialListener = function() {
  window.addEventListener('progress-changed', function(e) {
    if (window._tutDone === true && !e.detail.tutorial_complete) {
      location.reload();
    }
    window._tutDone = e.detail.tutorial_complete;
  });
};
