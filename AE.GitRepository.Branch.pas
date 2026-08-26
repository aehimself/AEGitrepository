{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Branch;

Interface

Uses AE.GitRepository.HeadTarget, AE.GitRepository.Context, AE.GitRepository.Commit, AE.GitRepository.RefreshableObject,
     System.Generics.Collections;

Type
  TAEGitBranch = Class(TAEGitHeadTarget)
  strict private
    _commits: TAEGitCommits;
    _incomingcommits: Integer;
    _name: String;
    _outgoingcommits: Integer;
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
    Procedure UpdateCommitCount(inRemote: String = '');
    Function MergeInProgress: Boolean;
    Function RebaseInProgress: Boolean;
    Property Commits: TAEGitCommits Read _commits;
    Property IncomingCommits: Integer Read _incomingcommits;
    Property Name: String Read _name;
    Property OutgoingCommits: Integer Read _outgoingcommits;
  End;

  TAEGitBranches = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _branches: TObjectDictionary<String, TAEGitBranch>;
    _current: TAEGitHeadTarget;
    _currentowned: Boolean;
    _order: TList<String>;
    Procedure FreeCurrent;
    Function GetCurrent: TAEGitHeadTarget;
    Function GetBranch(Const inBranchName: String): TAEGitBranch;
    Function GetNames: TArray<String>;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); Override;
    Destructor Destroy; Override;
    Procedure New(Const inBranchName: String);
    Procedure UpdateCurrent;
    Property Current: TAEGitHeadTarget Read GetCurrent;
    Property Names: TArray<String> Read GetNames;
    Property Branch[Const inBranchName: String]: TAEGitBranch Read GetBranch; Default;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.Exception, AE.GitRepository.TypeDef, AE.GitRepository.Libgit2Callbacks;

//
// TAEGitBranch
//

Procedure TAEGitBranch.AbortMerge;
Var
  head: Pgit_object;
Begin
  If Not Self.MergeInProgress Then
    Exit;

  Try
    Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@head, Context.Repository, 'HEAD'));
    Try
      Context.HandleLibGit2Output('git_reset', git_reset(Context.Repository, head, GIT_RESET_HARD, nil));

      Context.HandleLibGit2Output('git_repository_state_cleanup', git_repository_state_cleanup(Context.Repository));
    Finally
      git_object_free(Head);
    End;
  Finally
    Context.RefreshWorkTree;
  End;
End;

Constructor TAEGitBranch.Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String);
Begin
  inherited Create(inContext);

  _commits := TAEGitCommits.Create(Context, inBranchName);

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

  Context.SplitBranchName(branchname, remote);

  Context.HandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_SAFE;

  If Not Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, Context.Repository, PAnsiChar(UTF8String('refs/heads/' + branchname))), [geNotFound]) Then
  Begin
    Context.HandleLibGit2Output('git_reference_lookup', git_reference_lookup(@remotebranch, Context.Repository, PAnsiChar(UTF8String('refs/remotes/' + remote + '/' + branchname))));
    Try
      Context.HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@commit, Context.Repository, remotebranch));
      Try
        Context.HandleLibGit2Output('git_branch_create_from_annotated', git_branch_create_from_annotated(@localbranch, Context.Repository, PAnsiChar(UTF8String(branchname)), commit, 0));
        Try
          Context.HandleLibGit2Output('git_branch_set_upstream', git_branch_set_upstream(localbranch, PAnsiChar(UTF8String(remote + '/' + branchname))));

          Context.RefreshActualCommitCount;
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
  samereference: Boolean;
  logcode: TAEGitErrorCode;
