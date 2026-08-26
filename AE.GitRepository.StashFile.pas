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
    _stashhash: String;
  strict protected
    Function GetCommit(Const inRepository: Pgit_repository): Pgit_commit; Override;
    Function GetDiffString: String; Override;
    Function InternalGetOriginalContent: String; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashHash: String; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
  End;

Implementation

Uses System.SysUtils;

Constructor TAEGitStashFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashHash: String; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath, inStatus);

  _stashhash := inStashHash;
End;

Function TAEGitStashFile.GetCommit(Const inRepository: Pgit_repository): Pgit_commit;
Begin
  Result := Context.GetStashCommit(_stashhash);
End;

Function TAEGitStashFile.InternalGetOriginalContent: String;
Var
  stashcommit, parent: Pgit_commit;
  parenttree: Pgit_tree;
  parentcount: Cardinal;
Begin
  Result := '';

  If Self.Status In [gfsNew, gfsUntracked] Then
    Exit;

  stashcommit := Context.GetStashCommit(_stashhash);
  Try
    parentcount := git_commit_parentcount(stashcommit);

    Context.DoLibGit2Call('git_commit_parentcount');

    If parentcount < 2 Then
    Begin
      Result := inherited;

      Exit;
    End;

    Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, stashcommit, 1));
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
    git_commit_free(stashcommit);

    Context.DoLibGit2Call('git_commit_free');
  End;
End;

Function TAEGitStashFile.GetDiffString: String;
Var
  stashcommit, parent, parent0, parent1: Pgit_commit;
  stashtree, parenttree, parentTree0, parentTree1: Pgit_tree;
  parentcount: Cardinal;
Begin
  Result := '';

  stashcommit := Context.GetStashCommit(_stashhash);
  Try
    parentcount := git_commit_parentcount(stashcommit);

    Context.DoLibGit2Call('git_commit_parentcount');

    If Self.Status In AEGITSTAGEDFILESTATUSES Then
    Begin
      If parentcount < 2 Then
        Exit;

      Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent0, stashcommit, 0));
      Try
        Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent1, stashcommit, 1));
        Try
          Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parentTree0, parent0));
          Try
            Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parentTree1, parent1));
            Try
              Result := Self.GetPatchBetweenTrees(parentTree0, parentTree1, [Self.GitPath]);
            Finally
              git_tree_free(parentTree1);

              Context.DoLibGit2Call('git_tree_free');
            End;
          Finally
            git_tree_free(parentTree0);

            Context.DoLibGit2Call('git_tree_free');
          End;
        Finally
          git_commit_free(parent1);

          Context.DoLibGit2Call('git_commit_free');
        End;
      Finally
        git_commit_free(parent0);

        Context.DoLibGit2Call('git_commit_free');
      End;

      Exit;
    End;

    If Self.Status In [gfsNew, gfsUntracked] Then
    Begin
      If parentcount >= 3 Then
      Begin
        Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, stashcommit, 2));
        Try
          Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
          Try
            Result := Self.GetPatchBetweenTrees(nil, parenttree, [Self.GitPath]);
          Finally
            git_tree_free(parenttree);

            Context.DoLibGit2Call('git_tree_free');
          End;
        Finally
          git_commit_free(parent);

          Context.DoLibGit2Call('git_commit_free');
        End;
      End
      Else
      Begin
        Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@stashtree, stashcommit));
        Try
          Result := Self.GetPatchBetweenTrees(nil, stashtree, [Self.GitPath]);
        Finally
          git_tree_free(stashtree);

          Context.DoLibGit2Call('git_tree_free');
        End;
      End;
    End
    Else
    Begin
      If parentcount >= 2 Then
      Begin
        Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, stashcommit, 1));
        Try
          Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
          Try
            Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@stashtree, stashcommit));
            Try
              Result := Self.GetPatchBetweenTrees(parenttree, stashtree, [Self.GitPath]);
            Finally
              git_tree_free(stashtree);

              Context.DoLibGit2Call('git_tree_free');
            End;
          Finally
            git_tree_free(parenttree);

            Context.DoLibGit2Call('git_tree_free');
          End;
        Finally
          git_commit_free(parent);

          Context.DoLibGit2Call('git_commit_free');
        End;
      End
      Else
        Result := inherited;
    End;
  Finally
    git_commit_free(stashcommit);

    Context.DoLibGit2Call('git_commit_free');
  End;
End;

End.
