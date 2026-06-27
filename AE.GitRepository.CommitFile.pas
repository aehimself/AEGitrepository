{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.CommitFile;

Interface

Uses AE.GitRepository.FileObject, System.Generics.Collections, AE.GitRepository.TypeDef, AE.GitRepository.Context;

Type
  TAEGitCommitFile = Class(TAEGitRepositoryFile)
  strict private
    _commithash: String;
    Function GetStatus: TAEGitFileStatus;
  strict protected
    Function GetDiff: String; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inCommitHash, inGitPath: String; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
    Property Status: TAEGitFileStatus Read GetStatus;
  End;

  TAEGitCommitFileList = Class(TObjectDictionary<String, TAEGitCommitFile>);

Implementation

Uses libgit2, System.SysUtils;

Constructor TAEGitCommitFile.Create(Const inContext: TAEGitRepositoryContext; Const inCommitHash, inGitPath: String; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath);

  _commithash := inCommitHash;

  Self.InternalStatus := [inStatus];
End;

Function TAEGitCommitFile.GetDiff: String;
Var
  oid: git_oid;
  commit, parent: Pgit_commit;
  tree, parenttree: Pgit_tree;
  parentcount: Cardinal;
  diff: Pgit_diff;
  filecount: size_t;
  a: NativeUInt;
  delta: Pgit_diff_delta;
  patch: Pgit_patch;
  buf: git_buf;
  filename: String;
Begin
  Result := '';

  Context.ContextHandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_commithash))));

  Context.ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.ContextLibGit2Repository, @oid));
  Try
    Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
    Try
      parentcount := git_commit_parentcount(commit);
      Context.ContextDoLibGit2Call('git_commit_parentcount');

      parent := nil;
      parenttree := nil;

      If parentcount > 0 Then
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

            If filename <> Self.GitPath Then
              Continue;

            Context.ContextHandleLibGit2Output('git_patch_from_diff', git_patch_from_diff(@patch, diff, a));
            Try
              FillChar(buf, SizeOf(buf), 0);

              Context.ContextHandleLibGit2Output('git_patch_to_buf', git_patch_to_buf(@buf, patch));
              Try
                Result := String(UTF8String(buf.ptr));
              Finally
                git_buf_dispose(@buf);
                Context.ContextDoLibGit2Call('git_buf_dispose');
              End;
            Finally
              git_patch_free(patch);
              Context.ContextDoLibGit2Call('git_patch_free');
            End;

            Break;
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
End;

Function TAEGitCommitFile.GetStatus: TAEGitFileStatus;
Begin
  Result := Self.InternalStatus[0];
End;

End.