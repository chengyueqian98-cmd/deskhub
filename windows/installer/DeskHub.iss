; DeskHub Windows 安装包（Inno Setup 6）。装到当前用户目录，不需要管理员权限。
; 编译：iscc /DAppVersion=0.5.1 installer\DeskHub.iss （先用 scripts\build.ps1 发布出 out\DeskHub\DeskHub.exe）
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{8C1B6C2E-4D1A-4F6B-9B7E-DE5C0B1A2B3C}
AppName=DeskHub
AppVerName=DeskHub {#AppVersion}
AppVersion={#AppVersion}
AppPublisher=Shengyue Qian
AppPublisherURL=https://github.com/chengyueqian98-cmd/deskhub
AppSupportURL=https://github.com/chengyueqian98-cmd/deskhub/issues
DefaultDirName={localappdata}\Programs\DeskHub
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\out
OutputBaseFilename=DeskHub-Windows-{#AppVersion}-Setup
SetupIconFile=..\DeskHub\icon.ico
UninstallDisplayIcon={app}\DeskHub.exe
UninstallDisplayName=DeskHub
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\..\LICENSE

[Languages]
#if FileExists(CompilerPath + "Languages\ChineseSimplified.isl")
Name: "chs"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "..\out\DeskHub\DeskHub.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\DeskHub"; Filename: "{app}\DeskHub.exe"
Name: "{autodesktop}\DeskHub"; Filename: "{app}\DeskHub.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\DeskHub.exe"; Description: "{cm:LaunchProgram,DeskHub}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 先让它正常退出（把桌面图标还回去、把 Dock 占的底部空间还给系统），再兜底强制结束
Filename: "{app}\DeskHub.exe"; Parameters: "--quit"; Flags: runhidden waituntilterminated; RunOnceId: "QuitDeskHub"
Filename: "{sys}\timeout.exe"; Parameters: "/t 2 /nobreak"; Flags: runhidden waituntilterminated; RunOnceId: "WaitDeskHub"
Filename: "{sys}\taskkill.exe"; Parameters: "/IM DeskHub.exe /F"; Flags: runhidden waituntilterminated; RunOnceId: "KillDeskHub"

[Registry]
; 卸载时去掉「开机自动启动」
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "DeskHub"; Flags: uninsdeletevalue dontcreatekey
