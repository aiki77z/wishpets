# Releasing Electron Builds

Electron releases are built from the `electron` branch by GitHub Actions.

## Manual Build

1. Go to GitHub -> Actions -> build-electron.
2. Click Run workflow.
3. Select the `electron` branch.
4. Download the Windows and macOS artifacts from the run summary.

## Tag Release

Push a version tag from the `electron` branch. For version 1.1.2:

```powershell
git switch electron
git push origin electron
git tag v1.1.2
git push origin v1.1.2
```

The workflow builds:

- Windows x64 NSIS installer and portable executable
- macOS Apple Silicon dmg/zip
- macOS Intel dmg/zip

Tag builds also publish the artifacts to a GitHub Release.

## Notes

- The macOS artifacts are unsigned and not notarized.
- The workflow uses `npm ci`, so keep `package-lock.json` committed with the
  matching app version.
