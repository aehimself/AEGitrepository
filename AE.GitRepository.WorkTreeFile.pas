{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.WorkTreeFile;

Interface

Uses AE.GitRepository.FileObject, AE.GitRepository.TypeDef, AE.GitRepository.Context, AE.GitRepository.Diff;

Type
  TAEGitWorkTreeFile = Class(TAEGitRepositoryFile)
  strict private
    _stageddiff: TAEGitDiff;
    Procedure SetStatus(Const inStatus: TArray<TAEGitFileStatus>);
    Function GetStagedDiff: TAEGitDiff;
    Function GetStatus: TArray<TAEGitFileStatus>;
  strict protected
    Function GetDiff: TAEGitDiff; Override;
    Function GetDiffString: String; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String); Override;
    Destructor Destroy; Override;
    Procedure Revert;
    Procedure Stage;
    Procedure Unstage;
    Property StagedDiff: TAEGitDiff Read GetStagedDiff;
    Property Status: TArray<TAEGitFileStatus> Read GetStatus Write SetStatus;
  End;

Implementation

Uses libgit2, System.SysUtils;

Function TAEGitWorkTreeFile.GetDiffString: String;
Begin
  Result := Self.GetPatchFromWorkTree([Self.GitPath], False);
End;

Constructor TAEGitWorkTreeFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String);
Begin
  inherited;

  _stageddiff := TAEGitDiff.Create;
End;

Destructor TAEGitWorkTreeFile.Destroy;
Begin
  FreeAndNil(_stageddiff);

  inherited;
End;

Function TAEGitWorkTreeFile.GetDiff: TAEGitDiff;
Begin
  Result := inherited;

  Result.AsString := Self.GetDiffString;
End;

Function TAEGitWorkTreeFile.GetStagedDiff: TAEGitDiff;
Begin
  _stageddiff.AsString := Self.GetPatchFromWorkTree([Self.GitPath], True);

  Result := _stageddiff;
End;

Function TAEGitWorkTreeFile.GetStatus: TArray<TAEGitFileStatus>;
Begin
  Result := Self.InternalStatus;
End;

Procedure TAEGitWorkTreeFile.Revert;
Begin
  Context.RevertFile(Self.GitPath);
End;

Procedure TAEGitWorkTreeFile.SetStatus(Const inStatus: TArray<TAEGitFileStatus>);
Begin
  Self.InternalStatus := inStatus;
End;

Procedure TAEGitWorkTreeFile.Stage;
Begin
  Context.StageFile(Self.GitPath);
End;

Procedure TAEGitWorkTreeFile.Unstage;
Begin
  Context.UnstageFile(Self.GitPath);
End;

End.
