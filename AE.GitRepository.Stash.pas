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
  TAEGitStashRefreshEvent = Procedure Of Object;

  TAEGitStash = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _index: Integer;
    _items: TObjectDictionary<String, TAEGitStashFile>;
    _loaded: Boolean;
    _message: String;
    _onrefresh: TAEGitStashRefreshEvent;
    Function GetFileNames: TArray<String>;
    Function GetFile(Const inGitPath: String): TAEGitStashFile;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inIndex: Integer; Const inMessage: String; Const inOnRefresh: TAEGitStashRefreshEvent = nil); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure Drop;
    Procedure Pop;
    Function GetPatch(Const inFileNames: TArray<String>): String;
    Property FileNames: TArray<String> Read GetFileNames;
    Property Files[Const inGitPath: String]: TAEGitStashFile Read GetFile;
    Property Index: Integer Read _index;
    Property Message: String Read _message Write _message;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.TypeDef, AE.GitRepository.Exception, AE.GitRepository.CommitFile;

Procedure TAEGitStash.InternalClear;
Begin
  _items.Clear;

  _loaded := false;
End;

Constructor TAEGitStash.Create(Const inContext: TAEGitRepositoryContext; Const inIndex: Integer; Const inMessage: String; Const inOnRefresh: TAEGitStashRefreshEvent = nil);
Begin
  inherited Create(inContext);

  _items := TObjectDictionary<String, TAEGitStashFile>.Create([doOwnsValues]);

  _index := inIndex;
  _message := inMessage;
  _onrefresh := inOnRefresh;
End;

Destructor TAEGitStash.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Procedure TAEGitStash.Drop;
Begin
  Context.HandleLibGit2Output('git_stash_drop', git_stash_drop(Context.Repository, size_t(_index)));

  If Assigned(_onrefresh) Then
    _onrefresh;
End;

Function TAEGitStash.GetFile(Const inGitPath: String): TAEGitStashFile;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items[inGitPath];
End;

Function TAEGitStash.GetFileNames: TArray<String>;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items.Keys.ToArray;

  TArray.Sort<String>(Result);
End;

Function TAEGitStash.GetPatch(Const inFileNames: TArray<String>): String;
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

  If Assigned(_onrefresh) Then
    _onrefresh;
End;

Procedure TAEGitStash.InternalRefresh;
Var
  commit, parent: Pgit_commit;
  tree, parenttree: Pgit_tree;
  count: Cardinal;
  diff: Pgit_diff;
  filecount: size_t;
  a: NativeUInt;
  delta: Pgit_diff_delta;
  filename: String;
  filestatus: TAEGitFileStatus;
  stashfile: TAEGitStashFile;
  keystoremove: TList<String>;
Begin
  _loaded := False;

  keystoremove := TList<String>.Create;
  Try
    keystoremove.AddRange(_items.Keys);

    commit := Context.GetStashCommit(_index);
    Try
      Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
      Try
        count := git_commit_parentcount(commit);

        Context.DoLibGit2Call('git_commit_parentcount');

        parent := nil;
        parenttree := nil;

        If count > 0 Then
        Begin
          Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));

          Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
        End;

        Try
          Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.Repository, parenttree, tree, nil));
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

                If Not _items.TryGetValue(filename, stashfile) Then
                  _items.Add(filename, TAEGitStashFile.Create(Context, filename, _index, filestatus))
                Else If stashfile.Status <> filestatus Then
                  stashfile.UpdateStatus(filestatus);

                keystoremove.Remove(filename);
              End;

            For filename In keystoremove Do
              _items.Remove(filename);
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
    FreeAndNil(keystoremove);
  End;

  _loaded := True;
End;

End.
