Unit AE.GitRepository.Diff;

Interface

Uses System.UITypes;

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

  TAEGitDiff = Class
  strict private
    _diff: String;
    _usecache: Boolean;
    Function ColorToRtf(Const inColor: TColor): String;
    Function GetAsRTF: String;
    Function GetIsCached: Boolean;
    Function RTFEscape(Const inString: String): String;
  public
    Constructor Create(Const inUseCache: Boolean = True); ReIntroduce;
    Property AsString: String Read _diff Write _diff;
    Property AsRTF: String Read GetAsRTF;
    Property IsCached: Boolean Read GetIsCached;
  End;

Function AEGitDiffRTFColors: TAEGitDiffRTFColors;

Implementation

Uses System.SysUtils;

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
// TAEGitDiff
//

Constructor TAEGitDiff.Create(Const inUseCache: Boolean = True);
Begin
  inherited Create;

  _usecache := inUseCache;
End;

Function TAEGitDiff.GetIsCached: Boolean;
Begin
  Result := _usecache And Not _diff.IsEmpty;
End;

Function TAEGitDiff.ColorToRtf(Const inColor: TColor): String;
Var
  a: Integer;
Begin
  a := TColorRec.ColorToRGB(inColor);

  Result := Format('\red%d\green%d\blue%d;', [a And $FF, (a Shr 8) And $FF, (a Shr 16) And $FF]);
End;

Function TAEGitDiff.GetAsRTF: String;
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

Function TAEGitDiff.RTFEscape(Const inString: String): String;
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

Initialization

Finalization
  FreeAndNil(_rtfcolors);

End.
