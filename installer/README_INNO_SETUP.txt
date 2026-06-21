Jukebox Download Wizard Inno Setup Build Notes

Version: 0.2.3.2

Purpose:

This folder contains the Inno Setup installer script for Jukebox Download Wizard.

What the installer does:

- Installs Jukebox Download Wizard under Program Files.
- Hides the internal .jukebox_download_wizard folder.
- Grants write access to the folders the app needs for resources, visible downloads, logs, cache, and temp files.
- Lets the user choose Desktop and Start Menu shortcuts.
- Shows a cookie setup page.
- Allows the user to paste exported cookie text.
- Validates pasted cookie text before writing resources\ytcookies.txt.
- Allows installation to continue with an empty cookie file if the user skips or fails validation.

How to install Inno Setup:

1. Download Inno Setup from:
   https://jrsoftware.org/isdl.php

2. Install Inno Setup.

3. Open:
   installer\JukeboxDownloadWizard.iss

4. Click Build > Compile.

5. The setup executable will be created in:
   dist\JukeboxDownloadWizard_Setup_v0.2.0.0.exe

Notes:

- The installer requires admin permission because it installs into Program Files.
- Uninstall removes the app install folder, including resources, visible downloads, logs, and cache.
- The app still hides .jukebox_download_wizard on launch as an extra safeguard.
