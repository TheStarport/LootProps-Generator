unit UMainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls;

type
  TMainForm = class(TForm)
    SaveDialog: TSaveDialog;
    WarningsListBox: TListBox;
    SelectDirectoryDialog: TSelectDirectoryDialog;
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  FileUtil,
  Math;

type
  TStringsListArray = array of TStringList;

  THpTypeChance = record
    HpType: String;
    Chance: Uint8;
  end;

var
  ValidSectionNames: array of String = ('commodity', 'repairkit', 'shieldbattery', 'munition', 'gun', 'mine', 'minedropper', 'countermeasure', 'countermeasuredropper', 'thruster', 'shieldgenerator', 'power', 'engine', 'scanner', 'tractor', 'cloakingdevice', 'armor');

function EqualsSome(Str: String; constref Values: array of String): Boolean;
var
  Index: ValSInt;
begin
  for Index := 0 to High(Values) do
    if Str = Values[Index] then
      Exit(True);
  Result := False;
end;

function ExtractAllSection(constref IniFile: TStringList; constref ValidSectionNames: array of String): TStringsListArray;
var
  LineNumber: ValSInt;
  Line: String;
  LastSectionName: String = '';
begin
  Result := nil;

  // Ignore BINI files
  if (IniFile.Count > 0) and IniFile.Strings[0].StartsWith('BINI') then
    Exit;

  for LineNumber := 0 to IniFile.Count - 1 do
  begin
    Line := IniFile.Strings[LineNumber].Trim;
    if Line.Trim.IsEmpty then
      Continue;

    // We found a Ini section
    if Line.StartsWith('[') and Line.EndsWith(']') then
    begin
      Line := Line.Replace('[', '').Replace(']', '').ToLower;
      // Make sure it is a section we want to use for later
      if not EqualsSome(Line, ValidSectionNames) then
      begin
        LastSectionName := '';
        Continue;
      end;
      LastSectionName := Line;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := TStringList.Create;
      Result[High(Result)].Append(LastSectionName);
      Continue;
    end;

    // As long as we have a valid Ini section, copy everything of it
    if not LastSectionName.IsEmpty then
      Result[High(Result)].Append(Line);
  end;
end;

{
  https://the-starport.net/freelancer/forum/viewtopic.php?post_id=38848#forumpost38848

  drop_properties = chance, min_worth, worth_mult, min, max1, max2

  worth is your current worth
  rand is a random number between 0 and 1
  target_count is how many items the droppee has of this loot
  count is how many items to drop

  count = (worth - min_worth) / worth_mult
  if (count >= target_count)
    count = target_count
  if (count + min > max1)
    count = max1
  else
    count += min
  if (count >= target_count)
    count = target_count
  prob = chance * count
  count = floor( prob )
  prob -= count
  if (rand < prob)
    ++count
  if (count >= max2)
    count = max2
}

procedure CreateLootProp(Name: String; Chance: Uint8; Min: Uint16; MaxForChance: Uint16; MaxToDrop: Uint16; constref StringList: TStringList);
begin
  StringList.Append('[mLootProps]');
  StringList.Append('nickname = ' + Name);
  StringList.Append('drop_properties = ' + IntToStr(Math.Min(Chance, 100)) + ', 0, 1, ' + IntToStr(Min) + ', ' + IntToStr(MaxForChance) + ', ' + IntToStr(MaxToDrop));
  StringList.Append('');
end;

function IsLootable(constref Section: TStringList): Boolean;
var
  Index: ValSInt;
  Line: String;
begin
  for Index := 0 to Section.Count - 1 do
  begin
    Line := Section.Strings[Index].ToLower;
    if Line.StartsWith('lootable') and Line.EndsWith('true') then
      Exit(True);
  end;
  Result := False;
end;

function FindNickname(constref Section: TStringList): String;
var
  Index: ValSInt;
  Line: String;
begin
  for Index := 0 to Section.Count - 1 do
  begin
    Line := Section.Strings[Index].ToLower;
    if Line.StartsWith('nickname') then
      Exit(Line.Split(['='])[1].Trim);
  end;
  Result := '';
end;

function FindHpType(constref Section: TStringList): String;
var
  Index: ValSInt;
  Line: String;
begin
  for Index := 0 to Section.Count - 1 do
  begin
    Line := Section.Strings[Index].ToLower;
    if Line.StartsWith('hp_type') or Line.StartsWith('hp_gun_type') then
      Exit(Line.Split(['='])[1].Trim);
  end;
  Result := '';
end;

function CreateLootProps(constref Sections: TStringsListArray): TStringList;
var
  Index: ValSInt;
  Name: String;
begin
  Result := TStringList.Create;
  for Index := 0 to High(Sections) do
    if IsLootable(Sections[Index]) then
    begin
      Name := FindNickname(Sections[Index]);
      case Sections[Index].Strings[0].ToLower of
        'commodity': CreateLootProp(Name, 100, 65535, 65535, 65535, Result);
        'shieldbattery': CreateLootProp(Name, 100, 65535, 65535, 65535, Result);
        'repairkit': CreateLootProp(Name, 100, 65535, 65535, 65535, Result);
        'munition': CreateLootProp(Name, 100, 65535, 65535, 65535, Result);
        'mine': CreateLootProp(Name, 100, 65535, 65535, 65535, Result);
        'countermeasure': CreateLootProp(Name, 100, 65535, 65535, 65535, Result);
        else
          CreateLootProp(Name, 8, 0, 2, 1, Result);
      end;
    end;
end;

procedure CreateWarnings(Sections: TStringsListArray);
var
  Warnings: TStringList;
  SectionIndex: ValSInt;
begin
  Warnings := TStringList.Create;
  for SectionIndex := 0 to High(Sections) do
    if not IsLootable(Sections[SectionIndex]) then
      Warnings.Append(FindNickname(Sections[SectionIndex]) + ' - ' + 'lootable=false or not defined');
  MainForm.WarningsListBox.Items.Assign(Warnings);
  Warnings.Free;
end;

function CreateLootPropsFromIniFiles(const DirectoryPath: String): TStringList;
var
  Files: TStringList;
  Index: ValSInt;
  IniFile: TStringList;
  Sections: TStringsListArray;
  OldAllSectionsLength: ValSInt;
  AllSections: TStringsListArray;
  LootProps: TStringList;
begin
  Files := FindAllFiles(DirectoryPath, '*.ini', False);
  AllSections := nil;
  for Index := 0 to Files.Count - 1 do
  begin
    IniFile := TStringList.Create;
    IniFile.LoadFromFile(Files[Index]);
    Sections := ExtractAllSection(IniFile, ValidSectionNames);
    IniFile.Free;
    if Length(Sections) > 0 then
    begin
      OldAllSectionsLength := Length(AllSections);
      SetLength(AllSections, Length(AllSections) + Length(Sections));
      Move(Sections[0], AllSections[OldAllSectionsLength], Length(Sections) * SizeOf(TStringList));
    end;
    SetLength(Sections, 0);
  end;

  CreateWarnings(AllSections);
  Result := CreateLootProps(AllSections);

  for Index := 0 to High(AllSections) do
    AllSections[Index].Free;
  SetLength(AllSections, 0);
  Files.Free;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  LootProps: TStringList;
begin
  if SelectDirectoryDialog.Execute and SaveDialog.Execute then
  begin
    LootProps := CreateLootPropsFromIniFiles(SelectDirectoryDialog.FileName);
    LootProps.SaveToFile(SaveDialog.FileName);
    LootProps.Free;
  end;
end;

end.
