{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.SubModuleCommit;

Interface

Uses AE.GitRepository.Context, AE.GitRepository.HeadTarget, AE.GitRepository.SubModuleCommitFile, AE.GitRepository.TypeDef;

Type
  TAEGitSubmoduleCommit = Class(TAEGitHeadTarget)
  strict private
    _hash: String;
    _items: TAEGitSubmoduleFileList;
    _loaded: Boolean;
    _submodulepath: String;
    Function GetFile(Const inGitPath: String): TAEGitSubmoduleFile;
    Function GetFileNames: TArray<String>;
    Procedure LoadFiles;
  strict protected
    Procedure InternalCheckout; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inSubmodulePath, inHash: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure Clear;
    Function GetDiff(Const inFileNames: TArray<String> = nil): String;
    Property FileNames: TArray<String> Read GetFileNames;
    Property Files[Const inGitPath: String]: TAEGitSubmoduleFile Read GetFile;
    Property Hash: String Read _hash;
  End;

Implementation

Uses libgit2, System.Generics.Collections, System.SysUtils;

Constructor TAEGitSubmoduleCommit.Create(Const inContext: TAEGitRepositoryContext; Const inSubmodulePath, inHash: String);
Begin
  inherited Create(inContext);

  _hash := inHash;
  _submodulepath := inSubmodulePath;
  _items := TAEGitSubmoduleFileList.Create([doOwnsValues]);
  _loaded := False;
End;

Destructor TAEGitSubmoduleCommit.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Procedure TAEGitSubmoduleCommit.Clear;
Begin
  _items.Clear;
  _loaded := False;
End;

Procedure TAEGitSubmoduleCommit.InternalCheckout;
Var
  submodule: Pgit_submodule;
  subrepo: Pgit_repository;
  oid: git_oid;
  commit: Pgit_commit;
  tree: Pgit_tree;
  options: git_checkout_options;
Begin
  submodule := nil;
  subrepo := nil;

  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_submodulepath))));
  Try
    Context.HandleLibGit2Output('git_submodule_open', git_submodule_open(@subrepo, submodule));
    Try
      Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

      Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, subrepo, @oid));
      Try
        Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
        Try
          Context.HandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

          options.checkout_strategy := GIT_CHECKOUT_SAFE;

          Context.HandleLibGit2Output('git_checkout_tree', git_checkout_tree(subrepo, Pgit_object(tree), @options));

          Context.HandleLibGit2Output('git_repository_set_head_detached', git_repository_set_head_detached(subrepo, @oid));
        Finally
          git_tree_free(tree);

          Context.DoLibGit2Call('git_tree_free');
        End;
      Finally
        git_commit_free(commit);

        Context.DoLibGit2Call('git_commit_free');
      End;
    Finally
      git_repository_free(subrepo);

      Context.DoLibGit2Call('git_repository_free');
    End;
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;
End;

Function TAEGitSubmoduleCommit.GetDiff(Const inFileNames: TArray<String> = nil): String;
Var
  submodule: Pgit_submodule;
  subrepo: Pgit_repository;
  oid: git_oid;
  commit: Pgit_commit;
Begin
  Result := '';

  submodule := nil;
  subrepo := nil;
  commit := nil;

  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_submodulepath))));
  Try
    Context.HandleLibGit2Output('git_submodule_open', git_submodule_open(@subrepo, submodule));
    Try
      Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

      Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, subrepo, @oid));
      Try
        Result := Self.GetPatchFromCommit(commit, inFileNames, subrepo);
      Finally
        git_commit_free(commit);

        Context.DoLibGit2Call('git_commit_free');
      End;
    Finally
      git_repository_free(subrepo);

      Context.DoLibGit2Call('git_repository_free');
    End;
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;
End;

