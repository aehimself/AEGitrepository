Unit AE.GitRepository.Diff;

Interface

Uses System.UITypes, System.Generics.Collections;

Type
  TAEGitDiffRTFColors = Class
  strict private
    _addedbackgroundcolor: TColor;
    _addedfontcolor: TColor;
    _contextbackgroundcolor: TColor;
    _contextfontcolor: TColor;
    _fontname: String;
    _fontsize: Integer;
    _hunkheaderbackgroundcolor: TColor;
    _hunkheaderfontcolor: TColor;
    _removedbackgroundcolor: TColor;
    _removedfontcolor: TColor;
  public
    Constructor Create; ReIntroduce;
    Property AddedBackgroundColor: TColor Read _addedbackgroundcolor Write _addedbackgroundcolor;
    Property AddedFontColor: TColor Read _addedfontcolor Write _addedfontcolor;
    Property ContextBackgroundColor: TColor Read _contextbackgroundcolor Write _contextbackgroundcolor;
    Property ContextFontColor: TColor Read _contextfontcolor Write _contextfontcolor;
    Property FontName: String Read _fontname Write _fontname;
    Property FontSize: Integer Read _fontsize Write _fontsize;
    Property HunkHeaderBackgroundColor: TColor Read _hunkheaderbackgroundcolor Write _hunkheaderbackgroundcolor;
    Property HunkHeaderFontColor: TColor Read _hunkheaderfontcolor Write _hunkheaderfontcolor;
    Property RemovedBackgroundColor: TColor Read _removedbackgroundcolor Write _removedbackgroundcolor;
    Property RemovedFontColor: TColor Read _removedfontcolor Write _removedfontcolor;
  End;

  TAECustomGitDiff = Class
  strict private
    _bookmarks: TArray<NativeInt>;
    _diff: String;
    _usecache: Boolean;
    Function ColorToRtf(Const inColor: TColor): String;
    Function GetAsRTF: String;
    Function GetFullDiff: String;
    Function GetFullDiffAsRtf: String;
    Function GetIsCached: Boolean;
    Function InternalGetFullDiff(Out outBookmarks: TArray<NativeInt>): String;
    Function ParseHunkRange(Const inRange: String; Const inPrefix: Char; Out outStart, outCount: Integer): Boolean;
    Function RTFEscape(Const inString: String): String;
  strict protected
    Procedure ApplyFilePatch(Const inLines: TArray<String>; Var ioLine: Integer; Const inOriginalContent: String; Const inOutput: TList<String>; Const inBookmarks: TList<NativeInt>);
    Procedure BuildFullDiff(Const inLines: TArray<String>; Const inOutput: TList<String>; Const inBookmarks: TList<NativeInt>); Virtual; Abstract;
    Function ReadFileHeader(Const inLines: TArray<String>; Var ioLine: Integer; Out outIsNewFile: Boolean): String;
  public
    Constructor Create(Const inUseCache: Boolean = True); ReIntroduce;
    Property AsString: String Read _diff Write _diff;
    Property AsRTF: String Read GetAsRTF;
    Property Bookmarks: TArray<NativeInt> Read _bookmarks;
    Property FullDiff: String Read GetFullDiff;
    Property FullDiffAsRtf: String Read GetFullDiffAsRtf;
    Property IsCached: Boolean Read GetIsCached;
  End;

  TAEGitDiff = Class(TAECustomGitDiff)
  strict private
    _fullcontent: String;
  strict protected
    Procedure BuildFullDiff(Const inLines: TArray<String>; Const inOutput: TList<String>; Const inBookmarks: TList<NativeInt>); Override;
  public
    Property FullContent: String Read _fullcontent Write _fullcontent;
  End;

  TAEMultipleGitDiff = Class(TAECustomGitDiff)
  strict private
    _fullcontents: TDictionary<String, String>;
  strict protected
    Procedure BuildFullDiff(Const inLines: TArray<String>; Const inOutput: TList<String>; Const inBookmarks: TList<NativeInt>); Override;
  public
    Constructor Create(Const inUseCache: Boolean = True); ReIntroduce;
    Destructor Destroy; Override;
    // Keys are git paths (old path for renames); new files need no entry
    Property FullContents: TDictionary<String, String> Read _fullcontents;
  End;

