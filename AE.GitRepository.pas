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
    _ongitlibcall: TAEGitLibCallLogEvent;
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
    Procedure DoGitLibCall(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
    Procedure OpenGitRepository;
    Procedure SplitBranchName(Var outBranchName: String; Var outRemote: String);
    Procedure UpdateCommitCount(Const inRemote: String);
    Function AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer; Virtual;
    Function GetDefaultRemoteName: String;
    Function HandleGitLibOutput(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
  public
    Constructor Create; ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure CommitStagedFiles(Const inCommitMessage: String);
    Procedure CreateBranch(Const inBranchName: String);
    Procedure DeleteBranch(Const inBranchName: String);
    Procedure GetChangedFiles(Const inChangedFiles: TAEGitChangedFileList);
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
    Property OnGitLibCall: TAEGitLibCallLogEvent Read _ongitlibcall Write _ongitlibcall;
    Property OutgoingCommits: Integer Read _outgoingcommits;
    Property Settings: TAEGitRepositorySettings Read _settings;
  End;

Implementation

Uses AE.GitRepository.Exception, System.IOUtils, WinApi.Windows;

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

  Result := TGitLibAuthCallback(PMethod(payload)^)(out_, url, username_from_url, types);
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
  pathstrings: PAnsiChar;
Begin
  pathstrings := PAnsiChar(UTF8String(inFileName.Replace('\', '/')));
  HandleGitLibOutput('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_FORCE Or GIT_CHECKOUT_REMOVE_UNTRACKED Or GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH;
  options.paths.count := 1;
  options.paths.strings := @pathstrings;

  HandleGitLibOutput('git_checkout_tree', git_checkout_tree(_repo, nil, @options));
End;

Procedure TAEGitRepository.UnstageFile(Const inFileName: String);
Var
  target: Pgit_object;
  pathspec: git_strarray;
  filename: PAnsiChar;
Begin
  HandleGitLibOutput('git_revparse_single', git_revparse_single(@target, _repo, 'HEAD'));
  Try
    filename := PAnsiChar(UTF8String(inFileName));
    pathspec.count := 1;
    pathspec.strings := @filename;

    HandleGitLibOutput('git_reset_default', git_reset_default(_repo, target, @pathspec));
  Finally
    git_object_free(target);

    DoGitLibCall('git_object_free');
  End;
End;

Procedure TAEGitRepository.StageFile(Const inFileName: String);
Var
  index: Pgit_index;
Begin
  HandleGitLibOutput('git_repository_index', git_repository_index(@index, _repo));
  Try
    HandleGitLibOutput('git_index_add_bypath', git_index_add_bypath(index, PAnsiChar(UTF8String(inFileName.Replace('\', '/')))));

    HandleGitLibOutput('git_index_write', git_index_write(index));
  Finally
    git_index_free(index);

    DoGitLibCall('git_index_free');
  End;
End;

Procedure TAEGitRepository.Stash_Drop(Const inStashIndex: Integer);
Begin
  HandleGitLibOutput('git_stash_drop', git_stash_drop(_repo, size_t(inStashIndex)));
End;

Procedure TAEGitRepository.Stash_List(Const inStashList: TAEGitStashList);
Begin
  HandleGitLibOutput('git_stash_foreach', git_stash_foreach(_repo, @GitLibStashListCallback, @inStashList));
End;

Procedure TAEGitRepository.Stash_Pop(Const inStashIndex: Integer);
Var
  options: git_stash_apply_options;
Begin
  HandleGitLibOutput('git_stash_apply_options_init', git_stash_apply_options_init(@options, GIT_STASH_APPLY_OPTIONS_VERSION));
  options.flags := 0;

  HandleGitLibOutput('git_stash_pop', git_stash_pop(_repo, size_t(inStashIndex), @options));
End;

Procedure TAEGitRepository.Stash_Push(Const inStashMessage: String);
Var
  signature: Pgit_signature;
  oid: git_oid;
Begin
  HandleGitLibOutput('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
  Try
    HandleGitLibOutput('git_stash_save', git_stash_save(@oid, _repo, signature, PAnsiChar(UTF8String(inStashMessage)), GIT_STASH_INCLUDE_UNTRACKED));
  Finally
    git_signature_free(signature);

    DoGitLibCall('git_signature_free');
  End;
End;

Function TAEGitRepository.HandleGitLibOutput(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
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

  DoGitLibCall(inMethod, errorcode);

  Result := errorcode = geOK;

  If Not Result And inRaiseException Then
  Begin
    err := git_error_last;

    DoGitLibCall('git_error_last');

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

  If HandleGitLibOutput('git_repository_head', git_repository_head(@ref, _repo), False) Then
  Try
    If HandleGitLibOutput('git_reference_is_branch', git_reference_is_branch(ref), False) Then
    Begin
      // Detached HEAD

      oid := git_reference_target(ref);

      DoGitLibCall('git_reference_target');

      If Assigned(oid) Then
      Begin
        _currentbranch := String(UTF8String(git_oid_tostr_s(oid)));

        DoGitLibCall('git_oid_tostr_s');
      End;
    End
    Else
    If HandleGitLibOutput('git_branch_name', git_branch_name(@tmp, ref), False) Then
        _currentbranch := String(UTF8String(tmp));
  Finally
    git_reference_free(ref);

    DoGitLibCall('git_reference_free');
  End
  Else
  Begin
    // Try HEAD for worktree

    If HandleGitLibOutput('git_repository_head_for_worktree', git_repository_head_for_worktree(@ref, _repo, nil), False) Then
    Try
      tmp := git_reference_shorthand(ref);

      DoGitLibCall('git_reference_shorthand');

      If Assigned(tmp) Then
        _currentbranch := String(UTF8String(tmp));
    Finally
      git_reference_free(ref);

      DoGitLibCall('git_reference_free');
    End
    Else
    Begin
      // Manually read the symbolic HEAD

      s := String(UTF8String(git_repository_workdir(_repo))).Replace('/', PathDelim);

      DoGitLibCall('git_repository_workdir');

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

    HandleGitLibOutput('git_config_open_default', git_config_open_default(@cfg));
    Try
      tmp := nil;

      If HandleGitLibOutput('git_config_get_string', git_config_get_string(@tmp, cfg, 'init.defaultBranch'), False) Then
        _currentbranch := String(UTF8String(tmp));
    Finally
      git_config_free(cfg);

      DoGitLibCall('git_config_free');
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
  HandleGitLibOutput('git_reference_name_to_id', git_reference_name_to_id(@localoid, _repo, PAnsiChar(UTF8String('refs/heads/' + _currentbranch))));

  HandleGitLibOutput('git_repository_head', git_repository_head(@headref, _repo));
  Try
    If HandleGitLibOutput('git_branch_upstream', git_branch_upstream(@remoteref, headref), False) Then
    Try
      remote := git_reference_name(remoteref);

      DoGitLibCall('git_reference_name');

      If HandleGitLibOutput('git_reference_name_to_id', git_reference_name_to_id(@remoteoid, _repo, remote), False) Then
      Begin
        // Remote branch exist, use git_graph_ahead_behind
        HandleGitLibOutput('git_graph_ahead_behind', git_graph_ahead_behind(@ahead, @behind, _repo, @localoid, @remoteoid));

        _incomingcommits := behind;
        _outgoingcommits := ahead;
      End
    Finally
      git_reference_free(remoteref);

      DoGitLibCall('git_reference_free');
    End
    Else
    Begin
      // Remote branch does not exist. There can't be incoming commits, for outgoing count the commits unreachable on
      // other branches
      _incomingcommits := -1;
      _outgoingcommits := 0;

      HandleGitLibOutput('git_revwalk_new', git_revwalk_new(@walk, _repo));
      Try
        HandleGitLibOutput('git_revwalk_push', git_revwalk_push(walk, @localoid));

        HandleGitLibOutput('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@refiterator, _repo, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/*'))));
        Try
          While HandleGitLibOutput('git_reference_next', git_reference_next(@ref, refiterator), False) Do
          Begin
            Try
              // Skip symbolic refs such as refs/remotes/origin/HEAD
              a := git_reference_type(ref);

              DoGitLibCall('git_reference_type');

              If a = GIT_REFERENCE_DIRECT Then
              Begin
                remoteoid := git_reference_target(Ref)^;

                DoGitLibCall('git_reference_target');

                HandleGitLibOutput('git_revwalk_hide', git_revwalk_hide(walk, @remoteoid));
              End;
            Finally
              git_reference_free(ref);

              DoGitLibCall('git_reference_free');
            End;
          End;
        Finally
          git_reference_iterator_free(refiterator);

          DoGitLibCall('git_reference_iterator_free');
        End;

        While HandleGitLibOutput('git_revwalk_next', git_revwalk_next(@walkoid, walk), False) Do
          Inc(_outgoingcommits);
      Finally
        git_revwalk_free(Walk);

        DoGitLibCall('git_revwalk_free');
      End;
    End;
  Finally
    git_reference_free(headref);

    DoGitLibCall('git_reference_free');
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

  HandleGitLibOutput('git_remote_lookup', git_remote_lookup(@remote, _repo, PAnsiChar(UTF8String(inRemote))));
  Try
    HandleGitLibOutput('git_fetch_options_init', git_fetch_options_init(@options, GIT_FETCH_OPTIONS_VERSION));

    options.callbacks.payload := @_authmethod;
    options.callbacks.credentials := GitLibAuthCallback;

    If inDownloadTags Then
      options.download_tags := GIT_REMOTE_DOWNLOAD_TAGS_ALL;

    HandleGitLibOutput('git_remote_get_fetch_refspecs', git_remote_get_fetch_refspecs(@specs, remote));
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

      DoGitLibCall('git_strarray_dispose');
    End;

    fetchspecs.Count := Length(refs);

    If fetchspecs.Count > 0 then
      fetchspecs.strings := @refs[0]
    Else
      fetchspecs.strings := nil;

    HandleGitLibOutput('git_remote_fetch', git_remote_fetch(remote, @fetchspecs, @options, nil));
  Finally
    git_remote_free(remote);

    DoGitLibCall('git_remote_free');
  End;

  Self.UpdateCommitCount(inRemote);
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

  HandleGitLibOutput('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));
  options.checkout_strategy := GIT_CHECKOUT_SAFE;

  // Try local branch first
  If Not HandleGitLibOutput('git_revparse_single', git_revparse_single(@obj, _repo, PAnsiChar(UTF8String('refs/heads/' + inBranchName))), False) Then
  Begin
    HandleGitLibOutput('git_reference_lookup', git_reference_lookup(@remotebranch, _repo, PAnsiChar(UTF8String('refs/remotes/' + remote + '/' + inBranchName))));
    Try
      HandleGitLibOutput('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@commit, _repo, remotebranch));
      Try
        HandleGitLibOutput('git_branch_create_from_annotated', git_branch_create_from_annotated(@localbranch, _repo, PAnsiChar(UTF8String(inBranchName)), commit, 0));
        Try
          HandleGitLibOutput('git_branch_set_upstream', git_branch_set_upstream(localbranch, PAnsiChar(UTF8String(remote + '/' + inBranchName))));
        Finally
          git_reference_free(localbranch);

          DoGitLibCall('git_reference_free');
        End;
      Finally
        git_annotated_commit_free(commit);

        DoGitLibCall('git_annotated_commit_free');
      End;
    Finally
      git_reference_free(remotebranch);

      DoGitLibCall('git_reference_free');
    End;

    // Now lookup the newly-created local branch
    HandleGitLibOutput('git_revparse_single', git_revparse_single(@obj, _repo, PAnsiChar(UTF8String('refs/heads/' + inBranchName))));
  End;

  Try
    HandleGitLibOutput('git_checkout_tree', git_checkout_tree(_repo, obj, @options));
  Finally
    git_object_free(obj);

    DoGitLibCall('git_object_free');
  End;

  HandleGitLibOutput('git_repository_set_head', git_repository_set_head(_repo, PAnsiChar(UTF8String('refs/heads/' + inBranchName))));

  _currentbranch := inBranchName;
  // UpdateCurrentBranchName;
End;

Function TAEGitRepository.AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
Var
  sshuser, sshpass, pubkey, privkey: PAnsiChar;
Begin
  If Not _settings.UserName.IsEmpty Then
    sshuser := PAnsiChar(UTF8String(_settings.UserName))
  Else
    sshuser := inUsername;

  If Not _settings.Password.IsEmpty Then
    sshpass := PAnsiChar(UTF8String(_settings.Password))
  Else
    sshpass := nil;

  If (gaSshKey In inAllowedTypes) And _settings.UseSSHKeyAuth Then
  Begin
    If Not _settings.SSHPublicKey.IsEmpty Then
      pubkey := PAnsiChar(UTF8String(_settings.SSHPublicKey))
    Else
      pubkey := nil;

    If Not _settings.SSHPrivateKey.IsEmpty Then
      privkey := PAnsiChar(UTF8String(_settings.SSHPrivateKey))
    Else
      privkey := nil;

    Result := git_credential_ssh_key_new(outGitCredential, sshuser, pubkey, privkey, sshpass);

    DoGitLibCall('git_credential_ssh_key_new');
  End
  Else If gaUserPassPlainText In inAllowedTypes Then
  Begin
    Result := git_credential_userpass_plaintext_new(outGitCredential, sshuser, sshpass);

    DoGitLibCall('git_credential_userpass_plaintext_new');
  End
  Else
    Result := -1;
End;

Procedure TAEGitRepository.CloseGitRepository;
Begin
  If Not Assigned(_repo) Then
    Raise EAEGitException.Create(geError, 'git_repository_free', ecInternal, 'The repository is not yet open!');

  git_repository_free(_repo);

  DoGitLibCall('git_repository_free');

  _repo := nil;
End;

Procedure TAEGitRepository.Rebase_Abort;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  HandleGitLibOutput('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  HandleGitLibOutput('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
  Try
    HandleGitLibOutput('git_rebase_open', git_rebase_open(@rebase, _repo, @options));
    Try
      HandleGitLibOutput('git_rebase_abort', git_rebase_abort(rebase));

      HandleGitLibOutput('git_rebase_finish', git_rebase_finish(rebase, signature));
    Finally
      git_rebase_free(rebase);

      DoGitLibCall('git_rebase_free');
    End;
  Finally
    git_signature_free(signature);

    DoGitLibCall('git_signature_free');
  End;
End;

Procedure TAEGitRepository.DoRebase(Const inRebase: Pgit_rebase; Const inSignature: Pgit_signature);
Var
  rebaseop: Pgit_rebase_operation;
  index: Pgit_index;
  oid: git_oid;
Begin
  Repeat
    If Not HandleGitLibOutput('git_rebase_next', git_rebase_next(@rebaseop, inRebase), False) Then
      Break;

    HandleGitLibOutput('git_repository_index', git_repository_index(@index, _repo));
    Try
      If git_index_has_conflicts(index) <> 0 Then
        Raise EAEGitException.Create(geError, 'git_index_has_conflicts', ecRebase, 'Commit has conflicts, rebase aborted!');
    Finally
      DoGitLibCall('git_index_has_conflicts');

      git_index_free(index);

      DoGitLibCall('git_index_free');
    End;

    HandleGitLibOutput('git_rebase_commit', git_rebase_commit(@oid, inRebase, nil, inSignature, nil, nil));
  Until False;
End;

Procedure TAEGitRepository.Rebase_Continue;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
  signature: Pgit_signature;
Begin
  HandleGitLibOutput('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  HandleGitLibOutput('git_rebase_open', git_rebase_open(@rebase, _repo, @options));
  Try
    HandleGitLibOutput('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
    Try
      DoRebase(rebase, signature);

      HandleGitLibOutput('git_rebase_finish', git_rebase_finish(rebase, signature));
    Finally
      git_signature_free(signature);

      DoGitLibCall('git_signature_free');
    End;
  Finally
    git_rebase_free(rebase);

    DoGitLibCall('git_rebase_free');
  End;
End;

Function TAEGitRepository.Rebase_InProgress: Boolean;
Var
  options: git_rebase_options;
  rebase: Pgit_rebase;
Begin
  HandleGitLibOutput('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

  Result := HandleGitLibOutput('git_rebase_open', git_rebase_open(@rebase, _repo, @options), False);

  If Result Then
  Begin
    git_rebase_free(rebase);

    DoGitLibCall('git_rebase_free');
  End;
End;

Procedure TAEGitRepository.Revert_Last_Commit(Const inCommitCount: Integer);
Var
  target: Pgit_object;
Begin
  HandleGitLibOutput('git_revparse_single', git_revparse_single(@target, _repo, PAnsiChar(AnsiString('HEAD~' + inCommitCount.ToString))));
  Try
    HandleGitLibOutput('git_reset', git_reset(_repo, target, GIT_RESET_SOFT, nil));
  Finally
    git_object_free(target);

    DoGitLibCall('git_object_free');
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

  _ongitlibcall := nil;
  _repo := nil;
  _repodir := '';
End;

Procedure TAEGitRepository.CreateBranch(Const inBranchName: String);
Var
  ref, branch: Pgit_reference;
  commit: Pgit_commit;
Begin
  HandleGitLibOutput('git_repository_head', git_repository_head(@ref, _repo));
  Try
    HandleGitLibOutput('git_commit_lookup', git_commit_lookup(@commit, _repo, git_reference_target(ref)));
    Try
      HandleGitLibOutput('git_branch_create', git_branch_create(@branch, _repo, PAnsiChar(UTF8String(inBranchName)), commit, Ord(False)));

      git_reference_free(branch);

      DoGitLibCall('git_reference_free');
    Finally
      git_commit_free(Commit);

      DoGitLibCall('git_commit_free');
    End;
  Finally
    git_reference_free(ref);

    DoGitLibCall('git_reference_free');
  End;
End;

Procedure TAEGitRepository.DeleteBranch(Const inBranchName: String);
Var
  branch: Pgit_reference;
Begin
  HandleGitLibOutput('git_branch_lookup', git_branch_lookup(@branch, _repo, PAnsiChar(UTF8String(inBranchName)), GIT_BRANCH_LOCAL));
  Try
    HandleGitLibOutput('git_branch_delete', git_branch_delete(branch));
  Finally
    git_reference_free(branch);

    DoGitLibCall('git_reference_free');
  End;
End;

Destructor TAEGitRepository.Destroy;
Begin
  If Assigned(_repo) Then
    Self.CloseGitRepository;

  FreeAndNil(_settings);

  inherited;
End;

Procedure TAEGitRepository.DoGitLibCall(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  If Assigned(_ongitlibcall) Then
    _ongitlibcall(Self, inMethod, inErrorCode);
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

  HandleGitLibOutput('git_branch_iterator_new', git_branch_iterator_new(@iterator, _repo, branchtypeinput));
  Try
    Repeat
      If Not HandleGitLibOutput('git_branch_next', git_branch_next(@ref, @branchtypeoutput, iterator), False) Then
        Break;

      Try
        If HandleGitLibOutput('git_branch_name', git_branch_name(@branchname, ref), False) Then
        Begin
          SetLength(Result, Length(Result) + 1);

          Result[High(Result)] := String(UTF8String(branchname));
        End;
      Finally
        git_reference_free(ref);

        DoGitLibCall('git_reference_free');
      End;
    Until False;
  Finally
    git_branch_iterator_free(iterator);

    DoGitLibCall('git_branch_iterator_free');
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
  HandleGitLibOutput('git_status_options_init', git_status_options_init(@options, GIT_STATUS_OPTIONS_VERSION));

  options.flags := GIT_STATUS_OPT_INCLUDE_UNTRACKED Or GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS Or GIT_STATUS_OPT_EXCLUDE_SUBMODULES;

  HandleGitLibOutput('git_status_list_new', git_status_list_new(@statuslist, _repo, @options));
  Try
    count := git_status_list_entrycount(statuslist);

    DoGitLibCall('git_status_list_entrycount');

    For b := 0 To count - 1 Do
    Begin
      status := git_status_byindex(statuslist, b);

      DoGitLibCall('git_status_byindex');

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

    DoGitLibCall('git_status_list_free');
  End;
End;

Function TAEGitRepository.GetDefaultRemoteName: String;
Var
  remotes: git_strarray;
Begin
  Result := '';

  HandleGitLibOutput('git_remote_list', git_remote_list(@remotes, _repo));
  Try
    If remotes.Count > 0 Then
      Result := String(UTF8String(remotes.strings^));
  Finally
    git_strarray_dispose(@remotes);

    DoGitLibCall('git_strarray_dispose');
  End;
End;

Procedure TAEGitRepository.Patch_Apply(Const inPatch: String);
Var
  diff: Pgit_diff;
  options: git_apply_options;
  buf: PAnsiChar;
Begin
  HandleGitLibOutput('git_apply_options_init', git_apply_options_init(@options, GIT_APPLY_OPTIONS_VERSION));

  FillChar(buf, SizeOf(buf), 0);

  buf := PAnsiChar(UTF8String(inPatch));

  HandleGitLibOutput('git_diff_from_buffer', git_diff_from_buffer(@diff, buf, Length(buf)));
  Try
    HandleGitLibOutput('git_apply', git_apply(_repo, diff, GIT_APPLY_LOCATION_WORKDIR, @options));
  Finally
    git_diff_free(diff);

    DoGitLibCall('git_diff_free');
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
    HandleGitLibOutput('git_diff_to_buf', git_diff_to_buf(@buf, diff, GIT_DIFF_FORMAT_PATCH));
    Try
      Result := String(UTF8String(buf.ptr));
    Finally
      git_buf_dispose(@buf);

      DoGitLibCall('git_buf_dispose');
    End;
  Finally
    git_diff_free(diff);

    DoGitLibCall('git_diff_free');
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
  HandleGitLibOutput('git_revparse_single', git_revparse_single(@head, _repo, 'HEAD'));
  Try
    HandleGitLibOutput('git_commit_tree', git_commit_tree(@tree, Pgit_commit(head)));
    Try
      HandleGitLibOutput('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

      SetLength(utffilenames, Length(inFileNames));
      SetLength(filenames, Length(inFileNames));

      For a := Low(inFileNames) To High(inFileNames) Do
      Begin
        utffilenames[a] := UTF8String(inFileNames[a]);
        filenames[a] := PAnsiChar(utffilenames[a]);
      End;

      options.pathspec.count := Length(filenames);
      options.pathspec.strings := @filenames[0];

      HandleGitLibOutput('git_diff_tree_to_index', git_diff_tree_to_index(@Result, _repo, tree, nil, @options));
    Finally
      git_tree_free(tree);

      DoGitLibCall('git_tree_free');
    End;
  Finally
    git_object_free(head);

    DoGitLibCall('git_object_free');
  End;
End;

Function TAEGitRepository.GetIndexWorkdirDiff(Const inFileNames: TArray<String>): Pgit_diff;
Var
  options: git_diff_options;
  utffilenames: TArray<UTF8String>;
  filenames: TArray<PAnsiChar>;
  a: Integer;
Begin
  HandleGitLibOutput('git_diff_options_init', git_diff_options_init(@options, GIT_DIFF_OPTIONS_VERSION));

  SetLength(utffilenames, Length(inFileNames));
  SetLength(filenames, Length(inFileNames));

  For a := Low(inFileNames) To High(inFileNames) Do
  Begin
    utffilenames[a] := UTF8String(inFileNames[a]);
    filenames[a] := PAnsiChar(utffilenames[a]);
  End;

  options.pathspec.count := Length(filenames);
  options.pathspec.strings := @filenames[0];

  HandleGitLibOutput('git_diff_index_to_workdir', git_diff_index_to_workdir(@Result, _repo, nil, @options));
End;

Procedure TAEGitRepository.OpenGitRepository;
Begin
  If Assigned(_repo) Then
    Raise EAEGitException.Create(geUnknown, 'git_repository_open', ecInternal, 'A repository is already open!');

  HandleGitLibOutput('git_repository_open', git_repository_open(@_repo, PAnsiChar(UTF8String(_repodir))));

  Self.UpdateCurrentBranchName;
End;

Procedure TAEGitRepository.PushCommitsToRemote(inRemote: String = '');
Var
  options: git_push_options;
  remote: Pgit_remote;
  callbacks: git_remote_callbacks;
  ref: PAnsiChar;
  refarray: git_strarray;
  localref, remoteref: Pgit_reference;
  oid: Pgit_oid;
Begin
  If inRemote.IsEmpty Then
    inRemote := Self.GetDefaultRemoteName;

  HandleGitLibOutput('git_push_options_init', git_push_options_init(@options, GIT_PUSH_OPTIONS_VERSION));
  options.callbacks.payload := @_authmethod;
  options.callbacks.credentials := GitLibAuthCallback;

  HandleGitLibOutput('git_remote_init_callbacks', git_remote_init_callbacks(@callbacks, GIT_REMOTE_CALLBACKS_VERSION));
  callbacks.payload := @_authmethod;
  callbacks.credentials := GitLibAuthCallback;

  ref := PAnsiChar(UTF8String(Format('+refs/heads/%s:refs/heads/%s', [_currentbranch, _currentbranch])));
  refarray.strings := @ref;
  refarray.Count := 1;

  HandleGitLibOutput('git_remote_lookup', git_remote_lookup(@remote, _repo, PAnsiChar(UTF8String(inRemote))));
  Try
    HandleGitLibOutput('git_remote_connect', git_remote_connect(remote, GIT_DIRECTION_PUSH, @callbacks, nil, nil));
    Try
      HandleGitLibOutput('git_remote_push', git_remote_push(remote, @refarray, @options));
      HandleGitLibOutput('git_reference_lookup', git_reference_lookup(@localref, _repo, PAnsiChar(UTF8String('refs/heads/' + _currentbranch))));
      Try
        oid := git_reference_target(LocalRef);
        DoGitLibCall('git_reference_target');

        If HandleGitLibOutput('git_reference_lookup', git_reference_lookup(@remoteref, _repo, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/' + _currentbranch))), False) Then
        Try
          HandleGitLibOutput('git_reference_set_target', git_reference_set_target(@remoteref, remoteref, oid, nil));
        Finally
          git_reference_free(remoteref);

          DoGitLibCall('git_reference_free');
        End
        Else
        Try
          HandleGitLibOutput('git_reference_create', git_reference_create(@remoteref, _repo, PAnsiChar(UTF8String('refs/remotes/' + inRemote + '/' + _currentbranch)), oid, 0, nil));
        Finally
          git_reference_free(RemoteRef);

          DoGitLibCall('git_reference_free');
        End;
      Finally
        git_reference_free(LocalRef);

        DoGitLibCall('git_reference_free');
      End;
    Finally
      HandleGitLibOutput('git_remote_disconnect', git_remote_disconnect(remote));
    End;
  Finally
    git_remote_free(remote);

    DoGitLibCall('git_remote_free');
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

  HandleGitLibOutput('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
  Try
    HandleGitLibOutput('git_rebase_options_init', git_rebase_options_init(@options, GIT_REBASE_OPTIONS_VERSION));

    HandleGitLibOutput('git_repository_head', git_repository_head(@head, _repo));

    HandleGitLibOutput('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@branch, _repo, head));
    Try
      HandleGitLibOutput('git_branch_lookup', git_branch_lookup(@ref, _repo, PAnsiChar(UTF8String(inBranch)), GIT_BRANCH_ALL));
      Try
        HandleGitLibOutput('git_annotated_commit_from_ref', git_annotated_commit_from_ref(@onto, _repo, ref));
        Try
          HandleGitLibOutput('git_rebase_init', git_rebase_init(@rebase, _repo, branch, nil, onto, @options));
          Try
            DoRebase(rebase, signature);

            HandleGitLibOutput('git_rebase_finish', git_rebase_finish(rebase, signature));
          Finally
            git_rebase_free(rebase);

            DoGitLibCall('git_rebase_free');
          End;
        Finally
          git_annotated_commit_free(onto);

          DoGitLibCall('git_annotated_commit_free');
        End
      Finally
        git_reference_free(ref);

        DoGitLibCall('git_reference_free');
      End;
    Finally
      git_annotated_commit_free(branch);

      DoGitLibCall('git_annotated_commit_free');
    End;
  Finally
    git_signature_free(signature);

    DoGitLibCall('git_signature_free');
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
  HandleGitLibOutput('git_repository_index', git_repository_index(@index, _repo));
  Try
    HandleGitLibOutput('git_index_write_tree', git_index_write_tree(@treeoid, index));
  Finally
    git_index_free(index);

    DoGitLibCall('git_index_free');
  End;

  HandleGitLibOutput('git_tree_lookup', git_tree_lookup(@tree, _repo, @treeoid));
  Try
    parentcount := 0;
    parents := nil;
    Try
      If HandleGitLibOutput('git_reference_name_to_id', git_reference_name_to_id(@parentoid, _repo, 'HEAD'), False) And
         HandleGitLibOutput('git_commit_lookup', git_commit_lookup(@parentcommit, _repo, @parentoid), False) Then
      Begin
        parentsarray[0] := parentcommit;
        parents := @parentsarray[0];
        parentcount := 1;
      End;

      HandleGitLibOutput('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(_settings.FullName)), PAnsiChar(UTF8String(_settings.EMailAddress))));
      Try
        HandleGitLibOutput('git_commit_create',
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

        DoGitLibCall('git_signature_free');
      End;
    Finally
      If Assigned(parentcommit) then
      Begin
        git_commit_free(parentcommit);

        DoGitLibCall('git_commit_free');
      End;
    End;
  Finally
    // tree might be nil in normal operations...?
    git_tree_free(tree);

    DoGitLibCall('git_tree_free');
  End;
End;

initialization
  InitLibGit2;

finalization
  ShutdownLibgit2;

End.
