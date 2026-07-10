{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.WorkTree;

Interface

Uses AE.GitRepository.RefreshableObject, System.Generics.Collections, AE.GitRepository.TypeDef, AE.GitRepository.WorkTreeFile, AE.GitRepository.Context, AE.GitRepository.ChangedFileList;

Type
  TAEGitWorkTree = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _items: TObjectDictionary<String, TAEGitWorkTreeFile>;
    _loaded: Boolean;
    Procedure GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
    Function GetFileNames: TArray<String>;
    Function GetFile(Const inGitPath: String): TAEGitWorkTreeFile;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); Override;
    Destructor Destroy; Override;
    Procedure ApplyPatch(Const inPatch: String);
    Procedure Commit(Const inCommitMessage: String);
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
End;

Destructor TAEGitWorkTree.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Procedure TAEGitWorkTree.InternalClear;
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
  Context.HandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.Repository));
  Try
    Context.HandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeoid, index));
  Finally
    git_index_free(index);

    Context.DoLibGit2Call('git_index_free');
  End;

  Context.HandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, Context.Repository, @treeoid));
  Try
    parentcount := 0;
    parents := nil;
    parentcommit := nil;
    Try
      If Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@parentoid, Context.Repository, 'HEAD'), False) And
         Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@parentcommit, Context.Repository, @parentoid), False) Then
      Begin
        parentsarray[0] := parentcommit;
        parents := @parentsarray[0];
        parentcount := 1;
      End;

      Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
      Try
        Context.HandleLibGit2Output('git_commit_create',
          git_commit_create(
            @commitoid,
            Context.Repository,
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

        Context.DoLibGit2Call('git_signature_free');
      End;
    Finally
      If Assigned(parentcommit) Then
      Begin
        git_commit_free(parentcommit);

        Context.DoLibGit2Call('git_commit_free');
      End;
    End;
  Finally
    git_tree_free(tree);

    Context.DoLibGit2Call('git_tree_free');
  End;
End;

Procedure TAEGitWorkTree.GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
Var
  statuslist: Pgit_status_list;
  options: git_status_options;
  count, b: Integer;
  status: Pgit_status_entry;
Begin
  Context.HandleLibGit2Output('git_status_options_init', git_status_options_init(@options, GIT_STATUS_OPTIONS_VERSION));

  options.flags := GIT_STATUS_OPT_INCLUDE_UNTRACKED Or GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS Or GIT_STATUS_OPT_EXCLUDE_SUBMODULES;

  Context.HandleLibGit2Output('git_status_list_new', git_status_list_new(@statuslist, Context.Repository, @options));
  Try
    count := git_status_list_entrycount(statuslist);

    Context.DoLibGit2Call('git_status_list_entrycount');

    For b := 0 To count - 1 Do
    Begin
      status := git_status_byindex(statuslist, b);

      Context.DoLibGit2Call('git_status_byindex');

      If status.status = GIT_STATUS_IGNORED Then
        Continue;

      If (status.status And GIT_STATUS_INDEX_NEW) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedNew);

      If (status.status And GIT_STATUS_INDEX_MODIFIED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedModified);

      If (status.status And GIT_STATUS_INDEX_DELETED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.old_file.path)), gfsStagedDeleted);

      If (status.status And GIT_STATUS_INDEX_RENAMED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedRenamed);

      If (status.status And GIT_STATUS_INDEX_TYPECHANGE) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedTypeChange);

      If (status.status And GIT_STATUS_WT_NEW) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsNew);

      If (status.status And GIT_STATUS_WT_MODIFIED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsModified);

      If (status.status And GIT_STATUS_WT_DELETED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.old_file.path)), gfsDeleted);

      If (status.status And GIT_STATUS_WT_RENAMED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsRenamed);

      If (status.status And GIT_STATUS_WT_TYPECHANGE) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsTypeChange);

      If (status.status And GIT_STATUS_WT_UNREADABLE) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsUnreadable);

      If (status.status And GIT_STATUS_CONFLICTED) <> 0 Then
        If Assigned(status.index_to_workdir) Then
          inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsConflicted)
        Else
          inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsConflicted);

      If status.status = GIT_STATUS_CURRENT Then
        If Assigned(status.index_to_workdir) Then
          inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsCurrent)
        Else
          inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsCurrent);
    End;
  Finally
    git_status_list_free(statuslist);

    Context.DoLibGit2Call('git_status_list_free');
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
  Context.HandleLibGit2Output('git_apply_options_init', git_apply_options_init(@options, GIT_APPLY_OPTIONS_VERSION));

  utf8patch := UTF8String(inPatch);
  buf := PAnsiChar(utf8patch);

  Context.HandleLibGit2Output('git_diff_from_buffer', git_diff_from_buffer(@diff, buf, Length(buf)));
  Try
    Context.HandleLibGit2Output('git_apply', git_apply(Context.Repository, diff, GIT_APPLY_LOCATION_WORKDIR, @options));
  Finally
    git_diff_free(diff);

    Context.DoLibGit2Call('git_diff_free');
  End;
End;

Function TAEGitWorkTree.GetPatch(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): String;
Begin
  Result := Self.GetPatchFromWorkTree(inFileNames, inStagedOnly);
End;

Procedure TAEGitWorkTree.InternalRefresh;
Var
  changedFiles: TAEGitChangedFileList;
  remove: TList<String>;
  pair: TPair<String, TArray<TAEGitFileStatus>>;
  wtf: TAEGitWorkTreeFile;
  key: String;
Begin
  _loaded := False;

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