Function AEGitDiffRTFColors: TAEGitDiffRTFColors;

Implementation

Uses System.SysUtils, AE.GitRepository.Exception;

Var
  _rtfcolors: TAEGitDiffRTFColors;

Function AEGitDiffRTFColors: TAEGitDiffRTFColors;
Begin
  If Not Assigned(_rtfcolors) Then
    _rtfcolors := TAEGitDiffRTFColors.Create;

  Result := _rtfcolors;
End;

//
// TAEGitDiffRTFColors
//

Constructor TAEGitDiffRTFColors.Create;
Begin
  inherited;

  _addedbackgroundcolor := TColor($0000AA00);
  _addedfontcolor := TColor($00FFFFFF);
  _contextbackgroundcolor := TColor($00FFFFFF);
  _contextfontcolor := TColor($00000000);
  _fontname := 'Consolas';
  _fontsize := 10;
  _hunkheaderbackgroundcolor := TColor($00FFFFFF);
  _hunkheaderfontcolor := TColor($00808080);
  _removedbackgroundcolor := TColor($003C14DC);
  _removedfontcolor := TColor($00FFFFFF);
End;

//
// TAECustomGitDiff
//

Constructor TAECustomGitDiff.Create(Const inUseCache: Boolean = True);
Begin
  inherited Create;

  _usecache := inUseCache;
End;

Function TAECustomGitDiff.GetFullDiff: String;
Begin
  Result := InternalGetFullDiff(_bookmarks);
End;

Function TAECustomGitDiff.GetFullDiffAsRtf: String;
Var
  lines: TArray<String>;
  a: Integer;
  sb: TStringBuilder;
