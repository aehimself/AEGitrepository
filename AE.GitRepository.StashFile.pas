{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.StashFile;

Interface

Uses AE.GitRepository.CommitBasedFile, AE.GitRepository.TypeDef, AE.GitRepository.Context, libgit2, AE.GitRepository.Diff;

Type
  TAEGitStashFile = Class(TAEGitCommitBasedFile)
  strict private
    _stageddiff: TAEGitDiff;
    _stashhash: String;
    Function GetStagedDiff: TAEGitDiff;
    Function GetStatus: TArray<TAEGitFileStatus>;
  strict protected
    Function GetCommit(Const inRepository: Pgit_repository): Pgit_commit; Override;
    Function GetDiffString: String; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashHash: String; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure UpdateStatus(Const inStatus: TArray<TAEGitFileStatus>);
    Property StagedDiff: TAEGitDiff Read GetStagedDiff;
    Property Status: TArray<TAEGitFileStatus> Read GetStatus;
  End;

Implementation

Uses System.SysUtils;

Constructor TAEGitStashFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashHash: String; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath, inStatus);

  _stageddiff := TAEGitDiff.Create;

  _stashhash := inStashHash;
End;

Destructor TAEGitStashFile.Destroy;
Begin
  FreeAndNil(_stageddiff);

  inherited;
End;

Function TAEGitStashFile.GetCommit(Const inRepository: Pgit_repository): Pgit_commit;
Begin
  Result := Context.GetStashCommit(_stashhash);
End;

Function TAEGitStashFile.GetStatus: TArray<TAEGitFileStatus>;
Begin
  Result := Self.InternalStatus;
End;

Function TAEGitStashFile.GetDiffString: String;
Var
  stat: TAEGitFileStatus;
  hasnew: Boolean;
  stashcommit, parent: Pgit_commit;
  stashtree, parenttree: Pgit_tree;
  parentcount: Cardinal;
Begin
  hasnew := False;

  For stat In Self.InternalStatus Do
  Begin
    If stat In [gfsNew, gfsUntracked] Then
      hasnew := True;
  End;

  stashcommit := Context.GetStashCommit(_stashhash);
  Try
    parentcount := git_commit_parentcount(stashcommit);

    Context.DoLibGit2Call('git_commit_parentcount');

    If hasnew Then
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

Function TAEGitStashFile.GetStagedDiff: TAEGitDiff;
Var
  stashcommit, parent0, parent1: Pgit_commit;
  parentTree0, parentTree1: Pgit_tree;
  parentcount: Cardinal;
Begin
  Result := _stageddiff;

  If Not _stageddiff.AsString.IsEmpty Then
    Exit;

  stashcommit := Context.GetStashCommit(_stashhash);
  Try
    parentcount := git_commit_parentcount(stashcommit);

    Context.DoLibGit2Call('git_commit_parentcount');

    If parentcount < 2 Then
    Begin
      _stageddiff.AsString := '';

      Exit;
    End;

    Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent0, stashcommit, 0));
    Try
      Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent1, stashcommit, 1));
      Try
        Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parentTree0, parent0));
        Try
          Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parentTree1, parent1));
          Try
            _stageddiff.AsString := Self.GetPatchBetweenTrees(parentTree0, parentTree1, [Self.GitPath]);
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
  Finally
    git_commit_free(stashcommit);

    Context.DoLibGit2Call('git_commit_free');
  End;
End;

Procedure TAEGitStashFile.UpdateStatus(Const inStatus: TArray<TAEGitFileStatus>);
Begin
  Self.InternalStatus := inStatus;
End;

End.
