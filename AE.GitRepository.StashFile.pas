{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.StashFile;

Interface

Uses AE.GitRepository.CommitBasedFile, AE.GitRepository.TypeDef, AE.GitRepository.Context, libgit2;

Type
  TAEGitStashFile = Class(TAEGitCommitBasedFile)
  strict private
    _stashindex: Integer;
  strict protected
    Function GetCommit: Pgit_commit; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashIndex: Integer; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
  End;

Implementation

Constructor TAEGitStashFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashIndex: Integer; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath, inStatus);

  _stashindex := inStashIndex;
End;

Function TAEGitStashFile.GetCommit: Pgit_commit;
Begin
  Result := Context.ContextGetStashCommit(_stashindex);
End;

End.
