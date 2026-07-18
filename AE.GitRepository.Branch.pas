{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Branch;

Interface

Uses AE.GitRepository.HeadTarget, AE.GitRepository.Context, AE.GitRepository.BranchCommits, AE.GitRepository.Submodules;

Type
  TAEGitBranch = Class(TAEGitHeadTarget)
  strict private
    _commits: TAEGitBranchCommits;
    _incomingcommits: Integer;
    _name: String;
    _outgoingcommits: Integer;
    _submodules: TAEGitSubmodules;
    Procedure UpdateCommitCount(Const inRemote: String);
  strict protected
    Procedure InternalCheckout; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String); ReIntroduce;
    Destructor Destroy; Override;
    Procedure AbortMerge;
    Procedure AbortRebase;
    Procedure ContinueMerge(inMergeCommitMessage: String = '');
    Procedure ContinueRebase;
    Procedure Delete;
    Procedure Fetch(inRemote: String = ''; Const inDownloadTags: Boolean = False);
    Procedure Merge(Const inMergeFromBranch: String; inMergeCommitMessage: String = '');
    Procedure Push(inRemote: String = '');
    Procedure Rebase(inOnBranch: String = '');
    Procedure Revert_Last_Commit(Const inCommitCount: Integer);
    Function MergeInProgress: Boolean;
    Function RebaseInProgress: Boolean;
    Property Commits: TAEGitBranchCommits Read _commits;
    Property IncomingCommits: Integer Read _incomingcommits;
    Property Name: String Read _name;
    Property OutgoingCommits: Integer Read _outgoingcommits;
    Property Submodules: TAEGitSubmodules Read _submodules;
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

  Result := TAEGitRepositoryContext(payload).AuthCallback(out_, url, username_from_url, types);
End;

//
// TAEGitBranch
//

Procedure TAEGitBranch.AbortMerge;
Var
  head: Pgit_object;
Begin
  If Not Self.MergeInProgress Then
    Exit;

  Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@head, Context.Repository, 'HEAD'));
  Try
    Context.HandleLibGit2Output('git_reset', git_reset(Context.Repository, head, GIT_RESET_HARD, nil));

    Context.HandleLibGit2Output('git_repository_state_cleanup', git_repository_state_cleanup(Context.Repository))
  Finally
    git_object_free(Head);
  End;
End;

Constructor TAEGitBranch.Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String);
Begin
  inherited Create(inContext);

  _commits := TAEGitBranchCommits.Create(Context, inBranchName);
  _submodules := TAEGitSubmodules.Create(Context);

  _incomingcommits := 0;
  _name := inBranchName;
  _outgoingcommits := 0;
End;

Destructor TAEGitBranch.Destroy;
Begin
  FreeAndNil(_submodules);
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

  Context.SplitBranchName(branchname, remote);

  Context.HandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_SAFE;

  If Not Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, Context.Repository, PAnsiChar(UTF8String('refs/heads/' + branchname))), False) Then
  Begin
    Context.HandleLibGit2Output('git_reference_lookup', git_reference_lookup(@remotebranch, Context.Repository, PAnsiChar(UTF8String('refs/remotes/' + remote + '/' + branchname))));
    Try
      Context.HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@commit, Context.Repository, remotebranch));
      Try
        Context.HandleLibGit2Output('git_branch_create_from_annotated', git_branch_create_from_annotated(@localbranch, Context.Repository, PAnsiChar(UTF8String(branchname)), commit, 0));
        Try
          Context.HandleLibGit2Output('git_branch_set_upstream', git_branch_set_upstream(localbranch, PAnsiChar(UTF8String(remote + '/' + branchname))));
        Finally
          git_reference_free(localbranch);

          Context.DoLibGit2Call('git_reference_free');
        End;
      Finally
        git_annotated_commit_free(commit);

        Context.DoLibGit2Call('git_annotated_commit_free');
      End;
    Finally
      git_reference_free(remotebranch);

      Context.DoLibGit2Call('git_reference_free');
    End;

    Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, Context.Repository, PAnsiChar(UTF8String('refs/heads/' + branchname))));
  End;

  Try
    Context.HandleLibGit2Output('git_checkout_tree', git_checkout_tree(Context.Repository, obj, @options));
  Finally
    git_object_free(obj);

    Context.DoLibGit2Call('git_object_free');
  End;

  Context.HandleLibGit2Output('git_repository_set_head', git_repository_set_head(Context.Repository, PAnsiChar(UTF8String('refs/heads/' + branchname))));

  Context.UpdateCurrentBranch;
