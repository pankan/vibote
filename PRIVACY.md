# Privacy

Vibote has no analytics, advertising SDK, or account service.

- Button mappings and settings are stored locally in macOS preferences.
- On-device mode requires Apple's on-device speech recognition. Audio is held in memory; Vibote does not save recordings or send this mode's audio to a server. Recognition depends on language/model availability.
- Dictated text is typed into the focused application. That application may store or transmit it.
- In AI voice app mode, remote audio is made available through Vibote Mic. The selected app may use cloud services according to its own settings and policy.
- Local Bluetooth diagnostics are stored at `~/Library/Application Support/Vibote/bluetooth-diagnostics.txt`. They contain protocol metadata, device names, and errors, not captured audio or transcripts. Review diagnostics before sharing them.
- Installing Handy through Vibote invokes Homebrew, which contacts its own download services. Opening product and app links opens external websites.
- The project website loads DM Sans from Google Fonts and is hosted by GitHub Pages; these services receive normal web requests. There are no website analytics scripts.

Vibote Mic is an input device that other permitted apps can select. Avoid leaving a third-party app recording when you do not intend it to receive audio.
