{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository;

Interface

Uses libgit2, System.SysUtils, AE.GitRepository.TypeDef, AE.GitRepository.Settings;

Type
  TAEGitRepository = Class
  strict private
    _authmethod: TMethod;
    _currentbranch: String;
    _incomingcommits: Integer;
    _onblockconflict: TAEGitBlockConflictCallback;
    _onlibgit2call: TAELibGit2CallLogEvent;
    _onmergeconflict: TAEGitMergeConflictCallback;
    _outgoingcommits: Integer;
    _repo: Pgit_repository;
    _repodir: String;
    _settings: TAEGitRepositorySettings;
    Procedure DoRebase(Const inRebase: Pgit_rebase; Const inSignature: Pgit_signature);
    Procedure SetCurrentBranch(inBranchName: String);
    Procedure SetRepoDir(Const inRepoDir: String);
    Function GetHeadIndexDiff(Const inFileNames: TArray<String>): Pgit_diff;
    Function GetIndexWorkdirDiff(Const inFileNames: TArray<String>): Pgit_diff;
  strict protected
    Procedure CloseGitRepository;
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
    Procedure FillDecorationCache(Const outDecorationCache: TAEGitCommitDecorationCache);
    Procedure OpenGitRepository;
    Procedure SplitBranchName(Var outBranchName: String; Var outRemote: String);
    Procedure UpdateCommitCount(Const inRemote: String);
    Function AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer; Virtual;
    Function GetDefaultRemoteName: String;
    Function HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
    Function ResolveConflictsManually(Const inFileName, inConflictedContent: String): Boolean;
    Function SolveConflicts: Boolean;
  protected
    Property LibGit2Repository: Pgit_repository Read _repo;
  public
    Constructor Create; ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure CommitStagedFiles(Const inCommitMessage: String);
    Procedure CreateBranch(Const inBranchName: String);
    Procedure DeleteBranch(Const inBranchName: String);
    Procedure GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
    Procedure GetCommitContents(Const outCommitContents: TAEGitCommitContents; Const inCommitHash: String);
    Procedure GetCommitList(Const outCommitList: TAEGitCommitList; Const inStartCommitHash: String = ''; Const inCommitAmount: Integer = 0);
    Procedure Fetch(inRemote: String = ''; Const inDownloadTags: Boolean = False);
    Procedure Patch_Apply(Const inPatch: String);
    Procedure PushCommitsToRemote(inRemote: String = '');
    Procedure Rebase(inBranch: String = '');
    Procedure Rebase_Abort;
    Procedure Rebase_Continue;
    Procedure RevertFileModifications(Const inFileName: String);
    Procedure Revert_Last_Commit(Const inCommitCount: Integer);
    Procedure StageFile(Const inFileName: String);
    Procedure Stash_Drop(Const inStashIndex: Integer);
    Procedure Stash_List(Const inStashList: TAEGitStashList);
    Procedure Stash_Pop(Const inStashIndex: Integer);
    Procedure Stash_Push(Const inStashMessage: String);
    Procedure UnstageFile(Const inFileName: String);
    Procedure UpdateCurrentBranchName;
    Function BranchList(Const inBranchType: TAEGitBranchType): TArray<String>;
    Function Patch_Get(Const inFileName: String; Const inStagedOnly: Boolean): String; Overload;
    Function Patch_Get(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): String; Overload;
    Function Rebase_InProgress: Boolean;
    Property CurrentBranch: String Read _currentbranch Write SetCurrentBranch;
    Property IncomingCommits: Integer Read _incomingcommits;
    Property GitRepositoryDirectory: String Read _repodir Write SetRepoDir;
    Property OnBlockConflict: TAEGitBlockConflictCallback Read _onblockconflict Write _onblockconflict;
    Property OnLibGit2Call: TAELibGit2CallLogEvent Read _onlibgit2call Write _onlibgit2call;
    Property OnMergeConflict: TAEGitMergeConflictCallback Read _onmergeconflict Write _onmergeconflict;
    Property OutgoingCommits: Integer Read _outgoingcommits;
    Property Settings: TAEGitRepositorySettings Read _settings;
  End;

Implementation

Uses AE.GitRepository.Exception, System.IOUtils, System.DateUtils, System.Generics.Collections;

//
// LibGit2 callbacks. These can not be procedure / function of objects so in the payload we send the instances own
// handler to call back.
//

Function GitLibAuthCallback(out_: PPgit_credential; url, username_from_url: PAnsiChar; allowed_types: Cardinal; payload: Pointer): Integer; Cdecl;
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

  Result := TAELibGit2AuthCallback(PMethod(payload)^)(out_, url, username_from_url, types);
End;

Function GitLibStashListCallback(Index: NativeUInt; Const MessageText: PAnsiChar; Const StashId: Pgit_oid; Payload: Pointer): Integer; Cdecl;
Begin
  If PAEGitStashList(Payload)^.Count <= Int64(Index) Then
    PAEGitStashList(Payload)^.Count := Int64(Index) + 1;

  PAEGitStashList(Payload)^[Int64(Index)] := String(UTF8String(MessageText));

  Result := 0;
End;

//
// TAEGitRepository
//

Procedure TAEGitRepository.RevertFileModifications(Const inFileName: String);
Var
  options: git_checkout_options;
  utf8strings: UTF8String;
  pathstrings: PAnsiChar;
Begin
  utf8strings := UTF8String(inFileName.Replace('\', '/'));
  pathstrings := PAnsiChar(utf8strings);
  HandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_FORCE Or GIT_CHECKOUT_REMOVE_UNTRACKED Or GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH;
  options.paths.count := 1;
  options.paths.strings := @pathstrings;

  HandleLibGit2Output('git_checkout_tree', git_checkout_tree(_repo, nil, @options));
End;

Procedure TAEGitRepository.UnstageFile(Const inFileName: String);
Var
  target: Pgit_object;
  pathspec: git_strarray;
  utf8filename: UTF8String;
  filename: PAnsiChar;
Begin
  HandleLibGit2Output('git_revparse_single', git_revparse_single(@target, _repo, 'HEAD'));
  Try
    utf8filename := UTF8String(inFileName);
    filename := PAnsiChar(utf8filename);
    pathspec.count := 1;
    pathspec.strings := @filename;

    HandleLibGit2Output('git_reset_default', git_reset_default(_repo, target, @pathspec));
  Finally
    git_object_free(target);

    DoLibGit2Call('git_object_free');
  End;
End;

Procedure TAEGitRepository.StageFile(Const inFileName: String);
Var
  index: Pgit_index;
Begin
  HandleLibGit2Output('git_repository_index', git_repository_index(@index, _repo));
  Try
    HandleLibGit2Output('git_index_add_bypath', git_index_add_bypath(index, PAnsiChar(UTF8String(inFileName.Replace('\', '/')))));

    HandleLibGit2Output('git_index_write', git_index_write(index));
  Finally
    git_index_free(index);

    DoLibGit2Call('git_index_free');
  End;
End;

Procedure TAEGitRepository.Stash_Drop(Const inStashIndex: Integer);
Begin
  HandleLibGit2Output('git_stash_drop', git_stash_drop(_repo, size_t(inStashIndex)));
End;

Procedure TAEGitRepository.Stash_List(Const inStashList: TAEGitStashList);
Begin
  HandleLibGit2Output('git_stash_foreach', git_stash_foreach(_repo, @GitLibStashListCallback, @inStashList));
End;

Procedure TAEGitRepository.Stash_Pop(Const inStashIndex: Integer);
Var
  options: git_stash_apply_options;
Begin
  HandleLibGit2Output('git_stash_apply_options_init', git_stash_apply_options_init(@options, GIT_STASH_APPLY_OPTIONS_VERSION));
  options.flags := 0;

  HandleLibGit2Output('git_stash_pop', git_stash_pop(_repo, size_t(inStashIndex), @options));

  SolveConflicts;
End;

Procedure TAEGitRepository.Stash_Push(Const inStashMessage: String);
Var
  signature: Pgit_signature;
  oid: git_oid;
Begin
  HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
  Try
    HandleLibGit2Output('git_stash_save', git_stash_save(@oid, _repo, signature, PAnsiChar(UTF8String(inStashMessage)), GIT_STASH_INCLUDE_UNTRACKED));
  Finally
    git_signature_free(signature);

    DoLibGit2Call('git_signature_free');
  End;
End;

Function TAEGitRepository.HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
Var
  err: PGit_Error;
  errorcode: TAEGitErrorCode;
  errorclass: TAEGitErrorClass;
Begin
  Case inCommandResult Of
    1:
      errorcode := geFalse;
    GIT_OK:
      errorcode := geOk;
    GIT_ERROR:
      errorcode := geError;
    GIT_ENOTFOUND:
      errorcode := geNotFound;
    GIT_EEXISTS:
      errorcode := geObjectExists;
    GIT_EAMBIGUOUS:
      errorcode := geAmbiguous;
    GIT_EBUFS:
      errorcode := geBufTooSmall;
    GIT_EUSER:
      errorcode := geUser;
    GIT_EBAREREPO:
      errorcode := geBareRepo;
    GIT_EUNBORNBRANCH:
      errorcode := geUnbornBranch;
    GIT_EUNMERGED:
      errorcode := geUnmerged;
    GIT_ENONFASTFORWARD:
      errorcode := geNonFastForward;
    GIT_EINVALIDSPEC:
      errorcode := geInvalidSpec;
    GIT_ECONFLICT:
      errorcode := geConflict;
    GIT_ELOCKED:
      errorcode := geLocked;
    GIT_EMODIFIED:
      errorcode := geModified;
    GIT_EAUTH:
      errorcode := geAuth;
    GIT_ECERTIFICATE:
      errorcode := geCertificate;
    GIT_EAPPLIED:
      errorcode := geAlreadyApplied;
    GIT_EPEEL:
      errorcode := gePeel;
    GIT_EEOF:
      errorcode := geEOF;
    GIT_EINVALID:
      errorcode := geInvalid;
    GIT_EUNCOMMITTED:
      errorcode := geUncommitted;
    GIT_EDIRECTORY:
      errorcode := geDirectory;
    GIT_EMERGECONFLICT:
      errorcode := geMergeConflict;
    GIT_PASSTHROUGH:
      errorcode := gePassthrough;
    GIT_ITEROVER:
      errorcode := geIterationOver;
    GIT_RETRY:
      errorcode := geRetry;
    GIT_EMISMATCH:
      errorcode := geHashMismatch;
    GIT_EINDEXDIRTY:
      errorcode := geIndexDirty;
    GIT_EAPPLYFAIL:
      errorcode := geApplyFailed;
    GIT_EOWNER:
      errorcode := geWrongOwner;
    GIT_TIMEOUT:
      errorcode := geTimeout;
    GIT_EUNCHANGED:
      errorcode := geUnchanged;
    GIT_ENOTSUPPORTED:
      errorcode := geNotSupported;
    GIT_EREADONLY:
      errorcode := geReadOnly;
    Else
      errorcode := geUnknown;
  End;

  DoLibGit2Call(inMethod, errorcode);

  Result := errorcode = geOK;

  If Not Result And inRaiseException Then
  Begin
    err := git_error_last;

    DoLibGit2Call('git_error_last');

    Case err.klass Of
      GIT_ERROR_NONE:
        errorclass := ecNone;
      GIT_ERROR_NOMEMORY:
        errorclass := ecNoMemory;
      GIT_ERROR_OS:
        errorclass := ecOperatingSystem;
      GIT_ERROR_INVALID:
        errorclass := ecInvalid;
      GIT_ERROR_REFERENCE:
        errorclass := ecReference;
      GIT_ERROR_ZLIB:
        errorclass := ecZlib;
      GIT_ERROR_REPOSITORY:
        errorclass := ecRepository;
      GIT_ERROR_CONFIG:
        errorclass := ecConfig;
      GIT_ERROR_REGEX:
        errorclass := ecRegex;
      GIT_ERROR_ODB:
        errorclass := ecObjectDatabase;
      GIT_ERROR_INDEX:
        errorclass := ecIndex;
      GIT_ERROR_OBJECT:
        errorclass := ecObject;
      GIT_ERROR_NET:
        errorclass := ecNetwork;
      GIT_ERROR_TAG:
        errorclass := ecTag;
      GIT_ERROR_TREE:
        errorclass := ecTree;
      GIT_ERROR_INDEXER:
        errorclass := ecIndexer;
      GIT_ERROR_SSL:
        errorclass := ecSsl;
      GIT_ERROR_SUBMODULE:
        errorclass := ecSubmodule;
      GIT_ERROR_THREAD:
        errorclass := ecThread;
      GIT_ERROR_STASH:
        errorclass := ecStash;
      GIT_ERROR_CHECKOUT:
        errorclass := ecCheckout;
      GIT_ERROR_FETCHHEAD:
        errorclass := ecFetchHead;
      GIT_ERROR_MERGE:
        errorclass := ecMerge;
      GIT_ERROR_SSH:
        errorclass := ecSsh;
      GIT_ERROR_FILTER:
        errorclass := ecFilter;
      GIT_ERROR_REVERT:
        errorclass := ecRevert;
      GIT_ERROR_CALLBACK:
        errorclass := ecCallback;
      GIT_ERROR_CHERRYPICK:
        errorclass := ecCherryPick;
      GIT_ERROR_DESCRIBE:
        errorclass := ecDescribe;
      GIT_ERROR_REBASE:
        errorclass := ecRebase;
      GIT_ERROR_FILESYSTEM:
        errorclass := ecFileSystem;
      GIT_ERROR_PATCH:
        errorclass := ecPatch;
      GIT_ERROR_WORKTREE:
        errorclass := ecWorkTree;
      GIT_ERROR_SHA:
        errorclass := ecSha;
      GIT_ERROR_HTTP:
        errorclass := ecHttp;
      GIT_ERROR_INTERNAL:
        errorclass := ecInternal;
      GIT_ERROR_GRAFTS:
        errorclass := ecGrafts;
      Else
        errorclass := ecUnknown;
    End;

    Raise EAEGitException.Create(errorcode, inMethod, errorclass, String(UTF8String(err.message)));
  End;
End;

Procedure TAEGitRepository.UpdateCurrentBranchName;
Var
  ref: Pgit_reference;
  tmp: PAnsiChar;
  oid: Pgit_oid;
  s: string;
  contents: TArray<String>;
  cfg: Pgit_config;
Begin
  _currentbranch := '';
  tmp := nil;

  If HandleLibGit2Output('git_repository_head', git_repository_head(@ref, _repo), False) Then
  Try
    If HandleLibGit2Output('git_reference_is_branch', git_reference_is_branch(ref), False) Then
    Begin
      // Detached HEAD

      oid := git_reference_target(ref);

      DoLibGit2Call('git_reference_target');

      If Assigned(oid) Then
      Begin
        _currentbranch := String(UTF8String(git_oid_tostr_s(oid)));

        DoLibGit2Call('git_oid_tostr_s');
      End;
    End
    Else
    If HandleLibGit2Output('git_branch_name', git_branch_name(@tmp, ref), False) Then
        _currentbranch := String(UTF8String(tmp));
  Finally
    git_reference_free(ref);

    DoLibGit2Call('git_reference_free');
  End
  Else
  Begin
    // Try HEAD for worktree

    If HandleLibGit2Output('git_repository_head_for_worktree', git_repository_head_for_worktree(@ref, _repo, nil), False) Then
    Try
      tmp := git_reference_shorthand(ref);

      DoLibGit2Call('git_reference_shorthand');

      If Assigned(tmp) Then
        _currentbranch := String(UTF8String(tmp));
    Finally
      git_reference_free(ref);

      DoLibGit2Call('git_reference_free');
    End
    Else
    Begin
      // Manually read the symbolic HEAD

      s := String(UTF8String(git_repository_workdir(_repo))).Replace('/', PathDelim);

      DoLibGit2Call('git_repository_workdir');

      s := IncludeTrailingPathDelimiter(s) + '.git\HEAD';

      If TFile.Exists(s) Then
      Begin
        contents := TFile.ReadAllLines(s);

        If (Length(contents) > 0) And contents[0].StartsWith('ref: refs/heads/') Then
          _currentbranch := contents[0].Substring(16);
      End;
    End;
  End;

  If _currentbranch.IsEmpty Then
  Begin
    // Use configured default in Git

    _currentbranch := 'master';

    HandleLibGit2Output('git_config_open_default', git_config_open_default(@cfg));
    Try
      tmp := nil;

      If HandleLibGit2Output('git_config_get_string', git_config_get_string(@tmp, cfg, 'init.defaultBranch'), False) Then
        _currentbranch := String(UTF8String(tmp));
    Finally
      git_config_free(cfg);

      DoLibGit2Call('git_config_free');
    End;
  End;
End;

Procedure TAEGitRepository.UpdateCommitCount(const inRemote: string);
Var
  localoid, remoteoid, walkoid: git_oid;
  ahead, behind: size_t;
  walk: Pgit_revwalk;
  refiterator: Pgit_reference_iterator;
  ref, headref, remoteref: Pgit_reference;
  a: Integer;
  remote: PAnsiChar;
Begin
  HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@localoid, _repo, PAnsiChar(UTF8String('refs/heads/' + _currentbranch))));

  HandleLibGit2Output('git_repository_head', git_repository_head(@headref, _repo));
  Try
    If HandleLibGit2Output('git_branch_upstream', git_branch_upstream(@remoteref, headref), False) Then
    Try
      remote := git_reference_name(remoteref);

      DoLibGit2Call('git_reference_name');

      If HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@remoteoid, _repo, remote), False) Then
      Begin
        // Remote branch exist, use git_graph_ahead_behind
        HandleLibGit2Output('git_graph_ahead_behind', git_graph_ahead_behind(@ahead, @behind, _repo, @localoid, @remoteoid));

        _incomingcommits := behind;
        _outgoingcommits := ahead;
      End
    Finally
      git_reference_free(remoteref);

      DoLibGit2Call('git_reference_free');
    End
    Else
    Begin
      // Remote branch does not exist. There can't be incoming commits, for outgoing count the commits unreachable on
      // other branches
      _incomingcommits := -1;
      _outgoingcommits := 0;

      HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, _repo));
      Try
        HandleLibGit2Output('git_revwalk_push', git_revwalk_push(walk, @localoid));

        HandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@refiterator, _repo, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/*'))));
        Try
          While HandleLibGit2Output('git_reference_next', git_reference_next(@ref, refiterator), False) Do
          Begin
            Try
              // Skip symbolic refs such as refs/remotes/origin/HEAD
              a := git_reference_type(ref);

              DoLibGit2Call('git_reference_type');

              If a = GIT_REFERENCE_DIRECT Then
              Begin
                remoteoid := git_reference_target(Ref)^;

                DoLibGit2Call('git_reference_target');

                HandleLibGit2Output('git_revwalk_hide', git_revwalk_hide(walk, @remoteoid));
              End;
            Finally
              git_reference_free(ref);

              DoLibGit2Call('git_reference_free');
            End;
          End;
        Finally
          git_reference_iterator_free(refiterator);

          DoLibGit2Call('git_reference_iterator_free');
        End;

        While HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@walkoid, walk), False) Do
          Inc(_outgoingcommits);
      Finally
        git_revwalk_free(walk);

        DoLibGit2Call('git_revwalk_free');
      End;
    End;
  Finally
    git_reference_free(headref);

    DoLibGit2Call('git_reference_free');
  End;
End;

Procedure TAEGitRepository.Fetch(inRemote: String = ''; Const inDownloadTags: Boolean = False);
Var
  remote: Pgit_remote;
  options: git_fetch_options;
  specs, fetchspecs: git_strarray;
  refs: TArray<PAnsiChar>;
  p: PPAnsiChar;
  a: Integer;
  hastagrefs: Boolean;
Begin
  If inRemote.IsEmpty Then
    inRemote := Self.GetDefaultRemoteName;

  HandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, _repo, PAnsiChar(UTF8String(inRemote))));
  Try
    HandleLibGit2Output('git_fetch_options_init', git_fetch_options_init(@options, GIT_FETCH_OPTIONS_VERSION));

    options.callbacks.payload := @_authmethod;
    options.callbacks.credentials := GitLibAuthCallback;

    If inDownloadTags Then
      options.download_tags := GIT_REMOTE_DOWNLOAD_TAGS_ALL;

    HandleLibGit2Output('git_remote_get_fetch_refspecs', git_remote_get_fetch_refspecs(@specs, remote));
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

      SetLength(refs, Integer(specs.Count) + Ord(inDownloadTags And Not hastagrefs));

      p := specs.strings;

      For a := 0 To specs.Count - 1 Do
      Begin
        refs[a] := PAnsiChar(UTF8String(p^));

        Inc(p);
      End;

      If inDownloadTags And Not hastagrefs Then
        refs[High(refs)] := PAnsiChar(UTF8String('+refs/tags/*:refs/tags/*'));
    Finally
      git_strarray_dispose(@specs);

      DoLibGit2Call('git_strarray_dispose');
    End;

    fetchspecs.Count := Length(refs);

    If fetchspecs.Count > 0 then
      fetchspecs.strings := @refs[0]
    Else
      fetchspecs.strings := nil;

    HandleLibGit2Output('git_remote_fetch', git_remote_fetch(remote, @fetchspecs, @options, nil));
  Finally
    git_remote_free(remote);

    DoLibGit2Call('git_remote_free');
  End;

  Self.UpdateCommitCount(inRemote);
End;

Procedure TAEGitRepository.FillDecorationCache(Const outDecorationCache: TAEGitCommitDecorationCache);
Var
  iterator: Pgit_reference_iterator;
  ref: Pgit_reference;
  commit: Pgit_object;
  oid: Pgit_oid;
  tmp: PAnsiChar;
  sha: Array[0..GIT_OID_SHA1_HEXSIZE + 1] Of AnsiChar;
  branchiterator: Pgit_branch_iterator;
  branchtype: git_branch_t;
Begin
  // Tags

  HandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@iterator, _repo, 'refs/tags/*'));
  Try
    While HandleLibGit2Output('git_reference_next', git_reference_next(@ref, iterator), False) Do
    Try
      HandleLibGit2Output('git_reference_peel', git_reference_peel(@commit, ref, GIT_OBJECT_COMMIT));
      Try
        oid := git_object_id(commit);

        DoLibGit2Call('git_object_id');

        git_oid_tostr(sha, SizeOf(sha), oid);

        DoLibGit2Call('git_oid_tostr');

        tmp := git_reference_shorthand(ref);

        DoLibGit2Call('git_reference_shorthand');

        outDecorationCache.AddItem(String(UTF8String(sha)), dtTag, String(UTF8String(tmp)));
      Finally
        git_object_free(commit);

        DoLibGit2Call('git_object_free');
      End
    Finally
      git_reference_free(ref);
    End;
  Finally
    git_reference_iterator_free(iterator);

    DoLibGit2Call('git_reference_iterator_free');
  End;

  // Branches
  HandleLibGit2Output('git_branch_iterator_new', git_branch_iterator_new(@branchiterator, _repo, GIT_BRANCH_ALL));
  Try
    While HandleLibGit2Output('git_branch_next', git_branch_next(@ref, @branchtype, branchiterator), False) Do
    Try
      HandleLibGit2Output('git_reference_peel', git_reference_peel(@commit, ref, GIT_OBJECT_COMMIT));
      Try
        oid := git_object_id(commit);

        DoLibGit2Call('git_object_id');

        git_oid_tostr(sha, SizeOf(sha), oid);

        DoLibGit2Call('git_oid_tostr');

        HandleLibGit2Output('git_branch_name', git_branch_name(@tmp, ref));

        outDecorationCache.AddItem(String(UTF8String(sha)), dtBranch, String(UTF8String(tmp)));
      Finally
        git_object_free(commit);

        DoLibGit2Call('git_object_free');
      End;
    Finally
      git_reference_free(ref);

      DoLibGit2Call('git_reference_free');
    End;
  Finally
    git_branch_iterator_free(branchiterator);

    DoLibGit2Call('git_branch_iterator_free');
  End;

  // Heads
  HandleLibGit2Output('git_repository_head', git_repository_head(@ref, _repo));
  Try
    HandleLibGit2Output('git_reference_peel', git_reference_peel(@commit, ref, GIT_OBJECT_COMMIT));
    Try
      oid := git_object_id(commit);

      DoLibGit2Call('git_object_id');

      git_oid_tostr(sha, SizeOf(sha), oid);

      DoLibGit2Call('git_oid_tostr');

      outDecorationCache.Head := String(UTF8String(sha));
    Finally
      git_object_free(commit);

      DoLibGit2Call('git_object_free');
    End;
  Finally
    git_reference_free(ref);

    DoLibGit2Call('git_reference_free');
  End;
End;

Procedure TAEGitRepository.SetCurrentBranch(inBranchName: String);
Var
  options: git_checkout_options;
  obj: Pgit_object;
  localbranch, remotebranch: Pgit_reference;
  commit: Pgit_annotated_commit;
  remote: String;
Begin
  If _currentbranch = inBranchName Then
    Exit;

  SplitBranchName(inBranchName, remote);

  HandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));
  options.checkout_strategy := GIT_CHECKOUT_SAFE;

  // Try local branch first
  If Not HandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, _repo, PAnsiChar(UTF8String('refs/heads/' + inBranchName))), False) Then
  Begin
    HandleLibGit2Output('git_reference_lookup', git_reference_lookup(@remotebranch, _repo, PAnsiChar(UTF8String('refs/remotes/' + remote + '/' + inBranchName))));
    Try
      HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@commit, _repo, remotebranch));
      Try
        HandleLibGit2Output('git_branch_create_from_annotated', git_branch_create_from_annotated(@localbranch, _repo, PAnsiChar(UTF8String(inBranchName)), commit, 0));
        Try
          HandleLibGit2Output('git_branch_set_upstream', git_branch_set_upstream(localbranch, PAnsiChar(UTF8String(remote + '/' + inBranchName))));
        Finally
          git_reference_free(localbranch);

          DoLibGit2Call('git_reference_free');
        End;
      Finally
        git_annotated_commit_free(commit);

        DoLibGit2Call('git_annotated_commit_free');
      End;
    Finally
      git_reference_free(remotebranch);

      DoLibGit2Call('git_reference_free');
    End;

    // Now lookup the newly-created local branch
    HandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, _repo, PAnsiChar(UTF8String('refs/heads/' + inBranchName))));
  End;

  Try
    HandleLibGit2Output('git_checkout_tree', git_checkout_tree(_repo, obj, @options));
  Finally
    git_object_free(obj);

    DoLibGit2Call('git_object_free');
  End;

  HandleLibGit2Output('git_repository_set_head', git_repository_set_head(_repo, PAnsiChar(UTF8String('refs/heads/' + inBranchName))));

  _currentbranch := inBranchName;
  // UpdateCurrentBranchName;
End;

Function TAEGitRepository.AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
Var
  utf8user, utf8pass, utf8pubkey, utf8privkey: UTF8String;
  sshuser, sshpass, pubkey, privkey: PAnsiChar;
Begin
  If Not _settings.UserName.IsEmpty Then
  Begin
    utf8user := UTF8String(_settings.UserName);
    sshuser := PAnsiChar(utf8user);
  End
  Else
    sshuser := inUsername;

  If Not _settings.Password.IsEmpty Then
  Begin
    utf8pass := UTF8String(_settings.Password);
    sshpass := PAnsiChar(utf8pass);
  End
  Else
    sshpass := nil;

  If (gaSshKey In inAllowedTypes) And _settings.UseSSHKeyAuth Then
  Begin
    If Not _settings.SSHPublicKey.IsEmpty Then
    Begin
      utf8pubkey := UTF8String(_settings.SSHPublicKey);
      pubkey := PAnsiChar(utf8pubkey);
    End
    Else
      pubkey := nil;

    If Not _settings.SSHPrivateKey.IsEmpty Then
    Begin
      utf8privkey := UTF8String(_settings.SSHPrivateKey);
      privkey := PAnsiChar(utf8privkey);
    End
    Else
      privkey := nil;

    Result := git_credential_ssh_key_new(outGitCredential, sshuser, pubkey, privkey, sshpass);

    DoLibGit2Call('git_credential_ssh_key_new');
  End
  Else If gaUserPassPlainText In inAllowedTypes Then
  Begin
    Result := git_credential_userpass_plaintext_new(outGitCredential, sshuser, sshpass);

    DoLibGit2Call('git_credential_userpass_plaintext_new');
  End
  Else
    Result := -1;
End;

Procedure TAEGitRepository.CloseGitRepository;
Begin
  If Not Assigned(_repo) Then
    Raise EAEGitException.Create(geError, 'git_repository_free', ecInternal, 'The repository is not yet open!');

  git_repository_free(_repo);

  DoLibGit2Call('git_repository_free');

  _repo := nil;
End;

Procedure TAEGitRepository.Rebase_Abort;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
  Try
    HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, _repo, @options));
    Try
      HandleLibGit2Output('git_rebase_abort', git_rebase_abort(rebase));

      HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
    Finally
      git_rebase_free(rebase);

      DoLibGit2Call('git_rebase_free');
    End;
  Finally
    git_signature_free(signature);

    DoLibGit2Call('git_signature_free');
  End;
End;

Procedure TAEGitRepository.DoRebase(Const inRebase: Pgit_rebase; Const inSignature: Pgit_signature);
Var
  rebaseop: Pgit_rebase_operation;
  oid: git_oid;
Begin
  Repeat
    If Not HandleLibGit2Output('git_rebase_next', git_rebase_next(@rebaseop, inRebase), False) Then
      Break;

    If Not SolveConflicts Then
      Raise EAEGitException.Create(geError, 'git_index_has_conflicts', ecRebase, 'Commit has conflicts, rebase aborted!');

    HandleLibGit2Output('git_rebase_commit', git_rebase_commit(@oid, inRebase, nil, inSignature, nil, nil));
  Until False;
End;

Procedure TAEGitRepository.Rebase_Continue;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, _repo, @options));
  Try
    HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
    Try
      DoRebase(rebase, signature);

      HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
    Finally
      git_signature_free(signature);

      DoLibGit2Call('git_signature_free');
    End;
  Finally
    git_rebase_free(rebase);

    DoLibGit2Call('git_rebase_free');
  End;
End;

Function TAEGitRepository.Rebase_InProgress: Boolean;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
Begin
  HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  Result := HandleLibGit2Output('git_rebase_open', git_rebase_open(@rebase, _repo, @options), False);

  If Result Then
  Begin
    git_rebase_free(rebase);

    DoLibGit2Call('git_rebase_free');
  End;
End;

Function TAEGitRepository.ResolveConflictsManually(Const inFileName, inConflictedContent: String): Boolean;
Var
  ourindex, separatorindex, theirindex, a: NativeInt;
  ours, separator, theirs, buf, ourpart, theirpart: String;
  choice: TAEGitBlockConflictChoice;

  Procedure SkipToEOL;
  Var
    tmp: NativeInt;
  Begin
    tmp := inConflictedContent.IndexOf(#10, a);

    If tmp > -1 Then
    Begin
      a := tmp;

      If a < inConflictedContent.Length - 1 Then
        Inc(a);
    End;
  End;
Begin
  Result := False;

  If Assigned(_onmergeconflict) Then
  Begin
    buf := inConflictedContent;

    _onmergeconflict(inFileName, buf, Result);

    If Result Then
      TFile.WriteAllText(inFileName, buf);

    Exit;
  End;

  If Not Assigned(_onblockconflict) Then
    Exit;

  ours := String.Create('<', GIT_MERGE_CONFLICT_MARKER_SIZE);
  separator := String.Create('=', GIT_MERGE_CONFLICT_MARKER_SIZE);
  theirs := String.Create('>', GIT_MERGE_CONFLICT_MARKER_SIZE);

  buf := '';
  theirindex := 0;

  Repeat
    a := theirindex;

    ourindex := inConflictedContent.IndexOf(ours, theirindex);
    separatorindex := inConflictedContent.IndexOf(separator, ourindex);
    theirindex := inConflictedContent.IndexOf(theirs, separatorindex);

    If (ourindex = -1) Or (separatorindex = -1) Or (theirindex = -1) Then
    Begin
      // There's no more header left. Copy the rest of the text into the buffer and leave the cycle

      buf := buf + inConflictedContent.Substring(a, inConflictedContent.Length - a);

      TFile.WriteAllText(inFileName, buf);

      Break;
    End;

    buf := buf + inConflictedContent.Substring(a, ourindex - a);

    a := ourindex;

    SkipToEOL;

    ourpart := inConflictedContent.Substring(a, separatorindex - a);

    a := separatorindex;

    SkipToEOL;

    theirpart := inConflictedContent.Substring(a, theirindex - a);

    a := theirindex;

    SkipToEOL;

    theirindex := a;

    choice := ccAbort;

    _onblockconflict(inFileName, ourpart, theirpart, choice);

    Case choice Of
      ccTheirs:
        buf := buf + theirpart;
      ccOurs:
        buf := buf + ourpart;
      ccAbort:
        Exit;
    End;
  Until False;

  Result := True;
End;

Procedure TAEGitRepository.Revert_Last_Commit(Const inCommitCount: Integer);
Var
  target: Pgit_object;
Begin
  HandleLibGit2Output('git_revparse_single', git_revparse_single(@target, _repo, PAnsiChar(AnsiString('HEAD~' + inCommitCount.ToString))));
  Try
    HandleLibGit2Output('git_reset', git_reset(_repo, target, GIT_RESET_SOFT, nil));
  Finally
    git_object_free(target);

    DoLibGit2Call('git_object_free');
  End;
End;

Constructor TAEGitRepository.Create;
Begin
  inherited;

  _authmethod.Code := @TAEGitRepository.AuthCallBack;
  _authmethod.Data := Self;

  _incomingcommits := 0;
  _outgoingcommits := 0;
  _settings := TAEGitRepositorySettings.Create;

  _onblockconflict := nil;
  _onlibgit2call := nil;
  _onmergeconflict := nil;
  _repo := nil;
  _repodir := '';
End;

Procedure TAEGitRepository.CreateBranch(Const inBranchName: String);
Var
  ref, branch: Pgit_reference;
  commit: Pgit_commit;
Begin
  HandleLibGit2Output('git_repository_head', git_repository_head(@ref, _repo));
  Try
    HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, _repo, git_reference_target(ref)));
    Try
      HandleLibGit2Output('git_branch_create', git_branch_create(@branch, _repo, PAnsiChar(UTF8String(inBranchName)), commit, Ord(False)));

      git_reference_free(branch);

      DoLibGit2Call('git_reference_free');
    Finally
      git_commit_free(Commit);

      DoLibGit2Call('git_commit_free');
    End;
  Finally
    git_reference_free(ref);

    DoLibGit2Call('git_reference_free');
  End;
End;

Procedure TAEGitRepository.DeleteBranch(Const inBranchName: String);
Var
  branch: Pgit_reference;
Begin
  HandleLibGit2Output('git_branch_lookup', git_branch_lookup(@branch, _repo, PAnsiChar(UTF8String(inBranchName)), GIT_BRANCH_LOCAL));
  Try
    HandleLibGit2Output('git_branch_delete', git_branch_delete(branch));
  Finally
    git_reference_free(branch);

    DoLibGit2Call('git_reference_free');
  End;
End;

Destructor TAEGitRepository.Destroy;
Begin
  If Assigned(_repo) Then
    Self.CloseGitRepository;

  FreeAndNil(_settings);

  inherited;
End;

Procedure TAEGitRepository.DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  If Assigned(_onlibgit2call) Then
    _onlibgit2call(Self, inMethod, inErrorCode);
End;

Function TAEGitRepository.BranchList(Const inBranchType: TAEGitBranchType): TArray<String>;
Var
  iterator: Pgit_branch_iterator;
  ref: Pgit_reference;
  branchtypeoutput, branchtypeinput: git_branch_t;
  branchname: PAnsiChar;
Begin
  SetLength(Result, 0);

  Case inBranchType Of
    gbLocal:
      branchtypeinput := GIT_BRANCH_LOCAL;
    gbRemote:
      branchtypeinput := GIT_BRANCH_REMOTE;
    gbAll:
      branchtypeinput := GIT_BRANCH_ALL;
    Else
      Raise ENotImplemented.Create('This branch type is not implemented yet!');
  End;

  HandleLibGit2Output('git_branch_iterator_new', git_branch_iterator_new(@iterator, _repo, branchtypeinput));
  Try
    Repeat
      If Not HandleLibGit2Output('git_branch_next', git_branch_next(@ref, @branchtypeoutput, iterator), False) Then
        Break;

      Try
        If HandleLibGit2Output('git_branch_name', git_branch_name(@branchname, ref), False) Then
        Begin
          SetLength(Result, Length(Result) + 1);

          Result[High(Result)] := String(UTF8String(branchname));
        End;
      Finally
        git_reference_free(ref);

        DoLibGit2Call('git_reference_free');
      End;
    Until False;
  Finally
    git_branch_iterator_free(iterator);

    DoLibGit2Call('git_branch_iterator_free');
  End;
End;

Procedure TAEGitRepository.GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
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
  end;

Begin
  HandleLibGit2Output('git_status_options_init', git_status_options_init(@options, GIT_STATUS_OPTIONS_VERSION));

  options.flags := GIT_STATUS_OPT_INCLUDE_UNTRACKED Or GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS Or GIT_STATUS_OPT_EXCLUDE_SUBMODULES;

  HandleLibGit2Output('git_status_list_new', git_status_list_new(@statuslist, _repo, @options));
  Try
    count := git_status_list_entrycount(statuslist);

    DoLibGit2Call('git_status_list_entrycount');

    For b := 0 To count - 1 Do
    Begin
      status := git_status_byindex(statuslist, b);

      DoLibGit2Call('git_status_byindex');

      If status.status = GIT_STATUS_IGNORED Then
        Continue;

      If (status.status And GIT_STATUS_INDEX_NEW) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedNew);

      If (status.status And GIT_STATUS_INDEX_MODIFIED) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedModified);

      If (status.status And GIT_STATUS_INDEX_DELETED) <> 0 Then
        AddFileStatus(String(UTF8String(status.head_to_index.old_file.path)), gfsStagedDeleted);

      // TODO: During rename we might want to know the old name as well...
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

      // TODO: During rename we might want to know the old name as well...
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

      // This part is not needed as we are filtering this status out, but it might be needed in
      // the future...
      //
      // If status.status = GIT_STATUS_IGNORED Then
      //   If Assigned(status.index_to_workdir) Then
      //     AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsIgnored)
      //   Else
      //     AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsIgnored);
    End;
  Finally
    git_status_list_free(statuslist);

    DoLibGit2Call('git_status_list_free');
  End;
End;

Procedure TAEGitRepository.GetCommitContents(Const outCommitContents: TAEGitCommitContents; Const inCommitHash: String);
Var
  oid: git_oid;
  commit, parent: Pgit_commit;
  tree, parenttree: Pgit_tree;
  count: Cardinal;
  diff: Pgit_diff;
  filecount: size_t;
  a: NativeUInt;
  delta: Pgit_diff_delta;
  patch: Pgit_patch;
  buf: git_buf;
  filename: String;
  filestatus: TAEGitFileStatus;
Begin
  HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(inCommitHash))));

  HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, _repo, @oid));
  Try
    HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
    Try
      count := git_commit_parentcount(commit);

      DoLibGit2Call('git_commit_parentcount');

      If count > 0 Then
      Begin
        HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));

        HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
      End
      Else
      Begin
        commit := nil;
        parenttree := nil;
      End;

      Try
        HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, _repo, parenttree, tree, nil));
        Try
          filecount := git_diff_num_deltas(diff);

          DoLibGit2Call('git_diff_num_deltas');

          For a := 0 To filecount - 1 Do
          Begin
            delta := git_diff_get_delta(diff, a);

            DoLibGit2Call('git_diff_get_delta');

            HandleLibGit2Output('git_patch_from_diff', git_patch_from_diff(@patch, diff, a));
            Try
              HandleLibGit2Output('git_patch_to_buf', git_patch_to_buf(@buf, patch));
              Try
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
                  //GIT_DELTA_CONFLICTED:
                  Else
                    filestatus := gfsConflicted;
                End;

                outCommitContents.Add(filename, TPair<TAEGitFileStatus, String>.Create(filestatus, String(UTF8String(buf.ptr))));
              Finally
                git_buf_dispose(@buf);

                DoLibGit2Call('git_buf_dispose');
              End;
            Finally
              git_patch_free(patch);

              DoLibGit2Call('git_patch_free');
            End;
          End;
        Finally
          git_diff_free(diff);

          DoLibGit2Call('git_diff_free');
        End;
      Finally
        If Assigned(parenttree) Then
        Begin
          git_tree_free(parenttree);

          DoLibGit2Call('git_tree_free');
        End;

        If Assigned(parent) Then
        Begin
          git_commit_free(parent);

          DoLibGit2Call('git_commit_free');
        End;
       End;
    Finally
      git_tree_free(tree);

      DoLibGit2Call('git_tree_free');
    End;
  Finally
    git_commit_free(commit);

    DoLibGit2Call('git_commit_free');
  End;
End;

Procedure TAEGitRepository.GetCommitList(Const outCommitList: TAEGitCommitList; Const inStartCommitHash: String = ''; Const inCommitAmount: Integer = 0);
Var
  walker: Pgit_revwalk;
  startoid, currentoid: git_oid;
  parentoid: Pgit_oid;
  commit: Pgit_commit;
  sha: Array[0..GIT_OID_SHA1_HEXSIZE + 1] Of AnsiChar;
  signature: Pgit_signature;
  parentcount: Cardinal;
  a: NativeInt;
  hash, author, authoremail, committer, committeremail, summary, message: String;
  datetime: TDateTime;
  parentcommits: TArray<String>;
  cache: TAEGitCommitDecorationCache;
Begin
  cache := TAEGitCommitDecorationCache.Create;
  Try
    FillDecorationCache(cache);

    HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walker, _repo));
    Try
      HandleLibGit2Output('git_revwalk_sorting', git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL Or GIT_SORT_TIME));

      If Not inStartCommitHash.IsEmpty Then
      Begin
        HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@startoid, PAnsiChar(UTF8String(inStartCommitHash))));

        HandleLibGit2Output('git_revwalk_push', git_revwalk_push(walker, @startoid));
      End
      Else
      Begin
        HandleLibGit2Output('git_revwalk_push_head', git_revwalk_push_head(walker));

        HandleLibGit2Output('git_revwalk_push_ref', git_revwalk_push_ref(walker, PAnsiChar(UTF8String('refs/remotes/' + GetDefaultRemoteName + '/' + _currentbranch))));
      End;

      While HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@currentoid, walker), False) Do
      Begin
        If (inCommitAmount <> 0) And (outCommitList.Count >= inCommitAmount) Then
          Exit;

        git_oid_tostr(sha, SizeOf(sha), @currentoid);

        DoLibGit2Call('git_oid_tostr');

        If outCommitList.ContainsKey(String(UTF8String(sha))) Then
          Continue;

        HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, _repo, @currentoid));
        Try
          hash := String(UTF8String(sha));

          signature := git_commit_author(commit);

          DoLibGit2Call('git_commit_author');

          author := String(UTF8String(signature^.name_));
          authoremail := String(UTF8String(signature^.email));

          signature := git_commit_committer(commit);

          DoLibGit2Call('git_commit_committer');

          committer := String(UTF8String(signature^.name_));
          committeremail := String(UTF8String(signature^.email));

          summary := String(UTF8String(git_commit_summary(commit)));

          DoLibGit2Call('git_commit_summary');

          message := String(UTF8String(git_commit_message(commit)));

          DoLibGit2Call('git_commit_message');

          If message = summary Then
            message := '';

          datetime := UnixToDateTime(git_commit_time(commit), True);

          DoLibGit2Call('git_commit_time');

          datetime := IncMinute(datetime, git_commit_time_offset(commit));

          DoLibGit2Call('git_commit_time_offset');

          parentcount := git_commit_parentcount(commit);

          DoLibGit2Call('git_commit_parentcount');

          SetLength(parentcommits, parentcount);

          For a := 0 To Integer(parentcount) - 1 Do
          Begin
            parentoid := git_commit_parent_id(commit, a);

            DoLibGit2Call('git_commit_parent_id');

            git_oid_tostr(sha, SizeOf(sha), parentoid);

            DoLibGit2Call('git_oid_tostr');

            parentcommits[a] := String(UTF8String(sha));
          End;

          outCommitList.Add(hash, TAEGitCommit.Create(
            author,
            authoremail,
            committer,
            committeremail,
            hash,
            message,
            summary,
            datetime,
            parentcommits,
            cache.Items(hash, dtTag),
            cache.Items(hash, dtBranch),
            cache.Head = hash)
          );
        Finally
          git_commit_free(commit);

          DoLibGit2Call('git_commit_free');
        End;
      End;
    Finally
      git_revwalk_free(walker);

      DoLibGit2Call('git_revwalk_free');
    End;
  Finally
    FreeAndNil(cache);
  End;
End;

Function TAEGitRepository.GetDefaultRemoteName: String;
Var
  remotes: git_strarray;
Begin
  Result := '';

  HandleLibGit2Output('git_remote_list', git_remote_list(@remotes, _repo));
  Try
    If remotes.Count > 0 Then
      Result := String(UTF8String(remotes.strings^));
  Finally
    git_strarray_dispose(@remotes);

    DoLibGit2Call('git_strarray_dispose');
  End;
End;

Procedure TAEGitRepository.Patch_Apply(Const inPatch: String);
Var
  diff: Pgit_diff;
  options: git_apply_options;
  buf: PAnsiChar;
  utf8patch: UTF8String;
Begin
  HandleLibGit2Output('git_apply_options_init', git_apply_options_init(@options, GIT_APPLY_OPTIONS_VERSION));

  FillChar(buf, SizeOf(buf), 0);

  utf8patch := UTF8String(inPatch);
  buf := PAnsiChar(utf8patch);

  HandleLibGit2Output('git_diff_from_buffer', git_diff_from_buffer(@diff, buf, Length(buf)));
  Try
    HandleLibGit2Output('git_apply', git_apply(_repo, diff, GIT_APPLY_LOCATION_WORKDIR, @options));
  Finally
    git_diff_free(diff);

    DoLibGit2Call('git_diff_free');
  End;
End;

Function TAEGitRepository.Patch_Get(Const inFileName: String; Const inStagedOnly: Boolean): String;
Begin
  Result := Patch_Get([inFileName], inStagedOnly);
End;

Function TAEGitRepository.Patch_Get(Const inFileNames: TArray<String>; Const inStagedOnly: Boolean): String;
Var
  diff: Pgit_diff;
  buf: git_buf;
Begin
  FillChar(buf, SizeOf(buf), 0);

  If inStagedOnly Then
    diff := GetHeadIndexDiff(inFileNames)
  Else
    diff := GetIndexWorkdirDiff(inFileNames);
  Try
    HandleLibGit2Output('git_diff_to_buf', git_diff_to_buf(@buf, diff, GIT_DIFF_FORMAT_PATCH));
    Try
      Result := String(UTF8String(buf.ptr));
    Finally
      git_buf_dispose(@buf);

      DoLibGit2Call('git_buf_dispose');
    End;
  Finally
    git_diff_free(diff);

    DoLibGit2Call('git_diff_free');
  End;
End;

Function TAEGitRepository.GetHeadIndexDiff(Const inFileNames: TArray<String>): Pgit_diff;
Var
  head: Pgit_object;
  tree: Pgit_tree;
  options: git_diff_options;
  utffilenames: TArray<UTF8String>;
  filenames: TArray<PAnsiChar>;
  a: Integer;
Begin
  HandleLibGit2Output('git_revparse_single', git_revparse_single(@head, _repo, 'HEAD'));
  Try
    HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, Pgit_commit(head)));
    Try
      HandleLibGit2Output('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

      SetLength(utffilenames, Length(inFileNames));
      SetLength(filenames, Length(inFileNames));

      For a := Low(inFileNames) To High(inFileNames) Do
      Begin
        utffilenames[a] := UTF8String(inFileNames[a]);
        filenames[a] := PAnsiChar(utffilenames[a]);
      End;

      options.pathspec.count := Length(filenames);
      options.pathspec.strings := @filenames[0];

      HandleLibGit2Output('git_diff_tree_to_index', git_diff_tree_to_index(@Result, _repo, tree, nil, @options));
    Finally
      git_tree_free(tree);

      DoLibGit2Call('git_tree_free');
    End;
  Finally
    git_object_free(head);

    DoLibGit2Call('git_object_free');
  End;
End;

Function TAEGitRepository.GetIndexWorkdirDiff(Const inFileNames: TArray<String>): Pgit_diff;
Var
  options: git_diff_options;
  utffilenames: TArray<UTF8String>;
  filenames: TArray<PAnsiChar>;
  a: Integer;
Begin
  HandleLibGit2Output('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

  SetLength(utffilenames, Length(inFileNames));
  SetLength(filenames, Length(inFileNames));

  For a := Low(inFileNames) To High(inFileNames) Do
  Begin
    utffilenames[a] := UTF8String(inFileNames[a]);
    filenames[a] := PAnsiChar(utffilenames[a]);
  End;

  options.pathspec.count := Length(filenames);
  options.pathspec.strings := @filenames[0];

  HandleLibGit2Output('git_diff_index_to_workdir', git_diff_index_to_workdir(@Result, _repo, nil, @options));
End;

Procedure TAEGitRepository.OpenGitRepository;
Begin
  If Assigned(_repo) Then
    Raise EAEGitException.Create(geUnknown, 'git_repository_open', ecInternal, 'A repository is already open!');

  HandleLibGit2Output('git_repository_open', git_repository_open(@_repo, PAnsiChar(UTF8String(_repodir))));

  Self.UpdateCurrentBranchName;
End;

Procedure TAEGitRepository.PushCommitsToRemote(inRemote: String = '');
Var
  options: git_push_options;
  remote: Pgit_remote;
  callbacks: git_remote_callbacks;
  utf8ref: UTF8String;
  ref: PAnsiChar;
  refarray: git_strarray;
  localref, remoteref: Pgit_reference;
  oid: Pgit_oid;
Begin
  If inRemote.IsEmpty Then
    inRemote := Self.GetDefaultRemoteName;

  HandleLibGit2Output('git_push_options_init', git_push_options_init(@options, GIT_PUSH_OPTIONS_VERSION));
  options.callbacks.payload := @_authmethod;
  options.callbacks.credentials := GitLibAuthCallback;

  HandleLibGit2Output('git_remote_init_callbacks', git_remote_init_callbacks(@callbacks, GIT_REMOTE_CALLBACKS_VERSION));
  callbacks.payload := @_authmethod;
  callbacks.credentials := GitLibAuthCallback;

  utf8ref := UTF8String(Format('+refs/heads/%s:refs/heads/%s', [_currentbranch, _currentbranch]));
  ref := PAnsiChar(utf8ref);
  refarray.strings := @ref;
  refarray.Count := 1;

  HandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, _repo, PAnsiChar(UTF8String(inRemote))));
  Try
    HandleLibGit2Output('git_remote_connect', git_remote_connect(remote, GIT_DIRECTION_PUSH, @callbacks, nil, nil));
    Try
      HandleLibGit2Output('git_remote_push', git_remote_push(remote, @refarray, @options));
      HandleLibGit2Output('git_reference_lookup', git_reference_lookup(@localref, _repo, PAnsiChar(UTF8String('refs/heads/' + _currentbranch))));
      Try
        oid := git_reference_target(LocalRef);
        DoLibGit2Call('git_reference_target');

        If HandleLibGit2Output('git_reference_lookup', git_reference_lookup(@remoteref, _repo, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/' + _currentbranch))), False) Then
        Try
          HandleLibGit2Output('git_reference_set_target', git_reference_set_target(@remoteref, remoteref, oid, nil));
        Finally
          git_reference_free(remoteref);

          DoLibGit2Call('git_reference_free');
        End
        Else
        Try
          HandleLibGit2Output('git_reference_create', git_reference_create(@remoteref, _repo, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/' + _currentbranch)), oid, 0, nil));
        Finally
          git_reference_free(RemoteRef);

          DoLibGit2Call('git_reference_free');
        End;
      Finally
        git_reference_free(LocalRef);

        DoLibGit2Call('git_reference_free');
      End;
    Finally
      HandleLibGit2Output('git_remote_disconnect', git_remote_disconnect(remote));
    End;
  Finally
    git_remote_free(remote);

    DoLibGit2Call('git_remote_free');
  End;
End;

Procedure TAEGitRepository.Rebase(inBranch: String = '');
Var
  remote: String;
  options: git_rebase_options;
  head, ref: Pgit_reference;
  branch, onto: Pgit_annotated_commit;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  SplitBranchName(inBranch, remote);

  If inBranch.IsEmpty Then
    inBranch := remote + '/' + _currentbranch;

  HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
  Try
    HandleLibGit2Output('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    HandleLibGit2Output('git_repository_head', git_repository_head(@head, _repo));

    HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@branch, _repo, head));
    Try
      HandleLibGit2Output('git_branch_lookup', git_branch_lookup(@ref, _repo, PAnsiChar(UTF8String(inBranch)), GIT_BRANCH_ALL));
      Try
        HandleLibGit2Output('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@onto, _repo, ref));
        Try
          HandleLibGit2Output('git_rebase_init', git_rebase_init(@rebase, _repo, branch, nil, onto, @options));
          Try
            DoRebase(rebase, signature);

            HandleLibGit2Output('git_rebase_finish', git_rebase_finish(rebase, signature));
          Finally
            git_rebase_free(rebase);

            DoLibGit2Call('git_rebase_free');
          End;
        Finally
          git_annotated_commit_free(onto);

          DoLibGit2Call('git_annotated_commit_free');
        End
      Finally
        git_reference_free(ref);

        DoLibGit2Call('git_reference_free');
      End;
    Finally
      git_annotated_commit_free(branch);

      DoLibGit2Call('git_annotated_commit_free');
    End;
  Finally
    git_signature_free(signature);

    DoLibGit2Call('git_signature_free');
  End;
End;

Procedure TAEGitRepository.SetRepoDir(Const inRepoDir: String);
Begin
  If inRepoDir = _repodir Then
    Exit;

  If Assigned(_repo) Then
    Self.CloseGitRepository;

  _repodir := inRepoDir;

  Self.OpenGitRepository;
End;

Function TAEGitRepository.SolveConflicts: Boolean;
Var
  index: Pgit_index;
  iterator: Pgit_index_conflict_iterator;
  ancestor, ours, theirs: Pgit_index_entry;
  mergeresult: git_merge_file_result;
Begin
  Result := True;

  HandleLibGit2Output('git_repository_index', git_repository_index(@index, _repo));
  Try
    HandleLibGit2Output('git_index_read', git_index_read(index, 1));

    If Not HandleLibGit2Output('git_index_has_conflicts', git_index_has_conflicts(index), False) Then
      Exit;

    HandleLibGit2Output('git_index_conflict_iterator_new', git_index_conflict_iterator_new(@iterator, index));
    Try
      While HandleLibGit2Output('git_index_conflict_next', git_index_conflict_next(@ancestor, @ours, @theirs, iterator), False) Do
      Begin
        HandleLibGit2Output('git_merge_file_from_index', git_merge_file_from_index(@mergeresult, _repo, ancestor, ours, theirs, nil));
        Try
          Result := mergeresult.automergeable <> 0;

          If Result Then
          Begin
            TFile.WriteAllText(String(UTF8String(ours^.path)), String(UTF8String(mergeresult.ptr)));

            HandleLibGit2Output('git_index_add_bypath', git_index_add_bypath(index, ours^.path));

            HandleLibGit2Output('git_index_write', git_index_write(index));
          End
          Else If ResolveConflictsManually(String(UTF8String(ours^.path)), String(UTF8String(mergeresult.ptr))) Then
          Begin
            HandleLibGit2Output('git_index_add_bypath', git_index_add_bypath(index, ours^.path));

            HandleLibGit2Output('git_index_write', git_index_write(index));
          End;
        Finally
          git_merge_file_result_free(@mergeresult);

          DoLibGit2Call('git_merge_file_result_free');
        End;
      End;
    Finally
      git_index_conflict_iterator_free(iterator);

      DoLibGit2Call('git_index_conflict_iterator_free');
    End;
  Finally
    git_index_free(index);

    DoLibGit2Call('git_index_free');
  End;
End;

Procedure TAEGitRepository.SplitBranchName(Var outBranchName: String; Var outRemote: String);
Begin
  If outBranchName.Contains('/') Then
  Begin
    outRemote := outBranchName.Substring(0, outBranchName.IndexOf('/'));

    outBranchName := outBranchName.Substring(outBranchName.IndexOf('/') + 1);
  End
  Else
    outRemote := Self.GetDefaultRemoteName;
End;

Procedure TAEGitRepository.CommitStagedFiles(Const inCommitMessage: String);
var
  index: Pgit_index;
  tree: Pgit_tree;
  treeoid, parentoid, commitoid: git_oid;
  parentcommit: Pgit_commit;
  parents: PPgit_commit;
  parentsarray: array[0..0] of Pgit_commit;
  signature: Pgit_signature;
  parentcount: Integer;
begin
  HandleLibGit2Output('git_repository_index', git_repository_index(@index, _repo));
  Try
    HandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeoid, index));
  Finally
    git_index_free(index);

    DoLibGit2Call('git_index_free');
  End;

  HandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, _repo, @treeoid));
  Try
    parentcount := 0;
    parents := nil;
    Try
      If HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@parentoid, _repo, 'HEAD'), False) And
         HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@parentcommit, _repo, @parentoid), False) Then
      Begin
        parentsarray[0] := parentcommit;
        parents := @parentsarray[0];
        parentcount := 1;
      End;

      HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
      Try
        HandleLibGit2Output('git_commit_create',
          git_commit_create(
            @commitoid,
            _repo,
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

        DoLibGit2Call('git_signature_free');
      End;
    Finally
      If Assigned(parentcommit) then
      Begin
        git_commit_free(parentcommit);

        DoLibGit2Call('git_commit_free');
      End;
    End;
  Finally
    // tree might be nil in normal operations...?
    git_tree_free(tree);

    DoLibGit2Call('git_tree_free');
  End;
End;

initialization
  InitLibGit2;

finalization
  ShutdownLibgit2;

End.