Procedure TAEGitSubmoduleCommit.LoadFiles;
Var
  submodule: Pgit_submodule;
  subrepo: Pgit_repository;
  oid: git_oid;
  commit, parent: Pgit_commit;
  tree, parenttree: Pgit_tree;
  parentcount: Cardinal;
  diff: Pgit_diff;
  filecount: size_t;
  a: NativeUInt;
  delta: Pgit_diff_delta;
  filename: String;
  filestatus: TAEGitFileStatus;
Begin
  _loaded := False;
  _items.Clear;

  submodule := nil;
  subrepo := nil;
  commit := nil;
  tree := nil;

  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_submodulepath))));
  Try
    Context.HandleLibGit2Output('git_submodule_open', git_submodule_open(@subrepo, submodule));
    Try
      Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

      Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, subrepo, @oid));
      Try
        Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
        Try
          parentcount := git_commit_parentcount(commit);

          Context.DoLibGit2Call('git_commit_parentcount');

          If parentcount > 0 Then
          Begin
            Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));

            Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
          End
          Else
          Begin
            parent := nil;
            parenttree := nil;
          End;
          Try
            Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, subrepo, parenttree, tree, nil));
            Try
              filecount := git_diff_num_deltas(diff);

              Context.DoLibGit2Call('git_diff_num_deltas');

              If filecount > 0 Then
                For a := 0 To filecount - 1 Do
                Begin
                  delta := git_diff_get_delta(diff, a);

                  Context.DoLibGit2Call('git_diff_get_delta');

                  If Length(delta.new_file.path) <> 0 Then
                    filename := String(UTF8String(delta.new_file.path))
                  Else
                    filename := String(UTF8String(delta.old_file.path));

                  Case delta.status Of
                    GIT_DELTA_UNMODIFIED:
                      filestatus := gfsCurrent;
                    GIT_DELTA_ADDED:
                      filestatus := gfsNew;
                    GIT_DELTA_DELETED:
                      filestatus := gfsDeleted;
                    GIT_DELTA_MODIFIED:
                      filestatus := gfsModified;
                    GIT_DELTA_RENAMED:
                      filestatus := gfsRenamed;
                    GIT_DELTA_COPIED:
                      filestatus := gfsCopied;
                    GIT_DELTA_IGNORED:
                      filestatus := gfsIgnored;
                    GIT_DELTA_UNTRACKED:
                      filestatus := gfsUntracked;
                    GIT_DELTA_TYPECHANGE:
                      filestatus := gfsTypeChange;
                    GIT_DELTA_UNREADABLE:
                      filestatus := gfsUnreadable;
                    Else
                      filestatus := gfsConflicted;
                  End;

                  _items.Add(filename, TAEGitSubmoduleFile.Create(Context, _submodulepath, _hash, filename, filestatus));
                End;
            Finally
              git_diff_free(diff);

              Context.DoLibGit2Call('git_diff_free');
            End;
          Finally
            If Assigned(parenttree) Then
            Begin
              git_tree_free(parenttree);

              Context.DoLibGit2Call('git_tree_free');
            End;

            If Assigned(parent) Then
            Begin
              git_commit_free(parent);

              Context.DoLibGit2Call('git_commit_free');
            End;
          End;
        Finally
          git_tree_free(tree);

          Context.DoLibGit2Call('git_tree_free');
        End;
      Finally
        git_commit_free(commit);

        Context.DoLibGit2Call('git_commit_free');
      End;
    Finally
      git_repository_free(subrepo);

      Context.DoLibGit2Call('git_repository_free');
    End;
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;

  _loaded := True;
End;

Function TAEGitSubmoduleCommit.GetFile(Const inGitPath: String): TAEGitSubmoduleFile;
Begin
  If Not _loaded Then
    Self.LoadFiles;

  Result := _items[inGitPath];
End;

Function TAEGitSubmoduleCommit.GetFileNames: TArray<String>;
Begin
  If Not _loaded Then
    Self.LoadFiles;

  Result := _items.Keys.ToArray;

  TArray.Sort<String>(Result);
End;

End.
