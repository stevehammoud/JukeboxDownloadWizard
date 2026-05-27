Jukebox Download Wizard v0.2.1.2

Package layout:
  - .jukebox_download_wizard (hidden directory)
  - resources
  - JukeboxDownloadWizard.exe
  - README.txt
  - version.txt

How to run:
  1. Extract zip to preferred destination. 
  2. Double click on JukeboxDownloadWizard_Setup_vx.x.x.x.exe to begin the installation.
  3. Choose if you'd like shortcuts created.
  4. Paste contents of your exported cookie file. Clicking the button will open instructions to create the file. 
     If this is an upgrade of the application, users will not see this page and previous file will be used.
  5. Application can be launched from the installer on the last step.
  6. Application can be launched by double-clicking the desktop shortcut if one was created.
  7. Application can be launched by double-clicking JukeboxDownloadWizard.exe from the application folder 
     (C:\Program Files (x86)\Jukebox Download Wizard\).  
  8. Click Validate Required Tools & Resources inside the application to confirm the required tools have been 
     installed and the cookie file is valid. An error will be shown as the Selected Video list is empty.  
     This can be verified by clicking Show Console to see view application activity.

Cookie file setup:
  - NOTE:  This release does not include a cookie file.
  - Create your own YouTube cookie file by following:  
    C:\Program Files (x86)\Jukebox Download Wizard\resources\COOKIE_SETUP.txt
  - Save the exported cookie file as: 
    C:\Program Files (x86)\Jukebox Download Wizard\resources\ytcookies.txt
  - Do not share ytcookies.txt. It can contain private sign-in data for your YouTube/Google session.

The hidden .jukebox_download_wizard folder contains app internals, tools, cache, and temporary files. 
  - Users do not need to edit anything in the hidden folder. 
  - All downloaded MP4s and generated marquee artwork are also in this directory but will be emptied once MP4s 
    or artwork are moved to their respective storage medium.

Portable tools:
  - The app includes portable copies of yt-dlp, deno, and ffmpeg under the assets\tools folder.
    Clicking Resource Check will validate and report whether those bundled tools are being used.

Third-party notices:
  - Third-party tools, APIs, artwork sources, and relevant usage notes are documented here:
    C:\Program Files (x86)\Jukebox Download Wizard\resources\THIRD_PARTY_NOTICES.txt
  - This includes yt-dlp, FFmpeg, Deno, MusicBrainz, Cover Art Archive, Wikimedia/Wikidata, and fanart.tv notes.
  - Do not share private cookie files or personal API keys.

fanart.tv API keys:
  - The app includes a fanart.tv Project API Key for app-level artwork access.
  - Users may optionally add their own fanart.tv Personal API Key during installation or later here:
    C:\Program Files (x86)\Jukebox Download Wizard\resources\fanart_personal_api_key.txt
  - Personal keys should not be shared publicly.

Downloads and logs:
  - Downloaded videos are saved in the downloads folder.
  - Generated marquees are saved in the downloads\marquees folder.
  - App logs are saved in the logs folder.

Move MP4s to SSD:
  - All downloaded MP4s are moved to: \ha8800_screensaver\ or subdirectory of \ha8800_screensaver\ (if exists)

Move BitLCD Artwork:
  - All generated artwork is moved to:  \bitlcd\thirdparty\

Generate Missing MP4 Marquees:
  - Select any MP4 file from any directory (USB or Local PC) to generate the marquee artwork for selected MP4 files.




Source repository notes:
  - Third-party binaries are not tracked in Git. Local/release builds expect yt-dlp, Deno, FFmpeg, and FFprobe under assets\tools.
  - Private user files are not tracked. Use the .example.txt files in resources as local templates.
  - Do not commit real YouTube cookies or personal API keys.
  - The fanart.tv project key file is intentionally ignored for public source control.
