{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.FileObject;

Interface

Uses AE.GitRepository.ContextedObject, AE.GitRepository.TypeDef, AE.Gitrepository.Context, AE.GitRepository.Diff;

Type
  TAEGitRepositoryFile = Class(TAEGitRepositoryContextedObject)
  strict private
    _diff: TAEGitDiff;
    _gitpath: String;
    _status: TArray<TAEGitFileStatus>;
  strict protected
    Function GetDiff: TAEGitDiff; Virtual;
    Function GetDiffString: String; Virtual; Abstract;
    Property InternalStatus: TArray<TAEGitFileStatus> Read _status Write _status;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Property Diff: TAEGitDiff Read GetDiff;
    Property GitPath: String Read _gitpath;
  End;

Implementation

Uses System.SysUtils;

Constructor TAEGitRepositoryFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String);
Begin
  inherited Create(inContext);

  _diff := TAEGitDiff.Create;
  _gitpath := inGitPath;
  _status := [];
End;

Destructor TAEGitRepositoryFile.Destroy;
Begin
  FreeAndNil(_diff);

  inherited;
End;

Function TAEGitRepositoryFile.GetDiff: TAEGitDiff;
Begin
  If _diff.AsString.IsEmpty Then
    _diff.AsString := Self.GetDiffString;

  Result := _diff;
End;

End.
