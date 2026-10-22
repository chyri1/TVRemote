; Inno Setup Script for TV Remote by Chyri
; Produces a modern, lightweight, non-admin (portable-style) Windows installer.

#define MyAppName "TV Remote by Chyri"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Chyri"
#define MyAppURL "https://www.chyri.com.br/"
#define MyAppExeName "tv_remote.exe"

[Setup]
; Unique application GUID for clean upgrades and uninstallation
AppId={{E67A20B1-506D-4475-A1AC-404B5F7F8C9E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Ask language first before any other dialog
ShowLanguageDialog=yes
UsePreviousLanguage=no
UsePreviousPrivileges=no

; Automatically adapts based on install mode:
; - Current user (lowest): {localappdata}\Programs\TV Remote by Chyri (no admin required)
; - All users (admin): C:\Program Files\TV Remote by Chyri
DefaultDirName={autopf}\TV Remote by Chyri
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DirExistsWarning=no

; Default non-admin mode, allowing user to elevate for all users if desired
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Forcefully close running instances to prevent file lock errors on update/reinstall
CloseApplications=force
RestartApplications=no

; Output configuration
OutputDir=build\installer
OutputBaseFilename=TVRemote-Setup-v1.0.0
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

; High-efficiency compression
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
; English is first so it is used as fallback default if OS language is neither PT nor ES
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
; Strips automatic '(All users)' or '(Todos os usuários)' suffix from Windows Control Panel
UninstallDisplayNameMark=%1
UninstallDisplayNameMarks=%1

[CustomMessages]
; English
english.MaintenanceTitle=Maintenance & Repair
english.MaintenanceSubTitle=An existing installation of TV Remote was detected on your system.
english.MaintenancePrompt=Select the action you want Setup to perform:
english.OptUpdate=&Standard Update (updates program binaries and keeps all existing settings)
english.OptRepair=&Repair & Restore Files (restores all program files, icons, and repairs missing components)
english.OptCleanInstall=&Clean Reinstallation (restores program files and clears temporary caches/tools in AppData)

; Portuguese
brazilianportuguese.MaintenanceTitle=Manutenção e Restauração
brazilianportuguese.MaintenanceSubTitle=Uma instalação existente do TV Remote foi detectada no seu computador.
brazilianportuguese.MaintenancePrompt=Selecione a ação que deseja realizar:
brazilianportuguese.OptUpdate=&Atualização Normal (atualiza os binários e mantém todas as configurações)
brazilianportuguese.OptRepair=&Reparar e Restaurar Arquivos (restaura todos os arquivos do programa e recria atalhos)
brazilianportuguese.OptCleanInstall=&Reinstalação Limpa (restaura arquivos do programa e apaga caches/dados temporários em AppData)

; Spanish
spanish.MaintenanceTitle=Mantenimiento y Reparación
spanish.MaintenanceSubTitle=Se detectó una instalación existente de TV Remote en su equipo.
spanish.MaintenancePrompt=Seleccione la acción que desea realizar:
spanish.OptUpdate=&Actualización Normal (actualiza los binarios y conserva todas las configuraciones)
spanish.OptRepair=&Reparar y Restaurar Archivos (restaura todos los archivos del programa y recrea accesos directos)
spanish.OptCleanInstall=&Reinstalación Limpia (restaura archivos del programa y borra cachés/datos temporales en AppData)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; All compiled Flutter release binaries and assets
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu shortcut
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
; Desktop shortcut (optional task)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Enforces clean DisplayName in Windows registry without any suffixes
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1"; ValueType: string; ValueName: "DisplayName"; ValueData: "{#MyAppName}"; Flags: uninsdeletekeyifempty

[Run]
; Option to launch right after installation
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
var
  MaintenancePage: TInputOptionWizardPage;
  IsInstalled: Boolean;

// Detects if TV Remote is already installed on the machine
function CheckIsInstalled(): Boolean;
var
  UninstallKey: string;
begin
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1';
  Result := RegKeyExists(HKLM, UninstallKey) or 
            RegKeyExists(HKCU, UninstallKey) or 
            FileExists(ExpandConstant('{localappdata}\Programs\{#MyAppName}\{#MyAppExeName}')) or 
            FileExists(ExpandConstant('{commonpf}\{#MyAppName}\{#MyAppExeName}'));
end;

// Initializes wizard pages and creates Maintenance/Repair page when already installed
procedure InitializeWizard();
begin
  IsInstalled := CheckIsInstalled();
  if IsInstalled then
  begin
    MaintenancePage := CreateInputOptionPage(
      wpWelcome,
      CustomMessage('MaintenanceTitle'),
      CustomMessage('MaintenanceSubTitle'),
      CustomMessage('MaintenancePrompt'),
      True,
      False
    );
    MaintenancePage.Add(CustomMessage('OptUpdate'));
    MaintenancePage.Add(CustomMessage('OptRepair'));
    MaintenancePage.Add(CustomMessage('OptCleanInstall'));
    MaintenancePage.SelectedValueIndex := 0;
  end;
end;

// Skips the maintenance page if doing a fresh install
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if not IsInstalled and (MaintenancePage <> nil) and (PageID = MaintenancePage.ID) then
    Result := True;
end;

// Deletes temporary tools, downloaded ADB zip, and caches in AppData
procedure CleanTemporaryFiles();
var
  ToolsDir: string;
begin
  ToolsDir := ExpandConstant('{localappdata}\tv_remote\tools');
  if DirExists(ToolsDir) then
  begin
    DelTree(ToolsDir, True, True, True);
  end;
end;

// Ensures dialog buttons (like Yes/No on exit confirmation) are translated
// into the installer language rather than relying on Windows OS user32 buttons.
procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
var
  Btns: TArrayOfString;
begin
  Confirm := False;
  SetArrayLength(Btns, 2);
  Btns[0] := SetupMessage(msgButtonYes);
  Btns[1] := SetupMessage(msgButtonNo);
  Cancel := (TaskDialogMsgBox(
    SetupMessage(msgExitSetupTitle),
    SetupMessage(msgExitSetupMessage),
    mbConfirmation,
    MB_YESNO,
    Btns,
    0
  ) = IDYES);
end;

// Forcibly terminates any running instance of the app (including background mirrors)
// right before file copy begins so that files (like tv_remote.exe) are never locked.
// If Clean Reinstall was chosen, also clears temporary and cache files.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  Exec('taskkill.exe', '/f /im {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);

  if IsInstalled and (MaintenancePage <> nil) and (MaintenancePage.SelectedValueIndex = 2) then
  begin
    CleanTemporaryFiles();
  end;
end;

// Same clean termination during uninstall
function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/f /im {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
  Result := True;
end;
