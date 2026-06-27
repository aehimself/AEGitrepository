{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.WorkTree;

Interface

Uses AE.GitRepository.ContextedObject, System.Generics.Collections, AE.GitRepository.TypeDef, AE.GitRepository.WorkTreeFile, AE.GitRepository.Context;

Type
  TAEGitChangedFileList = Class(TDictionary<String, TArray<TAEGitFileStatus>>);

  TAEGitWorkTree = Class(TAEGitRepositoryContextedObject)
  strict private
    _items: TObjectDictionary<String, TAEGitWorkTreeFile>;
    _loaded: Boolean;
    Procedure GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
    Function GetFileNames: TArray<String>;
    Function GetFile(Const inGitPath: String): TAEGitWorkTreeFile;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); Override;
    Destructor Destroy; Override;
    Procedure ApplyPatch(Const inPatch: String);
    Procedure Clear;
    Procedure Commit(Const inCommitMessage: String);
    Procedure Refresh;
    Function GetPatch(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): String;
    Property FileNames: TArray<String> Read GetFileNames;
    Property Files[Const inGitPath: String]: TAEGitWorkTreeFile Read GetFile;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.Exception;

Constructor TAEGitWorkTree.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited;

  _items := TObjectDictionary<String, TAEGitWorkTreeFile>.Create([doOwnsValues]);

  _loaded := False;
End;

Destructor TAEGitWorkTree.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Procedure TAEGitWorkTree.Clear;
Begin
  _items.Clear;

  _loaded := False;
End;

Procedure TAEGitWorkTree.Commit(Const inCommitMessage: String);
Var
  index: Pgit_index;
  tree: Pgit_tree;
  treeoid, parentoid, commitoid: git_oid;
  parentcommit: Pgit_commit;
  parents: PPgit_commit;
  parentsarray: Array[0..0] Of Pgit_commit;
  signature: Pgit_signature;
  parentcount: Integer;
Begin
  Context.ContextHandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.ContextLibGit2Repository));
  Try
    Context.ContextHandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeoid, index));
  Finally
    git_index_free(index);

    Context.ContextDoLibGit2Call('git_index_free');
  End;

  Context.ContextHandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, Context.ContextLibGit2Repository, @treeoid));
  Try
    parentcount := 0;
    parents := nil;
    parentcommit := nil;
    Try
      If Context.ContextHandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@parentoid, Context.ContextLibGit2Repository, 'HEAD'), False) And
         Context.ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@parentcommit, Context.ContextLibGit2Repository, @parentoid), False) Then
      Begin
        parentsarray[0] := parentcommit;
        parents := @parentsarray[0];
        parentcount := 1;
      End;

      Context.ContextHandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.ContextGetSettings.FullName)), PAnsiChar(UTF8String(Context.ContextGetSettings.EMailAddress))));
      Try
        Context.ContextHandleLibGit2Output('git_commit_create',
          git_commit_create(
            @commitoid,
            Context.ContextLibGit2Repository,
            'HEAD',
            signature,
            signature,
            nil,
            PAnsiChar(UTF8String(inCommitMessage)),
            tree,
            parentcount,
            parents
          )
        );
      Finally
        git_signature_free(signature);

        Context.ContextDoLibGit2Call('git_signature_free');
      End;
    Finally
      If Assigned(parentcommit) Then
      Begin
        git_commit_free(parentcommit);

        Context.ContextDoLibGit2Call('git_commit_free');
      End;
    End;
  Finally
    git_tree_free(tree);

    Context.ContextDoLibGit2Call('git_tree_free');
  End;
End;

Procedure TAEGitWorkTree.GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
Var
  statuslist: Pgit_status_list;
  options: git_status_options;
  count, b: Integer;
  status: Pgit_status_entry;

  Procedure AddFileStatus(Const inFileName: String; Const inStatus: TAEGitFileStatus);
  Var
    statuses: TArray<TAEGitFileStatus>;
    len: Integer;
  Begin
    If inChangedFiles.TryGetValue(inFileName, statuses) Then
    Begin
      len := Length(statuses);
      SetLength(statuses, len + 1);
      statuses[len] := inStatus;

      inChangedFiles[inFileName] := statuses;
    End
    Else
      inChangedFiles.Add(inFileName, [inStatus]);
  End;
