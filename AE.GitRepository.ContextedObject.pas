{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.ContextedObject;

Interface

Uses AE.GitRepository.Context, libgit2;

Type
  TAEGitRepositoryContextedObject = Class
  strict private
    _context: TAEGitRepositoryContext;
  strict protected
    Function GetBlobContent(Const inOid: Pgit_oid; Const inRepository: Pgit_repository): String;
    Function GetFileContentFromTree(Const inTree: Pgit_tree; Const inGitPath: String; Const inRepository: Pgit_repository): String;
    Function GetPatchBetweenTrees(Const inFromTree: Pgit_tree; Const inToTree: Pgit_tree; Const inFileNames: TArray<String>): String;
    Function GetPatchFromCommit(Const inCommit: Pgit_commit; Const inFileNames: TArray<String>; Const inRepository: Pgit_repository): String;
    Function GetPatchFromWorkTree(Const inFileNames: TArray<String>; Const inStagedPatch: Boolean): String;
    Property Context: TAEGitRepositoryContext Read _context;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); ReIntroduce; Virtual;
  End;

Implementation

Uses AE.GitRepository.TypeDef;

Function TAEGitRepositoryContextedObject.GetBlobContent(Const inOid: Pgit_oid; Const inRepository: Pgit_repository): String;
Var
  blob: Pgit_blob;
  rawcontent: Pointer;
  rawsize: git_object_size_t;
  content: UTF8String;
  a: Integer;
Begin
  Result := '';

  If Not Assigned(inOid) Or (git_oid_is_zero(inOid) <> 0) Then
    Exit;

  If Not Context.HandleLibGit2Output('git_blob_lookup', git_blob_lookup(@blob, inRepository, inOid), [geNotFound]) Then
    Exit;

  Try
    a := git_blob_is_binary(blob);

    Context.DoLibGit2Call('git_blob_is_binary');

    If a <> 0 Then
      Exit;

    rawcontent := git_blob_rawcontent(blob);

    Context.DoLibGit2Call('git_blob_rawcontent');

    rawsize := git_blob_rawsize(blob);

    Context.DoLibGit2Call('git_blob_rawsize');

    SetLength(content, NativeInt(rawsize));

    If rawsize > 0 Then
      Move(rawcontent^, PAnsiChar(content)^, NativeInt(rawsize));

    Result := String(content);
  Finally
    git_blob_free(blob);

    Context.DoLibGit2Call('git_blob_free');
  End;
End;

Function TAEGitRepositoryContextedObject.GetFileContentFromTree(Const inTree: Pgit_tree; Const inGitPath: String; Const inRepository: Pgit_repository): String;
Var
  entry: Pgit_tree_entry;
Begin
  Result := '';

  If Not Assigned(inTree) Then
    Exit;

  If Not Context.HandleLibGit2Output('git_tree_entry_bypath', git_tree_entry_bypath(@entry, inTree, PAnsiChar(UTF8String(inGitPath))), [geNotFound]) Then
    Exit;

  Try
    If git_tree_entry_type(entry) <> GIT_OBJECT_BLOB Then
    Begin
      Context.DoLibGit2Call('git_tree_entry_type');

      Exit;
    End;

    Context.DoLibGit2Call('git_tree_entry_type');

    Result := Self.GetBlobContent(git_tree_entry_id(entry), inRepository);

    Context.DoLibGit2Call('git_tree_entry_id');
  Finally
    git_tree_entry_free(entry);

    Context.DoLibGit2Call('git_tree_entry_free');
  End;
End;

Function TAEGitRepositoryContextedObject.GetPatchFromCommit(Const inCommit: Pgit_commit; Const inFileNames: TArray<String>; Const inRepository: Pgit_repository): String;
Var
  parent: Pgit_commit;
  tree, parenttree: Pgit_tree;
  parentcount: Cardinal;
  diff: Pgit_diff;
  options: git_diff_options;
  buf: git_buf;
  utffilenames: TArray<UTF8String>;
  filenames: TArray<PAnsiChar>;
  a: Integer;
