{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.SubModuleCommitFile;

Interface

Uses AE.GitRepository.CommitBasedFile, AE.GitRepository.TypeDef, AE.GitRepository.Context, System.Generics.Collections, libgit2;

Type
  TAEGitSubmoduleFile = Class(TAEGitCommitBasedFile)
  strict private
    _submodulepath: String;
    _commithash: String;
  strict protected
    Function GetCommit(Const inRepository: Pgit_repository): Pgit_commit; Override;
    Function GetDiff: String; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inSubmodulePath, inCommitHash, inGitPath: String; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
  End;

  TAEGitSubmoduleFileList = Class(TObjectDictionary<String, TAEGitSubmoduleFile>);

Implementation

Constructor TAEGitSubmoduleFile.Create(Const inContext: TAEGitRepositoryContext; Const inSubmodulePath, inCommitHash, inGitPath: String; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath, inStatus);

  _submodulepath := inSubmodulePath;
  _commithash := inCommitHash;
End;

Function TAEGitSubmoduleFile.GetCommit(Const inRepository: Pgit_repository): Pgit_commit;
Var
  oid: git_oid;
Begin
  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_commithash))));

  Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@Result, inRepository, @oid));
End;

Function TAEGitSubmoduleFile.GetDiff: String;
Var
  submodule: Pgit_submodule;
  subrepo: Pgit_repository;
Begin
  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_submodulepath))));
  Try
    Context.HandleLibGit2Output('git_submodule_open', git_submodule_open(@subrepo, submodule));
    Try
      Result := Self.InternalGetDiff(subrepo);
    Finally
      git_repository_free(subrepo);

      Context.DoLibGit2Call('git_repository_free');
    End;
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;
End;

End.
