; ============================================================
; Pharmacy OS — مثبّت Windows احترافي (Inno Setup 6)
; يُبنى في CI هكذا:
;   ISCC.exe /DAppVersion=1.0.N mobile\windows\setup\pharmacy_os_setup.iss
; ============================================================
#define AppName "Pharmacy OS"
#define AppExe "PharmacyOS.exe"
#define AppPublisher "Pharmacy OS"
#define AppURL "https://pharmacy-public.dockhosting.dev"

#ifndef AppVersion
#define AppVersion "1.0.0"
#endif

[Setup]
; AppId ثابت — التحديث فوق النسخة المثبتة يعمل بلا تكرار إدخال في Add/Remove
AppId={{B7E3F2A1-5C48-4D9B-A2E1-3F6D8C9A0B45}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\Pharmacy OS
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=PharmacyOS-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardImageFile=assets\wizard_side.bmp
WizardSmallImageFile=assets\wizard_small.bmp
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
WizardResizable=yes
UninstallDisplayIcon={app}\{#AppExe}
PrivilegesRequired=admin
ShowLanguageDialog=no
MinVersion=10.0

[Languages]
Name: "arabic"; MessagesFile: "Arabic.isl"

[Tasks]
Name: "desktopicon"; \
    Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; \
    Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; \
    Description: "{cm:LaunchProgram,{#AppName}}"; \
    Flags: nowait postinstall skipifsilent
