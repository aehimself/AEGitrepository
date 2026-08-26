{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.CommitFile;

Interface

Uses AE.GitRepository.CommitBasedFile, System.Generics.Collections, AE.GitRepository.TypeDef, AE.GitRepository.Context, libgit2;

Type
  TAEGitCommitFile = Class(TAEGitCommitBasedFile)
  strict private
    _commithash: String;
  strict protected
    Function GetCommit(Const inRepository: Pgit_repository): Pgit_commit; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inCommitHash, inGitPath: String; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
  End;

  TAEGitCommitFileList = Class(TObjectList<TAEGitCommitFile>);

Implementation

Uses System.SysUtils;

Constructor TAEGitCommitFile.Create(Const inContext: TAEGitRepositoryContext; Const inCommitHash, inGitPath: String; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath, inStatus);

  _commithash := inCommitHash;
End;

Function TAEGitCommitFile.GetCommit(Const inRepository: Pgit_repository): Pgit_commit;
Var
  oid: git_oid;
Begin
  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_commithash))));

  Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@Result, inRepository, @oid));
End;

End.