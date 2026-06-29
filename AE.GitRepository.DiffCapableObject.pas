{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.DiffCapableObject;

Interface

Uses AE.GitRepository.ContextedObject, libgit2;

Type
  TAEGitRepositoryDiffCapableObject = Class(TAEGitRepositoryContextedObject)
  strict protected
    Function GetPatchFromCommit(Const inCommit: Pgit_commit; Const inFileNames: TArray<String>): String;
    Function GetPatchFromWorkTree(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): String;
  End;

Implementation

uses AE.GitRepository.Context;

Function TAEGitRepositoryDiffCapableObject.GetPatchFromCommit(Const inCommit: Pgit_commit; Const inFileNames: TArray<String>): String;
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

  Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, inCommit));
  Try
    parentcount := git_commit_parentcount(inCommit);
    Context.ContextDoLibGit2Call('git_commit_parentcount');

    parent := nil;
    parenttree := nil;

    If parentcount > 0 Then
    Begin
      Context.ContextHandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, inCommit, 0));
      Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
    End;

    Try
      Context.ContextHandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.ContextLibGit2Repository, parenttree, tree, @options));
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
End;

Function TAEGitRepositoryDiffCapableObject.GetPatchFromWorkTree(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): String;
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

End.
