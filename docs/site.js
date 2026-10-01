// Prefill a draft; visitors review and submit it themselves on GitHub.
const requestLink = document.getElementById('request-remote-link');
if (requestLink) {
  const request = new URL('https://github.com/pankan/vibote/issues/new');
  request.searchParams.set('title', '[Remote support] Brand / model');
  request.searchParams.set('body', `## Remote
Brand and model:
Product link:

## Features
Bluetooth support:
Microphone:
Keyboard on the back:

## Photos
Please attach photos of the front and back, if available.

## Testing
Do you own this remote?
Can you help test it on a Mac?
macOS version:

## Anything else
`);
  requestLink.href = request.toString();
}

document.querySelectorAll('[data-copy]').forEach((button) => {
  button.addEventListener('click', async () => {
    const code = document.getElementById(button.dataset.copy);
    const status = document.getElementById('copy-status');
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = 'Copied';
      status.textContent = 'Commands copied to clipboard.';
      window.setTimeout(() => { button.textContent = 'Copy'; }, 2000);
    } catch {
      // Let visitors copy manually if clipboard access is unavailable.
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(code);
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = 'Select and copy the highlighted commands.';
      button.textContent = 'Select & copy';
    }
  });
});

// A fixed dimensional pose with a gentle float; no pointer or flip interaction.
const motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
const stage = document.getElementById('remote-stage');

document.querySelectorAll('[data-shortcut]').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-shortcut]').forEach((option) => {
      option.classList.toggle('active', option === button);
      option.setAttribute('aria-pressed', String(option === button));
    });
    const key = document.getElementById('demo-key');
    key.textContent = button.dataset.shortcut;
    document.getElementById('shortcut-feedback').textContent = button.dataset.description;
    key.classList.add('pressed');
    window.setTimeout(() => key.classList.remove('pressed'), 160);
  });
});

// Progressive enhancement: content stays visible if observers are unavailable.
if ('IntersectionObserver' in window && !motionPreference.matches) {
  document.documentElement.classList.add('motion-ready');
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.08 });
  document.querySelectorAll('.section-heading, .feature, .app-heading, .app-screenshot, .hardware-copy, .hardware-image, .request-copy, .request-details, .setup-intro, .setup-steps, .faq, .open-source').forEach((element) => {
    element.classList.add('reveal');
    observer.observe(element);
  });
}

// Respect the system Reduce Motion setting.
function syncMotionPreference() {
  stage.classList.toggle('motion-paused', motionPreference.matches);
}
motionPreference.addEventListener('change', syncMotionPreference);
syncMotionPreference();
