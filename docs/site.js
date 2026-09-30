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

const voiceButton = document.getElementById('voice-play');
let voiceTimer;
function stopVoiceDemo() {
  voiceButton.closest('.voice-demo').classList.remove('is-playing');
  voiceButton.setAttribute('aria-pressed', 'false');
  voiceButton.innerHTML = '<span aria-hidden="true">▶</span> Try the rhythm';
  clearTimeout(voiceTimer);
}
voiceButton.addEventListener('click', () => {
  if (voiceButton.getAttribute('aria-pressed') === 'true') return stopVoiceDemo();
  voiceButton.closest('.voice-demo').classList.add('is-playing');
  voiceButton.setAttribute('aria-pressed', 'true');
  voiceButton.innerHTML = '<span aria-hidden="true">Ⅱ</span> Pause the rhythm';
  voiceTimer = window.setTimeout(stopVoiceDemo, 8000);
});
document.addEventListener('visibilitychange', () => {
  if (document.hidden) stopVoiceDemo();
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

const motionButton = document.getElementById('motion-toggle');
function setMotionPaused(paused) {
  stage.classList.toggle('motion-paused', paused);
  motionButton.setAttribute('aria-pressed', String(paused));
  motionButton.textContent = paused ? 'Resume motion' : 'Pause motion';
  motionButton.hidden = motionPreference.matches;
}
motionButton.addEventListener('click', () => setMotionPaused(!stage.classList.contains('motion-paused')));
motionPreference.addEventListener('change', () => {
  setMotionPaused(motionPreference.matches);
  if (motionPreference.matches) stopVoiceDemo();
});
setMotionPaused(motionPreference.matches);
