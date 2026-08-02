{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Stash;

Interface

Uses AE.GitRepository.RefreshableObject, AE.GitRepository.Context, System.Generics.Collections, AE.GitRepository.StashFile;

Type
  TAEGitStash = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _index: Integer;
    _items: TObjectDictionary<String, TAEGitStashFile>;
    _message: String;
    Function GetFileNames: TArray<String>;
    Function GetFile(Const inGitPath: String): TAEGitStashFile;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inIndex: Integer; Const inMessage: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure Drop;
    Procedure Pop;
    Function GetPatch(Const inFileNames: TArray<String> = []): String;
    Property FileNames: TArray<String> Read GetFileNames;
    Property Files[Const inGitPath: String]: TAEGitStashFile Read GetFile;
    Property Index: Integer Read _index;
    Property Message: String Read _message Write _message;
  End;

  TAEGitStashList = Class(TList<String>);

  TAEGitStashes = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _items: TObjectDictionary<Integer, TAEGitStash>;
    Function GetCount: Integer;
    Function GetItem(Const inStashIndex: Integer): TAEGitStash;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); Override;
    Destructor Destroy; Override;
    Procedure Push(Const inStashMessage: String);
    Property Count: Integer Read GetCount;
    Property Items[Const inStashIndex: Integer]: TAEGitStash Read GetItem; Default;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.TypeDef, AE.GitRepository.Exception, AE.GitRepository.CommitFile, AE.GitRepository.ChangedFileList, AE.GitRepository.Libgit2Callbacks;

//
// TAEGitStash
//

Procedure TAEGitStash.InternalClear;
Begin
  _items.Clear;
End;

Constructor TAEGitStash.Create(Const inContext: TAEGitRepositoryContext; Const inIndex: Integer; Const inMessage: String);
Begin
  inherited Create(inContext);

  _items := TObjectDictionary<String, TAEGitStashFile>.Create([doOwnsValues]);

  _index := inIndex;
  _message := inMessage;
End;

Destructor TAEGitStash.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Procedure TAEGitStash.Drop;
Begin
  Context.HandleLibGit2Output('git_stash_drop', git_stash_drop(Context.Repository, size_t(_index)));

  Context.RefreshStashes;
End;

Function TAEGitStash.GetFile(Const inGitPath: String): TAEGitStashFile;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items[inGitPath];
End;

Function TAEGitStash.GetFileNames: TArray<String>;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items.Keys.ToArray;

  TArray.Sort<String>(Result);
End;

Function TAEGitStash.GetPatch(Const inFileNames: TArray<String> = []): String;
var
  commit: Pgit_commit;
begin
  Result := '';

  commit := Context.GetStashCommit(_index);
  Try
    Result := Self.GetPatchFromCommit(commit, inFileNames, Context.Repository);
  Finally
    git_commit_free(commit);

    Context.DoLibGit2Call('git_commit_free');
  End;
End;

Procedure TAEGitStash.Pop;
Var
  options: git_stash_apply_options;
Begin
  Context.HandleLibGit2Output('git_stash_apply_options_init', git_stash_apply_options_init(@options, GIT_STASH_APPLY_OPTIONS_VERSION));

  options.flags := 0;

  Context.HandleLibGit2Output('git_stash_pop', git_stash_pop(Context.Repository, size_t(_index), @options));

  Context.SolveConflicts;

  Context.RefreshWorkTree;

  Context.RefreshStashes;
End;

Procedure TAEGitStash.InternalRefresh;
Var
  changedfiles: TAEGitChangedFileList;
  stashcommit, parent0, parent1, parent2: Pgit_commit;
  stashtree, parenttree0, parenttree1, parenttree2: Pgit_tree;
  parentcount: Cardinal;
  diff: Pgit_diff;
  stashfile: TAEGitStashFile;
  keystoremove: TList<String>;
  pair: TPair<String, TArray<TAEGitFileStatus>>;
  key: String;

  Procedure ProcessDiff(Const inDiff: Pgit_diff; Const inIsStaged: Boolean);
  Var
    filecount: size_t;
    a: NativeUInt;
    delta: Pgit_diff_delta;
    filename: String;
    filestatus: TAEGitFileStatus;
  Begin
    filecount := git_diff_num_deltas(inDiff);

    Context.DoLibGit2Call('git_diff_num_deltas');

    If filecount = 0 Then
      Exit;

    For a := 0 To filecount - 1 Do
    Begin
      delta := git_diff_get_delta(inDiff, a);

      Context.DoLibGit2Call('git_diff_get_delta');

      If Length(delta.new_file.path) <> 0 Then
        filename := String(UTF8String(delta.new_file.path))
      Else
        filename := String(UTF8String(delta.old_file.path));

      If inIsStaged Then
        Case delta.status Of
          GIT_DELTA_UNMODIFIED:
            filestatus := gfsCurrent;
          GIT_DELTA_ADDED:
            filestatus := gfsStagedNew;
          GIT_DELTA_DELETED:
            filestatus := gfsStagedDeleted;
          GIT_DELTA_MODIFIED:
            filestatus := gfsStagedModified;
          GIT_DELTA_RENAMED:
            filestatus := gfsStagedRenamed;
          GIT_DELTA_TYPECHANGE:
            filestatus := gfsStagedTypeChange;
          Else
            filestatus := gfsConflicted;
        End
      Else
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

      changedfiles.AddFileStatus(filename, filestatus);
    End;
  End;