End;

Procedure TAEGitBranch.Merge(Const inMergeFromBranch: String; inMergeCommitMessage: String = '');
Var
  checkoutoptions: git_checkout_options;
  headref, branchref, updatedref: Pgit_reference;
  theirhead: Pgit_annotated_commit;
  targetcommit, headcommit, theircommit: Pgit_commit;
  theirheads: Array[0..0] Of Pgit_annotated_commit;
  analysis: git_merge_analysis_t;
  preference: git_merge_preference_t;
  oid: Pgit_oid;
  index: Pgit_index;
  treeoid, commitoid: git_oid;
  tree: Pgit_tree;
  signature: Pgit_signature;
  parentcommits: Array[0..1] Of Pgit_commit;
Begin
  If inMergeCommitMessage.IsEmpty Then
    inMergeCommitMessage := 'Merge branch "' + inMergeFromBranch + '"';

  git_checkout_options_init(@checkoutoptions, GIT_CHECKOUT_OPTIONS_VERSION);

  checkoutoptions.checkout_strategy := GIT_CHECKOUT_SAFE;

  Context.HandleLibGit2Output('', git_repository_head(@headref, Context.Repository));
  Try
    Context.HandleLibGit2Output('', git_branch_lookup(@branchref, Context.Repository, PAnsiChar(UTF8String(inMergeFromBranch)), GIT_BRANCH_LOCAL));
    Try
      If Context.HandleLibGit2Output('git_reference_cmp', git_reference_cmp(headref, branchref), False) Then
        Exit;

      Context.HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@theirhead, Context.Repository, branchref));
      Try
        theirheads[0] := theirhead;

        Context.HandleLibGit2Output('git_merge_analysis_for_ref', git_merge_analysis_for_ref(@analysis, @preference, Context.Repository, headref, @theirheads, 1));

        If analysis And GIT_MERGE_ANALYSIS_UP_TO_DATE <> 0 Then
          Exit;

        If (preference And GIT_MERGE_PREFERENCE_FASTFORWARD_ONLY <> 0) And (analysis And GIT_MERGE_ANALYSIS_FASTFORWARD = 0) Then
          Raise EAEGitException.Create(geConflict, 'git_merge_analysis_for_ref', ecRepository, 'Repository required fast-forward which isn''t available!');

        // Fast-forward unless the repository explicitly requests not to
        If (analysis And GIT_MERGE_ANALYSIS_FASTFORWARD <> 0) And (preference And GIT_MERGE_PREFERENCE_NO_FASTFORWARD = 0) Then
        Begin
          oid := git_reference_target(branchref);

          Context.DoLibGit2Call('git_reference_target');

          Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@targetcommit, Context.Repository, oid));
          Try
            checkoutoptions.checkout_strategy := GIT_CHECKOUT_SAFE Or GIT_CHECKOUT_RECREATE_MISSING;

            Context.HandleLibGit2Output('git_checkout_tree', git_checkout_tree(Context.Repository, Pgit_object(targetcommit), @checkoutoptions));

            oid := git_commit_id(targetcommit);

            Context.DoLibGit2Call('git_commit_id');

            Context.HandleLibGit2Output('git_reference_set_target', git_reference_set_target(@updatedref, headref, oid, PAnsiChar(UTF8String('Fast-forward'))));

            git_reference_free(updatedref);

            Context.DoLibGit2Call('git_reference_free');
          Finally
            git_commit_free(targetcommit);

            Context.DoLibGit2Call('git_commit_free');
          End;
        End
        Else
        Begin
          // Three-way merge

          Context.HandleLibGit2Output('git_merge', git_merge(Context.Repository, @theirheads, 1, nil, @checkoutoptions));

          Context.HandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.Repository));
          Try
            If Not Context.SolveConflicts Then
              Exit;

            Context.HandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeoid, index));

            Context.HandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, Context.Repository, @treeoid));
            Try
              oid := git_reference_target(headref);

              Context.DoLibGit2Call('git_reference_target');

              Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@headcommit, Context.Repository, oid));
              Try
                oid := git_reference_target(branchref);

                Context.DoLibGit2Call('git_reference_target');

                Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@theircommit, Context.Repository, oid));
                Try
                  Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
                  Try
                    parentcommits[0] := headcommit;
                    parentcommits[1] := theircommit;

                    Context.HandleLibGit2Output('git_commit_create', git_commit_create(
                      @commitoid,
                      Context.Repository,
                      'HEAD',
                      signature,
                      signature,
                      nil,
                      PAnsiChar(UTF8String(inMergeCommitMessage)),
                      tree,
                      2,
                      @parentcommits));

                    Context.HandleLibGit2Output('git_repository_state_cleanup', git_repository_state_cleanup(Context.Repository));
                  Finally
                    git_signature_free(signature);

                    Context.DoLibGit2Call('git_signature_free');
                  End;
                Finally
                  git_commit_free(theircommit);

                  Context.DoLibGit2Call('git_commit_free');
                End;
              Finally
                git_commit_free(headcommit);

                Context.DoLibGit2Call('git_commit_free');
              End;
            Finally
              git_tree_free(tree);

              Context.DoLibGit2Call('git_tree_free');
            End;
          Finally
            git_index_free(index);

            Context.DoLibGit2Call('git_index_free');
          End;
        End;
      Finally
        git_annotated_commit_free(theirhead);

        Context.DoLibGit2Call('git_annotated_commit_free');
      End;
    Finally
      git_reference_free(branchref);

      Context.DoLibGit2Call('git_reference_free');
    End;
  Finally
    git_reference_free(headref);

    Context.DoLibGit2Call('git_reference_free');
  End;