Begin
  sb := TStringBuilder.Create('{\rtf1\ansi\deff0\viewkind4{\fonttbl{\f0 ' + AEGitDiffRTFColors.FontName + ';}}{\colortbl;' +
    ColorToRtf(AEGitDiffRTFColors.ContextFontColor) + // \cf1
    ColorToRtf(AEGitDiffRTFColors.RemovedBackgroundColor) + // \cbpat2
    ColorToRtf(AEGitDiffRTFColors.AddedBackgroundColor) + // \cbpat3
    ColorToRtf(AEGitDiffRTFColors.AddedFontColor) + // \cf4
    ColorToRtf(AEGitDiffRTFColors.HunkHeaderFontColor) + // \cf5
    ColorToRtf(AEGitDiffRTFColors.RemovedFontColor) + // \cf6
    ColorToRtf(AEGitDiffRTFColors.ContextBackgroundColor) + // \cbpat7
    ColorToRtf(AEGitDiffRTFColors.HunkHeaderBackgroundColor) + // \cbpat8
    '}\f0\fs' + Integer(AEGitDiffRTFColors.FontSize * 2).ToString + ' ');
  Try
    lines := Self.FullDiff.Split([#10]);

    For a := Low(lines) To High(lines) Do
    Begin
      lines[a] := lines[a].TrimRight;

      If lines[a].StartsWith('-') Then
        sb.Append('\pard\cf6\chshdng0\chcbpat2 ' + RTFEscape(lines[a].Substring(1)) + '\par ')
      Else If lines[a].StartsWith('+') Then
        sb.Append('\pard\cf4\chshdng0\chcbpat3 ' + RTFEscape(lines[a].Substring(1)) + '\par ')
      Else
        sb.Append('\pard\cf1\chshdng0\chcbpat7 ' + RTFEscape(lines[a].Substring(1)) + '\par ');
    End;

    sb.Append('}');

    Result := sb.ToString;
  Finally
    FreeAndNil(sb);
  End;
End;

Function TAECustomGitDiff.GetIsCached: Boolean;
Begin
  Result := _usecache And Not _diff.IsEmpty;
End;

Function TAECustomGitDiff.InternalGetFullDiff(Out outBookmarks: TArray<NativeInt>): String;
Var
  output: TList<String>;
  bookmarks: TList<NativeInt>;
Begin
  output := TList<String>.Create;
  Try
    bookmarks := TList<NativeInt>.Create;
    Try
      BuildFullDiff(_diff.Replace(#13#10, #10).Split([#10]), output, bookmarks);

      outBookmarks := bookmarks.ToArray;
      Result := String.Join(sLineBreak, output.ToArray);
    Finally
      FreeAndNil(bookmarks);
    End;
  Finally
    FreeAndNil(output);
  End;
End;

Procedure TAECustomGitDiff.ApplyFilePatch(Const inLines: TArray<String>; Var ioLine: Integer; Const inOriginalContent: String; Const inOutput: TList<String>; Const inBookmarks: TList<NativeInt>);
Var
  original: TArray<String>;
  position, newposition, hunkstart, newhunkstart, oldstart, oldcount, newstart, newcount, oldseen, newseen: Integer;
  inchange: Boolean;
  parts: TArray<String>;
  line: String;
  prefix: Char;
Begin
  line := inOriginalContent.Replace(#13#10, #10);
  If line.EndsWith(#10) Then
    line := line.Substring(0, line.Length - 1);

  If inOriginalContent.IsEmpty Then
    original := nil
  Else
    original := line.Split([#10]);

  position := 0;
  newposition := 0;

  While ioLine <= High(inLines) Do
  Begin
    line := inLines[ioLine];

    If line.StartsWith('diff --git ') Then
      Break;

    If line.IsEmpty Or line.StartsWith('\') Then
    Begin
      Inc(ioLine);

      Continue;
    End;

    parts := line.Split([' ']);

    If Not line.StartsWith('@@ ') Or (Length(parts) < 4) Or Not ParseHunkRange(parts[1], '-', oldstart, oldcount) Or
      Not ParseHunkRange(parts[2], '+', newstart, newcount) Or (oldstart < 0) Or (newstart < 0) Or (oldcount < 0) Or (newcount < 0) Or
      ((oldcount > 0) And (oldstart = 0)) Or ((newcount > 0) And (newstart = 0)) Then
      Raise EAEGitException.Create('Invalid diff: unexpected content at diff line ' + (ioLine + 1).ToString + '!');

    // A hunk removing nothing inserts after line oldstart
    If oldcount = 0 Then
      hunkstart := oldstart
    Else
      hunkstart := oldstart - 1;

    If newcount = 0 Then
      newhunkstart := newstart
    Else
      newhunkstart := newstart - 1;

    If (hunkstart < position) Or (hunkstart + oldcount > Length(original)) Then
      Raise EAEGitException.Create('Diff can not be applied: hunk at diff line ' + (ioLine + 1).ToString + ' does not fit the original content!');

    If (hunkstart - position) <> (newhunkstart - newposition) Then
      Raise EAEGitException.Create('Diff can not be applied: hunk at diff line ' + (ioLine + 1).ToString + ' has an inconsistent new-file position!');

    While position < hunkstart Do
    Begin
      inOutput.Add(' ' + original[position]);

      Inc(position);
      Inc(newposition);
    End;

    Inc(ioLine);
    oldseen := 0;
    newseen := 0;
    inchange := False;

    While (oldseen < oldcount) Or (newseen < newcount) Do
    Begin
      If ioLine > High(inLines) Then
        Raise EAEGitException.Create('Invalid diff: unexpected end of hunk!');

      line := inLines[ioLine];
      Inc(ioLine);

      If line.StartsWith('\') Then
        Continue;

      If line.IsEmpty Then
        prefix := ' '
      Else
        prefix := line.Chars[0];

      If (prefix <> ' ') And (prefix <> '-') And (prefix <> '+') Then
        Raise EAEGitException.Create('Invalid diff: unexpected content at diff line ' + ioLine.ToString + '!');

      If prefix = ' ' Then
        inchange := False
      Else If Not inchange Then
      Begin
        inBookmarks.Add(inOutput.Count + 1);
        inchange := True;
      End;

      If prefix <> '+' Then
      Begin
        If (position > High(original)) Or (original[position] <> line.Substring(1)) Then
          Raise EAEGitException.Create('Diff can not be applied: diff line ' + ioLine.ToString + ' does not match original line ' + (position + 1).ToString + '!');

        Inc(position);
        Inc(oldseen);
      End;

      If prefix <> '-' Then
      Begin
        Inc(newseen);
        Inc(newposition);
      End;

      If (oldseen > oldcount) Or (newseen > newcount) Then
        Raise EAEGitException.Create('Invalid diff: hunk line counts do not match at diff line ' + ioLine.ToString + '!');

      inOutput.Add(prefix + line.Substring(1));
    End;
  End;

  While position <= High(original) Do
  Begin
    inOutput.Add(' ' + original[position]);

    Inc(position);
  End;
End;

Function TAECustomGitDiff.ParseHunkRange(Const inRange: String; Const inPrefix: Char; Out outStart, outCount: Integer): Boolean;
Var
  parts: TArray<String>;
Begin
  outStart := 0;
  outCount := 1;

  Result := inRange.StartsWith(inPrefix);

  If Not Result Then
    Exit;

  parts := inRange.Substring(1).Split([',']);

  Result := (Length(parts) In [1, 2]) And TryStrToInt(parts[0], outStart) And ((Length(parts) = 1) Or TryStrToInt(parts[1], outCount));
  Result := Result And (outStart >= 0) And (outCount >= 0);
End;

Function TAECustomGitDiff.ReadFileHeader(Const inLines: TArray<String>; Var ioLine: Integer; Out outIsNewFile: Boolean): String;
Var
  headerpath, newpath: String;
  a: Integer;
Begin
  Result := '';
  headerpath := '';
  newpath := '';
  outIsNewFile := False;

  If (ioLine <= High(inLines)) And inLines[ioLine].StartsWith('diff --git a/') Then
  Begin
    a := inLines[ioLine].IndexOf(' b/', 13);

    If a > -1 Then
      headerpath := inLines[ioLine].Substring(13, a - 13);

    Inc(ioLine);
  End;

  While (ioLine <= High(inLines)) And Not inLines[ioLine].StartsWith('@@') And Not inLines[ioLine].StartsWith('diff --git ') Do
  Begin
    If (inLines[ioLine] = '--- /dev/null') Or inLines[ioLine].StartsWith('new file mode ') Then
      outIsNewFile := True
    Else If inLines[ioLine].StartsWith('--- a/') Then
      Result := inLines[ioLine].Substring(6)
    Else If inLines[ioLine].StartsWith('+++ b/') Then
      newpath := inLines[ioLine].Substring(6)
    Else If inLines[ioLine].StartsWith('rename from ') Then
      headerpath := inLines[ioLine].Substring(12);

    Inc(ioLine);
  End;

  If Result.IsEmpty Then
    Result := headerpath;

  If Result.IsEmpty Then
    Result := newpath;
End;

Function TAECustomGitDiff.ColorToRtf(Const inColor: TColor): String;
Var
  a: Integer;
Begin
  a := TColorRec.ColorToRGB(inColor);

  Result := Format('\red%d\green%d\blue%d;', [a And $FF, (a Shr 8) And $FF, (a Shr 16) And $FF]);
End;

Function TAECustomGitDiff.GetAsRTF: String;
Var
  lines: TArray<String>;
  a, b, contentstart: Integer;
  sb: TStringBuilder;
Begin
  sb := TStringBuilder.Create('{\rtf1\ansi\deff0\viewkind4{\fonttbl{\f0 ' + AEGitDiffRTFColors.FontName + ';}}{\colortbl;' +
    ColorToRtf(AEGitDiffRTFColors.ContextFontColor) + // \cf1
    ColorToRtf(AEGitDiffRTFColors.RemovedBackgroundColor) + // \cbpat2
    ColorToRtf(AEGitDiffRTFColors.AddedBackgroundColor) + // \cbpat3
    ColorToRtf(AEGitDiffRTFColors.AddedFontColor) + // \cf4
    ColorToRtf(AEGitDiffRTFColors.HunkHeaderFontColor) + // \cf5
    ColorToRtf(AEGitDiffRTFColors.RemovedFontColor) + // \cf6
    ColorToRtf(AEGitDiffRTFColors.ContextBackgroundColor) + // \cbpat7
    ColorToRtf(AEGitDiffRTFColors.HunkHeaderBackgroundColor) + // \cbpat8
    '}\f0\fs' + Integer(AEGitDiffRTFColors.FontSize * 2).ToString + ' ');
  Try
    lines := _diff.Split([#10]);

    contentstart := High(lines) + 1;

    For a := Low(lines) To High(lines) Do
      If lines[a].StartsWith('@@') Then
      Begin
        contentstart := a;

        Break;
      End;

    For a := contentstart To High(lines) Do
    Begin
      lines[a] := lines[a].TrimRight;

      If lines[a].StartsWith('@@ ') Then
      Begin
        If a <> contentstart Then
          sb.Append('\pard\chshdng0 \par ');

        b := lines[a].IndexOf('@@ ', 3);

        If b = -1 Then
          sb.Append('\pard\cf5\i\chshdng0\chcbpat8 ' + RTFEscape(lines[a].Substring(3, lines[a].IndexOf('@', 3) - 4)) + '\i0\par ')
        Else
        Begin
          sb.Append('\pard\cf5\i\chshdng0\chcbpat8 ' + RTFEscape(lines[a].Substring(3, b - 4)) + '\i0\par ');

          sb.Append('\pard\cf1\chshdng0\chcbpat7 ' + RTFEscape(lines[a].Substring(b + 3)) + '\par ');
        End;
      End
      Else If lines[a].StartsWith('-') Then
        sb.Append('\pard\cf6\chshdng0\chcbpat2 ' + RTFEscape(lines[a].Substring(1)) + '\par ')
      Else If lines[a].StartsWith('+') Then
        sb.Append('\pard\cf4\chshdng0\chcbpat3 ' + RTFEscape(lines[a].Substring(1)) + '\par ')
      Else
        sb.Append('\pard\cf1\chshdng0\chcbpat7 ' + RTFEscape(lines[a].Substring(1)) + '\par ');
    End;

    sb.Append('}');

    Result := sb.ToString;
  Finally
    FreeAndNil(sb);
  End;
End;

Function TAECustomGitDiff.RTFEscape(Const inString: String): String;
Var
  c: Char;
Begin
  Result := '';

  For c In inString Do
    Case c Of
      '\', '{', '}':
        Result := Result + '\' + c;
      #13:
        Begin End;
      #10:
        Result := Result + '\par ';
      Else
        If Ord(c) > 127 Then
          Result := Result + '\u' + IntToStr(SmallInt(Ord(c))) + '?'
        Else
          Result := Result + c;
    End;

  If Result.IsEmpty Then
    Result := ' ';
End;

//
// TAEGitDiff
//

Procedure TAEGitDiff.BuildFullDiff(Const inLines: TArray<String>; Const inOutput: TList<String>; Const inBookmarks: TList<NativeInt>);
Var
  a: Integer;
  isnew: Boolean;
Begin
  a := 0;

  ReadFileHeader(inLines, a, isnew);

  ApplyFilePatch(inLines, a, _fullcontent, inOutput, inBookmarks);

  If a <= High(inLines) Then
    Raise EAEGitException.Create('Diff contains more than one file, use TAEMultipleGitDiff instead!');
End;

//
// TAEMultipleGitDiff
//

Constructor TAEMultipleGitDiff.Create(Const inUseCache: Boolean = True);
Begin
  inherited;

  _fullcontents := TDictionary<String, String>.Create;
End;

Destructor TAEMultipleGitDiff.Destroy;
Begin
  FreeAndNil(_fullcontents);

  inherited;
End;

Procedure TAEMultipleGitDiff.BuildFullDiff(Const inLines: TArray<String>; Const inOutput: TList<String>; Const inBookmarks: TList<NativeInt>);
Var
  a: Integer;
  path, content: String;
  isnew: Boolean;
Begin
  a := 0;

  // File headers are needed to identify which original content belongs to which hunks
  While (a <= High(inLines)) And Not inLines[a].StartsWith('diff --git ') Do
    Inc(a);

  While a <= High(inLines) Do
  Begin
    inOutput.Add(inLines[a]);

    path := ReadFileHeader(inLines, a, isnew);

    If isnew Then
      content := ''
    Else If Not _fullcontents.TryGetValue(path, content) Then
      Raise EAEGitException.Create('Full content of ' + path + ' was not supplied!');

    ApplyFilePatch(inLines, a, content, inOutput, inBookmarks);
  End;
End;

Initialization

Finalization
  FreeAndNil(_rtfcolors);

End.