Begin
  Self.Loaded := False;

  changedfiles := TAEGitChangedFileList.Create;
  Try
    keystoremove := TList<String>.Create;
    Try
      keystoremove.AddRange(_items.Keys);

      stashcommit := Context.GetStashCommit(_index);
      Try
        parentcount := git_commit_parentcount(stashcommit);

        Context.DoLibGit2Call('git_commit_parentcount');

        If parentcount >= 2 Then
        Begin
          Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent0, stashcommit, 0));
          Try
            Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent1, stashcommit, 1));
            Try
              Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree0, parent0));
              Try
                Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree1, parent1));
                Try
                  Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@stashtree, stashcommit));
                  Try
                    // Staged: HEAD -> index
                    Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.Repository, parenttree0, parenttree1, nil));
                    Try
                      ProcessDiff(diff, True);
                    Finally
                      git_diff_free(diff);

                      Context.DoLibGit2Call('git_diff_free');
                    End;

                    // Unstaged: index -> stash WD
                    Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.Repository, parenttree1, stashTree, nil));
                    Try
                      ProcessDiff(diff, False);
                    Finally
                      git_diff_free(diff);

                      Context.DoLibGit2Call('git_diff_free');
                    End;
                  Finally
                    git_tree_free(stashtree);

                    Context.DoLibGit2Call('git_tree_free');
                  End;
                Finally
                  git_tree_free(parenttree1);

                  Context.DoLibGit2Call('git_tree_free');
                End;
              Finally
                git_tree_free(parenttree0);

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

          // Untracked: nil -> parent[2]
          If parentcount >= 3 Then
          Begin
            Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent2, stashcommit, 2));
            Try
              Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree2, parent2));
              Try
                Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.Repository, nil, parenttree2, nil));
                Try
                  ProcessDiff(diff, False);
                Finally
                  git_diff_free(diff);

                  Context.DoLibGit2Call('git_diff_free');
                End;
              Finally
                git_tree_free(parenttree2);

                Context.DoLibGit2Call('git_tree_free');
              End;
            Finally
              git_commit_free(parent2);

              Context.DoLibGit2Call('git_commit_free');
            End;
          End;
        End
        Else
        Begin
          // Fallback: diff against single parent or empty tree
          parent0 := nil;
          parenttree0 := nil;

          Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@stashtree, stashcommit));
          Try
            If parentcount = 1 Then
            Begin
              Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent0, stashcommit, 0));
              Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree0, parent0));
            End;

            Try
              Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.Repository, parenttree0, stashtree, nil));
              Try
                ProcessDiff(diff, False);
              Finally
                git_diff_free(diff);

                Context.DoLibGit2Call('git_diff_free');
              End;
            Finally
              If Assigned(parenttree0) Then
              Begin
                git_tree_free(parenttree0);

                Context.DoLibGit2Call('git_tree_free');
              End;

              If Assigned(parent0) Then
              Begin
                git_commit_free(parent0);

                Context.DoLibGit2Call('git_commit_free');
              End;
            End;
          Finally
            git_tree_free(stashtree);

            Context.DoLibGit2Call('git_tree_free');
          End;
        End;
      Finally
        git_commit_free(stashcommit);

        Context.DoLibGit2Call('git_commit_free');
      End;

      For pair In changedfiles Do
      Begin
        If Not _items.TryGetValue(pair.Key, stashfile) Then
        Begin
          stashfile := TAEGitStashFile.Create(Context, pair.Key, _index, pair.Value[0]);
          _items.Add(pair.Key, stashfile);
        End;

        stashfile.UpdateStatus(pair.Value);

        keystoremove.Remove(pair.Key);
      End;

      For key In keystoremove Do
        _items.Remove(key);
    Finally
      FreeAndNil(keystoremove);
    End;
  Finally
    FreeAndNil(changedfiles);
  End;

  Self.Loaded := True;
End;

//
// TAEGitStashes
//

Procedure TAEGitStashes.InternalClear;
Begin
  _items.Clear;
End;

Constructor TAEGitStashes.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited;

  _items := TObjectDictionary<Integer, TAEGitStash>.Create([doOwnsValues]);
End;

Destructor TAEGitStashes.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Function TAEGitStashes.GetItem(Const inStashIndex: Integer): TAEGitStash;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items[inStashIndex];
End;

Function TAEGitStashes.GetCount: Integer;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items.Count;
End;

Procedure TAEGitStashes.Push(Const inStashMessage: String);
Var
  signature: Pgit_signature;
  oid: git_oid;
Begin
  Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
  Try
    Context.HandleLibGit2Output('git_stash_save', git_stash_save(@oid, Context.Repository, signature, PAnsiChar(UTF8String(inStashMessage)), GIT_STASH_INCLUDE_UNTRACKED));
  Finally
    git_signature_free(signature);

    Context.DoLibGit2Call('git_signature_free');
  End;

  Context.RefreshWorkTree;

  Self.Refresh(False);
End;

Procedure TAEGitStashes.InternalRefresh;
Var
  list: TAEGitStashList;
  keystoremove: TList<Integer>;
  idx: Integer;
  stash: TAEGitStash;
Begin
  Self.Loaded := False;

  list := TAEGitStashList.Create;
  Try
    keystoremove := TList<Integer>.Create;
    Try
      Context.HandleLibGit2Output('git_stash_foreach', git_stash_foreach(Context.Repository, @LibGit2StashListCallback, @list));

      keystoremove.AddRange(_items.Keys);

      For idx := 0 To list.Count - 1 Do
      Begin
        If Not _items.TryGetValue(idx, stash) Then
        Begin
          stash := TAEGitStash.Create(Context, idx, list[idx]);

          _items.Add(idx, stash);
        End
        Else
          stash.Message := list[idx];

        keystoremove.Remove(idx);
      End;

      For idx In keystoremove Do
        _items.Remove(idx);
    Finally
      FreeAndNil(keystoremove);
    End;
  Finally
    FreeAndNil(list);
  End;

  Self.Loaded := True;
End;

End.
