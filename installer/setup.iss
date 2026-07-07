; Inno Setup script for Billing App
; This compiles into a single BillingSetup.exe that:
;   - Installs the Visual C++ Runtime the Flutter app needs (silently)
;   - Copies the app to Program Files
;   - Creates Start Menu + optional Desktop shortcuts
;   - Offers to launch the app right after install

#define MyAppName "Billing App"
#define MyAppVersion "1.0.0"
#define MyAppExeName "billing_app.exe"
#define MyAppPublisher "Billing App"

[Setup]
AppId={{B8E1B0A0-4F1A-4B7A-9C2A-0000BILLINGAPP}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=BillingSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
; Everything Flutter produced for the Windows release build
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
; Visual C++ Runtime installer, downloaded during CI before compiling this script
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Silently install the VC++ Runtime dependency before the app can run
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing required system components..."; Flags: waituntilterminated
; Offer to launch the app once install finishes
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
