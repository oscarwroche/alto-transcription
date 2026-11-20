# Scope and workflow protection

- Preserve every existing user-facing workflow outside the requested change. Never remove, hide, or replace a control, import path, shortcut, or file behavior as part of an unrelated fix. If preserving it conflicts with the request, explain the conflict and get explicit approval before changing it.
- Before changing a UI workflow, identify how the customer actually uses it and check it in the copy they are using. Record the app path and version and the exact action you tried. If the customer reports a working behavior you cannot reproduce or find in the source, treat it as a workflow to protect and state what you could verify.
- Test Finder drag and drop of a real audio file into the editor as its own workflow. Opening the same file with the file picker does not verify it. For releases that touch import, project opening, or the main UI, verify both paths, playback and looping, and opening a saved project in the release bundle.
- Leave existing copies in Applications available and unchanged during development, testing, and release. Test the exact new version in a separate bundle. Offer Body and Soul for opt-in install, and test in-app updates on a disposable copy. Replace an existing copy only at the user's explicit request.

# Git history

- Commit completed changes in focused commits. Tag each version delivered to the user at the exact commit used to build it and identify that commit in the handoff. Keep build products, test recordings, and local project files out of Git.

# Customer handoff

- Treat opening and using the release without Codex as part of delivery. Give the customer one clear location and the exact next action they can take on their own. If a link opens the containing folder in Finder, label it as a folder and say what to double-click.
- Verify the handoff as the customer will use it. Open the exact release bundle from that location in Finder and check that a normal launch shows the blank score and audio import controls. When delivering a change, also exercise the changed workflow in that bundle. A development copy, a successful build, or launching the app for the customer does not establish that the handoff works.
- For updates, check what happens when an older copy is still running or a second copy is installed in Applications. Identify the version and location the customer should use. If a restart is necessary, give the customer the steps to save, quit, and reopen the release. Preserve their open work during verification.
- Say what was actually verified. If the customer’s workflow could not be tested, say so before calling the release ready.
