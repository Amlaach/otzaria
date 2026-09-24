; מסייע ההורדה של אוצריא — Otzaria-Download-Assistant-windows.exe
;
; הכלי הזה אינו מתקין את אוצריא ואינו מתקין שום דבר: הוא אינו כותב לרישום,
; אינו יוצר קיצורי דרך ואין לו מסיר. כל תפקידו להוריד את הקבצים הדרושים
; מ-release של אוצריא ב-GitHub, לאמת אותם, ולהכין מהם התקנה — במחשב הזה או
; בתיקייה שאפשר להעתיק למחשב מנותק.
;
; שתי אבני היסוד:
;   * מניפסט ה-release (tool/release/generate_release_manifest.dart) הוא מקור
;     האמת היחיד. שום שם נכס אינו מקודד כאן: הרכיבים, הגדלים וה-hash מגיעים
;     ממנו. תג ה-release נקבע פעם אחת בתחילת הריצה ונשמר עד סופה.
;   * הרכבת נכס מפוצל לקובץ אחד היא שרשור בתים טהור דרך TFileStream, בלי
;     PowerShell ובלי כלים חיצוניים. נמדד: 2.4GB ב-6.5 שניות.

; תג ה-release שממנו נבנה הכלי, דרך משתנה סביבה: ‎/D‎ עם מרכאות מ-pwsh הגיע
; ל-ISPP עטוף בלוכסנים (נמדד: ‎\0.10.0+139\‎). בלעדיו — נפילה ל-latest.
#ifndef AssistantReleaseTag
  #define AssistantReleaseTag GetEnv("OTZARIA_ASSISTANT_RELEASE_TAG")
#endif

; החלק ‎X.Y.Z‎ של התג, לתצוגה במאפייני הקובץ. בלי תג מוטבע אין מה להציג.
#define TagVersionPart AssistantReleaseTag
#if Pos("+", TagVersionPart) > 0
  #define TagVersionPart Copy(TagVersionPart, 1, Pos("+", TagVersionPart) - 1)
#endif