Begin
  Result := '';

  If Not Assigned(inCommit) Then
    Exit;

  FillChar(buf, SizeOf(buf), 0);

  Context.HandleLibGit2Output('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

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

  Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, inCommit));
  Try
    parentcount := git_commit_parentcount(inCommit);
    Context.DoLibGit2Call('git_commit_parentcount');

    parent := nil;
    parenttree := nil;

    If parentcount > 0 Then
    Begin
      Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, inCommit, 0));
      Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
    End;

    Try
      Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, inRepository, parenttree, tree, @options));
      Try
        Context.HandleLibGit2Output('git_diff_to_buf', git_diff_to_buf(@buf, diff, GIT_DIFF_FORMAT_PATCH));
        Try
          Result := String(UTF8String(buf.ptr));
        Finally
          git_buf_dispose(@buf);

          Context.DoLibGit2Call('git_buf_dispose');
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
End;

Function TAEGitRepositoryContextedObject.GetPatchFromWorkTree(Const inFileNames: TArray<String>; Const inStagedPatch: Boolean): String;
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

  Context.HandleLibGit2Output('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

  options.flags := GIT_DIFF_INCLUDE_UNTRACKED Or GIT_DIFF_RECURSE_UNTRACKED_DIRS Or GIT_DIFF_SHOW_UNTRACKED_CONTENT;

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

  If inStagedPatch Then
  Begin
    Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@head, Context.Repository, 'HEAD'));
    Try
      Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, Pgit_commit(head)));
      Try
        Context.HandleLibGit2Output('git_diff_tree_to_index', git_diff_tree_to_index(@diff, Context.Repository, tree, nil, @options));
      Finally
        git_tree_free(tree);

        Context.DoLibGit2Call('git_tree_free');
      End;
    Finally
      git_object_free(head);

      Context.DoLibGit2Call('git_object_free');
    End;
  End
  Else
    Context.HandleLibGit2Output('git_diff_index_to_workdir', git_diff_index_to_workdir(@diff, Context.Repository, nil, @options));

  Try
    Context.HandleLibGit2Output('git_diff_to_buf', git_diff_to_buf(@buf, diff, GIT_DIFF_FORMAT_PATCH));
    Try
      Result := String(UTF8String(buf.ptr));
    Finally
      git_buf_dispose(@buf);

      Context.DoLibGit2Call('git_buf_dispose');
    End;
  Finally
    git_diff_free(diff);

    Context.DoLibGit2Call('git_diff_free');
  End;
End;

Function TAEGitRepositoryContextedObject.GetPatchBetweenTrees(Const inFromTree: Pgit_tree; Const inToTree: Pgit_tree; Const inFileNames: TArray<String>): String;
Var
  diff: Pgit_diff;
  options: git_diff_options;
  buf: git_buf;
  utffilenames: TArray<UTF8String>;
  filenames: TArray<PAnsiChar>;
  a: NativeInt;
Begin
  Result := '';

  FillChar(buf, SizeOf(buf), 0);

  Context.HandleLibGit2Output('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

  SetLength(utffilenames, Length(inFileNames));
  SetLength(filenames, Length(inFileNames));

  For a := Low(inFileNames) To High(inFileNames) Do
  Begin
    utffilenames[a] := UTF8String(inFileNames[a]);
    filenames[a] := PAnsiChar(utffilenames[a]);
  End;

  options.pathspec.count := Length(filenames);
  options.pathspec.strings := @filenames[0];

  Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.Repository, inFromTree, inToTree, @options));
  Try
    Context.HandleLibGit2Output('git_diff_to_buf', git_diff_to_buf(@buf, diff, GIT_DIFF_FORMAT_PATCH));
    Try
      Result := String(UTF8String(buf.ptr));
    Finally
      git_buf_dispose(@buf);

      Context.DoLibGit2Call('git_buf_dispose');
    End;
  Finally
    git_diff_free(diff);

    Context.DoLibGit2Call('git_diff_free');
  End;
End;

Constructor TAEGitRepositoryContextedObject.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited Create;

  _context := inContext;
End;

End.
