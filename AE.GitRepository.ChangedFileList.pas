{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.ChangedFileList;

Interface

Uses System.Generics.Collections, AE.GitRepository.TypeDef;

Type
  TAEGitChangedFileList = Class(TDictionary<String, TArray<TAEGitFileStatus>>)
  public
    Procedure AddFileStatus(Const inFileName: String; Const inStatus: TAEGitFileStatus);
  End;

Implementation

Procedure TAEGitChangedFileList.AddFileStatus(Const inFileName: String; Const inStatus: TAEGitFileStatus);
Var
  statuses: TArray<TAEGitFileStatus>;
  len: Integer;
  existing: TAEGitFileStatus;
Begin
  If Self.TryGetValue(inFileName, statuses) Then
  Begin
    For existing In statuses Do
      If existing = inStatus Then
        Exit;

    len := Length(statuses);
    SetLength(statuses, len + 1);
    statuses[len] := inStatus;
    Self[inFileName] := statuses;
  End
  Else
    Self.Add(inFileName, [inStatus]);
End;

End.
