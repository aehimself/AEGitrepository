{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.WorkTreeFile;

Interface

Uses AE.GitRepository.FileObject, AE.GitRepository.TypeDef, AE.GitRepository.Context;

Type
  TAEGitWorkTreeFile = Class(TAEGitRepositoryFile)
  strict private
    Procedure SetStatus(Const inStatus: TArray<TAEGitFileStatus>);
    Function GetStatus: TArray<TAEGitFileStatus>;
  strict protected
    Function GetDiff: String; Override;
    Function GetStagedDiff: String;
  public
    Procedure Revert;
    Procedure Stage;
    Procedure Unstage;
    Property StagedDiff: String Read GetStagedDiff;
    Property Status: TArray<TAEGitFileStatus> Read GetStatus Write SetStatus;
  End;

Implementation

Uses libgit2;

Function TAEGitWorkTreeFile.GetDiff: String;
Begin
  Result := Self.GetPatchFromWorkTree([Self.GitPath], False);
End;

Function TAEGitWorkTreeFile.GetStagedDiff: String;
Begin
  Result := Self.GetPatchFromWorkTree([Self.GitPath], True);
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
