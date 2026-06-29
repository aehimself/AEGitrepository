{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.CommitBasedFile;

Interface

Uses AE.GitRepository.FileObject, AE.GitRepository.TypeDef, AE.GitRepository.Context, libgit2;

Type
  TAEGitCommitBasedFile = Class(TAEGitRepositoryFile)
  strict private
    Function GetStatus: TAEGitFileStatus;
  strict protected
    Function GetCommit: Pgit_commit; Virtual; Abstract;
    Function GetDiff: String; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
    Property Status: TAEGitFileStatus Read GetStatus;
  End;

Implementation

Uses System.SysUtils;

Constructor TAEGitCommitBasedFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath);

  Self.InternalStatus := [inStatus];
End;

Function TAEGitCommitBasedFile.GetDiff: String;
Var
  commit: Pgit_commit;
Begin
  Result := '';

  commit := Self.GetCommit;

  If Assigned(commit) Then
  Try
    Result := Self.GetPatchFromCommit(commit, [Self.GitPath]);
  Finally
    git_commit_free(commit);

    Context.ContextDoLibGit2Call('git_commit_free');
  End;
End;

Function TAEGitCommitBasedFile.GetStatus: TAEGitFileStatus;
Begin
  Result := Self.InternalStatus[0];
End;

End.
