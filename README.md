# Jukebox Download Wizard

Windows desktop app for building YouTube video lists, downloading videos, and generating One saUCE jukebox marquee artwork.

## Download the app

Download the latest release from:

https://github.com/stevehammoud/JukeboxDownloadWizard/releases

Download the release ZIP:

```text
JukeboxDownloadWizard.zip
```

Extract the ZIP, then run the setup executable inside it:

```text
JukeboxDownloadWizard_Setup_vX.X.X.X.exe
```

The setup executable installs the app to:

```text
C:\Program Files (x86)\Jukebox Download Wizard\
```

## First run

1. Choose whether to create Desktop and Start Menu shortcuts.
2. Add YouTube cookie text during setup, or skip and add it later.
3. Optionally add a fanart.tv Personal API Key during setup, or skip and add it later.
4. Launch the app from the installer, Desktop shortcut, Start Menu shortcut, or installed app folder.
5. Click **Resource Check** inside the app to validate required tools and resources.

## YouTube cookie setup

This release does not include a YouTube cookie file. Users must provide their own if downloads require authentication.

After installation, cookie instructions are installed here:

```text
C:\Program Files (x86)\Jukebox Download Wizard\resources\COOKIE_SETUP.txt
```

The cookie file should be saved as:

```text
C:\Program Files (x86)\Jukebox Download Wizard\resources\ytcookies.txt
```

Do not share `ytcookies.txt`. It can contain private sign-in data for your YouTube/Google session.

## fanart.tv API keys

The app can use fanart.tv for optional artist artwork lookup. Packaged releases may include an app-level project key when allowed by the release maintainer.

Users may optionally add their own fanart.tv Personal API Key during installation or later here:

```text
C:\Program Files (x86)\Jukebox Download Wizard\resources\fanart_personal_api_key.txt
```

Personal API keys should not be shared publicly.

## Installed package layout

After installation, the app uses this layout:

```text
C:\Program Files (x86)\Jukebox Download Wizard\
  JukeboxDownloadWizard.exe
  README.txt
  version.txt
  resources\
  downloads\
  .jukebox_download_wizard\   hidden app internals
```

The hidden `.jukebox_download_wizard` folder contains app internals, bundled tools, cache, temporary files, and logs. Users normally do not need to edit anything in that hidden folder.

## Downloads and generated artwork

- Downloaded videos are saved in the visible app downloads folder: `C:\Program Files (x86)\Jukebox Download Wizard\downloads`.
- Generated marquees are saved in the visible app downloads\marquee folder.
- App logs are saved in the logs folder.
- Moving MP4s to SSD targets an existing `\ha8800_screensaver\` folder or selected subfolder.
- Moving BitLCD artwork targets an existing `\bitlcd\thirdparty\` folder.
- Generate Missing MP4 Marquees can create marquee artwork for selected MP4 files from another local, USB, or SSD directory.

## Third-party notices

Third-party tools, APIs, artwork sources, and usage notes are documented after installation here:

```text
C:\Program Files (x86)\Jukebox Download Wizard\resources\THIRD_PARTY_NOTICES.txt
```

The source copy is also available in this repository:

```text
THIRD_PARTY_NOTICES.txt
```

This includes notes for yt-dlp, FFmpeg, Deno, MusicBrainz, Cover Art Archive, Wikimedia/Wikidata, fanart.tv, bundled fonts, downloaded media, and generated artwork.

## Source repository notes

This GitHub repository contains source code and source assets. It does not include packaged release ZIPs or setup EXEs. Downloadable installers should be attached to GitHub Releases.

The following are intentionally not tracked in Git:

- release ZIP files
- setup EXE files
- downloaded videos
- generated marquees
- logs, cache, and temp files
- YouTube cookie files
- personal API keys
- local fanart.tv project API key file
- bundled third-party tool binaries

Local/release builds expect these third-party tools under `assets\tools`:

```text
assets\tools\yt-dlp.exe
assets\tools\deno\deno.exe
assets\tools\ffmpeg\bin\ffmpeg.exe
assets\tools\ffmpeg\bin\ffprobe.exe
```

These binaries are kept out of source control because they are large third-party redistribution artifacts with their own licenses. See `assets\tools\README.md` and `THIRD_PARTY_NOTICES.txt`.

## Build from source

A simple local build script is provided:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1
```

The installer script is located at:

```text
installer\JukeboxDownloadWizard.iss
```

Inno Setup is required to compile the installer.

