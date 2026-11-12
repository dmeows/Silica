---
name: release
description: Release a new version of Silica — write the release notes from the git history since the last tag, run scripts/release.sh to build, notarize and publish it, then verify the GitHub release and the Sparkle update feed. Use this whenever the user asks to release, ship, publish or cut a version of Silica ("release 0.4.0", "ship a new version", "cut a patch release"), or asks for release notes for the next version, even if they don't mention the release script.
---

# Releasing Silica

`scripts/release.sh <version> <notes-file>` does the whole release: bumps the
version, archives, signs, notarizes the app and the DMG, tags, creates the GitHub
release and adds it to `docs/appcast.xml`. Your part is the three things the
script can't do: write good notes, run it without blocking, and check that what
it published is really there. `RELEASING.md` has the one-time setup and the
recovery steps; read it if a check fails or the script stops partway.

A release is public and can't be taken back (Sparkle never downgrades), so only
start one when the user asked for it. If they didn't name a version, propose one
(a minor bump when there are new features, a patch bump for fixes only) and get
their answer before running anything.

## 1. Read what changed

```bash
LAST=$(git describe --tags --abbrev=0)
git log "$LAST"..HEAD --pretty='%h %s%n%b'
gh release view "$LAST" --json body -q .body
```

Read the commit bodies, not just the subjects: they say what the user saw before
and what they see now, which is what the notes are made of. The previous
release's body is the format to match.

## 2. Write the notes

The notes appear on the GitHub release and in Sparkle's update window, so they
are read by people who use Silica, not people who build it. Write each item as
what changed for them.

```markdown
### What's new

- **Short statement of the change.** One or two sentences on what it does and, where it applies, where to find or turn off the setting.
- **Another change.** …

If you already have Silica, it will offer this update on its own, or choose **Silica › Check for Updates…**.

Found a bug or have an idea? Please [open an issue](https://github.com/dqhieu/Silica/issues).
```

- Leave out commits that don't change the app: the `Release x.y.z` and
  `Offer x.y.z in the update feed` commits, tooling, docs, CI, the launch video.
- One bullet per change the user would notice. Fold a fix into the feature it
  fixes when both are new in this release.
- Put the biggest change first.
- When a bullet names a menu item, a setting or a shortcut, look it up in the
  source (`Silica/App/AppCommands.swift`, `Silica/Views/SettingsView.swift`)
  and use the exact label and pane. Commit messages paraphrase.
- Write menu paths as **View › Minimap** and shortcuts with their symbols (⌃Tab).
- Keep the two closing paragraphs as they are.

Save the file where git won't see it, because the script refuses to run with
uncommitted or untracked files: the session scratchpad, or `build/` (ignored).
Not `build/release/<version>/`, which the script deletes when it starts.

## 3. Run the script

```bash
scripts/release.sh <version> <absolute path to the notes file>
```

Run it in the background: it takes several minutes, most of it waiting on Apple's
notarization. While it runs, show the user the notes you wrote.

The script checks its own preconditions before changing anything (clean tree, on
`main`, in sync with `origin/main`, tag not taken, signing certificate,
notarization profile, no mounted volume named Silica). If one fails, it says
which; fix that or tell the user, then run it again.

If it stops later, where it stopped decides what to do:

- **Before `==> Tagging`**: nothing was published and the version bump was
  undone. Fix the cause and run the script again.
- **After the tag was pushed**: don't run the script again, the tag exists.
  Follow "If a release stops partway" in `RELEASING.md` to finish by hand, and
  tell the user what state it is in before you do.

The first release on a Mac asks to let the terminal control Finder (for the DMG
window layout). If the script hangs at "Packing and notarizing the DMG", that
prompt is probably waiting on the user.

## 4. Verify

Exit code 0 means the script finished, not that users can get the update. Check
each of these:

```bash
# Every step ran, both notarizations were accepted
grep -E "^==>|status:" <script output>

# Two new commits and the tag, all pushed, tree clean
git status -sb && git log --oneline -3

# The release exists, isn't a draft, and has the DMG
gh release view v<version> --json name,isDraft,url,assets

# The committed feed has the new item
grep -n "sparkle:shortVersionString" docs/appcast.xml | head -3
```

Then the live feed, which is what running copies read. GitHub Pages redeploys
`docs/` within a minute or so of the push, so poll it rather than checking once:

```bash
FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" Config/Info.plist)
for i in $(seq 1 30); do
  curl -s "$FEED" | grep -q "<sparkle:shortVersionString><version></sparkle:shortVersionString>" && { echo live; break; }
  sleep 10
done
```

Run that in the background too. If the live feed still lacks the version after
five minutes, say so and point the user at the repository's Pages deployments
rather than reporting the release as done.

## 5. Report

Tell the user the release URL, the version and build number, what you verified
(notarization, git, release asset, live feed), and the notes as published,
including which commits you left out and why. Say plainly what you didn't check:
normally that is installing the update through Sparkle on a running copy.
