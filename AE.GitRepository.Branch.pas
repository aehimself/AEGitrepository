{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Branch;

Interface

Uses AE.GitRepository.HeadTarget, AE.GitRepository.Context, AE.GitRepository.BranchCommits;

Type
  TAEGitBranch = Class(TAEGitHeadTarget)
  strict private
    _commits: TAEGitBranchCommits;
    _incomingcommits: Integer;
    _name: String;
    _outgoingcommits: Integer;
    Procedure UpdateCommitCount(Const inRemote: String);
  strict protected
    Procedure InternalCheckout; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String); ReIntroduce;
    Destructor Destroy; Override;
    Procedure Delete;
    Procedure Fetch(inRemote: String = ''; Const inDownloadTags: Boolean = False);
    Procedure Push(inRemote: String = '');
    Procedure Rebase(inOnBranch: String = '');
    Procedure Rebase_Abort;
    Procedure Rebase_Continue;
    Procedure Revert_Last_Commit(Const inCommitCount: Integer);
    Function RebaseInProgress: Boolean;
    Property Commits: TAEGitBranchCommits Read _commits;
    Property IncomingCommits: Integer Read _incomingcommits;
    Property Name: String Read _name;
    Property OutgoingCommits: Integer Read _outgoingcommits;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.Exception, AE.GitRepository.TypeDef;

//
// libgit2 callbacks
//

Function LibGit2AuthCallback(out_: PPgit_credential; url, username_from_url: PAnsiChar; allowed_types: Cardinal; payload: Pointer): Integer; Cdecl;
Var
  types: TAEGitAuthTypes;
Begin
  types := [];

  If (allowed_types And GIT_CREDENTIAL_USERPASS_PLAINTEXT_) <> 0 Then
    Include(types, gaUserPassPlainText);

  If (allowed_types And GIT_CREDENTIAL_SSH_KEY_) <> 0 Then
    Include(types, gaSshKey);

  If (allowed_types And GIT_CREDENTIAL_SSH_CUSTOM_) <> 0 Then
    Include(types, gaSshCustom);

  If (allowed_types And GIT_CREDENTIAL_DEFAULT_) <> 0 Then
    Include(types, gaDefault);

  If (allowed_types And GIT_CREDENTIAL_SSH_INTERACTIVE_) <> 0 Then
    Include(types, gaSshInteractive);

  If (allowed_types And GIT_CREDENTIAL_USERNAME_) <> 0 Then
    Include(types, gaUsername);

  If (allowed_types And GIT_CREDENTIAL_SSH_MEMORY) <> 0 Then
    Include(types, gaSshMemory);

  Result := TAEGitRepositoryContext(payload).ContextAuthCallback(out_, url, username_from_url, types);
End;

//
// TAEGitBranch
//

Constructor TAEGitBranch.Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String);
Begin
  inherited Create(inContext);

  _commits := TAEGitBranchCommits.Create(Context, inBranchName);

  _incomingcommits := 0;
  _name := inBranchName;
  _outgoingcommits := 0;
End;

Destructor TAEGitBranch.Destroy;
Begin
  FreeAndNil(_commits);

  inherited;
End;

Procedure TAEGitBranch.InternalCheckout;
Var
  options: git_checkout_options;
  obj: Pgit_object;
  localbranch, remotebranch: Pgit_reference;
  commit: Pgit_annotated_commit;
  remote: String;
  branchname: String;
