#define MyAppName "Jukebox Download Wizard"
#define MyAppId "B8F37529-4779-4554-9B74-E5153AE71362"
#define MyAppVersion "0.2.2.1"
#define MyAppPublisher "Steve Hammoud"
#define MyAppExeName "JukeboxDownloadWizard.exe"

[Setup]
AppId={{B8F37529-4779-4554-9B74-E5153AE71362}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=JukeboxDownloadWizard_Setup_v{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
SetupIconFile=..\assets\images\JukeboxDownloadWizard.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a Desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce
Name: "startmenuicon"; Description: "Create a Start Menu shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Dirs]
Name: "{app}\resources"; Permissions: users-modify
Name: "{app}\downloads"; Permissions: users-modify
Name: "{app}\downloads\discard"; Permissions: users-modify
Name: "{app}\logs"; Permissions: users-modify
Name: "{app}\.jukebox_download_wizard"; Attribs: hidden; Permissions: users-modify
Name: "{app}\.jukebox_download_wizard\assets\resources"; Permissions: users-modify
Name: "{app}\.jukebox_download_wizard\assets\resources\cache"; Permissions: users-modify
Name: "{app}\.jukebox_download_wizard\assets\resources\temp"; Permissions: users-modify

[Files]
Source: "..\JukeboxDownloadWizard.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion
Source: "..\version.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\resources\COOKIE_SETUP.txt"; Flags: dontcopy
Source: "..\resources\FANART_SETUP.txt"; Flags: dontcopy
Source: "..\resources\COOKIE_SETUP.txt"; DestDir: "{app}\resources"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.txt"; DestDir: "{app}\resources"; Flags: ignoreversion
Source: "..\resources\FANART_SETUP.txt"; DestDir: "{app}\resources"; Flags: ignoreversion
Source: "..\resources\fanart_project_api_key.txt"; DestDir: "{app}\resources"; Flags: ignoreversion
Source: "..\resources\fanart_personal_api_key.example.txt"; DestDir: "{app}\resources"; DestName: "fanart_personal_api_key.txt"; Flags: onlyifdoesntexist
Source: "..\resources\ytcookies.example.txt"; DestDir: "{app}\resources"; DestName: "ytcookies.txt"; Flags: onlyifdoesntexist
Source: "..\resources\jukebox_urls.example.txt"; DestDir: "{app}\resources"; DestName: "jukebox_urls.txt"; Flags: onlyifdoesntexist
Source: "..\version.txt"; DestDir: "{app}\.jukebox_download_wizard"; Flags: ignoreversion
Source: "..\assets\*"; DestDir: "{app}\.jukebox_download_wizard\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startmenuicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
var
  CookiePage: TWizardPage;
  AddCookieNowCheck: TNewCheckBox;
  CookieMemo: TMemo;
  CookieInstructions: TNewStaticText;
  ViewCookieInstructionsButton: TNewButton;
  ValidatedCookieText: String;
  FanartPage: TWizardPage;
  AddFanartNowCheck: TNewCheckBox;
  FanartMemo: TMemo;
  FanartInstructions: TNewStaticText;
  ViewFanartInstructionsButton: TNewButton;
  ValidatedFanartPersonalKey: String;
  ExistingInstallPath: String;
  IsUpgradeInstall: Boolean;
const
  HWND_TOPMOST = -1;
  HWND_NOTOPMOST = -2;
  SW_RESTORE = 9;
  SWP_NOSIZE = 1;
  SWP_NOMOVE = 2;
  SWP_SHOWWINDOW = 64;

function SetForegroundWindow(hWnd: HWND): Boolean;
  external 'SetForegroundWindow@user32.dll stdcall';
function BringWindowToTop(hWnd: HWND): Boolean;
  external 'BringWindowToTop@user32.dll stdcall';
function ShowWindow(hWnd: HWND; nCmdShow: Integer): Boolean;
  external 'ShowWindow@user32.dll stdcall';
function SetWindowPos(hWnd: HWND; hWndInsertAfter: Integer; X: Integer; Y: Integer; cx: Integer; cy: Integer; uFlags: Integer): Boolean;
  external 'SetWindowPos@user32.dll stdcall';

procedure ForceWizardToFront;
begin
  ShowWindow(WizardForm.Handle, SW_RESTORE);
  SetWindowPos(WizardForm.Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_SHOWWINDOW);
  BringWindowToTop(WizardForm.Handle);
  SetForegroundWindow(WizardForm.Handle);
  SetWindowPos(WizardForm.Handle, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_SHOWWINDOW);
end;


function CountTabs(Value: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(Value) do
  begin
    if Value[I] = #9 then
    begin
      Result := Result + 1;
    end;
  end;
end;

function IsCookieDomainLine(Line: String): Boolean;
var
  LowerLine: String;
begin
  LowerLine := Lowercase(Line);
  Result :=
    (Pos('youtube.com', LowerLine) > 0) or
    (Pos('google.com', LowerLine) > 0) or
    (Pos('googlevideo.com', LowerLine) > 0);
end;

function GetExistingInstallPath(var InstallPath: String): Boolean;
var
  KeyPath: String;
begin
  KeyPath := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\\{{#MyAppId}_is1';
  Result :=
    RegQueryStringValue(HKLM, KeyPath, 'InstallLocation', InstallPath) or
    RegQueryStringValue(HKLM64, KeyPath, 'InstallLocation', InstallPath) or
    RegQueryStringValue(HKCU, KeyPath, 'InstallLocation', InstallPath);

  if Result then
  begin
    InstallPath := RemoveBackslash(InstallPath);
  end;
end;

function IsFirstInstall: Boolean;
begin
  Result := not IsUpgradeInstall;
end;
function ValidateCookieText(Text: String): Boolean;
var
  Lines: TStringList;
  I: Integer;
  Line: String;
  ValidCookieLines: Integer;
begin
  Result := False;
  ValidCookieLines := 0;

  if Trim(Text) = '' then
  begin
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then
      begin
        Continue;
      end;
      if Copy(Line, 1, 1) = '#' then
      begin
        Continue;
      end;

      if (CountTabs(Line) >= 6) and IsCookieDomainLine(Line) then
      begin
        ValidCookieLines := ValidCookieLines + 1;
      end;
    end;

    Result := ValidCookieLines > 0;
  finally
    Lines.Free;
  end;
end;

procedure ToggleCookieMemo;
begin
  CookieMemo.Enabled := AddCookieNowCheck.Checked;
  CookieMemo.Color := clWindow;
  if not AddCookieNowCheck.Checked then
  begin
    CookieMemo.Color := $F0F0F0;
  end;
end;

procedure AddCookieNowCheckClick(Sender: TObject);
begin
  ToggleCookieMemo;
end;

function ValidateFanartPersonalKey(Text: String): Boolean;
var
  KeyText: String;
  I: Integer;
  Ch: String;
begin
  KeyText := Trim(Text);
  Result := False;
  if (Length(KeyText) < 16) or (Length(KeyText) > 80) then
  begin
    Exit;
  end;

  for I := 1 to Length(KeyText) do
  begin
    Ch := Copy(KeyText, I, 1);
    if Pos(Ch, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-') = 0 then
    begin
      Exit;
    end;
  end;

  Result := True;
end;

procedure ToggleFanartMemo;
begin
  FanartMemo.Enabled := AddFanartNowCheck.Checked;
  FanartMemo.Color := clWindow;
  if not AddFanartNowCheck.Checked then
  begin
    FanartMemo.Color := $F0F0F0;
  end;
end;

procedure AddFanartNowCheckClick(Sender: TObject);
begin
  ToggleFanartMemo;
end;

procedure ViewCookieInstructionsButtonClick(Sender: TObject);
var
  ErrorCode: Integer;
begin
  ExtractTemporaryFile('COOKIE_SETUP.txt');
  if not ShellExec('', ExpandConstant('{tmp}\COOKIE_SETUP.txt'), '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
  begin
    MsgBox('Could not open the full cookie setup instructions. The file will still be installed to resources\COOKIE_SETUP.txt.', mbError, MB_OK);
  end;
end;

procedure ViewFanartInstructionsButtonClick(Sender: TObject);
begin
  MsgBox(
    'fanart.tv Personal API Key setup' + #13#10 + #13#10 +
    'The app includes a fanart.tv Project API Key for app-level access.' + #13#10 + #13#10 +
    'Adding your own Personal API Key is optional, but can help because:' + #13#10 +
    '- Newer approved artwork may appear sooner.' + #13#10 +
    '- fanart.tv can associate requests with your account as well as the app project.' + #13#10 +
    '- You can update or remove the personal key later without reinstalling.' + #13#10 + #13#10 +
    'To get a key, sign into fanart.tv and visit:' + #13#10 +
    'https://fanart.tv/get-an-api-key/' + #13#10 + #13#10 +
    'Paste only the Personal API Key value. Do not share your personal key publicly.',
    mbInformation,
    MB_OK
  );
end;

function ExistingCookieFileValid: Boolean;
var
  Lines: TStringList;
  CookieText: String;
begin
  Result := False;
  if not FileExists(ExpandConstant('{app}\resources\ytcookies.txt')) then
  begin
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(ExpandConstant('{app}\resources\ytcookies.txt'));
    CookieText := Lines.Text;
    Result := ValidateCookieText(CookieText);
  finally
    Lines.Free;
  end;
end;

function ExistingFanartPersonalKeyValid: Boolean;
var
  Lines: TStringList;
  KeyText: String;
begin
  Result := False;
  if not FileExists(ExpandConstant('{app}\resources\fanart_personal_api_key.txt')) then
  begin
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(ExpandConstant('{app}\resources\fanart_personal_api_key.txt'));
    KeyText := Lines.Text;
    Result := ValidateFanartPersonalKey(KeyText);
  finally
    Lines.Free;
  end;
end;

procedure InitializeWizard;
begin
  IsUpgradeInstall := GetExistingInstallPath(ExistingInstallPath);
  ForceWizardToFront;
  CookiePage := CreateCustomPage(
    wpSelectTasks,
    'YouTube Cookie File',
    'Downloads may require a YouTube cookie file.'
  );

  CookieInstructions := TNewStaticText.Create(CookiePage);
  CookieInstructions.Parent := CookiePage.Surface;
  CookieInstructions.Left := 0;
  CookieInstructions.Top := 0;
  CookieInstructions.Width := CookiePage.SurfaceWidth;
  CookieInstructions.Height := ScaleY(82);
  CookieInstructions.WordWrap := True;
  CookieInstructions.Caption :=
    'Jukebox Download Wizard can be installed without cookies, but some YouTube downloads may fail until a valid ytcookies.txt file is added.' + #13#10 + #13#10 +
    'On upgrades, your existing cookies, video list, downloads, logs, cache, and settings are preserved. Cookie import is shown only when the existing cookie file is missing or invalid.' + #13#10 + #13#10 +
    'To add cookies now, export a Netscape-format YouTube cookie file, check the box below, and paste the full cookie text. You can also skip this step and add or update the cookie file later from the app resources folder.';

  ViewCookieInstructionsButton := TNewButton.Create(CookiePage);
  ViewCookieInstructionsButton.Parent := CookiePage.Surface;
  ViewCookieInstructionsButton.Left := 0;
  ViewCookieInstructionsButton.Top := CookieInstructions.Top + CookieInstructions.Height + ScaleY(8);
  ViewCookieInstructionsButton.Width := ScaleX(230);
  ViewCookieInstructionsButton.Height := ScaleY(25);
  ViewCookieInstructionsButton.Caption := 'Open full cookie setup instructions';
  ViewCookieInstructionsButton.OnClick := @ViewCookieInstructionsButtonClick;

  AddCookieNowCheck := TNewCheckBox.Create(CookiePage);
  AddCookieNowCheck.Parent := CookiePage.Surface;
  AddCookieNowCheck.Left := 0;
  AddCookieNowCheck.Top := ViewCookieInstructionsButton.Top + ViewCookieInstructionsButton.Height + ScaleY(10);
  AddCookieNowCheck.Width := CookiePage.SurfaceWidth;
  AddCookieNowCheck.Caption := 'I want to paste my exported cookie file now';
  AddCookieNowCheck.Checked := False;
  AddCookieNowCheck.Enabled := True;
  if IsUpgradeInstall and not ExistingCookieFileValid then
  begin
    AddCookieNowCheck.Caption := 'Existing cookie file is missing or invalid. I want to paste a replacement now.';
  end;
  AddCookieNowCheck.OnClick := @AddCookieNowCheckClick;

  CookieMemo := TMemo.Create(CookiePage);
  CookieMemo.Parent := CookiePage.Surface;
  CookieMemo.Left := 0;
  CookieMemo.Top := AddCookieNowCheck.Top + ScaleY(28);
  CookieMemo.Width := CookiePage.SurfaceWidth;
  CookieMemo.Height := ScaleY(140);
  CookieMemo.ScrollBars := ssVertical;
  CookieMemo.WordWrap := False;
  CookieMemo.Enabled := False;
  CookieMemo.Color := $F0F0F0;
  if IsUpgradeInstall then
  begin
    CookieMemo.Text := 'Upgrade detected at: ' + ExistingInstallPath + #13#10 + #13#10 + 'Existing user data will be preserved. This page is shown because ytcookies.txt is missing, empty, or invalid. You may paste a replacement now or continue and update it later from the app resources folder.';
  end;

  FanartPage := CreateCustomPage(
    CookiePage.ID,
    'fanart.tv Personal API Key',
    'Optional artist artwork access for marquee generation.'
  );

  FanartInstructions := TNewStaticText.Create(FanartPage);
  FanartInstructions.Parent := FanartPage.Surface;
  FanartInstructions.Left := 0;
  FanartInstructions.Top := 0;
  FanartInstructions.Width := FanartPage.SurfaceWidth;
  FanartInstructions.Height := ScaleY(110);
  FanartInstructions.WordWrap := True;
  FanartInstructions.Caption :=
    'Jukebox Download Wizard includes a fanart.tv Project API Key for app-level access. You may optionally add your own fanart.tv Personal API Key.' + #13#10 + #13#10 +
    'Benefits: newer approved artwork may become available sooner, requests are associated with your fanart.tv account as well as the app project, and the key can be updated later without reinstalling.' + #13#10 + #13#10 +
    'This step is skipped on upgrades when a valid personal key already exists. You can also leave it blank and add it later in the resources folder.';

  ViewFanartInstructionsButton := TNewButton.Create(FanartPage);
  ViewFanartInstructionsButton.Parent := FanartPage.Surface;
  ViewFanartInstructionsButton.Left := 0;
  ViewFanartInstructionsButton.Top := FanartInstructions.Top + FanartInstructions.Height + ScaleY(8);
  ViewFanartInstructionsButton.Width := ScaleX(250);
  ViewFanartInstructionsButton.Height := ScaleY(25);
  ViewFanartInstructionsButton.Caption := 'Open fanart.tv key instructions';
  ViewFanartInstructionsButton.OnClick := @ViewFanartInstructionsButtonClick;

  AddFanartNowCheck := TNewCheckBox.Create(FanartPage);
  AddFanartNowCheck.Parent := FanartPage.Surface;
  AddFanartNowCheck.Left := 0;
  AddFanartNowCheck.Top := ViewFanartInstructionsButton.Top + ViewFanartInstructionsButton.Height + ScaleY(10);
  AddFanartNowCheck.Width := FanartPage.SurfaceWidth;
  AddFanartNowCheck.Caption := 'I want to paste my fanart.tv Personal API Key now';
  AddFanartNowCheck.Checked := False;
  AddFanartNowCheck.OnClick := @AddFanartNowCheckClick;

  FanartMemo := TMemo.Create(FanartPage);
  FanartMemo.Parent := FanartPage.Surface;
  FanartMemo.Left := 0;
  FanartMemo.Top := AddFanartNowCheck.Top + ScaleY(28);
  FanartMemo.Width := FanartPage.SurfaceWidth;
  FanartMemo.Height := ScaleY(70);
  FanartMemo.ScrollBars := ssVertical;
  FanartMemo.WordWrap := False;
  FanartMemo.Enabled := False;
  FanartMemo.Color := $F0F0F0;
  if IsUpgradeInstall then
  begin
    FanartMemo.Text := 'Upgrade detected at: ' + ExistingInstallPath + #13#10 + #13#10 + 'This page is shown because fanart_personal_api_key.txt is missing or invalid. You may paste a personal key now or continue without one.';
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = CookiePage.ID) and ExistingCookieFileValid then
  begin
    Result := True;
  end;
  if (PageID = FanartPage.ID) and ExistingFanartPersonalKeyValid then
  begin
    Result := True;
  end;
end;
procedure CurPageChanged(CurPageID: Integer);
begin
  ForceWizardToFront;
end;
function NextButtonClick(CurPageID: Integer): Boolean;
var
  Retry: Integer;
begin
  Result := True;

  if CurPageID = CookiePage.ID then
  begin
    ValidatedCookieText := '';

    if AddCookieNowCheck.Checked then
    begin
      if ValidateCookieText(CookieMemo.Text) then
      begin
        ValidatedCookieText := CookieMemo.Text;
        MsgBox('Cookie file validation passed. The installer will save this to resources\ytcookies.txt.', mbInformation, MB_OK);
      end
      else
      begin
        Retry := MsgBox(
          'Cookie validation failed. The pasted text must look like a Netscape-format cookie export and include at least one YouTube or Google cookie line.' + #13#10 + #13#10 +
          'Click Yes to retry, or No to continue with an empty cookie file. Downloads that require cookies may not work until a valid cookie file is added later.',
          mbError,
          MB_YESNO
        );

        if Retry = IDYES then
        begin
          Result := False;
        end
        else
        begin
          AddCookieNowCheck.Checked := False;
          ValidatedCookieText := '';
          ToggleCookieMemo;
        end;
      end;
    end;
  end;

  if CurPageID = FanartPage.ID then
  begin
    ValidatedFanartPersonalKey := '';

    if AddFanartNowCheck.Checked then
    begin
      if ValidateFanartPersonalKey(FanartMemo.Text) then
      begin
        ValidatedFanartPersonalKey := Trim(FanartMemo.Text);
        MsgBox('fanart.tv Personal API Key validation passed. The installer will save this to resources\fanart_personal_api_key.txt.', mbInformation, MB_OK);
      end
      else
      begin
        Retry := MsgBox(
          'fanart.tv Personal API Key validation failed. The key should be a single API key value without spaces.' + #13#10 + #13#10 +
          'Click Yes to retry, or No to continue without a personal key. The app can still use the bundled project key.',
          mbError,
          MB_YESNO
        );

        if Retry = IDYES then
        begin
          Result := False;
        end
        else
        begin
          AddFanartNowCheck.Checked := False;
          ValidatedFanartPersonalKey := '';
          ToggleFanartMemo;
        end;
      end;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  CookiePath: String;
  FanartPersonalKeyPath: String;
begin
  if CurStep = ssPostInstall then
  begin
    CookiePath := ExpandConstant('{app}\resources\ytcookies.txt');
    if ValidatedCookieText <> '' then
    begin
      SaveStringToFile(CookiePath, ValidatedCookieText, False);
    end
    else if not FileExists(CookiePath) then
    begin
      SaveStringToFile(CookiePath, '', False);
    end;

    FanartPersonalKeyPath := ExpandConstant('{app}\resources\fanart_personal_api_key.txt');
    if ValidatedFanartPersonalKey <> '' then
    begin
      SaveStringToFile(FanartPersonalKeyPath, ValidatedFanartPersonalKey, False);
    end
    else if not FileExists(FanartPersonalKeyPath) then
    begin
      SaveStringToFile(FanartPersonalKeyPath, '', False);
    end;
  end;
end;