End;

Function TAEGitBranch.MergeInProgress: Boolean;
Var
  a: Integer;
Begin
  a := git_repository_state(Context.Repository);

  Context.DoLibGit2Call('git_repository_state');

  Result := a = GIT_REPOSITORY_STATE_MERGE;
End;

Procedure TAEGitBranch.Delete;
Var
  branch: Pgit_reference;
Begin
  Context.HandleLibGit2Output('git_branch_lookup', git_branch_lookup(@branch, Context.Repository, PAnsiChar(UTF8String(_name)), GIT_BRANCH_LOCAL));
  Try
    Context.HandleLibGit2Output('git_branch_delete', git_branch_delete(branch));
  Finally
    git_reference_free(branch);

    Context.DoLibGit2Call('git_reference_free');
  End;

  Context.RefreshBranches;
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
  a, previncoming, prevoutgoing: Integer;
Begin
  previncoming := _incomingcommits;
  prevoutgoing := _outgoingcommits;

  Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@localoid, Context.Repository, PAnsiChar(UTF8String('refs/heads/' + _name))));

  Context.HandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.Repository));
  Try
    If Context.HandleLibGit2Output('git_branch_upstream', git_branch_upstream(@remoteref, headref), False) Then
    Try
      remotename := git_reference_name(remoteref);

      Context.DoLibGit2Call('git_reference_name');

      If Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@remoteoid, Context.Repository, remotename), False) Then
      Begin
        Context.HandleLibGit2Output('git_graph_ahead_behind', git_graph_ahead_behind(@ahead, @behind, Context.Repository, @localoid, @remoteoid));

        _incomingcommits := behind;
        _outgoingcommits := ahead;
      End
    Finally
      git_reference_free(remoteref);

      Context.DoLibGit2Call('git_reference_free');
    End
    Else
    Begin
      _incomingcommits := -1;
      _outgoingcommits := 0;

      Context.HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, Context.Repository));
      Try
        Context.HandleLibGit2Output('git_revwalk_push', git_revwalk_push(walk, @localoid));

        Context.HandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@refiterator, Context.Repository, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/*'))));
        Try
          While Context.HandleLibGit2Output('git_reference_next', git_reference_next(@ref, refiterator), False) Do
          Begin
            Try
              a := git_reference_type(ref);

              Context.DoLibGit2Call('git_reference_type');

              If a = GIT_REFERENCE_DIRECT Then
              Begin
                remoteoid := git_reference_target(ref)^;

                Context.DoLibGit2Call('git_reference_target');

                Context.HandleLibGit2Output('git_revwalk_hide', git_revwalk_hide(walk, @remoteoid));
              End;
            Finally
              git_reference_free(ref);

              Context.DoLibGit2Call('git_reference_free');
            End;
          End;
        Finally
          git_reference_iterator_free(refiterator);

          Context.DoLibGit2Call('git_reference_iterator_free');
        End;

        While Context.HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@walkoid, walk), False) Do
          Inc(_outgoingcommits);
      Finally
        git_revwalk_free(walk);

        Context.DoLibGit2Call('git_revwalk_free');
      End;
    End;
  Finally
    git_reference_free(headref);

    Context.DoLibGit2Call('git_reference_free');
  End;

  If (_incomingcommits > previncoming) Or (_outgoingcommits > prevoutgoing) Then
  Begin
    Context.ClearCommitDecorationCache;

    If _commits.Loaded Then
      _commits.Refresh;
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
    inRemote := Context.GetDefaultRemoteName;

  Context.HandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, Context.Repository, PAnsiChar(UTF8String(inRemote))));
  Try
    Context.HandleLibGit2Output('git_fetch_options_init', git_fetch_options_init(@options, GIT_FETCH_OPTIONS_VERSION));

    options.callbacks.payload := Context;
    options.callbacks.credentials := LibGit2AuthCallback;

    If inDownloadTags Then
      options.download_tags := GIT_REMOTE_DOWNLOAD_TAGS_ALL;

    Context.HandleLibGit2Output('git_remote_get_fetch_refspecs', git_remote_get_fetch_refspecs(@specs, remote));
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

      Context.DoLibGit2Call('git_strarray_dispose');
    End;

    fetchspecs.Count := Length(refs);

    If fetchspecs.Count > 0 Then
      fetchspecs.strings := @refs[0]
    Else
      fetchspecs.strings := nil;

    Context.HandleLibGit2Output('git_remote_fetch', git_remote_fetch(remote, @fetchspecs, @options, nil));
  Finally
    git_remote_free(remote);

    Context.DoLibGit2Call('git_remote_free');
  End;

  UpdateCommitCount(inRemote);

  If inDownloadTags Then
    Context.ClearCommitDecorationCache;
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
    inRemote := Context.GetDefaultRemoteName;

  Context.HandleLibGit2Output('git_push_options_init', git_push_options_init(@options, GIT_PUSH_OPTIONS_VERSION));

  options.callbacks.payload := Context;
  options.callbacks.credentials := LibGit2AuthCallback;

  Context.HandleLibGit2Output('git_remote_init_callbacks', git_remote_init_callbacks(@callbacks, GIT_REMOTE_CALLBACKS_VERSION));

  callbacks.payload := Context;
  callbacks.credentials := LibGit2AuthCallback;

  utf8ref := UTF8String(Format('+refs/heads/%s:refs/heads/%s', [_name, _name]));
  ref := PAnsiChar(utf8ref);
  refarray.strings := @ref;
  refarray.Count := 1;

  Context.HandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, Context.Repository, PAnsiChar(UTF8String(inRemote))));
  Try
    Context.HandleLibGit2Output('git_remote_connect', git_remote_connect(remote, GIT_DIRECTION_PUSH, @callbacks, nil, nil));
    Try
      Context.HandleLibGit2Output('git_remote_push', git_remote_push(remote, @refarray, @options));

      Context.HandleLibGit2Output('git_reference_lookup', git_reference_lookup(@localref, Context.Repository, PAnsiChar(UTF8String('refs/heads/' + _name))));
      Try
        If Context.HandleLibGit2Output('git_branch_upstream', git_branch_upstream(@remoteref, localref), False) Then
        Begin
          git_reference_free(remoteref);

          Context.DoLibGit2Call('git_reference_free');
        End
        Else
          Context.HandleLibGit2Output('git_branch_set_upstream', git_branch_set_upstream(localref, PAnsiChar(UTF8String(inRemote + '/' + _name))));
      Finally
        git_reference_free(localref);

        Context.DoLibGit2Call('git_reference_free');
      End;
    Finally
      Context.HandleLibGit2Output('git_remote_disconnect', git_remote_disconnect(remote));
    End;
  Finally
    git_remote_free(remote);

    Context.DoLibGit2Call('git_remote_free');
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

    Context.SplitBranchName(inOnBranch, remote);

    If inOnBranch.IsEmpty Then
      inOnBranch := remote + '/' + _name;

    Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
    Try
      Context.HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

      Context.HandleLibGit2Output('git_repository_head', git_repository_head(@head, Context.Repository));
      Try
        Context.HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@branch, Context.Repository, head));
        Try
          Context.HandleLibGit2Output('git_branch_lookup', git_branch_lookup(@ref, Context.Repository, PAnsiChar(UTF8String(inOnBranch)), GIT_BRANCH_ALL));
          Try
            Context.HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@onto, Context.Repository, ref));
            Try
              Context.HandleLibGit2Output('git_rebase_init', git_rebase_init(@rebase, Context.Repository, branch, nil, onto, @options));
              Try
                Repeat
                  If Not Context.HandleLibGit2Output('git_rebase_next', git_rebase_next(@rebaseop, rebase), False) Then
                    Break;

                  If Not Context.SolveConflicts Then
                    Raise EAEGitException.Create(geError, 'git_index_has_conflicts', ecRebase, 'Commit has conflicts, rebase aborted!');

                  Context.HandleLibGit2Output('git_rebase_commit', git_rebase_commit(@oid, rebase, nil, signature, nil, nil));
                Until False;

                Context.HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
              Finally
                git_rebase_free(rebase);

                Context.DoLibGit2Call('git_rebase_free');
              End;
            Finally
              git_annotated_commit_free(onto);

              Context.DoLibGit2Call('git_annotated_commit_free');
            End;
          Finally
            git_reference_free(ref);

            Context.DoLibGit2Call('git_reference_free');
          End;
        Finally
          git_annotated_commit_free(branch);

          Context.DoLibGit2Call('git_annotated_commit_free');
        End;
      Finally
        git_reference_free(head);

        Context.DoLibGit2Call('git_reference_free');
      End;
    Finally
      git_signature_free(signature);

      Context.DoLibGit2Call('git_signature_free');
    End;
  Finally
    Context.RefreshWorkTree;
  End;
End;

Procedure TAEGitBranch.Revert_Last_Commit(Const inCommitCount: Integer);
Var
  target: Pgit_object;
Begin
  Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@target, Context.Repository, PAnsiChar(AnsiString('HEAD~' + inCommitCount.ToString))));
  Try
    Context.HandleLibGit2Output('git_reset', git_reset(Context.Repository, target, GIT_RESET_SOFT, nil));
  Finally
    git_object_free(target);

    Context.DoLibGit2Call('git_object_free');
  End;

  Context.RefreshWorkTree;
End;

Procedure TAEGitBranch.AbortRebase;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  Try
    Context.HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
    Try
      Context.HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.Repository, @options));
      Try
        Context.HandleLibGit2Output('git_rebase_abort', git_rebase_abort(rebase));

        Context.HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
      Finally
        git_rebase_free(rebase);

        Context.DoLibGit2Call('git_rebase_free');
      End;
    Finally
      git_signature_free(signature);

      Context.DoLibGit2Call('git_signature_free');
    End;
  Finally
    Context.RefreshWorkTree;
  End;
End;

Procedure TAEGitBranch.ContinueMerge(inMergeCommitMessage: String = '');
Var
  index: Pgit_index;
  tree: Pgit_tree;
  treeoid, commitoid: git_oid;
  headref, mergeheadref: Pgit_reference;
  headcommit, theircommit: Pgit_commit;
  signature: Pgit_signature;
  parents: Array[0..1] Of Pgit_commit;
  oid: Pgit_oid;
Begin
  If inMergeCommitMessage.IsEmpty Then
    inMergeCommitMessage := 'Merge commit';

  If Not Context.SolveConflicts Then
    Exit;

  Context.HandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.Repository));
  Try
    Context.HandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeoid, Index));

    Context.HandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, Context.Repository, @treeoid));
    Try
      Context.HandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.Repository));
      Try
        oid := git_reference_target(headref);

        Context.DoLibGit2Call('git_reference_target');

        Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@headcommit, Context.Repository, oid));
        Try
          Context.HandleLibGit2Output('git_reference_lookup', git_reference_lookup(@mergeheadref, Context.Repository, 'MERGE_HEAD'));
          Try
            oid := git_reference_target(mergeheadref);

            Context.DoLibGit2Call('git_reference_target');

            Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@theircommit, Context.Repository, oid));
            Try
              Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
              Try
                parents[0] := headcommit;
                parents[1] := theircommit;

                Context.HandleLibGit2Output('git_commit_create', git_commit_create(
                  @commitoid,
                  Context.Repository,
                  'HEAD',
                  signature,
                  signature,
                  nil,
                  PAnsiChar(UTF8String(inMergeCommitMessage)),
                  tree,
                  2,
                  @parents));

                Context.HandleLibGit2Output('git_repository_state_cleanup', git_repository_state_cleanup(Context.Repository));
              Finally
                git_signature_free(signature);

                Context.DoLibGit2Call('git_signature_free');
              End;
            Finally
              git_commit_free(theircommit);

              Context.DoLibGit2Call('git_commit_free');
            End;
          Finally
            git_reference_free(mergeheadref);

            Context.DoLibGit2Call('git_reference_free');
          End;
        Finally
          git_commit_free(headcommit);

          Context.DoLibGit2Call('git_commit_free');
        End;
      Finally
        git_reference_free(headref);

        Context.DoLibGit2Call('git_reference_free');
      End;
    Finally
      git_tree_free(tree);

      Context.DoLibGit2Call('git_tree_free');
    End;
  Finally
    git_index_free(index);

    Context.DoLibGit2Call('git_index_free');
  End;
End;

Procedure TAEGitBranch.ContinueRebase;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
  rebaseop: Pgit_rebase_operation;
  oid: git_oid;
Begin
  Try
    Context.HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    Context.HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.Repository, @options));
    Try
      Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
      Try
        Repeat
          If Not Context.HandleLibGit2Output('git_rebase_next', git_rebase_next(@rebaseop, rebase), False) Then
            Break;

          If Not Context.SolveConflicts Then
            Raise EAEGitException.Create(geError, 'git_index_has_conflicts', ecRebase, 'Commit has conflicts, rebase aborted!');

          Context.HandleLibGit2Output('git_rebase_commit', git_rebase_commit(@oid, rebase, nil, signature, nil, nil));
        Until False;

        Context.HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
      Finally
        git_signature_free(signature);

        Context.DoLibGit2Call('git_signature_free');
      End;
    Finally
      git_rebase_free(rebase);

      Context.DoLibGit2Call('git_rebase_free');
    End;
  Finally
    Context.RefreshWorkTree;
  End;
End;

Function TAEGitBranch.RebaseInProgress: Boolean;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
Begin
  Context.HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  Result := Context.HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.Repository, @options), False);

  If Result Then
  Begin
    git_rebase_free(rebase);

    Context.DoLibGit2Call('git_rebase_free');
  End;
End;

End.