Begin
  branchname := _name;

  Context.ContextSplitBranchName(branchname, remote);

  Context.ContextHandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_SAFE;

  If Not Context.ContextHandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/heads/' + branchname))), False) Then
  Begin
    Context.ContextHandleLibGit2Output('git_reference_lookup', git_reference_lookup(@remotebranch, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/remotes/' + remote + '/' + branchname))));
    Try
      Context.ContextHandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@commit, Context.ContextLibGit2Repository, remotebranch));
      Try
        Context.ContextHandleLibGit2Output('git_branch_create_from_annotated', git_branch_create_from_annotated(@localbranch, Context.ContextLibGit2Repository, PAnsiChar(UTF8String(branchname)), commit, 0));
        Try
          Context.ContextHandleLibGit2Output('git_branch_set_upstream', git_branch_set_upstream(localbranch, PAnsiChar(UTF8String(remote + '/' + branchname))));
        Finally
          git_reference_free(localbranch);

          Context.ContextDoLibGit2Call('git_reference_free');
        End;
      Finally
        git_annotated_commit_free(commit);

        Context.ContextDoLibGit2Call('git_annotated_commit_free');
      End;
    Finally
      git_reference_free(remotebranch);

      Context.ContextDoLibGit2Call('git_reference_free');
    End;

    Context.ContextHandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/heads/' + branchname))));
  End;

  Try
    Context.ContextHandleLibGit2Output('git_checkout_tree', git_checkout_tree(Context.ContextLibGit2Repository, obj, @options));
  Finally
    git_object_free(obj);

    Context.ContextDoLibGit2Call('git_object_free');
  End;

  Context.ContextHandleLibGit2Output('git_repository_set_head', git_repository_set_head(Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/heads/' + branchname))));

  Context.ContextUpdateCurrentBranch;
End;

Procedure TAEGitBranch.Delete;
Var
  branch: Pgit_reference;
Begin
  Context.ContextHandleLibGit2Output('git_branch_lookup', git_branch_lookup(@branch, Context.ContextLibGit2Repository, PAnsiChar(UTF8String(_name)), GIT_BRANCH_LOCAL));
  Try
    Context.ContextHandleLibGit2Output('git_branch_delete', git_branch_delete(branch));
  Finally
    git_reference_free(branch);

    Context.ContextDoLibGit2Call('git_reference_free');
  End;

  Context.ContextRefreshBranches;
End;

Procedure TAEGitBranch.UpdateCommitCount(Const inRemote: String);
Var
  localoid: git_oid;
  ref, headref, remoteref: Pgit_reference;
  remotename: PAnsiChar;
  remoteoid, walkoid: git_oid;
  ahead, behind: size_t;
  walk: Pgit_revwalk;
  refiterator: Pgit_reference_iterator;
  a: Integer;
Begin
  Context.ContextHandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@localoid, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/heads/' + _name))));

  Context.ContextHandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.ContextLibGit2Repository));
  Try
    If Context.ContextHandleLibGit2Output('git_branch_upstream', git_branch_upstream(@remoteref, headref), False) Then
    Try
      remotename := git_reference_name(remoteref);

      Context.ContextDoLibGit2Call('git_reference_name');

      If Context.ContextHandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@remoteoid, Context.ContextLibGit2Repository, remotename), False) Then
      Begin
        Context.ContextHandleLibGit2Output('git_graph_ahead_behind', git_graph_ahead_behind(@ahead, @behind, Context.ContextLibGit2Repository, @localoid, @remoteoid));

        _incomingcommits := behind;
        _outgoingcommits := ahead;
      End
    Finally
      git_reference_free(remoteref);

      Context.ContextDoLibGit2Call('git_reference_free');
    End
    Else
    Begin
      _incomingcommits := -1;
      _outgoingcommits := 0;

      Context.ContextHandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, Context.ContextLibGit2Repository));
      Try
        Context.ContextHandleLibGit2Output('git_revwalk_push', git_revwalk_push(walk, @localoid));

        Context.ContextHandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@refiterator, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/*'))));
        Try
          While Context.ContextHandleLibGit2Output('git_reference_next', git_reference_next(@ref, refiterator), False) Do
          Begin
            Try
              a := git_reference_type(ref);

              Context.ContextDoLibGit2Call('git_reference_type');

              If a = GIT_REFERENCE_DIRECT Then
              Begin
                remoteoid := git_reference_target(ref)^;

                Context.ContextDoLibGit2Call('git_reference_target');

                Context.ContextHandleLibGit2Output('git_revwalk_hide', git_revwalk_hide(walk, @remoteoid));
              End;
            Finally
              git_reference_free(ref);

              Context.ContextDoLibGit2Call('git_reference_free');
            End;
          End;
        Finally
          git_reference_iterator_free(refiterator);

          Context.ContextDoLibGit2Call('git_reference_iterator_free');
        End;

        While Context.ContextHandleLibGit2Output('git_revwalk_next', git_revwalk_next(@walkoid, walk), False) Do
          Inc(_outgoingcommits);
      Finally
        git_revwalk_free(walk);

        Context.ContextDoLibGit2Call('git_revwalk_free');
      End;
    End;
  Finally
    git_reference_free(headref);

    Context.ContextDoLibGit2Call('git_reference_free');
  End;
End;

Procedure TAEGitBranch.Fetch(inRemote: String = ''; Const inDownloadTags: Boolean = False);
Var
  remote: Pgit_remote;
  options: git_fetch_options;
  specs, fetchspecs: git_strarray;
  refs: TArray<PAnsiChar>;
  p: PPAnsiChar;
  a: Integer;
  hastagrefs: Boolean;
  utf8refs: TArray<UTF8String>;
Begin
  If inRemote.IsEmpty Then
    inRemote := Context.ContextGetDefaultRemoteName;

  Context.ContextHandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, Context.ContextLibGit2Repository, PAnsiChar(UTF8String(inRemote))));
  Try
    Context.ContextHandleLibGit2Output('git_fetch_options_init', git_fetch_options_init(@options, GIT_FETCH_OPTIONS_VERSION));

    options.callbacks.payload := Context;
    options.callbacks.credentials := LibGit2AuthCallback;

    If inDownloadTags Then
      options.download_tags := GIT_REMOTE_DOWNLOAD_TAGS_ALL;

    Context.ContextHandleLibGit2Output('git_remote_get_fetch_refspecs', git_remote_get_fetch_refspecs(@specs, remote));
    Try
      hastagrefs := False;

      If inDownloadTags Then
      Begin
        p := specs.strings;

        For a := 0 To specs.Count - 1 Do
        Begin
          hastagrefs := String(UTF8String(p^)).Contains('refs/tags/');

          If hastagrefs Then
            Break;

          Inc(p);
        End;
      End;

      SetLength(utf8refs, Integer(specs.Count) + Ord(inDownloadTags And Not hastagrefs));
      SetLength(refs, Length(utf8refs));

      p := specs.strings;

      For a := 0 To specs.Count - 1 Do
      Begin
        utf8refs[a] := UTF8String(p^);
        refs[a] := PAnsiChar(utf8refs[a]);

        Inc(p);
      End;

      If inDownloadTags And Not hastagrefs Then
      Begin
        utf8refs[High(utf8refs)] := UTF8String('+refs/tags/*:refs/tags/*');
        refs[High(refs)] := PAnsiChar(utf8refs[High(utf8refs)]);
      End;
    Finally
      git_strarray_dispose(@specs);

      Context.ContextDoLibGit2Call('git_strarray_dispose');
    End;

    fetchspecs.Count := Length(refs);

    If fetchspecs.Count > 0 Then
      fetchspecs.strings := @refs[0]
    Else
      fetchspecs.strings := nil;

    Context.ContextHandleLibGit2Output('git_remote_fetch', git_remote_fetch(remote, @fetchspecs, @options, nil));
  Finally
    git_remote_free(remote);

    Context.ContextDoLibGit2Call('git_remote_free');
  End;

  UpdateCommitCount(inRemote);
End;

Procedure TAEGitBranch.Push(inRemote: String = '');
Var
  options: git_push_options;
  remote: Pgit_remote;
  callbacks: git_remote_callbacks;
  utf8ref: UTF8String;
  ref: PAnsiChar;
  refarray: git_strarray;
  localref, remoteref: Pgit_reference;
Begin
  If inRemote.IsEmpty Then
    inRemote := Context.ContextGetDefaultRemoteName;

  Context.ContextHandleLibGit2Output('git_push_options_init', git_push_options_init(@options, GIT_PUSH_OPTIONS_VERSION));

  options.callbacks.payload := Context;
  options.callbacks.credentials := LibGit2AuthCallback;

  Context.ContextHandleLibGit2Output('git_remote_init_callbacks', git_remote_init_callbacks(@callbacks, GIT_REMOTE_CALLBACKS_VERSION));

  callbacks.payload := Context;
  callbacks.credentials := LibGit2AuthCallback;

  utf8ref := UTF8String(Format('+refs/heads/%s:refs/heads/%s', [_name, _name]));
  ref := PAnsiChar(utf8ref);
  refarray.strings := @ref;
  refarray.Count := 1;

  Context.ContextHandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, Context.ContextLibGit2Repository, PAnsiChar(UTF8String(inRemote))));
  Try
    Context.ContextHandleLibGit2Output('git_remote_connect', git_remote_connect(remote, GIT_DIRECTION_PUSH, @callbacks, nil, nil));
    Try
      Context.ContextHandleLibGit2Output('git_remote_push', git_remote_push(remote, @refarray, @options));

      Context.ContextHandleLibGit2Output('git_reference_lookup', git_reference_lookup(@localref, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/heads/' + _name))));
      Try
        If Context.ContextHandleLibGit2Output('git_branch_upstream', git_branch_upstream(@remoteref, localref), False) Then
        Begin
          git_reference_free(remoteref);

          Context.ContextDoLibGit2Call('git_reference_free');
        End
        Else
          Context.ContextHandleLibGit2Output('git_branch_set_upstream', git_branch_set_upstream(localref, PAnsiChar(UTF8String(inRemote + '/' + _name))));
      Finally
        git_reference_free(localref);

        Context.ContextDoLibGit2Call('git_reference_free');
      End;
    Finally
      Context.ContextHandleLibGit2Output('git_remote_disconnect', git_remote_disconnect(remote));
    End;
  Finally
    git_remote_free(remote);

    Context.ContextDoLibGit2Call('git_remote_free');
  End;
End;

Procedure TAEGitBranch.Rebase(inOnBranch: String = '');
Var
  branch, onto: Pgit_annotated_commit;
  head, ref: Pgit_reference;
  options: git_rebase_options;
  rebase: Pgit_rebase;
  rebaseop: Pgit_rebase_operation;
  remote: String;
  signature: Pgit_signature;
  oid: git_oid;
Begin
  Try
    remote := '';

    Context.ContextSplitBranchName(inOnBranch, remote);

    If inOnBranch.IsEmpty Then
      inOnBranch := remote + '/' + _name;

    Context.ContextHandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.ContextGetSettings.FullName)), PAnsiChar(UTF8String(Context.ContextGetSettings.EMailAddress))));
    Try
      Context.ContextHandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

      Context.ContextHandleLibGit2Output('git_repository_head', git_repository_head(@head, Context.ContextLibGit2Repository));
      Try
        Context.ContextHandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@branch, Context.ContextLibGit2Repository, head));
        Try
          Context.ContextHandleLibGit2Output('git_branch_lookup', git_branch_lookup(@ref, Context.ContextLibGit2Repository, PAnsiChar(UTF8String(inOnBranch)), GIT_BRANCH_ALL));
          Try
            Context.ContextHandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@onto, Context.ContextLibGit2Repository, ref));
            Try
              Context.ContextHandleLibGit2Output('git_rebase_init', git_rebase_init(@rebase, Context.ContextLibGit2Repository, branch, nil, onto, @options));
              Try
                Repeat
                  If Not Context.ContextHandleLibGit2Output('git_rebase_next', git_rebase_next(@rebaseop, rebase), False) Then
                    Break;

                  If Not Context.ContextSolveConflicts Then
                    Raise EAEGitException.Create(geError, 'git_index_has_conflicts', ecRebase, 'Commit has conflicts, rebase aborted!');

                  Context.ContextHandleLibGit2Output('git_rebase_commit', git_rebase_commit(@oid, rebase, nil, signature, nil, nil));
                Until False;

                Context.ContextHandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
              Finally
                git_rebase_free(rebase);

                Context.ContextDoLibGit2Call('git_rebase_free');
              End;
            Finally
              git_annotated_commit_free(onto);

              Context.ContextDoLibGit2Call('git_annotated_commit_free');
            End;
          Finally
            git_reference_free(ref);

            Context.ContextDoLibGit2Call('git_reference_free');
          End;
        Finally
          git_annotated_commit_free(branch);

          Context.ContextDoLibGit2Call('git_annotated_commit_free');
        End;
      Finally
        git_reference_free(head);

        Context.ContextDoLibGit2Call('git_reference_free');
      End;
    Finally
      git_signature_free(signature);

      Context.ContextDoLibGit2Call('git_signature_free');
    End;
  Finally
    Context.ContextRefreshWorkTree;
  End;
End;

Procedure TAEGitBranch.Revert_Last_Commit(Const inCommitCount: Integer);
Var
  target: Pgit_object;
Begin
  Context.ContextHandleLibGit2Output('git_revparse_single', git_revparse_single(@target, Context.ContextLibGit2Repository, PAnsiChar(AnsiString('HEAD~' + inCommitCount.ToString))));
  Try
    Context.ContextHandleLibGit2Output('git_reset', git_reset(Context.ContextLibGit2Repository, target, GIT_RESET_SOFT, nil));
  Finally
    git_object_free(target);

    Context.ContextDoLibGit2Call('git_object_free');
  End;

  Context.ContextRefreshWorkTree;
End;

Procedure TAEGitBranch.Rebase_Abort;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  Try
    Context.ContextHandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    Context.ContextHandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.ContextGetSettings.FullName)), PAnsiChar(UTF8String(Context.ContextGetSettings.EMailAddress))));
    Try
      Context.ContextHandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.ContextLibGit2Repository, @options));
      Try
        Context.ContextHandleLibGit2Output('git_rebase_abort', git_rebase_abort(rebase));

        Context.ContextHandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
      Finally
        git_rebase_free(rebase);

        Context.ContextDoLibGit2Call('git_rebase_free');
      End;
    Finally
      git_signature_free(signature);

      Context.ContextDoLibGit2Call('git_signature_free');
    End;
  Finally
    Context.ContextRefreshWorkTree;
  End;
End;

Procedure TAEGitBranch.Rebase_Continue;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
  rebaseop: Pgit_rebase_operation;
  oid: git_oid;
Begin
  Try
    Context.ContextHandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    Context.ContextHandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.ContextLibGit2Repository, @options));
    Try
      Context.ContextHandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.ContextGetSettings.FullName)), PAnsiChar(UTF8String(Context.ContextGetSettings.EMailAddress))));
      Try
        Repeat
          If Not Context.ContextHandleLibGit2Output('git_rebase_next', git_rebase_next(@rebaseop, rebase), False) Then
            Break;

          If Not Context.ContextSolveConflicts Then
            Raise EAEGitException.Create(geError, 'git_index_has_conflicts', ecRebase, 'Commit has conflicts, rebase aborted!');

          Context.ContextHandleLibGit2Output('git_rebase_commit', git_rebase_commit(@oid, rebase, nil, signature, nil, nil));
        Until False;

        Context.ContextHandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
      Finally
        git_signature_free(signature);

        Context.ContextDoLibGit2Call('git_signature_free');
      End;
    Finally
      git_rebase_free(rebase);

      Context.ContextDoLibGit2Call('git_rebase_free');
    End;
  Finally
    Context.ContextRefreshWorkTree;
  End;
End;

Function TAEGitBranch.RebaseInProgress: Boolean;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
Begin
  Context.ContextHandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  Result := Context.ContextHandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.ContextLibGit2Repository, @options), False);

  If Result Then
  Begin
    git_rebase_free(rebase);

    Context.ContextDoLibGit2Call('git_rebase_free');
  End;
End;

End.
