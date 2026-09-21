# Publishing a Linux release

The release workflow is [Packages](../.github/workflows/packages.yml). It builds
`.deb`, `.rpm`, Arch, AppImage and Flatpak assets for x86_64. There is no separate
`release.yml` workflow.

## Build artifacts versus releases

Running **Actions → Packages → Run workflow** on `main` builds and validates
packages, then stores them in the run's **Artifacts** section. It does **not**
create a GitHub Release. Publishing requires a `vMAJOR.MINOR.PATCH` tag whose
version matches `[workspace.package].version` in `Cargo.toml`.

The current package version is `0.1.0`. Versions starting with `0.` are marked
as GitHub **prereleases**. Use the repository's `/releases` page, since
`/releases/latest` does not select prereleases. Package filenames currently
require a numeric three-part version; prerelease suffixes are not supported.

## Prepare the commit

1. Update `Cargo.toml` when changing versions, regenerate `Cargo.lock` with
   `cargo check`, and update `packaging/linux/arch/PKGBUILD` and the AppStream
   release entry in `packaging/linux/org.betternotes.BetterNotes.metainfo.xml`.
2. Update `CHANGELOG.md`, the version examples in `README.md`, and
   `docs/release-notes.md`. The latter is the release body; GitHub-generated
   commit notes are appended automatically.
3. Run the checks below. Review the diff, commit the intended files, and push
   the release commit. Do not include local exports or build output.

```bash
cargo fmt --check
cargo check --locked
cargo clippy --all-targets --all-features --locked -- -D warnings
cargo test --locked
cargo build --release --locked
```

The app needs Qt 6.5+; the QML integration tests need Qt 6.7+ and QtTest.
See [packaging](../packaging/linux/README.md) for dependencies and known limitations.

## Publish

After deciding to publish the prepared commit, inspect `git status` and confirm
that HEAD is the intended release commit. Check that the tag does not already
exist locally or on the remote. For the first preview:

```bash
git tag -a v0.1.0 -m "BetterNotes v0.1.0"
git push origin v0.1.0
```

Use the actual Cargo version for later releases. Do not move or force-push a
published tag.

The workflow:

1. Rejects a tag/version mismatch before any package build.
2. Runs the shared CI formatting, Clippy, Rust/QML tests and release build.
3. Builds all five formats. It installs native packages in clean containers
   and smoke-tests them, then smoke-tests the AppImage on Ubuntu 24.04.
4. Waits for every required job before publishing.
5. Adds a source archive from the tagged commit and `SHA256SUMS`, then publishes
   all assets with the release notes. Missing package formats fail publication.

Only the publishing job receives `contents: write`. The repository's Actions
policy must permit that permission. No personal access token is needed.

Check the completed run and its release assets at
[GitHub Releases](https://github.com/thebanri/BetterNotes/releases). Download a
package with `SHA256SUMS` and check it before installation:

```bash
sha256sum --check --ignore-missing SHA256SUMS
```

If a transient job fails, rerun it from the tagged workflow run. To start another
full run for an existing tag, use:

```bash
gh workflow run packages.yml --ref v0.1.0
```

Running the same command with `--ref main` only produces build artifacts.
If fixing code or a workflow requires a new commit, prepare a new version and tag;
do not rewrite a tag already associated with distributed packages.

## Validation limits

Headless startup does not verify tray menus, notifications, compositor behavior,
or visual quality on every desktop. Flatpak currently has build coverage but no
GUI smoke test; host KWin integration and autostart are not working in its sandbox.
Record manual checks separately. A green package run does not establish Linux
v1.0 readiness across all target desktops.

Workflow references: [GitHub reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
and [the release action's inputs](https://github.com/softprops/action-gh-release#inputs).
