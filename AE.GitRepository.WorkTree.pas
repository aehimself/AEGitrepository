{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.WorkTree;

Interface

Uses AE.GitRepository.RefreshableObject, System.Generics.Collections, AE.GitRepository.TypeDef, AE.GitRepository.WorkTreeFile,
     AE.GitRepository.Context, AE.GitRepository.Diff;

Type
  TAEGitWorkTree = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _changedfiles: TObjectList<TAEGitWorkTreeFile>;
    _patch: TAEGitDiff;
    Procedure GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
    Function GetFileNames: TArray<String>;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); Override;
    Destructor Destroy; Override;
    Procedure ApplyPatch(Const inPatch: String);
    Procedure Commit(Const inCommitMessage: String);
    Procedure RevertFiles(Const inFileNames: TArray<String>);
    Procedure StageFiles(Const inFileNames: TArray<String>);
    Procedure UnstageFiles(Const inFileNames: TArray<String>);
    Function Files(Const inGitPath: String = ''): TArray<TAEGitWorkTreeFile>;
    Function GetPatch(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): TAEGitDiff;
    Property FileNames: TArray<String> Read GetFileNames;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.Exception;

Constructor TAEGitWorkTree.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited;

  _changedfiles := TObjectList<TAEGitWorkTreeFile>.Create;
  _patch := TAEGitDiff.Create;
End;

Destructor TAEGitWorkTree.Destroy;
Begin
  FreeAndNil(_changedfiles);
  FreeAndNil(_patch);

  inherited;
End;

Procedure TAEGitWorkTree.InternalClear;
Begin
  inherited;

  _changedfiles.Clear;
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
      If Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@parentoid, Context.Repository, 'HEAD'), [geNotFound, geUnbornBranch]) And
        Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@parentcommit, Context.Repository, @parentoid), [geNotFound]) Then
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

  Self.Refresh(False);

  Context.RefreshCurrentBranchCommits;
End;

Procedure TAEGitWorkTree.GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
Begin
  Context.CollectChangedFiles(inChangedFiles, True);
End;

Function TAEGitWorkTree.GetFileNames: TArray<String>;
Var
  names: TList<String>;
  wtfile: TAEGitWorkTreeFile;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  names := TList<String>.Create;
  Try
    For wtfile In _changedfiles Do
      If Not names.Contains(wtfile.GitPath) Then
        names.Add(wtfile.GitPath);

    Result := names.ToArray;
  Finally
    FreeAndNil(names);
  End;

  TArray.Sort<String>(Result);
End;

Function TAEGitWorkTree.Files(Const inGitPath: String = ''): TArray<TAEGitWorkTreeFile>;
Var
  results: TList<TAEGitWorkTreeFile>;
  wtfile: TAEGitWorkTreeFile;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  results := TList<TAEGitWorkTreeFile>.Create;
  Try
    For wtfile In _changedfiles Do
      If inGitPath.IsEmpty Or (wtfile.GitPath = inGitPath) Then
        results.Add(wtfile);

    Result := results.ToArray;
  Finally
    FreeAndNil(results);
  End;
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

  Context.RefreshWorkTree;
End;

Function TAEGitWorkTree.GetPatch(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): TAEGitDiff;
Begin
  _patch.AsString := Self.GetPatchFromWorkTree(inFileNames, inStagedOnly);

  Result := _patch;
End;

Procedure TAEGitWorkTree.InternalRefresh;
Var
  changedfiles: TAEGitChangedFileList;
  toremove: TList<TAEGitWorkTreeFile>;
  pair: TPair<String, TAEGitFileStatus>;
  existing: TAEGitWorkTreeFile;
  found: Boolean;
Begin
  Self.Loaded := False;

  changedfiles := TAEGitChangedFileList.Create;
  Try
    toremove := TList<TAEGitWorkTreeFile>.Create;
    Try
      GetChangedFiles(changedfiles);

      toremove.AddRange(_changedfiles);

      For pair In changedfiles Do
      Begin
        found := False;

        For existing In toremove Do
          If (existing.GitPath = pair.Key) And (existing.Status = pair.Value) Then
          Begin
            toremove.Remove(existing);

            found := True;

            Break;
          End;

        If Not found Then
          _changedfiles.Add(TAEGitWorkTreeFile.Create(Context, pair.Key, pair.Value));
      End;

      For existing In toremove Do
        _changedfiles.Remove(existing);
    Finally
      FreeAndNil(toremove);
    End;
  Finally
    FreeAndNil(changedfiles);
  End;

  Self.Loaded := True;
End;

Procedure TAEGitWorkTree.RevertFiles(Const inFileNames: TArray<String>);
Var
  options: git_checkout_options;
  filenames: TArray<PAnsiChar>;
  utffilenames: TArray<UTF8String>;
  a: NativeInt;
Begin
  SetLength(filenames, Length(inFileNames));
  SetLength(utffilenames, Length(inFileNames));

  For a := Low(inFileNames) To High(inFileNames) Do
  Begin
    utffilenames[a] := UTF8String(inFileNames[a]);
    filenames[a] := PAnsiChar(utffilenames[a]);
  End;

  Context.HandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_FORCE Or GIT_CHECKOUT_REMOVE_UNTRACKED Or GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH;
  options.paths.count := Length(inFileNames);
  options.paths.strings := @filenames[0];

  Context.HandleLibGit2Output('git_checkout_tree', git_checkout_tree(Context.Repository, nil, @options));

  Self.Refresh(False);

  Context.RefreshCurrentBranchCommits;
End;

Procedure TAEGitWorkTree.StageFiles(Const inFileNames: TArray<String>);
Var
  index: Pgit_index;
  filename: String;
  wtfile: TAEGitWorkTreeFile;
  deleted: Boolean;
Begin
  Context.HandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.Repository));
  Try
    For filename In inFileNames Do
    Begin
      deleted := False;

      For wtfile In Self.Files(filename) Do
        If wtfile.Status = gfsDeleted Then
        Begin
          deleted := True;

          Break;
        End;

      If deleted Then
        Context.HandleLibGit2Output('git_index_remove_bypath', git_index_remove_bypath(index, PAnsiChar(UTF8String(filename))))
      Else
        Context.HandleLibGit2Output('git_index_add_bypath', git_index_add_bypath(index, PAnsiChar(UTF8String(filename))));
    End;

    Context.HandleLibGit2Output('git_index_write', git_index_write(index));

    Self.Refresh(False);
  Finally
    git_index_free(index);

    Context.DoLibGit2Call('git_index_free');
  End;
End;

Procedure TAEGitWorkTree.UnstageFiles(Const inFileNames: TArray<String>);
Var
  pathspec: git_strarray;
  target: Pgit_object;
  filenames: TArray<PAnsiChar>;
  utffilenames: TArray<UTF8String>;
  a: NativeInt;
Begin
  SetLength(filenames, Length(inFileNames));
  SetLength(utffilenames, Length(inFileNames));

  For a := Low(inFileNames) To High(inFileNames) Do
  Begin
    utffilenames[a] := UTF8String(inFileNames[a]);
    filenames[a] := PAnsiChar(utffilenames[a]);
  End;

  Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@target, Context.Repository, 'HEAD'));
  Try
    pathspec.count := Length(inFileNames);;
    pathspec.strings := @filenames[0];

    Context.HandleLibGit2Output('git_reset_default', git_reset_default(Context.Repository, target, @pathspec));

    Context.RefreshWorkTree;
  Finally
    git_object_free(target);

    Context.DoLibGit2Call('git_object_free');
  End;
End;

End.
