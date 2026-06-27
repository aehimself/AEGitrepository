{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Stash;

Interface

Uses AE.GitRepository.ContextedObject, AE.GitRepository.Context, System.Generics.Collections, AE.GitRepository.StashFile;

Type
  TAEGitStashRefreshEvent = Procedure Of Object;

  TAEGitStash = Class(TAEGitRepositoryContextedObject)
  strict private
    _index: Integer;
    _items: TObjectDictionary<String, TAEGitStashFile>;
    _loaded: Boolean;
    _message: String;
    _onrefresh: TAEGitStashRefreshEvent;
    Function GetFileNames: TArray<String>;
    Function GetFile(Const inGitPath: String): TAEGitStashFile;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inIndex: Integer; Const inMessage: String; Const inOnRefresh: TAEGitStashRefreshEvent = nil); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure Clear;
    Procedure Drop;
    Procedure Pop;
    Procedure Refresh;
    Function GetPatch(Const inFileNames: TArray<String>): String;
    Property FileNames: TArray<String> Read GetFileNames;
    Property Files[Const inGitPath: String]: TAEGitStashFile Read GetFile;
    Property Index: Integer Read _index;
    Property Message: String Read _message Write _message;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.TypeDef, AE.GitRepository.Exception, AE.GitRepository.CommitFile;

Procedure TAEGitStash.Clear;
Begin
  _items.Clear;

  _loaded := false;
End;

Constructor TAEGitStash.Create(Const inContext: TAEGitRepositoryContext; Const inIndex: Integer; Const inMessage: String; Const inOnRefresh: TAEGitStashRefreshEvent = nil);
Begin
  inherited Create(inContext);

  _items := TObjectDictionary<String, TAEGitStashFile>.Create([doOwnsValues]);

  _index := inIndex;
  _loaded := False;
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
  Context.ContextHandleLibGit2Output('git_stash_drop', git_stash_drop(Context.ContextLibGit2Repository, size_t(_index)));

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
  commit, parent: Pgit_commit;
  tree, parenttree: Pgit_tree;
  diff: Pgit_diff;
  options: git_diff_options;
  buf: git_buf;
  utffilenames: TArray<UTF8String>;
  filenames: TArray<PAnsiChar>;
  a: NativeInt;
begin
  Result := '';

  commit := Context.ContextGetStashCommit(_index);
  Try
    FillChar(buf, SizeOf(buf), 0);

    Context.ContextHandleLibGit2Output('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

    SetLength(utffilenames, Length(inFileNames));
    SetLength(filenames, Length(inFileNames));

    For a := Low(inFileNames) To High(inFileNames) Do
    Begin
      utffilenames[a] := UTF8String(inFileNames[a]);
      filenames[a] := PAnsiChar(utffilenames[a]);
    End;

    If Length(filenames) > 0 Then
    Begin
      options.pathspec.count := Length(filenames);
      options.pathspec.strings := @filenames[0];
    End;

    Context.ContextHandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));
    Try
      Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
      Try
        Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
        Try
          Context.ContextHandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.ContextLibGit2Repository, parenttree, tree, @options));
          Try
            Context.ContextHandleLibGit2Output('git_diff_to_buf', git_diff_to_buf(@buf, diff, GIT_DIFF_FORMAT_PATCH));
            Try
              Result := String(UTF8String(buf.ptr));
            Finally
              git_buf_dispose(@buf);

              COntext.ContextDoLibGit2Call('git_buf_dispose');
            End;
          Finally
            git_diff_free(diff);

            Context.ContextDoLibGit2Call('git_diff_free');
          End;
        Finally
          git_tree_free(ParentTree);

          Context.ContextDoLibGit2Call('git_tree_free');
        End;
      Finally
        git_tree_free(tree);

        Context.ContextDoLibGit2Call('git_tree_free');
      End;
    Finally
      git_commit_free(parent);

      Context.ContextDoLibGit2Call('git_commit_free');
    End;
  Finally
    git_commit_free(commit);

    Context.ContextDoLibGit2Call('git_commit_free');
  End;
End;

Procedure TAEGitStash.Pop;
Var
  options: git_stash_apply_options;
Begin
  Context.ContextHandleLibGit2Output('git_stash_apply_options_init', git_stash_apply_options_init(@options, GIT_STASH_APPLY_OPTIONS_VERSION));
  options.flags := 0;

  Context.ContextHandleLibGit2Output('git_stash_pop', git_stash_pop(Context.ContextLibGit2Repository, size_t(_index), @options));

  Context.ContextSolveConflicts;

  Context.ContextRefreshWorkTree;

  If Assigned(_onrefresh) Then
    _onrefresh;
End;

Procedure TAEGitStash.Refresh;
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
Begin
  Self.Clear;

  commit := Context.ContextGetStashCommit(_index);
  Try
    Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
    Try
      count := git_commit_parentcount(commit);

      Context.ContextDoLibGit2Call('git_commit_parentcount');

      parent := nil;
      parenttree := nil;

      If count > 0 Then
      Begin
        Context.ContextHandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));
        Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
      End;

      Try
        Context.ContextHandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.ContextLibGit2Repository, parenttree, tree, nil));
        Try
          filecount := git_diff_num_deltas(diff);

          Context.ContextDoLibGit2Call('git_diff_num_deltas');

          For a := 0 To filecount - 1 Do
          Begin
            delta := git_diff_get_delta(diff, a);

            Context.ContextDoLibGit2Call('git_diff_get_delta');

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

            _items.Add(filename, TAEGitStashFile.Create(Context, filename, _index, filestatus));
          End;
        Finally
          git_diff_free(diff);

          Context.ContextDoLibGit2Call('git_diff_free');
        End;
      Finally
        If Assigned(parenttree) Then
        Begin
          git_tree_free(parenttree);

          Context.ContextDoLibGit2Call('git_tree_free');
        End;

        If Assigned(parent) Then
        Begin
          git_commit_free(parent);

          Context.ContextDoLibGit2Call('git_commit_free');
        End;
      End;
    Finally
      git_tree_free(tree);

      Context.ContextDoLibGit2Call('git_tree_free');
    End;
  Finally
    git_commit_free(commit);

    Context.ContextDoLibGit2Call('git_commit_free');
  End;

  _loaded := True;
End;

End.