Begin
  Context.AssertCleanWorkTree;

  If inMergeCommitMessage.IsEmpty Then
    inMergeCommitMessage := 'Merge branch "' + inMergeFromBranch + '"';

  Try
    git_checkout_options_init(@checkoutoptions, GIT_CHECKOUT_OPTIONS_VERSION);

    checkoutoptions.checkout_strategy := GIT_CHECKOUT_SAFE;

    Context.HandleLibGit2Output('', git_repository_head(@headref, Context.Repository));
    Try
      Context.HandleLibGit2Output('', git_branch_lookup(@branchref, Context.Repository, PAnsiChar(UTF8String(inMergeFromBranch)), GIT_BRANCH_LOCAL));
      Try
        samereference := git_reference_cmp(headref, branchref) = 0;

        If samereference Then
          logcode := geTrue
        Else
          logcode := geFalse;

        Context.DoLibGit2Call('git_reference_cmp', logcode);

        If samereference Then
          Exit;

        Context.HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@theirhead, Context.Repository, branchref));
        Try
          theirheads[0] := theirhead;

          Context.HandleLibGit2Output('git_merge_analysis_for_ref', git_merge_analysis_for_ref(@analysis, @preference, Context.Repository, headref, @theirheads, 1));

          If analysis And GIT_MERGE_ANALYSIS_UP_TO_DATE <> 0 Then
            Exit;

          If (preference And GIT_MERGE_PREFERENCE_FASTFORWARD_ONLY <> 0) And (analysis And GIT_MERGE_ANALYSIS_FASTFORWARD = 0) Then
            Raise EAEGitException.Create('Repository required fast-forward which isn''t available!');

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

          Self.UpdateCommitCount;

          Context.RefreshSubmodules;
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
  Finally
    Context.RefreshWorkTree;
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
  If Context.GetCurrentBranchName = _name Then
    Raise EAEGitException.Create('Cannot delete the currently checked out branch.');

  Context.HandleLibGit2Output('git_branch_lookup', git_branch_lookup(@branch, Context.Repository, PAnsiChar(UTF8String(_name)), GIT_BRANCH_LOCAL));
  Try
    Context.HandleLibGit2Output('git_branch_delete', git_branch_delete(branch));
  Finally
    git_reference_free(branch);

    Context.DoLibGit2Call('git_reference_free');
  End;

  Context.RefreshBranches;
End;

Procedure TAEGitBranch.UpdateCommitCount(inRemote: String = '');
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
  If inRemote.IsEmpty Then
  Begin
    inRemote := Context.GetDefaultRemoteName;

    If inRemote.IsEmpty Then
      Raise EAEGitException.Create('Cannot fetch: no remote is configured.');
  End;

  previncoming := _incomingcommits;
  prevoutgoing := _outgoingcommits;

  Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@localoid, Context.Repository, PAnsiChar(UTF8String('refs/heads/' + _name))));

  Context.HandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.Repository));
  Try
    If Context.HandleLibGit2Output('git_branch_upstream', git_branch_upstream(@remoteref, headref), [geNotFound]) Then
    Try
      remotename := git_reference_name(remoteref);

      Context.DoLibGit2Call('git_reference_name');

      If Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@remoteoid, Context.Repository, remotename), [geNotFound]) Then
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
          While Context.HandleLibGit2Output('git_reference_next', git_reference_next(@ref, refiterator), [geIterationOver]) Do
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

        While Context.HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@walkoid, walk), [geIterationOver]) Do
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

    _commits.Refresh(False);
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
  Begin
    inRemote := Context.GetDefaultRemoteName;

    If inRemote.IsEmpty Then
      Raise EAEGitException.Create('Cannot fetch: no remote is configured.');
  End;

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
  Begin
    inRemote := Context.GetDefaultRemoteName;

    If inRemote.IsEmpty Then
      Raise EAEGitException.Create('Cannot push: no remote is configured.');
  End;

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
        If Context.HandleLibGit2Output('git_branch_upstream', git_branch_upstream(@remoteref, localref), [geNotFound]) Then
        Begin
          git_reference_free(remoteref);

          Context.DoLibGit2Call('git_reference_free');
        End
        Else
        Begin
          Context.HandleLibGit2Output('git_branch_set_upstream', git_branch_set_upstream(localref, PAnsiChar(UTF8String(inRemote + '/' + _name))));

          Context.ClearCommitDecorationCache;
        End;

        Self.UpdateCommitCount;
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
    Begin
      If remote.IsEmpty Then
        Raise EAEGitException.Create('Cannot rebase: no remote is configured.');

      inOnBranch := remote + '/' + _name;
    End;

    Context.AssertCleanWorkTree;

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
                  If Not Context.HandleLibGit2Output('git_rebase_next', git_rebase_next(@rebaseop, rebase), [geIterationOver]) Then
                    Break;

                  If Not Context.SolveConflicts Then
                    Raise EAEGitException.Create('Commit has conflicts, rebase aborted!');

                  Context.HandleLibGit2Output('git_rebase_commit', git_rebase_commit(@oid, rebase, nil, signature, nil, nil));
                Until False;

                Context.HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));

                Self.UpdateCommitCount;

                Context.RefreshSubmodules;
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
  If inCommitCount <= 0 Then
    Raise EAEGitException.Create('Invalid commit count (' + inCommitCount.ToString + ')');

  Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@target, Context.Repository, PAnsiChar(AnsiString('HEAD~' + inCommitCount.ToString))));
  Try
    Context.HandleLibGit2Output('git_reset', git_reset(Context.Repository, target, GIT_RESET_SOFT, nil));

    Context.RefreshSubmodules;
  Finally
    git_object_free(target);

    Context.DoLibGit2Call('git_object_free');
  End;

  Context.RefreshWorkTree;

  Self.UpdateCommitCount;
