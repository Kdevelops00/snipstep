# Release checklist

Use the [validation record](VALIDATION.md) to distinguish an implemented feature from an observed run. This checklist separates the source preview from a downloadable consumer release.

## Source preview

- [x] Use Snipstep in the app, documentation, and widget configuration. Credit @Kdevelops00 and upstream work. The MIT license names the project copyright holder.
- [x] Verify manual tasks, offline capture processing, API request handling, and widget data logic with local tests.
- [x] Review the cropped walkthrough screenshots and credit the source material.
- [ ] Verify GitHub CI and private vulnerability reporting.

## Consumer download

- [ ] Resolve the built-in provider’s eligibility for the intended audience and regions. Google limits that API to professional or business use and imposes age and regional conditions. An optional bring-your-own-key setting does not resolve this distribution question. [Google’s API terms](https://ai.google.dev/gemini-api/terms).
- [ ] Test supported OS versions and hardware, screen permission transitions, shortcut conflicts, multiple displays, widget launch states, and VoiceOver and keyboard navigation.
- [ ] Verify branding, thumbnail legibility, completion, deletion and Add task from the physical macOS widget gallery.
- [ ] Check failure recovery on real disk exhaustion and restart, Keychain access across updates, and performance with a realistic library.
- [ ] Test each cloud integration promoted as working with synthetic content and a real credential. Check offline, quota, timeouts, key rejection, consent revocation, and local-only capture. Keep live credentials out of public CI.
- [ ] Verify distribution signing, sandbox and privacy declarations, and notarization as applicable. Inspect the signed archive for debug-only controls, private files, and credentials.