[Setup]
AppId={{9A6B5F2E-7C31-4E18-9D44-1F0B8C3A5D72}
AppName=אוצריא — מסייע הורדה
; גרסת הכלי עצמו. היא אינה גרסת אוצריא: תג אוצריא מוטבע ב-AssistantReleaseTag
; בזמן הבנייה, ולכן tool/version/update_version אינו נוגע בקובץ הזה.
AppVersion=1.0
AppPublisher=sivan22
AppPublisherURL=https://github.com/otzaria/otzaria
; אינו מתקין: בלי תיקיית התקנה, בלי מסיר, בלי רישום ובלי קיצורי דרך.
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
DisableWelcomePage=yes
DisableProgramGroupPage=yes
DisableReadyPage=no
PrivilegesRequired=lowest
OutputDir=.\
; שם הנכס חייב להישאר ASCII: GitHub מוחק תווים שאינם ‎[A-Za-z0-9._-]‎ משם נכס
; שמועלה. הזיהוי העברי מגיע ממאפייני הקובץ שלמטה.
OutputBaseFilename=Otzaria-Download-Assistant-windows
VersionInfoProductName=מסייע הורדה לאוצריא
VersionInfoDescription=מוריד את קובצי אוצריא ומכין מהם התקנה. אינו מתקין את אוצריא.
VersionInfoCompany=sivan22
#if TagVersionPart != ""
VersionInfoProductTextVersion={#TagVersionPart}
#endif
SetupIconFile=white_sketch128x128.ico
WizardImageFile=wizard_large.bmp,wizard_large@2x.bmp,wizard_large@3x.bmp
; Inno טוען BMP בלי אלפא: אייקון שקוף שנשמר כך מקבל רקע שחור. הקבצים האלה
; נשטחו מראש על לבן, ולכן הם נפרדים מאלה של המתקינים.
WizardSmallImageFile=wizard_small_white.bmp,wizard_small_white@2x.bmp,wizard_small_white@3x.bmp
WizardStyle=modern
Compression=lzma
SolidCompression=yes
SetupLogging=yes
; ההרכבה קוראת וכותבת קבצים של גיגה-בתים — אין טעם לאפשר 32-bit בלבד.
ArchitecturesAllowed=x64compatible or arm64

[Languages]
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"

; ברירות המחדל של Inno מנוסחות כמתקין ("מתקין את...", "תוכנת ההתקנה"), והכלי
; הזה אינו מתקין דבר. כל מחרוזת כזאת שמופיעה במסך כלשהו מוחלפת כאן.
[Messages]
SetupAppTitle=אוצריא — מסייע הורדה
SetupWindowTitle=אוצריא — מסייע הורדה
SetupLdrStartupMessage=הכלי יוריד את קובצי אוצריא ויכין מהם התקנה. להמשיך?
ButtonInstall=&התחל
WizardReady=הכול מוכן
ReadyLabel1=הכול מוכן להורדה.
ReadyLabel2a=לחץ "התחל" כדי להוריד את הקבצים ולהכין מהם התקנה, או "הקודם" כדי לשנות את הבחירה.
ReadyLabel2b=לחץ "התחל" כדי להוריד את הקבצים ולהכין מהם התקנה.
WizardPreparing=רגע לפני ההתחלה
PreparingDesc=המסייע נערך להורדה.
WizardInstalling=הורדה והכנה
InstallingLabel=הקבצים יורדים מאתר אוצריא ונבדקים. אפשר לעצור בכל רגע.
StatusCreateDirs=מכין את התיקייה...
StatusExtractFiles=מעתיק קבצים...
StatusSavingUninstall=שומר נתונים...
StatusRunProgram=מסיים...
FinishedHeadingLabel=הפעולה הסתיימה
FinishedLabel=הפעולה הסתיימה.
FinishedLabelNoIcons=הפעולה הסתיימה.
ClickFinish=לחץ "סיים" לסגירת המסייע.
SetupAborted=הפעולה לא הושלמה.%n%nאפשר להפעיל את המסייע שוב; מה שכבר ירד יישמר.
ExitSetupTitle=יציאה מהמסייע
ExitSetupMessage=ההורדה לא הושלמה. קבצים שכבר ירדו יישמרו, והפעלה חוזרת תמשיך מהמקום שבו הפסקת.%n%nלצאת עכשיו?

[Code]
type
  TByHandleFileInformation = record
    dwFileAttributes: LongWord;
    ftCreationTime, ftLastAccessTime, ftLastWriteTime: TFileTime;
    dwVolumeSerialNumber, nFileSizeHigh, nFileSizeLow, nNumberOfLinks,
      nFileIndexHigh, nFileIndexLow: LongWord;
  end;

function GetFileInformationByHandle(hFile: THandle;
  var Info: TByHandleFileInformation): BOOL;
  external 'GetFileInformationByHandle@kernel32.dll stdcall';
function SetEndOfFile(hFile: THandle): BOOL;
  external 'SetEndOfFile@kernel32.dll stdcall';
function CreateHardLink(lpFileName, lpExistingFileName: String;
  lpSecurityAttributes: Integer): BOOL;
  external 'CreateHardLinkW@kernel32.dll stdcall';
function GetTickCount(): LongWord;
  external 'GetTickCount@kernel32.dll stdcall';

const
  { מגבלת GitHub לנכס בודד. נכס גדול ממנה מתפרסם כחלקים. }
  GithubAssetLimit = 2147483648;
  { Windows מסרב להריץ exe בגודל 4 GiB ומעלה (ERROR_BAD_EXE_FORMAT), ו-FAT32
    אינו מחזיק קובץ כזה. }
  MaxSingleOutputFileSize = 4294967296;
  CopyChunkSize = 4194304;
  AppendSliceSize = 67108864;
  ManifestSchemaVersion = 1;
  SpeedWindowMs = 5000;

  ModeThisComputer = 0;
  ModeOtherComputer = 1;

  KnownPlatforms = 'windows,macos,linux,android';
  PortableFormat = 'portable';
  { השם שה-workflow כותב (--out). משמש לתג המוטבע בלי API: מגבלת הקצב של
    api.github.com (403/429) משותפת לכל מי שיוצא מאותה כתובת, למשל בנטפרי. }
  ReleaseManifestAsset = 'otzaria-release-manifest.json';

type
  TInt64Array = array of Int64;

var
  { --- מה שנקרא מה-release --- }
  PinnedTag: String;
  ReleaseVersion: String;
  ManifestLoaded: Boolean;
  LoadErrorHeb: String;
  LoadErrorTech: String;

  CompId, CompName, CompDesc, CompType, CompPlatform, CompArch, CompFormat,
    CompDependsOn, CompInstalledBy: TArrayOfString;
  CompRequired, CompSelected: array of Boolean;
  CompDownloadSize: TInt64Array;
  CompAssetStart, CompAssetCount: array of Integer;

  AssetKind, AssetRepo, AssetTag, AssetName, AssetSha: TArrayOfString;
  AssetSize: TInt64Array;
  AssetPartStart, AssetPartCount: array of Integer;

  PartName, PartSha: TArrayOfString;
  PartSize: TInt64Array;

  { --- מחשב היעד: נקבע מהעמודים ב-UpdateTarget ונקרא רק מכאן --- }
  TargetPlatform, TargetArchitecture, TargetFormat: String;
  PlatformList, ArchList, FormatList: TArrayOfString;
  ArchListFor, FormatListFor: String;

  { --- הצעות מוכנות, נגזרות מהמניפסט --- }
  PresetId, PresetLabel, PresetDesc, PresetMembers: TArrayOfString;

  { --- מצב האשף --- }
  ModePage: TInputOptionWizardPage;
  PlatformPage: TInputOptionWizardPage;
  ArchPage: TInputOptionWizardPage;
  FormatPage: TInputOptionWizardPage;
  PresetPage: TInputOptionWizardPage;
  CustomPage: TInputOptionWizardPage;
  FolderPage: TInputDirWizardPage;
  DownloadPage: TDownloadWizardPage;
  WorkPage: TOutputProgressWizardPage;
  CustomIndex: array of Integer;
  CustomPresetIndex: Integer;
  ResultText: String;
  RunAfterExe: String;
  RevealPath: String;
  RevealIsFile: Boolean;
  RevealCheck: TNewCheckBox;

  { --- תור ההורדה של הריצה הנוכחית --- }
  QueueUrl, QueueFile, QueueSha, QueueLabel: TArrayOfString;
  QueueSize: TInt64Array;
  ProgressCaption: String;
  ProgressDone, ProgressTotal: Int64;
  SampleTick, SampleBytes: TInt64Array;
  VerifyStartTick: Int64;

{ ============================ עזרי טקסט ============================ }

function EndsWithText(const S, Suffix: String): Boolean;
begin
  Result := (Length(Suffix) <= Length(S)) and
    (Lowercase(Copy(S, Length(S) - Length(Suffix) + 1, Length(Suffix))) =
      Lowercase(Suffix));
end;

{ גודל בעברית קריאה. אין "בתים" ואין קיצורים לועזיים בעמודים הרגילים. }
function HumanSize(Bytes: Int64): String;
var
  Tenths: Int64;
begin
  if Bytes >= Int64(1073741824) then
  begin
    Tenths := (Bytes * 10) div Int64(1073741824);
    Result := IntToStr(Tenths div 10) + '.' + IntToStr(Tenths mod 10) +
      ' ג׳יגה';
  end
  else if Bytes >= 1048576 then
    Result := IntToStr(Bytes div 1048576) + ' מגה'
  else
    Result := IntToStr((Bytes + 1023) div 1024) + ' קילו';
end;

function IsExecutableName(const Name: String): Boolean;
begin
  Result := EndsWithText(Name, '.exe');
end;

{ ====================== קורא JSON מינימלי ====================== }

{ תווי המבנה של JSON הם ASCII וכל בית ברצף UTF-8 הוא 80 ומעלה, ולכן סריקה
  בבתים בטוחה; רק הערכים שחולצו עוברים Utf8Decode. }

{ מיקום 0 הוא "לא נמצא" מכל העזרים כאן, ולכן הוא מתורגם למיקום שמעבר לסוף
  ולא לגישה מחוץ לתחום. }
function JSkipWs(const S: AnsiString; P: Integer): Integer;
begin
  if P < 1 then
  begin
    Result := Length(S) + 1;
    exit;
  end;
  while (P <= Length(S)) and (S[P] <= ' ') do
    P := P + 1;
  Result := P;
end;

{ P על מרכאות הפתיחה; מחזיר את המיקום שאחרי מרכאות הסגירה. }
function JSkipString(const S: AnsiString; P: Integer): Integer;
begin
  if P < 1 then
  begin
    Result := Length(S) + 1;
    exit;
  end;
  P := P + 1;
  while P <= Length(S) do
  begin
    if S[P] = '\' then
      P := P + 2
    else if S[P] = '"' then
    begin
      Result := P + 1;
      exit;
    end
    else
      P := P + 1;
  end;
  Result := P;
end;

function JSkipValue(const S: AnsiString; P: Integer): Integer;
var
  Depth: Integer;
begin
  P := JSkipWs(S, P);
  if P > Length(S) then
  begin
    Result := P;
    exit;
  end;
  if S[P] = '"' then
  begin
    Result := JSkipString(S, P);
    exit;
  end;
  if (S[P] = '{') or (S[P] = '[') then
  begin
    Depth := 0;
    while P <= Length(S) do
    begin
      if S[P] = '"' then
        P := JSkipString(S, P)
      else
      begin
        if (S[P] = '{') or (S[P] = '[') then
          Depth := Depth + 1
        else if (S[P] = '}') or (S[P] = ']') then
        begin
          Depth := Depth - 1;
          if Depth = 0 then
          begin
            Result := P + 1;
            exit;
          end;
        end;
        P := P + 1;
      end;
    end;
    Result := P;
    exit;
  end;
  while (P <= Length(S)) and (S[P] > ' ') and (S[P] <> ',') and
        (S[P] <> '}') and (S[P] <> ']') do
    P := P + 1;
  Result := P;
end;

{ ערך גולמי של מחרוזת JSON ש-P מצביע על מרכאות הפתיחה שלה. }
function JRawString(const S: AnsiString; P: Integer): AnsiString;
var
  C: AnsiChar;
begin
  Result := '';
  if P < 1 then
    exit;
  P := P + 1;
  while P <= Length(S) do
  begin
    C := S[P];
    if C = '"' then
      exit;
    if C = '\' then
    begin
      P := P + 1;
      if P > Length(S) then
        exit;
      C := S[P];
      if C = 'n' then
        Result := Result + #10
      else if C = 't' then
        Result := Result + #9
      else if C = 'r' then
        Result := Result + #13
      else if C = 'u' then
      begin
        { \uXXXX אינו מופיע בפלט של הגנרטור; נשמר כסימן שאלה ולא נבלע. }
        Result := Result + '?';
        P := P + 4;
      end
      else
        Result := Result + C;
    end
    else
      Result := Result + C;
    P := P + 1;
  end;
end;

{ ObjPos על '{'. מחזיר את מיקום הערך של Key, או 0. }
function JFind(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := JSkipWs(S, ObjPos);
  if (P > Length(S)) or (S[P] <> '{') then
    exit;
  P := P + 1;
  while True do
  begin
    P := JSkipWs(S, P);
    if (P > Length(S)) or (S[P] = '}') then
      exit;
    if S[P] <> '"' then
      exit;
    if JRawString(S, P) = Key then
    begin
      P := JSkipWs(S, JSkipString(S, P));
      if (P > Length(S)) or (S[P] <> ':') then
        exit;
      Result := JSkipWs(S, P + 1);
      exit;
    end;
    P := JSkipWs(S, JSkipString(S, P));
    if (P > Length(S)) or (S[P] <> ':') then
      exit;
    P := JSkipValue(S, P + 1);
    P := JSkipWs(S, P);
    if (P <= Length(S)) and (S[P] = ',') then
      P := P + 1
    else
      exit;
  end;
end;

function JArrFirst(const S: AnsiString; ArrPos: Integer): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := JSkipWs(S, ArrPos);
  if (P > Length(S)) or (S[P] <> '[') then
    exit;
  P := JSkipWs(S, P + 1);
  if (P <= Length(S)) and (S[P] <> ']') then
    Result := P;
end;

function JArrNext(const S: AnsiString; ElemPos: Integer): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := JSkipWs(S, JSkipValue(S, ElemPos));
  if (P > Length(S)) or (S[P] <> ',') then
    exit;
  P := JSkipWs(S, P + 1);
  if (P <= Length(S)) and (S[P] <> ']') then
    Result := P;
end;

function JStr(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): String;
var
  P: Integer;
begin
  Result := '';
  P := JFind(S, ObjPos, Key);
  if (P > 0) and (P <= Length(S)) and (S[P] = '"') then
    Result := Utf8Decode(JRawString(S, P));
end;

function JInt(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): Int64;
var
  P, E: Integer;
begin
  Result := -1;
  P := JFind(S, ObjPos, Key);
  if P = 0 then
    exit;
  E := JSkipValue(S, P);
  Result := StrToInt64Def(Trim(Copy(S, P, E - P)), -1);
end;

function JBool(const S: AnsiString; ObjPos: Integer; const Key: AnsiString): Boolean;
var
  P, E: Integer;
begin
  Result := False;
  P := JFind(S, ObjPos, Key);
  if P = 0 then
    exit;
  E := JSkipValue(S, P);
  Result := Trim(Copy(S, P, E - P)) = 'true';
end;

{ ========================= כתובות ומטמון ========================= }

{ כתובת נכס נבנית תמיד מ-repository + releaseTag + שם קובץ, לעולם לא
  מכתובת חופשית. רק מאגרים בארגון Otzaria ב-github.com. }
function IsOtzariaRepository(const Repository: String): Boolean;
begin
  Result := (Length(Repository) > 8) and (Copy(Repository, 1, 8) = 'Otzaria/') and
    (Pos('/', Copy(Repository, 9, Length(Repository))) = 0) and
    (Pos('..', Repository) = 0);
end;

{ ‎^[A-Za-z0-9._+-]+$‎, ולא נקודות בלבד: השם משמש גם כנתיב קובץ, ו-'..' או '\'
  היו כותבים מחוץ למטמון ולתיקיית היעד. }
function IsSafeName(const Name: String): Boolean;
var
  I: Integer;
  C: Char;
  OnlyDots: Boolean;
begin
  Result := False;
  if Name = '' then
    exit;
  OnlyDots := True;
  for I := 1 to Length(Name) do
  begin
    C := Name[I];
    if not (((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
            ((C >= '0') and (C <= '9')) or (C = '.') or (C = '_') or
            (C = '+') or (C = '-')) then
      exit;
    if C <> '.' then
      OnlyDots := False;
  end;
  Result := not OnlyDots;
end;

function AssetUrl(const Repository, Tag, Name: String): String;
begin
  Result := '';
  if not IsOtzariaRepository(Repository) or not IsSafeName(Tag) or
     not IsSafeName(Name) then
    exit;
  Result := 'https://github.com/' + Repository + '/releases/download/' + Tag +
    '/' + Name;
end;

function ReleaseApiUrl(const Path: String): String;
begin
#ifdef DevApiBase
  { פיתוח בלבד (/DDevApiBase=<url/>): מדמה API שאינו עונה. }
  Result := '{#DevApiBase}' + Path;
  exit;
#endif
  Result := 'https://api.github.com/repos/Otzaria/otzaria/releases/' + Path;
end;

{ החלק ה-X.Y.Z של תג. סיומת ‎+build‎ אינה משתתפת בהשוואה: שני תגים של אותה
  גרסה הם אותה גרסה, וסדר מספרי ה-run אינו סדר גרסאות. }
function VersionPart(const Tag: String): String;
var
  P: Integer;
begin
  Result := Trim(Tag);
  P := Pos('+', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  if (Result <> '') and ((Result[1] = 'v') or (Result[1] = 'V')) then
    Result := Copy(Result, 2, Length(Result));
end;

{ 1 אם A גדול מ-B, ‎-1‎ אם קטן, 0 אם שווה. }
function CompareVersionText(const A, B: String): Integer;
var
  PA, PB: TArrayOfString;
  I, N, NA, NB: Integer;
  VA, VB: Int64;
begin
  Result := 0;
  PA := StringSplitEx(VersionPart(A), ['.'], #0, stExcludeEmpty);
  PB := StringSplitEx(VersionPart(B), ['.'], #0, stExcludeEmpty);
  NA := GetArrayLength(PA);
  NB := GetArrayLength(PB);
  if NA > NB then
    N := NA
  else
    N := NB;
  for I := 0 to N - 1 do
  begin
    if I < NA then
      VA := StrToInt64Def(PA[I], 0)
    else
      VA := 0;
    if I < NB then
      VB := StrToInt64Def(PB[I], 0)
    else
      VB := 0;
    if VA > VB then
    begin
      Result := 1;
      exit;
    end;
    if VA < VB then
    begin
      Result := -1;
      exit;
    end;
  end;
end;

function CacheDir(): String;
begin
  Result := ExpandConstant('{localappdata}\Otzaria\DownloadAssistant\cache');
end;

function CachePath(const Name: String): String;
begin
  Result := CacheDir() + '\' + Name;
end;

{ התיקייה שממנה הופעל המסייע — ברירת המחדל לשמירה. }
function AssistantDir(): String;
begin
  Result := RemoveBackslashUnlessRoot(
    ExtractFileDir(ExpandConstant('{srcexe}')));
end;

function FallbackOutputBase(): String;
begin
  Result := ExpandConstant('{userdocs}\אוצריא-להתקנה');
end;

{ כתיבה ממשית ולא ניחוש מהנתיב: דיסק-און-קי לקריאה בלבד, שיתוף רשת ותיקייה
  מוגנת נראים תקינים עד לניסיון הכתיבה הראשון. }
function DirIsWritable(const Dir: String): Boolean;
var
  Probe: String;
begin
  Result := False;
  if Dir = '' then
    exit;
  if not ForceDirectories(Dir) then
    exit;
  Probe := AddBackslash(Dir) + 'otzaria_write_test.tmp';
  DeleteFile(Probe);
  if not SaveStringToFile(Probe, 'otzaria', False) then
    exit;
  Result := FileExists(Probe);
  DeleteFile(Probe);
end;

{ ============================ זמן ו-hash ============================ }

function NowMs(): Int64;
begin
  Result := GetTickCount();
end;

{ מחשב hash ומתעד את משך הקריאה; הרכבה מחודשת מחייבת גם אימות של התוצר. }
function HashFile(const Path: String): String;
var
  Started: Int64;
begin
  Started := NowMs();
  Result := Lowercase(GetSHA256OfFile(Path));
  Log('DownloadAssistant: hashed ' + ExtractFileName(Path) + ' in ' +
    IntToStr(NowMs() - Started) + ' ms');
end;

function FileWriteTime(const Path: String; var Stamp: Int64): Boolean;
var
  Rec: TFindRec;
begin
  Result := FindFirst(Path, Rec);
  if not Result then
    exit;
  Stamp := Int64(Rec.LastWriteTime.dwHighDateTime) * 4294967296 +
    Int64(Rec.LastWriteTime.dwLowDateTime);
  FindClose(Rec);
end;

{ ============================ מטמון ============================ }

{ החותם `<name>.sha256` בפורמט sha256sum מעיד שהקובץ כבר אומת. }
function MarkerPath(const Name: String): String;
begin
  Result := CachePath(Name) + '.sha256';
end;

function ReadMarkerHex(const Name: String): String;
var
  Raw: AnsiString;
begin
  Result := '';
  if not LoadStringFromFile(MarkerPath(Name), Raw) then
    exit;
  if Length(Raw) >= 64 then
    Result := Lowercase(Copy(Raw, 1, 64));
end;

procedure WriteMarker(const Name, Sha: String);
begin
  if not SaveStringToFile(MarkerPath(Name),
    Utf8Encode(Lowercase(Sha) + '  ' + Name + #10), False) then
    Log('DownloadAssistant: cannot write marker for ' + Name);
end;

{ ‎-1‎ כשלא ניתן לדעת. }
function LinkCount(const Path: String): Integer;
var
  F: TFileStream;
  Info: TByHandleFileInformation;
begin
  Result := -1;
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      if GetFileInformationByHandle(F.Handle, Info) then
        Result := Info.nNumberOfLinks;
    finally
      F.Free;
    end;
  except
    Result := -1;
  end;
end;

{ קובץ שלא השתנה אחרי שנכתב לו חותם תואם — מוכן בלי hash. קובץ שחותמו מעיד
  על תוכן אחר אינו מוכן. בלי חותם (מטמון ישן) — hash אחד, ואז חותם. קישור
  קשיח נוסף ביעד יכול להידרס בלי לקדם את זמן השינוי, ולכן אז אין אמון בחותם. }
function FileMatchesMarker(const Path, Name: String; Size: Int64;
  const Sha: String): Boolean;
var
  Actual, FileStamp, MarkerStamp: Int64;
  Marker: String;
begin
  Result := False;
  if not FileSize64(Path, Actual) or (Actual <> Size) then
    exit;
  Marker := ReadMarkerHex(Name);
  if (Marker <> '') and (Marker <> Lowercase(Sha)) then
    exit;
  if (Marker <> '') and FileWriteTime(Path, FileStamp) and
     FileWriteTime(MarkerPath(Name), MarkerStamp) and
     (FileStamp <= MarkerStamp) and (LinkCount(Path) = 1) then
  begin
    Result := True;
    exit;
  end;
  Result := HashFile(Path) = Lowercase(Sha);
  if Result then
    WriteMarker(Name, Sha);
end;

function CachedFileIsGood(const Name: String; Size: Int64; const Sha: String): Boolean;
begin
  Result := FileMatchesMarker(CachePath(Name), Name, Size, Sha);
end;

{ עמוד ההורדה כבר אימת את ה-sha256 (הוא מועבר אליו תמיד), ולכן כאן נבדק
  גודל בלבד. הקובץ מקבל את שמו הסופי רק אחרי הבדיקה, והחותם — אחריו. }
function PromoteToCache(const TempPath, Name: String; Size: Int64;
  const Sha: String): Boolean;
var
  Staged: String;
  Actual: Int64;
begin
  Result := False;
  ForceDirectories(CacheDir());
  Staged := CachePath(Name) + '.download';
  DeleteFile(Staged);
  if not RenameFile(TempPath, Staged) then
    if not CopyFile(TempPath, Staged, False) then
      exit;
  if FileSize64(Staged, Actual) and (Actual = Size) then
  begin
    DeleteFile(MarkerPath(Name));
    DeleteFile(CachePath(Name));
    Result := RenameFile(Staged, CachePath(Name));
    if Result then
      WriteMarker(Name, Sha);
  end;
  if not Result then
    DeleteFile(Staged);
end;

{ ========================= קריאת המניפסט ========================= }

{ מערך JSON של מזהים כרשימה מופרדת בפסיקים ('' כשהמפתח חסר). }
function JIdList(const Raw: AnsiString; ObjPos: Integer;
  const Key: AnsiString): String;
var
  P: Integer;
begin
  Result := '';
  P := JArrFirst(Raw, JFind(Raw, ObjPos, Key));
  while P > 0 do
  begin
    if Raw[P] = '"' then
      Result := Result + Utf8Decode(JRawString(Raw, P)) + ',';
    P := JArrNext(Raw, P);
  end;
end;

function ParseManifest(const Raw: AnsiString): Boolean;
var
  CompPos, AssetPos, PartPos, ArrPos: Integer;
  NC, NA, NP: Integer;
  Schema: Int64;
begin
  Result := False;
  Schema := JInt(Raw, 1, 'schemaVersion');
  if Schema <> ManifestSchemaVersion then
  begin
    LoadErrorTech := 'schemaVersion=' + IntToStr(Schema);
    exit;
  end;
  PinnedTag := JStr(Raw, 1, 'releaseTag');
  ReleaseVersion := JStr(Raw, 1, 'releaseVersion');
  if (PinnedTag = '') or (ReleaseVersion = '') then
  begin
    LoadErrorTech := 'missing releaseTag/releaseVersion';
    exit;
  end;

  ArrPos := JFind(Raw, 1, 'components');
  if ArrPos = 0 then
  begin
    LoadErrorTech := 'no components';
    exit;
  end;

  NC := 0;
  NA := 0;
  NP := 0;
  CompPos := JArrFirst(Raw, ArrPos);
  while CompPos > 0 do
  begin
    SetArrayLength(CompId, NC + 1);
    SetArrayLength(CompName, NC + 1);
    SetArrayLength(CompDesc, NC + 1);
    SetArrayLength(CompType, NC + 1);
    SetArrayLength(CompPlatform, NC + 1);
    SetArrayLength(CompArch, NC + 1);
    SetArrayLength(CompFormat, NC + 1);
    SetArrayLength(CompDependsOn, NC + 1);
    SetArrayLength(CompInstalledBy, NC + 1);
    SetArrayLength(CompRequired, NC + 1);
    SetArrayLength(CompSelected, NC + 1);
    SetArrayLength(CompDownloadSize, NC + 1);
    SetArrayLength(CompAssetStart, NC + 1);
    SetArrayLength(CompAssetCount, NC + 1);

    CompId[NC] := JStr(Raw, CompPos, 'id');
    CompName[NC] := JStr(Raw, CompPos, 'name');
    CompDesc[NC] := JStr(Raw, CompPos, 'description');
    CompType[NC] := JStr(Raw, CompPos, 'type');
    CompPlatform[NC] := JStr(Raw, CompPos, 'platform');
    CompArch[NC] := JStr(Raw, CompPos, 'architecture');
    CompFormat[NC] := JStr(Raw, CompPos, 'packageFormat');
    CompRequired[NC] := JBool(Raw, CompPos, 'required');
    CompDownloadSize[NC] := JInt(Raw, CompPos, 'downloadSize');
    CompSelected[NC] := False;

    CompDependsOn[NC] := JIdList(Raw, CompPos, 'dependsOn');
    CompInstalledBy[NC] := JIdList(Raw, CompPos, 'installedBy');

    CompAssetStart[NC] := NA;
    AssetPos := JArrFirst(Raw, JFind(Raw, CompPos, 'assets'));
    while AssetPos > 0 do
    begin
      SetArrayLength(AssetKind, NA + 1);
      SetArrayLength(AssetRepo, NA + 1);
      SetArrayLength(AssetTag, NA + 1);
      SetArrayLength(AssetName, NA + 1);
      SetArrayLength(AssetSha, NA + 1);
      SetArrayLength(AssetSize, NA + 1);
      SetArrayLength(AssetPartStart, NA + 1);
      SetArrayLength(AssetPartCount, NA + 1);

      AssetKind[NA] := JStr(Raw, AssetPos, 'kind');
      AssetRepo[NA] := JStr(Raw, AssetPos, 'repository');
      AssetTag[NA] := JStr(Raw, AssetPos, 'releaseTag');
      AssetName[NA] := JStr(Raw, AssetPos, 'name');
      AssetSha[NA] := JStr(Raw, AssetPos, 'sha256');
      AssetSize[NA] := JInt(Raw, AssetPos, 'size');
      AssetPartStart[NA] := NP;

      PartPos := JArrFirst(Raw, JFind(Raw, AssetPos, 'parts'));
      while PartPos > 0 do
      begin
        SetArrayLength(PartName, NP + 1);
        SetArrayLength(PartSha, NP + 1);
        SetArrayLength(PartSize, NP + 1);
        PartName[NP] := JStr(Raw, PartPos, 'name');
        PartSha[NP] := JStr(Raw, PartPos, 'sha256');
        PartSize[NP] := JInt(Raw, PartPos, 'size');
        if not IsSafeName(PartName[NP]) or (Length(PartSha[NP]) <> 64) or
           (PartSize[NP] <= 0) then
        begin
          LoadErrorTech := 'bad part in component ' + CompId[NC];
          exit;
        end;
        NP := NP + 1;
        PartPos := JArrNext(Raw, PartPos);
      end;
      AssetPartCount[NA] := NP - AssetPartStart[NA];

      if (AssetName[NA] = '') or (Length(AssetSha[NA]) <> 64) or
         (AssetSize[NA] <= 0) or (AssetUrl(AssetRepo[NA], AssetTag[NA],
           AssetName[NA]) = '') then
      begin
        LoadErrorTech := 'bad asset in component ' + CompId[NC];
        exit;
      end;
      if (AssetKind[NA] = 'split') and (AssetPartCount[NA] = 0) then
      begin
        LoadErrorTech := 'split asset without parts: ' + AssetName[NA];
        exit;
      end;

      NA := NA + 1;
      AssetPos := JArrNext(Raw, AssetPos);
    end;
    CompAssetCount[NC] := NA - CompAssetStart[NC];

    if (CompId[NC] = '') or (CompName[NC] = '') or (CompAssetCount[NC] = 0) then
    begin
      LoadErrorTech := 'component without id/name/assets';
      exit;
    end;

    NC := NC + 1;
    CompPos := JArrNext(Raw, CompPos);
  end;

  Result := NC > 0;
  if not Result then
    LoadErrorTech := 'manifest has no components';
end;

{ JSON של release, או '' בכישלון הורדה/קריאה. }
function FetchReleaseJson(const Url, FileName: String): AnsiString;
var
  Raw: AnsiString;
begin
  Result := '';
  try
    DownloadTemporaryFile(Url, FileName, '', nil);
  except
    LoadErrorTech := GetExceptionMessage;
    exit;
  end;
  if LoadStringFromFile(ExpandConstant('{tmp}\') + FileName, Raw) then
    Result := Raw
  else
    LoadErrorTech := 'cannot read ' + FileName;
end;

{ התג ננעל לכל הריצה — release שמתעדכן באמצע היה מערבב גרסאות. latest מדלג
  על prerelease, ולכן הוא גובר על התג המוטבע רק כשגרסתו גבוהה יותר. }
function LoadReleaseManifest(): Boolean;
var
  ApiRaw, ManifestRaw: AnsiString;
  ManifestPath, ManifestAsset, Url: String;
  EmbeddedTag, LatestTag: String;
  ElemPos: Integer;
  Name: String;
begin
  Result := False;
  LoadErrorHeb := 'לא ניתן לקרוא את רשימת הקבצים של אוצריא.';

#ifdef DevManifestFile
  { פיתוח בלבד (/DDevManifestFile=<path>): ה-CI לעולם אינו מגדיר את זה. }
  Log('DownloadAssistant: DEV manifest from {#DevManifestFile}');
  if LoadStringFromFile('{#DevManifestFile}', ManifestRaw) then
    Result := ParseManifest(ManifestRaw)
  else
    LoadErrorTech := 'cannot read {#DevManifestFile}';
  exit;
#endif

  EmbeddedTag := Trim('{#AssistantReleaseTag}');
  ApiRaw := FetchReleaseJson(ReleaseApiUrl('latest'), 'release.json');
  if ApiRaw <> '' then
    LatestTag := JStr(ApiRaw, 1, 'tag_name')
  else
    LatestTag := '';

  if EmbeddedTag = '' then
    PinnedTag := LatestTag
  else if (LatestTag <> '') and
          (CompareVersionText(LatestTag, EmbeddedTag) > 0) then
    PinnedTag := LatestTag
  else
    PinnedTag := EmbeddedTag;

  Log('DownloadAssistant: embedded=' + EmbeddedTag + ' latest=' + LatestTag +
    ' pinned=' + PinnedTag);
  if PinnedTag = '' then
  begin
    LoadErrorHeb := 'לא ניתן להתחבר לאתר ההורדות של אוצריא.';
    if LoadErrorTech = '' then
      LoadErrorTech := 'release has no tag_name';
    exit;
  end;

  { התג המוטבע אינו צריך את ה-API: שם המניפסט קבוע, והכתובת הישירה אינה
    כפופה למגבלת הקצב. latest שנכשל פשוט אינו גובר עליו. }
  ManifestAsset := '';
  if PinnedTag <> LatestTag then
  begin
    ManifestAsset := ReleaseManifestAsset;
    Log('DownloadAssistant: manifest of ' + PinnedTag + ' by direct URL');
  end
  else
  begin
    ElemPos := JArrFirst(ApiRaw, JFind(ApiRaw, 1, 'assets'));
    while ElemPos > 0 do
    begin
      Name := JStr(ApiRaw, ElemPos, 'name');
      if EndsWithText(Name, 'release-manifest.json') then
      begin
        ManifestAsset := Name;
        Break;
      end;
      ElemPos := JArrNext(ApiRaw, ElemPos);
    end;
  end;
  if ManifestAsset = '' then
  begin
    LoadErrorTech := 'release ' + PinnedTag + ' has no release-manifest asset';
    exit;
  end;

  Url := AssetUrl('Otzaria/otzaria', PinnedTag, ManifestAsset);
  try
    DownloadTemporaryFile(Url, 'manifest.json', '', nil);
  except
    LoadErrorTech := GetExceptionMessage;
    exit;
  end;
  ManifestPath := ExpandConstant('{tmp}\manifest.json');
  if not LoadStringFromFile(ManifestPath, ManifestRaw) then
  begin
    LoadErrorTech := 'cannot read manifest.json';
    exit;
  end;
  Result := ParseManifest(ManifestRaw);
end;

{ ====================== מחשב היעד ====================== }

{ חוזה משותף לשלושת המסייעים; מימוש הייחוס הוא
  tool/release/download_assistant_selection.dart, ו-fixtures שלצדו. }

function IsWildcard(const Value: String): Boolean;
begin
  Result := (Value = '') or (Value = 'any');
end;

function ListIndex(const List: TArrayOfString; const Value: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GetArrayLength(List) - 1 do
    if List[I] = Value then
    begin
      Result := I;
      exit;
    end;
end;

procedure ListAdd(var List: TArrayOfString; const Value: String);
var
  N: Integer;
begin
  if ListIndex(List, Value) >= 0 then
    exit;
  N := GetArrayLength(List);
  SetArrayLength(List, N + 1);
  List[N] := Value;
end;

procedure ListSort(var List: TArrayOfString);
var
  I, J: Integer;
  Value: String;
begin
  for I := 1 to GetArrayLength(List) - 1 do
  begin
    Value := List[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(List[J], Value) > 0) do
    begin
      List[J + 1] := List[J];
      J := J - 1;
    end;
    List[J + 1] := Value;
  end;
end;

function PlatformDisplayName(const Platform: String): String;
begin
  if Platform = 'windows' then
    Result := 'Windows'
  else if Platform = 'macos' then
    Result := 'macOS'
  else if Platform = 'linux' then
    Result := 'Linux'
  else if Platform = 'android' then
    Result := 'Android'
  else
    Result := Platform;
end;

function ArchitectureDisplayName(const Architecture: String): String;
begin
  if Architecture = 'x64' then
    Result := 'מחשב רגיל'
  else if Architecture = 'arm64' then
    Result := 'מחשב עם מעבד מסוג ARM'
  else
    Result := Architecture;
end;

function FormatDisplayName(const Format: String): String;
begin
  if Format = 'deb' then
    Result := 'Ubuntu, Debian, Mint והפצות דומות (DEB)'
  else if Format = 'rpm' then
    Result := 'Fedora, openSUSE והפצות דומות (RPM)'
  else if Format = PortableFormat then
    Result := 'הפצה אחרת — ללא התקנה'
  else
    Result := Format;
end;

{ רק פלטפורמות שיש להן רכיב ייעודי; רכיב 'any' לבדו אינו מספיק. }
function PlatformChoices(): TArrayOfString;
var
  Known: TArrayOfString;
  I: Integer;
begin
  SetArrayLength(Result, 0);
  Known := StringSplitEx(KnownPlatforms, [','], #0, stExcludeEmpty);
  for I := 0 to GetArrayLength(Known) - 1 do
    if ListIndex(CompPlatform, Known[I]) >= 0 then
      ListAdd(Result, Known[I]);
end;

function ArchitectureChoices(const Platform: String): TArrayOfString;
var
  I: Integer;
begin
  SetArrayLength(Result, 0);
  for I := 0 to GetArrayLength(CompId) - 1 do
    if (CompPlatform[I] = Platform) and not IsWildcard(CompArch[I]) then
      ListAdd(Result, CompArch[I]);
  ListSort(Result);
  I := ListIndex(Result, 'x64');
  while I > 0 do
  begin
    Result[I] := Result[I - 1];
    Result[I - 1] := 'x64';
    I := I - 1;
  end;
end;

{ 'portable' מוצע כשיש רכיב תוכנה שאינו תלוי מנהל חבילות. }
function PackageFormatChoices(const Platform, Architecture: String): TArrayOfString;
var
  I: Integer;
  Portable: Boolean;
begin
  SetArrayLength(Result, 0);
  Portable := False;
  for I := 0 to GetArrayLength(CompId) - 1 do
  begin
    if CompPlatform[I] <> Platform then
      Continue;
    if not IsWildcard(CompArch[I]) and (CompArch[I] <> Architecture) then
      Continue;
    if not IsWildcard(CompFormat[I]) then
      ListAdd(Result, CompFormat[I])
    else if Copy(CompType[I], 1, 11) = 'application' then
      Portable := True;
  end;
  if GetArrayLength(Result) = 0 then
    exit;
  ListSort(Result);
  if Portable then
    ListAdd(Result, PortableFormat);
end;

{ מחוץ ל-Linux אין os-release, ולכן ברירת המחדל היא deb — רוב המשתמשים. }
function DefaultIndex(const List: TArrayOfString; const Preferred: String): Integer;
begin
  Result := ListIndex(List, Preferred);
  if Result < 0 then
    Result := 0;
end;

function RunningArchitecture(): String;
begin
  if IsArm64 then
    Result := 'arm64'
  else
    Result := 'x64';
end;

function IsThisComputerMode(): Boolean;
begin
  Result := ModePage.SelectedValueIndex = ModeThisComputer;
end;

procedure FillOptions(Page: TInputOptionWizardPage; const Values: TArrayOfString;
  const Kind: String; Selected: Integer);
var
  I: Integer;
begin
  Page.CheckListBox.Items.Clear;
  for I := 0 to GetArrayLength(Values) - 1 do
    if Kind = 'arch' then
      Page.Add(ArchitectureDisplayName(Values[I]))
    else
      Page.Add(FormatDisplayName(Values[I]));
  if GetArrayLength(Values) > 0 then
    Page.SelectedValueIndex := Selected;
end;

function SelectedFrom(Page: TInputOptionWizardPage;
  const List: TArrayOfString): String;
var
  I: Integer;
begin
  Result := '';
  if GetArrayLength(List) = 0 then
    exit;
  I := Page.SelectedValueIndex;
  if (I < 0) or (I >= GetArrayLength(List)) then
    I := 0;
  Result := List[I];
end;

{ קובע את היעד מהעמודים. רשימות הארכיטקטורה והפורמט נבנות מחדש רק כשהבחירה
  שמעליהן השתנתה, כדי שחזרה אחורה לא תמחק את בחירת המשתמש. }
procedure UpdateTarget();
begin
  if IsThisComputerMode() then
  begin
    TargetPlatform := 'windows';
    TargetArchitecture := RunningArchitecture();
    TargetFormat := '';
    exit;
  end;

  TargetPlatform := SelectedFrom(PlatformPage, PlatformList);

  if ArchListFor <> TargetPlatform then
  begin
    ArchList := ArchitectureChoices(TargetPlatform);
    if TargetPlatform = 'windows' then
      FillOptions(ArchPage, ArchList, 'arch',
        DefaultIndex(ArchList, RunningArchitecture()))
    else
      FillOptions(ArchPage, ArchList, 'arch', DefaultIndex(ArchList, 'x64'));
    ArchListFor := TargetPlatform;
  end;
  TargetArchitecture := SelectedFrom(ArchPage, ArchList);

  if FormatListFor <> TargetPlatform + '/' + TargetArchitecture then
  begin
    FormatList := PackageFormatChoices(TargetPlatform, TargetArchitecture);
    FillOptions(FormatPage, FormatList, 'format', DefaultIndex(FormatList, 'deb'));
    FormatListFor := TargetPlatform + '/' + TargetArchitecture;
  end;
  TargetFormat := SelectedFrom(FormatPage, FormatList);
end;

{ ====================== הצעות מוכנות מהמניפסט ====================== }

{ ההצעות נגזרות מ-type ומ-required, לא משמות קבצים — רכיב חדש נוחת בהצעה
  הנכונה בלי שינוי קוד. הצעה ריקה או זהה להצעה קודמת אינה מוצגת. }

{ שלושת השדות: חסר או 'any' מתאים לכל יעד; ערך לא מוכר אינו מתאים לאף יעד. }
function ComponentFitsTarget(Index: Integer): Boolean;
begin
  Result := False;
  if not IsWildcard(CompPlatform[Index]) and
     (CompPlatform[Index] <> TargetPlatform) then
    exit;
  if not IsWildcard(CompArch[Index]) and
     (CompArch[Index] <> TargetArchitecture) then
    exit;
  if not IsWildcard(CompFormat[Index]) and
     (CompFormat[Index] <> TargetFormat) then
    exit;
  Result := True;
end;

function IndexOfComponent(const Id: String): Integer;
begin
  Result := ListIndex(CompId, Id);
end;

function MembersContain(const Members, Id: String): Boolean;
begin
  Result := Pos(',' + Id + ',', ',' + Members) > 0;
end;

{ exe בגודל 4 GiB ומעלה אינו רץ, ולכן רכיב שנושא כזה אינו מוצע. }
function ComponentIsRunnable(Index: Integer): Boolean;
var
  A: Integer;
begin
  Result := True;
  for A := CompAssetStart[Index] to CompAssetStart[Index] + CompAssetCount[Index] - 1 do
    if IsExecutableName(AssetName[A]) and
       (AssetSize[A] >= MaxSingleOutputFileSize) then
      Result := False;
end;

{ המתקין הראשון ב-installedBy שמוצע ביעד, או -1. }
function InstallerFor(Index: Integer): Integer;
var
  Parts: TArrayOfString;
  J, Idx: Integer;
begin
  Result := -1;
  Parts := StringSplitEx(CompInstalledBy[Index], [','], #0, stExcludeEmpty);
  for J := 0 to GetArrayLength(Parts) - 1 do
  begin
    Idx := IndexOfComponent(Parts[J]);
    if (Idx >= 0) and ComponentFitsTarget(Idx) and ComponentIsRunnable(Idx) then
    begin
      Result := Idx;
      exit;
    end;
  end;
end;

{ מה שמוצע ביעד, בהצעות ובבחירה האישית: מתאים, ניתן להרצה, ואם מישהו אחר
  מתקין אותו (installedBy) — אחד מהם מוצע. }
function ComponentIsOffered(Index: Integer): Boolean;
begin
  Result := ComponentFitsTarget(Index) and ComponentIsRunnable(Index) and
    ((CompInstalledBy[Index] = '') or (InstallerFor(Index) >= 0));
end;

function AnyMember(const Members, Ids: String): Boolean;
var
  Parts: TArrayOfString;
  J: Integer;
begin
  Result := False;
  Parts := StringSplitEx(Ids, [','], #0, stExcludeEmpty);
  for J := 0 to GetArrayLength(Parts) - 1 do
    if MembersContain(Members, Parts[J]) then
      Result := True;
end;

{ סוגר את dependsOn (תלות שאינה מוצעת ביעד נדלגת), ולכל רכיב שמתקין שלו
  אינו בבחירה — את המתקין מ-InstallerFor. }
function WithDependencies(const Members: String): String;
var
  Changed: Boolean;
  I, J, Idx: Integer;
  Parts: TArrayOfString;
begin
  Result := Members;
  Changed := True;
  while Changed do
  begin
    Changed := False;
    for I := 0 to GetArrayLength(CompId) - 1 do
    begin
      if not MembersContain(Result, CompId[I]) then
        Continue;
      Parts := StringSplitEx(CompDependsOn[I], [','], #0, stExcludeEmpty);
      for J := 0 to GetArrayLength(Parts) - 1 do
      begin
        Idx := IndexOfComponent(Parts[J]);
        if (Idx >= 0) and ComponentIsOffered(Idx) and
           not MembersContain(Result, Parts[J]) then
        begin
          Result := Result + Parts[J] + ',';
          Changed := True;
        end;
      end;
      if (CompInstalledBy[I] <> '') and
         not AnyMember(Result, CompInstalledBy[I]) then
      begin
        Idx := InstallerFor(I);
        if Idx >= 0 then
        begin
          Result := Result + CompId[Idx] + ',';
          Changed := True;
        end;
      end;
    end;
  end;
end;

function MembersSize(const Members: String): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if MembersContain(Members, CompId[I]) then
      Result := Result + CompDownloadSize[I];
end;

{ צורה קנונית: כל מזהה פעם אחת, בסדר הרכיבים שבמניפסט. בלעדיה שתי הצעות
  שמכילות בדיוק את אותם רכיבים נראות שונות ושתיהן מוצגות. }
function CanonicalMembers(const Members: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(CompId) - 1 do
    if MembersContain(Members, CompId[I]) then
      Result := Result + CompId[I] + ',';
end;

procedure AddPreset(const Id, Caption, Description, Members: String);
var
  N, I: Integer;
  Closed: String;
begin
  if Members = '' then
    exit;
  Closed := CanonicalMembers(WithDependencies(Members));
  if Closed = '' then
    exit;
  for I := 0 to GetArrayLength(PresetMembers) - 1 do
    if PresetMembers[I] = Closed then
      exit;
  N := GetArrayLength(PresetLabel);
  SetArrayLength(PresetId, N + 1);
  SetArrayLength(PresetLabel, N + 1);
  SetArrayLength(PresetDesc, N + 1);
  SetArrayLength(PresetMembers, N + 1);
  PresetId[N] := Id;
  PresetLabel[N] := Caption + ' — ' + HumanSize(MembersSize(Closed));
  PresetDesc[N] := Description;
  PresetMembers[N] := Closed;
end;

function CollectByTypes(const Types: String; RequiredOnly: Boolean): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(CompId) - 1 do
  begin
    if not ComponentIsOffered(I) then
      Continue;
    if RequiredOnly and not CompRequired[I] then
      Continue;
    if (Types <> '') and not MembersContain(Types, CompType[I]) then
      Continue;
    Result := Result + CompId[I] + ',';
  end;
end;

procedure BuildPresets();
var
  Bundle, I: Integer;
  Members: String;
begin
  SetArrayLength(PresetId, 0);
  SetArrayLength(PresetLabel, 0);
  SetArrayLength(PresetDesc, 0);
  SetArrayLength(PresetMembers, 0);

  { מלאה: החבילה הגדולה ביותר עם מה שהיא מתקינה, אחרת התוכנה עם הספרייה —
    ובלי ספרייה אין "מלאה". }
  Bundle := -1;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if ComponentIsOffered(I) and (CompType[I] = 'application-bundle') and
       ((Bundle < 0) or (CompDownloadSize[I] > CompDownloadSize[Bundle])) then
      Bundle := I;
  if Bundle >= 0 then
  begin
    Members := CompId[Bundle] + ',';
    for I := 0 to GetArrayLength(CompId) - 1 do
      if MembersContain(CompInstalledBy[I], CompId[Bundle]) and
         ComponentIsOffered(I) then
        Members := Members + CompId[I] + ',';
  end
  else
  begin
    Members := CollectByTypes('application,library,dependency,', False);
    if CollectByTypes('library,', False) = '' then
      Members := '';
  end;
  AddPreset('full', 'התקנה מלאה (למחשב בלי אינטרנט)',
    'התוכנה יחד עם כל ספריית הספרים — למחשב שאין בו אינטרנט.', Members);

  AddPreset('basic', 'התקנה בסיסית (מומלצת)',
    'מומלץ כשבמחשב שבו תותקן אוצריא יש אינטרנט — הספרייה תרד מתוך התוכנה.',
    CollectByTypes('application,', False) + CollectByTypes('', True));

  AddPreset('update', 'עדכון התוכנה בלבד',
    'קובץ ההתקנה של הגרסה החדשה, לעדכון התקנה קיימת.',
    CollectByTypes('application,', False));

  { "בחירה אישית" אינה נגזרת מהמניפסט והיא תמיד האפשרות האחרונה. }
  CustomPresetIndex := GetArrayLength(PresetLabel);
end;

procedure ApplyPreset(Index: Integer);
var
  I: Integer;
begin
  for I := 0 to GetArrayLength(CompId) - 1 do
    CompSelected[I] := (Index >= 0) and (Index < GetArrayLength(PresetMembers)) and
      MembersContain(PresetMembers[Index], CompId[I]);
end;

{ ========================= צורת הפלט ========================= }

{ יעד Windows: רק exe מתחת ל-4 GiB — ארכיון נשאר חלקים, כי המתקין שצורך
  אותו קורא אותם. כל יעד אחר: כל נכס מתחת ל-4 GiB, כי שם המשתמש פורס אותו. }
function ShouldAssembleSingleFile(AssetIndex: Integer): Boolean;
begin
  Result := False;
  if AssetSize[AssetIndex] >= MaxSingleOutputFileSize then
    exit;
  if TargetPlatform = 'windows' then
    Result := IsExecutableName(AssetName[AssetIndex])
  else
    Result := True;
end;

{ הפלטפורמה בשם, כדי שהכנה לשני יעדים באותו דיסק-און-קי לא תערבב קבצים. }
function OutputSubFolderName(): String;
begin
  Result := 'אוצריא להתקנה ל-' + PlatformDisplayName(TargetPlatform);
end;

{ הקבצים שייווצרו ביעד, בסדר המניפסט — לפי אותם כללים שמריץ PrepareOutput. }
function PlannedOutputNames(): TArrayOfString;
var
  C, A, P, N: Integer;
begin
  SetArrayLength(Result, 0);
  N := 0;
  for C := 0 to GetArrayLength(CompId) - 1 do
  begin
    if not CompSelected[C] then
      Continue;
    for A := CompAssetStart[C] to CompAssetStart[C] + CompAssetCount[C] - 1 do
    begin
      if (AssetKind[A] = 'split') and not ShouldAssembleSingleFile(A) then
      begin
        for P := AssetPartStart[A] to AssetPartStart[A] + AssetPartCount[A] - 1 do
        begin
          SetArrayLength(Result, N + 1);
          Result[N] := PartName[P];
          N := N + 1;
        end;
      end
      else
      begin
        SetArrayLength(Result, N + 1);
        Result[N] := AssetName[A];
        N := N + 1;
      end;
    end;
  end;
end;

function ProducedFileCount(): Integer;
begin
  Result := GetArrayLength(PlannedOutputNames());
end;

#ifdef DevSelectionDump
{ פיתוח בלבד (/DDevSelectionDump=<path>): מריץ את כללי הבחירה על כל יעד
  ושומר אותם להשוואה מול expected-selections.json. ה-CI לעולם אינו מגדיר. }
procedure DumpSelections();
var
  Platforms, Archs, Formats, Names: TArrayOfString;
  P, A, F, I, J: Integer;
  Text, Line: String;
begin
  Text := '';
  Platforms := PlatformChoices();
  for P := 0 to GetArrayLength(Platforms) - 1 do
  begin
    Archs := ArchitectureChoices(Platforms[P]);
    Text := Text + 'platform ' + Platforms[P] + ' archs=';
    for I := 0 to GetArrayLength(Archs) - 1 do
      Text := Text + Archs[I] + ',';
    Text := Text + #10;
    if GetArrayLength(Archs) = 0 then
    begin
      SetArrayLength(Archs, 1);
      Archs[0] := '';
    end;
    for A := 0 to GetArrayLength(Archs) - 1 do
    begin
      Formats := PackageFormatChoices(Platforms[P], Archs[A]);
      Text := Text + 'formats ' + Platforms[P] + '/' + Archs[A] + '=';
      for I := 0 to GetArrayLength(Formats) - 1 do
        Text := Text + Formats[I] + ',';
      Text := Text + #10;
      if GetArrayLength(Formats) = 0 then
      begin
        SetArrayLength(Formats, 1);
        Formats[0] := '';
      end;
      for F := 0 to GetArrayLength(Formats) - 1 do
      begin
        TargetPlatform := Platforms[P];
        TargetArchitecture := Archs[A];
        TargetFormat := Formats[F];
        Line := '';
        for I := 0 to GetArrayLength(CompId) - 1 do
          if ComponentIsOffered(I) then
            Line := Line + CompId[I] + ',';
        Text := Text + 'target ' + TargetPlatform + '/' + TargetArchitecture +
          '/' + TargetFormat + ' offered=' + Line + #10;
        BuildPresets();
        for I := 0 to GetArrayLength(PresetId) - 1 do
        begin
          ApplyPreset(I);
          Names := PlannedOutputNames();
          Line := '';
          for J := 0 to GetArrayLength(Names) - 1 do
            Line := Line + Names[J] + '|';
          Text := Text + 'preset ' + PresetId[I] + ' members=' +
            PresetMembers[I] + ' files=' + Line + ' subfolder=';
          if GetArrayLength(Names) > 1 then
            Text := Text + OutputSubFolderName();
          Text := Text + #10;
        end;
      end;
    end;
  end;
  SaveStringToFile('{#DevSelectionDump}', Utf8Encode(Text), False);
end;
#endif

{ ============================== עמודים ============================== }

procedure RefreshPresetPage();
var
  I: Integer;
begin
  BuildPresets();
  PresetPage.CheckListBox.Items.Clear;
  for I := 0 to GetArrayLength(PresetLabel) - 1 do
  begin
    PresetPage.Add(PresetLabel[I]);
    PresetPage.CheckListBox.ItemSubItem[I] := PresetDesc[I];
  end;
  PresetPage.Add('בחירה אישית');
  PresetPage.CheckListBox.ItemSubItem[CustomPresetIndex] :=
    'אני רוצה לבחור בעצמי מה להוריד.';
  if PresetPage.SelectedValueIndex < 0 then
    PresetPage.SelectedValueIndex := DefaultIndex(PresetId, 'basic');
end;

procedure RefreshCustomPage();
var
  I, N: Integer;
  Extra: String;
begin
  CustomPage.CheckListBox.Items.Clear;
  SetArrayLength(CustomIndex, 0);
  N := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
  begin
    if not ComponentIsOffered(I) then
      Continue;
    if CompRequired[I] then
      Extra := ' (נדרש)'
    else
      Extra := '';
    CustomPage.Add(CompName[I] + ' — ' + HumanSize(CompDownloadSize[I]) + Extra);
    CustomPage.CheckListBox.ItemSubItem[N] := CompDesc[I];
    CustomPage.Values[N] := CompSelected[I] or CompRequired[I];
    SetArrayLength(CustomIndex, N + 1);
    CustomIndex[N] := I;
    N := N + 1;
  end;
end;

{ "3 דקות", "שעה ו-10 דקות" — בלי שניות מדויקות, שממילא אינן יציבות. }
function HumanDuration(Seconds: Int64): String;
var
  Hours, Minutes: Int64;
begin
  if Seconds < 60 then
  begin
    Result := 'פחות מדקה';
    exit;
  end;
  Hours := Seconds div 3600;
  Minutes := (Seconds mod 3600 + 30) div 60;
  if Minutes = 60 then
  begin
    Hours := Hours + 1;
    Minutes := 0;
  end;
  if Hours = 0 then
    Result := ''
  else if Hours = 1 then
    Result := 'שעה'
  else if Hours = 2 then
    Result := 'שעתיים'
  else
    Result := IntToStr(Hours) + ' שעות';
  if Minutes = 0 then
    exit;
  if Result <> '' then
    Result := Result + ' ו-';
  if Minutes = 1 then
    Result := Result + 'דקה'
  else
    Result := Result + IntToStr(Minutes) + ' דקות';
end;

function HumanRate(BytesPerSecond: Int64): String;
var
  Tenths: Int64;
begin
  if BytesPerSecond >= 1048576 then
  begin
    Tenths := (BytesPerSecond * 10) div 1048576;
    Result := IntToStr(Tenths div 10) + '.' + IntToStr(Tenths mod 10) +
      ' מגה בשנייה';
  end
  else
    Result := IntToStr(BytesPerSecond div 1024) + ' קילו בשנייה';
end;

procedure ResetSpeed();
begin
  SetArrayLength(SampleTick, 0);
  SetArrayLength(SampleBytes, 0);
end;

{ ממוצע נע על ~5 שניות: נשמרת דגימה כל רבע שנייה, והישנות נזרקות. }
procedure AddSpeedSample(Bytes: Int64);
var
  N, I: Integer;
  Tick: Int64;
begin
  Tick := NowMs();
  N := GetArrayLength(SampleTick);
  if (N > 0) and (Tick < SampleTick[N - 1]) then
  begin
    ResetSpeed();
    N := 0;
  end;
  if (N > 0) and (Tick - SampleTick[N - 1] < 250) then
    exit;
  SetArrayLength(SampleTick, N + 1);
  SetArrayLength(SampleBytes, N + 1);
  SampleTick[N] := Tick;
  SampleBytes[N] := Bytes;
  N := N + 1;
  while (N > 2) and (Tick - SampleTick[1] >= SpeedWindowMs) do
  begin
    for I := 0 to N - 2 do
    begin
      SampleTick[I] := SampleTick[I + 1];
      SampleBytes[I] := SampleBytes[I + 1];
    end;
    N := N - 1;
    SetArrayLength(SampleTick, N);
    SetArrayLength(SampleBytes, N);
  end;
end;

{ בתים לשנייה, או ‎-1‎ כשעדיין אין מספיק דגימות. }
function CurrentSpeed(): Int64;
var
  N: Integer;
  Elapsed: Int64;
begin
  Result := -1;
  N := GetArrayLength(SampleTick);
  if N < 2 then
    exit;
  Elapsed := SampleTick[N - 1] - SampleTick[0];
  if Elapsed < 1000 then
    exit;
  Result := ((SampleBytes[N - 1] - SampleBytes[0]) * 1000) div Elapsed;
end;

{ הקבצים יורדים אחד-אחד כדי שכל קובץ שהושלם ייכנס למטמון מיד, ולכן הסכום
  הכולל, המהירות והזמן המשוער מחושבים כאן ולא בעמוד עצמו. }
function OnDownloadProgress(const Url, FileName: String;
  const Progress, ProgressMax: Int64): Boolean;
var
  Done, Speed: Int64;
  Status: String;
begin
  Done := ProgressDone + Progress;
  AddSpeedSample(Done);
  Status := 'ירדו ' + HumanSize(Done) + ' מתוך ' + HumanSize(ProgressTotal);
  Speed := CurrentSpeed();
  if Speed > 0 then
    Status := Status + ' · ' + HumanRate(Speed) + ' · נותרו ' +
      HumanDuration((ProgressTotal - Done) div Speed);
  { Inno מחשב את ה-hash אחרי הבית האחרון בלי לדווח התקדמות — הכותרת מסבירה
    למה הפס עומד. }
  if (ProgressMax > 0) and (Progress >= ProgressMax) then
  begin
    if VerifyStartTick = 0 then
    begin
      VerifyStartTick := NowMs();
      Log('DownloadAssistant: ' + FileName + ' received, download page verifies');
    end;
    DownloadPage.SetText('בודק את הקובץ שירד', Status);
  end
  else
    DownloadPage.SetText(ProgressCaption, Status);
  Result := True;
end;

procedure InitializeWizard();
var
  DefaultBase, FolderNote: String;
  I: Integer;
begin
  ModePage := CreateInputOptionPage(wpWelcome,
    'אוצריא — מסייע הורדה',
    'כלי זה אינו מתקין את אוצריא.',
    'הכלי מאפשר להוריד את הקבצים הדרושים ולהכין התקנה עבור מחשב זה או עבור ' +
    'מחשב אחר.' + #13#10#13#10 +
    'יש אינטרנט במחשב שבו תותקן אוצריא? מספיקה ההתקנה הבסיסית — הספרייה תרד ' +
    'מתוך התוכנה.' + #13#10#13#10 + 'מה ברצונך לעשות?',
    True, False);
  ModePage.Add('הורדה והתקנה במחשב הזה');
  ModePage.Add('הכנת התקנה למחשב אחר');
  ModePage.SelectedValueIndex := ModeOtherComputer;

  PlatformPage := CreateInputOptionPage(ModePage.ID,
    'המחשב שאליו מכינים',
    'איזו מערכת הפעלה מותקנת בו?',
    'אם אינך יודע, בחר Windows — היא מותקנת ברוב המחשבים.',
    True, False);
  PlatformList := PlatformChoices();
  for I := 0 to GetArrayLength(PlatformList) - 1 do
    PlatformPage.Add(PlatformDisplayName(PlatformList[I]));
  if GetArrayLength(PlatformList) > 0 then
    PlatformPage.SelectedValueIndex := DefaultIndex(PlatformList, 'windows');

  ArchPage := CreateInputOptionPage(PlatformPage.ID,
    'המחשב שאליו מכינים',
    'איזה סוג מחשב הוא היעד?',
    'אם אינך יודע, בחר באפשרות הראשונה — היא מתאימה כמעט לכל המחשבים.',
    True, False);
  ArchListFor := #0;

  FormatPage := CreateInputOptionPage(ArchPage.ID,
    'המחשב שאליו מכינים',
    'איזו גרסה של Linux מותקנת בו?',
    'אם אינך יודע, השאר את הבחירה המסומנת — היא מתאימה לרוב המחשבים.',
    True, False);
  FormatListFor := #0;

  PresetPage := CreateInputOptionPage(FormatPage.ID,
    'מה להוריד',
    'בחר את היקף ההורדה.',
    'אפשר לשנות את הבחירה בהמשך.',
    True, False);

  CustomPage := CreateInputOptionPage(PresetPage.ID,
    'בחירה אישית',
    'סמן את הרכיבים שברצונך להוריד.',
    'ליד כל רכיב מופיע גודל ההורדה שלו.',
    False, True);

  DefaultBase := AssistantDir();
  FolderNote := '';
  if not DirIsWritable(DefaultBase) then
  begin
    DefaultBase := FallbackOutputBase();
    FolderNote := #13#10#13#10 + 'אי אפשר לשמור בתיקייה שממנה הופעל המסייע ' +
      '(למשל דיסק-און-קי לקריאה בלבד), ולכן הוצעה כאן תיקייה אחרת.';
  end;

  FolderPage := CreateInputDirPage(CustomPage.ID,
    'לאן לשמור',
    'כברירת מחדל התוצאה נשמרת ליד המסייע עצמו.',
    'אפשר לבחור תיקייה אחרת. בסיום אפשר יהיה להעתיק את התוצאה לדיסק-און-קי ' +
    'ולהעביר אותה למחשב המנותק.' + FolderNote,
    False, '');
  FolderPage.Add('');
  FolderPage.Values[0] := DefaultBase;

  DownloadPage := CreateDownloadPage('הורדת הקבצים',
    'הקבצים יורדים מאתר אוצריא. אפשר לעצור בכל רגע — מה שכבר ירד יישמר.',
    @OnDownloadProgress);
  WorkPage := CreateOutputProgressPage('הכנת ההתקנה',
    'רגע, מכינים את הקבצים.');
end;

{ עמוד שיש בו אפשרות אחת בלבד אינו מוצג. }
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = PlatformPage.ID then
    Result := IsThisComputerMode() or (GetArrayLength(PlatformList) <= 1)
  else if PageID = ArchPage.ID then
  begin
    UpdateTarget();
    Result := IsThisComputerMode() or (GetArrayLength(ArchList) <= 1);
  end
  else if PageID = FormatPage.ID then
  begin
    UpdateTarget();
    Result := IsThisComputerMode() or (GetArrayLength(FormatList) <= 1);
  end
  else if PageID = CustomPage.ID then
    Result := PresetPage.SelectedValueIndex <> CustomPresetIndex
  else if PageID = FolderPage.ID then
    Result := IsThisComputerMode();
end;

{ ====================== בניית תור ההורדה ====================== }

procedure QueueAdd(const Url, FileName, Sha, Caption: String; Size: Int64);
var
  N: Integer;
begin
  N := GetArrayLength(QueueUrl);
  SetArrayLength(QueueUrl, N + 1);
  SetArrayLength(QueueFile, N + 1);
  SetArrayLength(QueueSha, N + 1);
  SetArrayLength(QueueLabel, N + 1);
  SetArrayLength(QueueSize, N + 1);
  QueueUrl[N] := Url;
  QueueFile[N] := FileName;
  QueueSha[N] := Sha;
  QueueLabel[N] := Caption;
  QueueSize[N] := Size;
end;

function OutputBaseDir(): String;
begin
  if IsThisComputerMode() then
    Result := CacheDir()
  else
    Result := RemoveBackslashUnlessRoot(FolderPage.Values[0]);
end;

{ קובץ בודד יושב ישירות בתיקייה שנבחרה; כמה קבצים שחייבים להישאר יחד מקבלים
  תיקייה משלהם. }
function OutputDir(): String;
begin
  Result := OutputBaseDir();
  if not IsThisComputerMode() and (ProducedFileCount() > 1) then
    Result := Result + '\' + OutputSubFolderName();
end;

{ הקובץ שכבר מורכב ביעד: גודל תואם וחותם מהמטמון שנכתב אחרי ההרכבה. }
function AssembledIsReady(AssetIndex: Integer): Boolean;
begin
  Result := FileMatchesMarker(OutputDir() + '\' + AssetName[AssetIndex],
    AssetName[AssetIndex], AssetSize[AssetIndex], AssetSha[AssetIndex]);
end;

function AssemblyTmpPath(AssetIndex: Integer): String;
begin
  Result := OutputDir() + '\' + AssetName[AssetIndex] + '.tmp';
end;

{ `<name>.tmp.sha256` נכתב לפני הבית הראשון. שם הנכס חוזר בין בניות של אותה
  גרסה, ובלעדיו .tmp של בנייה אחרת היה נספר כחלקים שכבר נבלעו. }
function AssemblyTmpBelongs(AssetIndex: Integer): Boolean;
var
  Raw: AnsiString;
begin
  Result := LoadStringFromFile(AssemblyTmpPath(AssetIndex) + '.sha256', Raw) and
    (Lowercase(Copy(Raw, 1, 64)) = Lowercase(AssetSha[AssetIndex]));
end;

{ כמה חלקים כבר נבלעו לתוך קובץ ההרכבה החלקי. חלק נמחק רק אחרי שהוספתו
  הושלמה, ולכן גודל הקובץ החלקי מזהה בדיוק היכן נעצרנו. }
function ConsumedPartCount(AssetIndex: Integer; var Prefix: Int64): Integer;
var
  TmpPath: String;
  Size, Acc: Int64;
  I: Integer;
begin
  Result := 0;
  Prefix := 0;
  TmpPath := AssemblyTmpPath(AssetIndex);
  if not FileExists(TmpPath) then
    exit;
  if not AssemblyTmpBelongs(AssetIndex) then
  begin
    Log('DownloadAssistant: discarding foreign partial ' + TmpPath);
    DeleteFile(TmpPath);
    DeleteFile(TmpPath + '.sha256');
    exit;
  end;
  if not FileSize64(TmpPath, Size) then
    exit;
  Acc := 0;
  for I := 0 to AssetPartCount[AssetIndex] - 1 do
  begin
    if Acc + PartSize[AssetPartStart[AssetIndex] + I] > Size then
      Break;
    Acc := Acc + PartSize[AssetPartStart[AssetIndex] + I];
    Result := Result + 1;
    Prefix := Acc;
  end;
end;

{ בונה את תור ההורדה: מה שכבר במטמון ומאומת אינו נכנס אליו. }
function BuildQueue(): Boolean;
var
  C, A, P, First, Consumed: Integer;
  Prefix: Int64;
  Url: String;
begin
  SetArrayLength(QueueUrl, 0);
  SetArrayLength(QueueFile, 0);
  SetArrayLength(QueueSha, 0);
  SetArrayLength(QueueLabel, 0);
  SetArrayLength(QueueSize, 0);
  Result := True;

  WorkPage.SetText('בודק קבצים שכבר הורדו', '');
  WorkPage.Show;
  try
    for C := 0 to GetArrayLength(CompId) - 1 do
    begin
      if not CompSelected[C] then
        Continue;
      for A := CompAssetStart[C] to CompAssetStart[C] + CompAssetCount[C] - 1 do
      begin
        WorkPage.SetText('בודק קבצים שכבר הורדו', CompName[C]);
        if AssetKind[A] = 'split' then
        begin
          if ShouldAssembleSingleFile(A) and AssembledIsReady(A) then
            Continue;
          if ShouldAssembleSingleFile(A) then
            Consumed := ConsumedPartCount(A, Prefix)
          else
            Consumed := 0;
          First := AssetPartStart[A];
          for P := First + Consumed to First + AssetPartCount[A] - 1 do
          begin
            if CachedFileIsGood(PartName[P], PartSize[P], PartSha[P]) then
              Continue;
            Url := AssetUrl(AssetRepo[A], AssetTag[A], PartName[P]);
            if Url = '' then
            begin
              Result := False;
              LoadErrorTech := 'refusing non-Otzaria url for ' + PartName[P];
              exit;
            end;
            QueueAdd(Url, PartName[P], PartSha[P], CompName[C], PartSize[P]);
          end;
        end
        else
        begin
          if CachedFileIsGood(AssetName[A], AssetSize[A], AssetSha[A]) then
            Continue;
          Url := AssetUrl(AssetRepo[A], AssetTag[A], AssetName[A]);
          if Url = '' then
          begin
            Result := False;
            LoadErrorTech := 'refusing non-Otzaria url for ' + AssetName[A];
            exit;
          end;
          QueueAdd(Url, AssetName[A], AssetSha[A], CompName[C], AssetSize[A]);
        end;
      end;
    end;
  finally
    WorkPage.Hide;
  end;
end;

{ ============================== הורדה ============================== }

function RunDownloads(): Boolean;
var
  I: Integer;
  Started: Int64;
begin
  Result := True;
  if GetArrayLength(QueueUrl) = 0 then
    exit;

  ProgressTotal := 0;
  ProgressDone := 0;
  for I := 0 to GetArrayLength(QueueUrl) - 1 do
    ProgressTotal := ProgressTotal + QueueSize[I];

  DownloadPage.ShowBaseNameInsteadOfUrl := True;
  DownloadPage.Show;
  try
    for I := 0 to GetArrayLength(QueueUrl) - 1 do
    begin
      ProgressCaption := 'מוריד: ' + QueueLabel[I] + ' (' + IntToStr(I + 1) +
        ' מתוך ' + IntToStr(GetArrayLength(QueueUrl)) + ')';
      DownloadPage.SetText(ProgressCaption, '');
      DownloadPage.Clear;
      ResetSpeed();
      VerifyStartTick := 0;
      Started := NowMs();
      { ה-hash מהמניפסט מועבר תמיד — קובץ שאינו תואם נדחה כאן ולא נשמר. }
      DownloadPage.Add(QueueUrl[I], QueueFile[I], QueueSha[I]);
      try
        DownloadPage.Download;
      except
        if DownloadPage.AbortedByUser then
          LoadErrorHeb := 'ההורדה הופסקה.'
        else
        begin
          LoadErrorHeb := 'לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים ' +
            'אינו זמין.';
          LoadErrorTech := QueueFile[I] + ': ' + GetExceptionMessage;
        end;
        Result := False;
        exit;
      end;
      if VerifyStartTick > 0 then
        Log('DownloadAssistant: ' + QueueFile[I] + ' downloaded in ' +
          IntToStr(VerifyStartTick - Started) + ' ms, verified by download page in ' +
          IntToStr(NowMs() - VerifyStartTick) + ' ms')
      else
        Log('DownloadAssistant: ' + QueueFile[I] + ' done in ' +
          IntToStr(NowMs() - Started) + ' ms');
      ProgressDone := ProgressDone + QueueSize[I];
      if not PromoteToCache(ExpandConstant('{tmp}\') + QueueFile[I],
        QueueFile[I], QueueSize[I], QueueSha[I]) then
      begin
        LoadErrorHeb := 'אחד הקבצים שהורדו נמצא פגום ולא נשמר.';
        LoadErrorTech := 'size check failed for ' + QueueFile[I];
        Result := False;
        exit;
      end;
    end;
  finally
    DownloadPage.Hide;
  end;
end;

{ ============================== הרכבה ============================== }

function MegaBytes(Bytes: Int64): Integer;
begin
  Result := Bytes div 1048576;
end;

{ משרשר את Src (בדיוק Expected בתים) לסוף Dest ומדווח התקדמות בבתים.
  שרשור בתים טהור — התוצאה זהה בית-בית למקור. }
function AppendFileTo(const Dest, Src: String; Expected, DoneBefore,
  Total: Int64; const Caption: String): Boolean;
var
  Output, Input: TFileStream;
  Start, Copied, Slice, Got: Int64;
begin
  Result := False;
  try
    if FileExists(Dest) then
      Output := TFileStream.Create(Dest, fmOpenWrite)
    else
      Output := TFileStream.Create(Dest, fmCreate);
    try
      Start := Output.Seek(Int64(0), soFromEnd);
      Input := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);
      try
        Copied := 0;
        while Copied < Expected do
        begin
          Slice := Expected - Copied;
          if Slice > AppendSliceSize then
            Slice := AppendSliceSize;
          Got := Output.CopyFrom(Input, Slice, CopyChunkSize);
          if Got <> Slice then
            Break;
          Copied := Copied + Got;
          WorkPage.SetText('מחבר את הקבצים: ' + Caption,
            HumanSize(DoneBefore + Copied) + ' מתוך ' + HumanSize(Total));
          WorkPage.SetProgress(MegaBytes(DoneBefore + Copied), MegaBytes(Total));
        end;
      finally
        Input.Free;
      end;
      Result := (Copied = Expected) and
        (Output.Seek(Int64(0), soFromCurrent) = Start + Expected);
    finally
      Output.Free;
    end;
    if not Result then
      LoadErrorTech := 'append wrote a wrong byte count: ' + Src;
  except
    LoadErrorTech := 'append failed: ' + GetExceptionMessage;
  end;
end;

{ מקצץ קובץ חלקי חזרה לגבול חלק בין חלקים. Size של TStream הוא 32 סיביות
  ולכן הקיצוץ נעשה דרך Seek של 64 סיביות ו-SetEndOfFile. }
function TruncateFileTo(const Path: String; NewSize: Int64): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  try
    F := TFileStream.Create(Path, fmOpenWrite);
    try
      F.Seek(NewSize, soFromBeginning);
      Result := SetEndOfFile(F.Handle);
    finally
      F.Free;
    end;
  except
    LoadErrorTech := 'truncate failed: ' + GetExceptionMessage;
  end;
end;

{ כל חלק נמחק מיד אחרי שנוסף: שיא הדיסק הוא הקובץ המורכב ועוד חלק אחד. }
function AssembleAsset(AssetIndex: Integer; const Caption: String): Boolean;
var
  TmpPath, FinalPath, PartPath: String;
  Consumed, I, First: Integer;
  Prefix, Actual, Done: Int64;
begin
  Result := False;
  FinalPath := OutputDir() + '\' + AssetName[AssetIndex];
  TmpPath := AssemblyTmpPath(AssetIndex);
  First := AssetPartStart[AssetIndex];
  Consumed := ConsumedPartCount(AssetIndex, Prefix);
  if FileExists(TmpPath) then
  begin
    if not TruncateFileTo(TmpPath, Prefix) then
      exit;
  end
  else if not SaveStringToFile(TmpPath + '.sha256',
    Lowercase(AssetSha[AssetIndex]) + #10, False) then
  begin
    LoadErrorHeb := 'לא ניתן היה לכתוב את הקובץ המאוחד. ייתכן שאין מספיק ' +
      'מקום פנוי.';
    LoadErrorTech := 'cannot write ' + TmpPath + '.sha256';
    exit;
  end;

  Done := Prefix;
  for I := Consumed to AssetPartCount[AssetIndex] - 1 do
  begin
    PartPath := CachePath(PartName[First + I]);
    if not CachedFileIsGood(PartName[First + I], PartSize[First + I],
      PartSha[First + I]) then
    begin
      LoadErrorHeb := 'לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים ' +
        'אינו זמין.';
      LoadErrorTech := 'part failed verification: ' + PartName[First + I];
      exit;
    end;
    if not AppendFileTo(TmpPath, PartPath, PartSize[First + I], Done,
      AssetSize[AssetIndex], Caption) then
    begin
      LoadErrorHeb := 'לא ניתן היה לכתוב את הקובץ המאוחד. ייתכן שאין מספיק ' +
        'מקום פנוי.';
      exit;
    end;
    DeleteFile(PartPath);
    DeleteFile(MarkerPath(PartName[First + I]));
    Done := Done + PartSize[First + I];
  end;

  if not FileSize64(TmpPath, Actual) or (Actual <> AssetSize[AssetIndex]) then
  begin
    LoadErrorHeb := 'הקובץ המאוחד נמצא פגום ולכן לא נשמר.';
    LoadErrorTech := 'assembled size mismatch: ' + AssetName[AssetIndex];
    DeleteFile(TmpPath);
    DeleteFile(TmpPath + '.sha256');
    exit;
  end;
  WorkPage.SetText('בודק את הקובץ המאוחד: ' + Caption,
    'מאמת את תוכן הקובץ מול המניפסט');
  WorkPage.SetProgress(0, 1);
  if HashFile(TmpPath) <> Lowercase(AssetSha[AssetIndex]) then
  begin
    LoadErrorHeb := 'הקובץ המאוחד נמצא פגום ולכן לא נשמר.';
    LoadErrorTech := 'assembled sha256 mismatch: ' + AssetName[AssetIndex];
    DeleteFile(TmpPath);
    DeleteFile(TmpPath + '.sha256');
    exit;
  end;
  DeleteFile(FinalPath);
  Result := RenameFile(TmpPath, FinalPath);
  if Result then
  begin
    DeleteFile(TmpPath + '.sha256');
    WriteMarker(AssetName[AssetIndex], AssetSha[AssetIndex]);
  end
  else
    LoadErrorTech := 'rename failed: ' + TmpPath;
end;

{ קישור קשיח חוסך העתקה של גיגה-בתים; נכשל בין כוננים ועל FAT32/exFAT, ואז
  מעתיקים. }
function CopyToOutput(const Name: String): Boolean;
var
  Dest: String;
begin
  Result := True;
  if CompareText(OutputDir(), CacheDir()) = 0 then
    exit;
  Dest := OutputDir() + '\' + Name;
  DeleteFile(Dest);
  if CreateHardLink(Dest, CachePath(Name), 0) then
  begin
    Log('DownloadAssistant: linked ' + Name);
    exit;
  end;
  Result := CopyFile(CachePath(Name), Dest, False);
  if Result then
    Log('DownloadAssistant: copied ' + Name)
  else
    LoadErrorTech := 'copy failed: ' + Name;
end;

{ ==================== הרכבה והכנת תיקיית היעד ==================== }

{ מה עושים בקובץ במחשב היעד. נגזר מהסיומת, לא משם רכיב. }
function OpenHint(const Name: String): String;
begin
  if EndsWithText(Name, '.exe') then
    Result := ' שם הפעל אותו — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות.'
  else if EndsWithText(Name, '.dmg') then
    Result := ' שם פתח אותו בלחיצה כפולה וגרור את אוצריא לתיקיית היישומים.'
  else if EndsWithText(Name, '.deb') or EndsWithText(Name, '.rpm') then
    Result := ' שם פתח אותו בלחיצה כפולה כדי להתקין את אוצריא.'
  else if EndsWithText(Name, '.apk') then
    Result := ' שם העבר אותו לטלפון או לטאבלט ופתח אותו כדי להתקין את אוצריא.'
  else
    Result := ' שם חלץ אותו והפעל את אוצריא מתוך התיקייה שנוצרה.';
end;

{ חלקים שנשארו בנפרד ביעד שאינו Windows — המשתמש מחבר אותם בעצמו. }
function JoinCommand(AssetIndex: Integer): String;
var
  P, First: Integer;
  AllNamed: Boolean;
begin
  First := AssetPartStart[AssetIndex];
  AllNamed := True;
  for P := First to First + AssetPartCount[AssetIndex] - 1 do
    if Pos(AssetName[AssetIndex] + '.part-', PartName[P]) <> 1 then
      AllNamed := False;
  if AllNamed then
    Result := 'cat ' + AssetName[AssetIndex] + '.part-* > ' +
      AssetName[AssetIndex]
  else
  begin
    Result := 'cat';
    for P := First to First + AssetPartCount[AssetIndex] - 1 do
      Result := Result + ' ' + PartName[P];
    Result := Result + ' > ' + AssetName[AssetIndex];
  end;
end;

function PrepareOutput(): Boolean;
var
  C, A, P, Total: Integer;
  Notes, PartsNote, SingleName, JoinNote, FirstExe: String;
  Produced: Integer;
begin
  Result := False;
  ForceDirectories(OutputDir());
  Notes := '';
  SingleName := '';
  JoinNote := '';
  FirstExe := '';
  Produced := 0;
  RunAfterExe := '';
  RevealPath := '';
  Total := ProducedFileCount();

  WorkPage.Show;
  try
    for C := 0 to GetArrayLength(CompId) - 1 do
    begin
      if not CompSelected[C] then
        Continue;
      for A := CompAssetStart[C] to CompAssetStart[C] + CompAssetCount[C] - 1 do
      begin
        if AssetKind[A] = 'split' then
        begin
          if ShouldAssembleSingleFile(A) then
          begin
            if not AssembledIsReady(A) then
              if not AssembleAsset(A, CompName[C]) then
                exit;
            Notes := Notes + '• ' + AssetName[A] + #13#10;
            SingleName := AssetName[A];
            Produced := Produced + 1;
          end
          else
          begin
            { גדול מקובץ אחד, או ארכיון שמתקין Windows צורך כחלקים — החלקים
              נשארים כפי שהם. }
            PartsNote := '';
            for P := AssetPartStart[A] to AssetPartStart[A] + AssetPartCount[A] - 1 do
            begin
              WorkPage.SetText('מעתיק לתיקייה שנבחרה: ' + CompName[C], PartName[P]);
              WorkPage.SetProgress(Produced, Total);
              if not CopyToOutput(PartName[P]) then
              begin
                LoadErrorHeb := 'לא ניתן היה להעתיק את הקבצים לתיקייה שנבחרה.';
                exit;
              end;
              PartsNote := PartsNote + '• ' + PartName[P] + #13#10;
              SingleName := PartName[P];
              Produced := Produced + 1;
            end;
            Notes := Notes + PartsNote;
            if TargetPlatform <> 'windows' then
              JoinNote := JoinNote + JoinCommand(A) + #13#10;
          end;
        end
        else
        begin
          WorkPage.SetText('מעתיק לתיקייה שנבחרה: ' + CompName[C], AssetName[A]);
          WorkPage.SetProgress(Produced, Total);
          if not CopyToOutput(AssetName[A]) then
          begin
            LoadErrorHeb := 'לא ניתן היה להעתיק את הקבצים לתיקייה שנבחרה.';
            exit;
          end;
          Notes := Notes + '• ' + AssetName[A] + #13#10;
          SingleName := AssetName[A];
          Produced := Produced + 1;
        end;
        if IsExecutableName(AssetName[A]) and (FirstExe = '') and
           ((AssetKind[A] <> 'split') or ShouldAssembleSingleFile(A)) then
          FirstExe := AssetName[A];
        if IsThisComputerMode() and IsExecutableName(AssetName[A]) and
           (RunAfterExe = '') then
          RunAfterExe := OutputDir() + '\' + AssetName[A];
      end;
    end;
  finally
    WorkPage.Hide;
  end;

  { הניסוח נגזר ממה שנוצר בפועל, ולא מהרכיב שנבחר. }
  if IsThisComputerMode() then
    ResultText := 'הקבצים ירדו ואומתו.' + #13#10#13#10 +
      'כעת ייפתח מתקין אוצריא. המשך בו כרגיל.'
  else if Produced = 1 then
  begin
    RevealPath := OutputDir() + '\' + SingleName;
    RevealIsFile := True;
    ResultText := 'הקובץ מוכן:' + #13#10 + SingleName + #13#10#13#10 +
      'הוא נמצא בתיקייה:' + #13#10 + OutputDir() + #13#10#13#10 +
      'העתק את הקובץ הזה לדיסק-און-קי ומשם למחשב המנותק (' +
      PlatformDisplayName(TargetPlatform) + ').' + OpenHint(SingleName);
  end
  else
  begin
    RevealPath := OutputDir();
    RevealIsFile := False;
    ResultText := 'ההתקנה מוכנה בתיקייה:' + #13#10 + OutputDir() + #13#10#13#10 +
      'העתק את כל התיקייה הזאת לדיסק-און-קי ומשם למחשב המנותק (' +
      PlatformDisplayName(TargetPlatform) + '). הקבצים חייבים להישאר יחד ' +
      'באותה תיקייה.';
    if (TargetPlatform = 'windows') and (FirstExe <> '') then
      ResultText := ResultText + ' במחשב המנותק הפעל מתוכה את ' + FirstExe +
        ' — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות.';
    if JoinNote <> '' then
      ResultText := ResultText + #13#10#13#10 + 'חלק מהקבצים גדולים מדי ' +
        'לקובץ אחד ולכן נשארו מחולקים. במחשב היעד מחברים אותם בחלון מסוף ' +
        '(טרמינל), מתוך התיקייה, בפקודה:' + #13#10 + JoinNote;
    ResultText := ResultText + #13#10#13#10 + 'הקבצים שהוכנו:' + #13#10 + Notes;
  end;
  Result := True;
end;

{ ============================== זרימה ============================== }

procedure ShowFailure();
begin
  if LoadErrorTech <> '' then
    Log('DownloadAssistant: ' + LoadErrorTech);
  if MsgBox(LoadErrorHeb + #13#10#13#10 + 'להציג פרטים טכניים?',
    mbError, MB_YESNO) = IDYES then
    MsgBox(LoadErrorTech, mbInformation, MB_OK);
end;

function InitializeSetup(): Boolean;
var
  ErrorCode: Integer;
begin
  Result := True;
  ManifestLoaded := LoadReleaseManifest();
#ifdef DevSelectionDump
  if ManifestLoaded then
    DumpSelections();
  Result := False;
  exit;
#endif
  if ManifestLoaded then
    exit;
  Log('DownloadAssistant: ' + LoadErrorTech);
  { אין נתונים מאומתים, ולכן לא מורידים כלום. האפשרות היחידה שמוצעת היא
    לפתוח את עמוד ההורדות ולהוריד ידנית. }
  if MsgBox(LoadErrorHeb + #13#10#13#10 +
    'אפשר לפתוח את עמוד ההורדות של אוצריא בדפדפן ולהוריד משם ידנית ' +
    '(אפשרות מוגבלת: המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).'
    + #13#10#13#10 + 'לפתוח את עמוד ההורדות?', mbError, MB_YESNO) = IDYES then
    ShellExecAsOriginalUser('open',
      'https://github.com/Otzaria/otzaria/releases/latest', '', '',
      SW_SHOWNORMAL, ewNoWait, ErrorCode);
  Result := False;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = PresetPage.ID then
  begin
    UpdateTarget();
    RefreshPresetPage();
  end
  else if CurPageID = CustomPage.ID then
  begin
    UpdateTarget();
    RefreshCustomPage();
  end
  else if CurPageID = wpFinished then
  begin
    { ברירת המחדל של התווית נמוכה מדי — טקסט הסיום ארוך ממשפט אחד. }
    WizardForm.FinishedLabel.AutoSize := False;
    WizardForm.FinishedLabel.WordWrap := True;
    WizardForm.FinishedLabel.Height := WizardForm.FinishedPage.ClientHeight -
      WizardForm.FinishedLabel.Top;
    WizardForm.FinishedLabel.Caption := ResultText;
    if RevealPath <> '' then
    begin
      if not Assigned(RevealCheck) then
      begin
        RevealCheck := TNewCheckBox.Create(WizardForm);
        RevealCheck.Parent := WizardForm.FinishedPage;
        RevealCheck.Left := WizardForm.FinishedLabel.Left;
        RevealCheck.Width := WizardForm.FinishedLabel.Width;
        RevealCheck.Height := ScaleY(17);
        RevealCheck.Checked := True;
      end;
      RevealCheck.Top := WizardForm.FinishedPage.ClientHeight -
        RevealCheck.Height;
      WizardForm.FinishedLabel.Height := RevealCheck.Top - ScaleY(8) -
        WizardForm.FinishedLabel.Top;
      if RevealIsFile then
        RevealCheck.Caption := 'הצג את הקובץ שהוכן'
      else
        RevealCheck.Caption := 'הצג את התיקייה שהוכנה';
    end;
  end;
end;

{ פתיחת הסיירת היא נוחות בלבד: אם היא נכשלת, התוצאה כבר מוכנה ואין מה לומר. }
procedure DeinitializeSetup();
var
  ErrorCode: Integer;
begin
  if (RevealPath = '') or not Assigned(RevealCheck) or
     not RevealCheck.Checked then
    exit;
  if not ExecAsOriginalUser(ExpandConstant('{win}\explorer.exe'),
    '/select,"' + RevealPath + '"', '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
    Log('DownloadAssistant: explorer /select failed: ' + IntToStr(ErrorCode));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
  Selected: Boolean;
  Members: String;
  Free, Total, Needed: Int64;
begin
  Result := True;

  if CurPageID = PresetPage.ID then
  begin
    if PresetPage.SelectedValueIndex <> CustomPresetIndex then
      ApplyPreset(PresetPage.SelectedValueIndex);
    exit;
  end;

  if CurPageID = CustomPage.ID then
  begin
    { רכיב של יעד קודם אינו מוצג ברשימה, ולכן אסור שיישאר מסומן. }
    for I := 0 to GetArrayLength(CompId) - 1 do
      CompSelected[I] := False;
    Selected := False;
    Members := '';
    for I := 0 to GetArrayLength(CustomIndex) - 1 do
      if CustomPage.Values[I] then
      begin
        Members := Members + CompId[CustomIndex[I]] + ',';
        Selected := True;
      end;
    if not Selected then
    begin
      MsgBox('יש לבחור לפחות רכיב אחד להורדה.', mbError, MB_OK);
      Result := False;
      exit;
    end;
    { ספרייה שנבחרה לבדה מגיעה עם המתקין שקורא אותה, כמו בהצעות. }
    Members := WithDependencies(Members);
    for I := 0 to GetArrayLength(CompId) - 1 do
      CompSelected[I] := MembersContain(Members, CompId[I]);
    exit;
  end;

  if CurPageID = FolderPage.ID then
  begin
    if DirIsWritable(FolderPage.Values[0]) then
      exit;
    if DirIsWritable(FallbackOutputBase()) then
    begin
      MsgBox('לא ניתן לשמור בתיקייה שנבחרה. במקומה מוצעת התיקייה:' + #13#10 +
        FallbackOutputBase() + #13#10#13#10 +
        'אפשר להמשיך איתה או לבחור תיקייה אחרת.', mbInformation, MB_OK);
      FolderPage.Values[0] := FallbackOutputBase();
    end
    else
      MsgBox('לא ניתן לשמור בתיקייה שנבחרה. נסה תיקייה אחרת.', mbError, MB_OK);
    Result := False;
    exit;
  end;

  if CurPageID <> wpReady then
    exit;

  UpdateTarget();
  Log('DownloadAssistant: target=' + TargetPlatform + '/' + TargetArchitecture +
    '/' + TargetFormat);
  Needed := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if CompSelected[I] then
      Needed := Needed + CompDownloadSize[I] * 2;
  if GetSpaceOnDisk64(OutputBaseDir(), Free, Total) and (Free < Needed) then
    if MsgBox('נראה שאין מספיק מקום פנוי. דרושים בערך ' + HumanSize(Needed) +
      '.' + #13#10#13#10 + 'להמשיך בכל זאת?', mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
      exit;
    end;

  LoadErrorHeb := '';
  LoadErrorTech := '';
  if not BuildQueue() or not RunDownloads() or not PrepareOutput() then
  begin
    if LoadErrorHeb = '' then
      LoadErrorHeb := 'לא ניתן להכין את ההתקנה.';
    ShowFailure();
    Result := False;
    exit;
  end;

  if RunAfterExe <> '' then
    if not ShellExec('', RunAfterExe, '', ExtractFileDir(RunAfterExe),
      SW_SHOWNORMAL, ewNoWait, I) then
      ResultText := ResultText + #13#10#13#10 +
        'לא ניתן היה להפעיל את המתקין. אפשר להפעיל אותו ידנית מתוך:'
        + #13#10 + OutputDir();
end;