End;

Procedure TAEGitBranch.AbortRebase;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  If Not Self.RebaseInProgress Then
    Raise EAEGitException.Create('Cannot abort rebase: no rebase is in progress.');

  Try
    Context.HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
    Try
      Context.HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.Repository, @options));
      Try
        Context.HandleLibGit2Output('git_rebase_abort', git_rebase_abort(rebase));

        Context.HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));

        Context.RefreshSubmodules;
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
  If Not Self.MergeInProgress Then
    Raise EAEGitException.Create('Cannot continue merge: no merge is in progress.');

  If inMergeCommitMessage.IsEmpty Then
    inMergeCommitMessage := 'Merge commit';

  If Not Context.SolveConflicts Then
    Exit;

  Try
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

                  Self.UpdateCommitCount;

                  Context.RefreshSubmodules;
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
  Finally
    Context.RefreshWorkTree;
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
  If Not Self.RebaseInProgress Then
    Raise EAEGitException.Create('Cannot continue rebase: no rebase is in progress.');

  Try
    Context.HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    Context.HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.Repository, @options));
    Try
      Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
      Try
        Repeat
          If Not Context.HandleLibGit2Output('git_rebase_next', git_rebase_next(@rebaseop, rebase), [geIterationOver]) Then
            Break;

          If Not Context.SolveConflicts Then
            Raise EAEGitException.Create('Commit has conflicts, rebase aborted!');

          Context.HandleLibGit2Output('git_rebase_commit', git_rebase_commit(@oid, rebase, nil, signature, nil, nil));
        Until False;

        Context.HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));

        Self.UpdateCommitCount;

        Context.RefreshSubmodules;
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

  Result := Context.HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, Context.Repository, @options), [geNotFound]);

  If Result Then
  Begin
    git_rebase_free(rebase);

    Context.DoLibGit2Call('git_rebase_free');
  End;
End;

//
// TAEGitBranches
//

Procedure TAEGitBranches.InternalClear;
Begin
  inherited;

  Self.FreeCurrent;

  _branches.Clear;
End;

Constructor TAEGitBranches.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited;

  _branches := TObjectDictionary<String, TAEGitBranch>.Create([doOwnsValues]);
  _order := TList<String>.Create;
End;

Destructor TAEGitBranches.Destroy;
Begin
  Self.FreeCurrent;

  FreeAndNil(_branches);
  FreeAndNil(_order);

  inherited;
End;

Procedure TAEGitBranches.FreeCurrent;
Begin
  If _currentowned Then
  Begin
    FreeAndNil(_current);

    _currentowned := False;
  End
  Else
    _current := nil;
End;

Procedure TAEGitBranches.New(Const inBranchName: String);
Var
  ref, branchref: Pgit_reference;
  commit: Pgit_commit;