Begin
  Context.ContextHandleLibGit2Output('git_status_options_init', git_status_options_init(@options, GIT_STATUS_OPTIONS_VERSION));

  options.flags := GIT_STATUS_OPT_INCLUDE_UNTRACKED Or GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS Or GIT_STATUS_OPT_EXCLUDE_SUBMODULES;

  Context.ContextHandleLibGit2Output('git_status_list_new', git_status_list_new(@statuslist, Context.ContextLibGit2Repository, @options));
  Try
    count := git_status_list_entrycount(statuslist);

    Context.ContextDoLibGit2Call('git_status_list_entrycount');

    For b := 0 To count - 1 Do
    Begin
      status := git_status_byindex(statuslist, b);

      Context.ContextDoLibGit2Call('git_status_byindex');

      If status.status = GIT_STATUS_IGNORED Then
        Continue;

      If (status.status And GIT_STATUS_INDEX_NEW) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedNew);

      If (status.status And GIT_STATUS_INDEX_MODIFIED) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedModified);

      If (status.status And GIT_STATUS_INDEX_DELETED) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.old_file.path)), gfsStagedDeleted);

      If (status.status And GIT_STATUS_INDEX_RENAMED) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedRenamed);

      If (status.status And GIT_STATUS_INDEX_TYPECHANGE) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedTypeChange);

      If (status.status And GIT_STATUS_WT_NEW) <> 0 Then
        AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsNew);

      If (status.status And GIT_STATUS_WT_MODIFIED) <> 0 Then
        AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsModified);

      If (status.status And GIT_STATUS_WT_DELETED) <> 0 Then
        AddFileStatus(String(UTF8String(status.index_to_workdir.old_file.path)), gfsDeleted);

      If (status.status And GIT_STATUS_WT_RENAMED) <> 0 Then
        AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsRenamed);

      If (status.status And GIT_STATUS_WT_TYPECHANGE) <> 0 Then
        AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsTypeChange);

      If (status.status And GIT_STATUS_WT_UNREADABLE) <> 0 Then
        AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsUnreadable);

      If (status.status And GIT_STATUS_CONFLICTED) <> 0 Then
        If Assigned(status.index_to_workdir) Then
          AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsConflicted)
        Else
          AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsConflicted);

      If status.status = GIT_STATUS_CURRENT Then
        If Assigned(status.index_to_workdir) Then
          AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsCurrent)
        Else
          AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsCurrent);
    End;
  Finally
    git_status_list_free(statuslist);

    Context.ContextDoLibGit2Call('git_status_list_free');
  End;
End;

Function TAEGitWorkTree.GetFileNames: TArray<String>;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items.Keys.ToArray;

  TArray.Sort<String>(Result);
End;

Function TAEGitWorkTree.GetFile(Const inGitPath: String): TAEGitWorkTreeFile;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items[inGitPath];
End;

Procedure TAEGitWorkTree.ApplyPatch(Const inPatch: String);
Var
  diff: Pgit_diff;
  options: git_apply_options;
  buf: PAnsiChar;
  utf8patch: UTF8String;
Begin
  Context.ContextHandleLibGit2Output('git_apply_options_init', git_apply_options_init(@options, GIT_APPLY_OPTIONS_VERSION));

  utf8patch := UTF8String(inPatch);
  buf := PAnsiChar(utf8patch);

  Context.ContextHandleLibGit2Output('git_diff_from_buffer', git_diff_from_buffer(@diff, buf, Length(buf)));
  Try
    Context.ContextHandleLibGit2Output('git_apply', git_apply(Context.ContextLibGit2Repository, diff, GIT_APPLY_LOCATION_WORKDIR, @options));
  Finally
    git_diff_free(diff);

    Context.ContextDoLibGit2Call('git_diff_free');
  End;
End;

Function TAEGitWorkTree.GetPatch(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): String;
Var
  diff: Pgit_diff;
  buf: git_buf;
  head: Pgit_object;
  tree: Pgit_tree;
  options: git_diff_options;
  utffilenames: TArray<UTF8String>;
  filenames: TArray<PAnsiChar>;
  a: Integer;
Begin
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

  If inStagedOnly Then
  Begin
    Context.ContextHandleLibGit2Output('git_revparse_single', git_revparse_single(@head, Context.ContextLibGit2Repository, 'HEAD'));
    Try
      Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, Pgit_commit(head)));
      Try
        Context.ContextHandleLibGit2Output('git_diff_tree_to_index', git_diff_tree_to_index(@diff, Context.ContextLibGit2Repository, tree, nil, @options));
      Finally
        git_tree_free(tree);

        Context.ContextDoLibGit2Call('git_tree_free');
      End;
    Finally
      git_object_free(head);

      Context.ContextDoLibGit2Call('git_object_free');
    End;
  End
  Else
    Context.ContextHandleLibGit2Output('git_diff_index_to_workdir', git_diff_index_to_workdir(@diff, Context.ContextLibGit2Repository, nil, @options));

  Try
    Context.ContextHandleLibGit2Output('git_diff_to_buf', git_diff_to_buf(@buf, diff, GIT_DIFF_FORMAT_PATCH));
    Try
      Result := String(UTF8String(buf.ptr));
    Finally
      git_buf_dispose(@buf);

      Context.ContextDoLibGit2Call('git_buf_dispose');
    End;
  Finally
    git_diff_free(diff);

    Context.ContextDoLibGit2Call('git_diff_free');
  End;
End;

Procedure TAEGitWorkTree.Refresh;
Var
  changedFiles: TAEGitChangedFileList;
  remove: TList<String>;
  pair: TPair<String, TArray<TAEGitFileStatus>>;
  wtf: TAEGitWorkTreeFile;
  key: String;
Begin
  changedFiles := TAEGitChangedFileList.Create;
  Try
    remove := TList<String>.Create;
    Try
      GetChangedFiles(changedFiles);

      For key In _items.Keys Do
        remove.Add(key);

      For pair In changedFiles Do
      Begin
        If Not _items.TryGetValue(pair.Key, wtf) Then
        Begin
          wtf := TAEGitWorkTreeFile.Create(Context, pair.Key);

          _items.Add(pair.Key, wtf);
        End;

        wtf.Status := pair.Value;
        remove.Remove(pair.Key);
      End;

      For key In remove Do
        _items.Remove(key);
    Finally
      FreeAndNil(remove);
    End;
  Finally
    FreeAndNil(changedFiles);
  End;

  _loaded := True;
End;

End.
