# Releasing Silica

Releases are DMGs attached to GitHub releases. Running copies find them through
[Sparkle](https://sparkle-project.org): they read the feed at `SUFeedURL` in
`Config/Info.plist`, which GitHub Pages serves from `docs/appcast.xml` on `main`.

```
scripts/release.sh 1.2.0                 # notes generated from the commits
scripts/release.sh 1.2.0 notes/1.2.0.md  # notes from a file
```

The script bumps the version, archives, signs with your Developer ID, notarizes
and staples the app and the DMG, tags `v1.2.0`, creates the GitHub release, then
adds the release to `docs/appcast.xml` and pushes it. Copies of Silica see the
update as soon as Pages redeploys. Run it from a clean, pushed `main`.

## One-time setup

1. **Bundle identifier.** It's `com.hieudinh.Silica`. Don't change it after the
   first release: settings are stored under it, and Sparkle only installs
   updates that keep it.

2. **GitHub repository and Pages.** Create the repository as `dqhieu/Silica`
   and push `main`. Then, in Settings › Pages, deploy from the `main` branch,
   `/docs` folder. The feed URL is `https://dqhieu.github.io/Silica/appcast.xml`;
   if the repository gets another name, change `SUFeedURL` to match before the
   first release. A custom domain later is fine as long as the old URL redirects.

3. **GitHub CLI.** `brew install gh`, then `gh auth login`.

4. **Developer ID certificate.** A "Developer ID Application" certificate for
   team BH46VD9229 has to be in your login keychain (Xcode › Settings ›
   Accounts › Manage Certificates).

5. **Notarization credentials.** Create an app-specific password at
   [account.apple.com](https://account.apple.com), then store it in the keychain:

   ```
   xcrun notarytool store-credentials silica-notary \
       --apple-id <your Apple ID> --team-id BH46VD9229
   ```

   Another profile name works too: `NOTARY_PROFILE=<name> scripts/release.sh …`.

6. **Sparkle signing key.** Updates are signed with the EdDSA key in your login
   keychain (the default `ed25519` account, which every Sparkle app you ship can
   share). Its public half is `SUPublicEDKey` in `Config/Info.plist`.

   The private key is the one secret that matters most. Anyone who has it can sign
   updates that every copy of Silica will install, and if it's lost, existing
   copies can never be updated again. Back it up in a password manager. Export it
   to your home folder, never into the repository, copy its contents into the
   password manager, then delete the file:

   ```
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/sparkle-private-key.txt
   rm ~/sparkle-private-key.txt
   ```

   To set up another Mac for releases, save the key from the password manager to
   a file outside the repository, import it with `generate_keys -f <file>`, and
   delete the file.

   The tools are there after the first release build; before that, they're in
   DerivedData under `SourcePackages/artifacts/sparkle/Sparkle/bin`. `.gitignore`
   also ignores files named like `*private-key*`, but don't rely on it.

## If a release stops partway

- **Before "Tagging"**: nothing was published, and the version bump is undone.
  Fix the problem and run the script again.
- **After the tag was pushed**: the GitHub release or the feed is missing. Create
  the release by hand with the DMG in `build/release/<version>/`, then run the
  last block of `scripts/release.sh` (generate_appcast and the commit of
  `docs/appcast.xml`) by hand. Don't re-run the whole script: the tag exists.

## Pulling a bad update

Delete its `<item>` from `docs/appcast.xml` and push. Copies that haven't
installed it yet stop being offered it. Then fix it and release a newer version:
Sparkle never downgrades.