Begin
  Context.HandleLibGit2Output('git_repository_head', git_repository_head(@ref, Context.Repository));
  Try
    Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.Repository, git_reference_target(ref)));
    Try
      Context.HandleLibGit2Output('git_branch_create', git_branch_create(@branchref, Context.Repository, PAnsiChar(UTF8String(inBranchName)), commit, Ord(False)));

      git_reference_free(branchref);

      Context.DoLibGit2Call('git_reference_free');
    Finally
      git_commit_free(commit);

      Context.DoLibGit2Call('git_commit_free');
    End;
  Finally
    git_reference_free(ref);

    Context.DoLibGit2Call('git_reference_free');
  End;

  If Self.Loaded Then
    _branches.Add(inBranchName, TAEGitBranch.Create(Context, inBranchName));
End;

Function TAEGitBranches.GetCurrent: TAEGitHeadTarget;
Begin
  If Not Assigned(_current) Then
    Self.UpdateCurrent;

  Result := _current;
End;

Function TAEGitBranches.GetBranch(Const inBranchName: String): TAEGitBranch;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _branches[inBranchName];
End;

Function TAEGitBranches.GetNames: TArray<String>;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _order.ToArray;
End;

Procedure TAEGitBranches.InternalRefresh;
Var
  names: TArray<String>;
  name: String;
  branch: TAEGitBranch;
  keystoremove: TList<String>;
  ref: Pgit_reference;
  iterator: Pgit_branch_iterator;
  branchtypeoutput: git_branch_t;
  branchname: PAnsiChar;
  a: Integer;
Begin
  Self.FreeCurrent;

  Self.Loaded := False;
  SetLength(names, 0);

  Context.HandleLibGit2Output('git_branch_iterator_new', git_branch_iterator_new(@iterator, Context.Repository, GIT_BRANCH_ALL));
  Try
    Repeat
      If Not Context.HandleLibGit2Output('git_branch_next', git_branch_next(@ref, @branchtypeoutput, iterator), [geIterationOver]) Then
        Break;

      Try
        If Context.HandleLibGit2Output('git_branch_name', git_branch_name(@branchname, ref), [geNotFound]) Then
        Begin
          a := Length(names);
          SetLength(names, a + 1);

          names[a] := String(UTF8String(branchname));
        End;
      Finally
        git_reference_free(ref);

        Context.DoLibGit2Call('git_reference_free');
      End;
    Until False;
  Finally
    git_branch_iterator_free(iterator);

    Context.DoLibGit2Call('git_branch_iterator_free');
  End;

  keystoremove := TList<String>.Create;
  Try
    _order.Clear;

    keystoremove.AddRange(_branches.Keys);

    For name In names Do
    Begin
      If Not _branches.TryGetValue(name, branch) Then
      Begin
        branch := TAEGitBranch.Create(Context, name);

        _branches.Add(name, branch);
      End
      Else
        branch.Commits.Refresh(False);

      _order.Add(name);

      keystoremove.Remove(name);
    End;

    For name In keystoremove Do
      _branches.Remove(name);
  Finally
    FreeAndNil(keystoremove);
  End;

  Self.Loaded := True;

  UpdateCurrent;
End;

Procedure TAEGitBranches.UpdateCurrent;
Var
  isBranch: Integer;
  oid: git_oid;
  ref: Pgit_reference;
  name: String;
  branchname: PAnsiChar;
Begin
  Self.FreeCurrent;

  If Context.HandleLibGit2Output('git_repository_head', git_repository_head(@ref, Context.Repository), [geUnbornBranch]) Then
  Try
    isBranch := git_reference_is_branch(ref);

    Context.DoLibGit2Call('git_reference_is_branch');

    If isBranch <> 0 Then
    Begin
      If Context.HandleLibGit2Output('git_branch_name', git_branch_name(@branchname, ref), [geNotFound]) Then
        name := String(UTF8String(branchname))
      Else
        name := '';

      If Not Self.Loaded Then
        Self.Refresh;

      If _branches.ContainsKey(name) Then
        _current := _branches[name]
      Else
      Begin
        _current := TAEGitBranch.Create(Context, name);
        _currentowned := True;
      End;
    End
    Else
    Begin
      oid := git_reference_target(ref)^;

      Context.DoLibGit2Call('git_reference_target');

      _current := TAEGitCommit.Create(Context, Context.OidToString(@oid));
      _currentowned := True;
    End;
  Finally
    git_reference_free(ref);

    Context.DoLibGit2Call('git_reference_free');
  End;
End;

End.
