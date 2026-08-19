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
    Function GetCommit(Const inRepository: Pgit_repository): Pgit_commit; Virtual; Abstract;
    Function GetDiffString: String; Override;
    Function InternalGetOriginalContent: String; Override;
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

Function TAEGitCommitBasedFile.GetDiffString: String;
Var
  commit: Pgit_commit;
Begin
  Result := '';

  commit := Self.GetCommit(Context.Repository);
  Try
    Result := Self.GetPatchFromCommit(commit, [Self.GitPath], Context.Repository);
  Finally
    git_commit_free(commit);

    Context.DoLibGit2Call('git_commit_free');
  End;
End;

Function TAEGitCommitBasedFile.InternalGetOriginalContent: String;
Var
  commit, parent: Pgit_commit;
  parenttree: Pgit_tree;
  parentcount: Cardinal;
Begin
  Result := '';

  commit := Self.GetCommit(Context.Repository);
  Try
    parentcount := git_commit_parentcount(commit);

    Context.DoLibGit2Call('git_commit_parentcount');

    If parentcount = 0 Then
      Exit;

    Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));
    Try
      Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
      Try
        Result := Self.GetFileContentFromTree(parenttree, Self.GitPath, Context.Repository);
      Finally
        git_tree_free(parenttree);

        Context.DoLibGit2Call('git_tree_free');
      End;
    Finally
      git_commit_free(parent);

      Context.DoLibGit2Call('git_commit_free');
    End;
  Finally
    git_commit_free(commit);

    Context.DoLibGit2Call('git_commit_free');
  End;
End;

Function TAEGitCommitBasedFile.GetStatus: TAEGitFileStatus;
Begin
  Result := Self.InternalStatus[0];
End;

End.
