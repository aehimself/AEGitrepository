{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository;

Interface

Uses libgit2, AE.GitRepository.TypeDef, AE.GitRepository.Settings, AE.GitRepository.Context, AE.GitRepository.Branches,
     AE.GitRepository.Stashes, AE.GitRepository.WorkTree, AE.GitRepository.CommitDecorationCache;

Type
  TAEGitRepository = Class(TAEGitRepositoryContext)
  strict private
    _commitdecorationcache: TAEGitCommitDecorationCache;
    _branches: TAEGitBranches;
    _onblockconflict: TAEGitBlockConflictCallback;
    _onlibgit2call: TAELibGit2CallLogEvent;
    _onmergeconflict: TAEGitMergeConflictCallback;
    _repo: Pgit_repository;
    _repodir: String;
    _settings: TAEGitRepositorySettings;
    _stashes: TAEGitStashes;
    _worktree: TAEGitWorkTree;
    Procedure SetRepoDir(Const inRepoDir: String);
    Function GetCommitDecorationCache: TAEGitCommitDecorationCache;
  protected
    Procedure ClearCommitDecoCache;
    Procedure CloseGitRepository;
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
    Procedure OpenGitRepository;
    Procedure RefreshCommitDecoCache;
    Procedure SplitBranchName(Var outBranchName: String; Var outRemote: String);
    Function AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer; Virtual;
    Function CurrentBranchName: String;
    Function GetDefaultRemoteName: String;
    Function HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
    Function ResolveConflictsManually(Const inFileName, inConflictedContent: String): Boolean;
    Function SolveConflicts: Boolean;
    Property CommitDecoCache: TAEGitCommitDecorationCache Read GetCommitDecorationCache;
    Property LibGit2Repository: Pgit_repository Read _repo;
  public
    Constructor Create; ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Property Branches: TAEGitBranches Read _branches;
    Property GitRepositoryDirectory: String Read _repodir Write SetRepoDir;
    Property OnBlockConflict: TAEGitBlockConflictCallback Read _onblockconflict Write _onblockconflict;
    Property OnLibGit2Call: TAELibGit2CallLogEvent Read _onlibgit2call Write _onlibgit2call;
    Property OnMergeConflict: TAEGitMergeConflictCallback Read _onmergeconflict Write _onmergeconflict;
    Property Settings: TAEGitRepositorySettings Read _settings;
    Property Stashes: TAEGitStashes Read _stashes;
    Property WorkTree: TAEGitWorkTree Read _worktree;
  End;

Implementation

Uses System.SysUtils, AE.GitRepository.Exception,System.IOUtils, System.Generics.Collections, AE.GitRepository.Branch, AE.GitRepository.Commit;

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

    Raise EAELibGitException.Create(errorcode, inMethod, errorclass, String(UTF8String(err.message)));
  End;
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

Procedure TAEGitRepository.ClearCommitDecoCache;
Begin
  If _commitdecorationcache.Loaded Then
    _commitdecorationcache.Clear;
End;

Procedure TAEGitRepository.CloseGitRepository;
Begin
  If Not Assigned(_repo) Then
    Raise EAEGitException.Create('The repository is not yet open!');

  git_repository_free(_repo);

  DoLibGit2Call('git_repository_free');

  _repo := nil;
End;

Procedure TAEGitRepository.RefreshCommitDecoCache;
Var
  iterator: Pgit_reference_iterator;
  ref, headref: Pgit_reference;
  shortname: PAnsiChar;
  hash: String;
  oid: Pgit_oid;
  obj: Pgit_object;

  Function TryGetCommitHashFromReference(Const inRef: Pgit_reference; out outHash: String): Boolean;
  Begin
    Result := False;
    outHash := '';

    oid := git_reference_target(inRef);

    DoLibGit2Call('git_reference_target');

    If Assigned(oid) Then
    Begin
      outHash := OidToString(oid);

      Exit(True);
    End;

    If HandleLibGit2Output('git_reference_peel', git_reference_peel(@obj, inRef, GIT_OBJECT_COMMIT), False) Then
    Try
      oid := git_object_id(obj);

      DoLibGit2Call('git_object_id');

      If Assigned(oid) Then
      Begin
        outHash := OidToString(oid);

        Result := True;
      End;
    Finally
      git_object_free(obj);

      DoLibGit2Call('git_object_free');
    End;
  End;
Begin
  _commitdecorationcache.Clear;

  HandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@iterator, _repo, PAnsiChar(UTF8String('refs/tags/*'))));
  Try
    While HandleLibGit2Output('git_reference_next', git_reference_next(@ref, iterator), False) Do
    Try
      HandleLibGit2Output('git_reference_peel', git_reference_peel(@obj, ref, GIT_OBJECT_COMMIT));
      Try
        oid := git_object_id(obj);

        DoLibGit2Call('git_object_id');

        hash := OidToString(oid);

        shortname := git_reference_shorthand(ref);

        DoLibGit2Call('git_reference_shorthand');

        _commitdecorationcache.AddCommitTag(hash, String(UTF8String(shortname)));
      Finally
        git_object_free(obj);

        DoLibGit2Call('git_object_free');
      End
    Finally
      git_reference_free(ref);
    End;
  Finally
    git_reference_iterator_free(iterator);

    DoLibGit2Call('git_reference_iterator_free');
  End;

  HandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@iterator, _repo, PAnsiChar(UTF8String('refs/heads/*'))));
  Try
    While HandleLibGit2Output('git_reference_next', git_reference_next(@ref, iterator), False) Do
    Begin
      Try
        If TryGetCommitHashFromReference(ref, hash) Then
        Begin
          shortname := git_reference_shorthand(ref);

          DoLibGit2Call('git_reference_shorthand');

          _commitdecorationcache.AddCommitBranch(hash, String(UTF8String(shortname)));
        End;
      Finally
        git_reference_free(ref);

        DoLibGit2Call('git_reference_free');
      End;
    End;
  Finally
    git_reference_iterator_free(iterator);

    DoLibGit2Call('git_reference_iterator_free');
  End;

  HandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@iterator, _repo, PAnsiChar(UTF8String('refs/remotes/*'))));
  Try
    While HandleLibGit2Output('git_reference_next', git_reference_next(@ref, iterator), False) Do
    Begin
      Try
        If TryGetCommitHashFromReference(ref, hash) Then
        Begin
          shortname := git_reference_shorthand(ref);

          DoLibGit2Call('git_reference_shorthand');

          _commitdecorationcache.AddCommitBranch(hash, String(UTF8String(shortname)));
        End;
      Finally
        git_reference_free(ref);

        DoLibGit2Call('git_reference_free');
      End;
    End;
  Finally
    git_reference_iterator_free(iterator);

    DoLibGit2Call('git_reference_iterator_free');
  End;

  If HandleLibGit2Output('git_repository_head', git_repository_head(@headref, _repo), False) Then
  Try
    If TryGetCommitHashFromReference(headref, hash) Then
      _commitdecorationcache.Head := hash;
  Finally
    git_reference_free(headref);

    DoLibGit2Call('git_reference_free');
  End;

  _commitdecorationcache.Loaded := True;
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

Constructor TAEGitRepository.Create;
Begin
  inherited;

  _settings := TAEGitRepositorySettings.Create;
  _branches := TAEGitBranches.Create(Self);
  _commitdecorationcache := TAEGitCommitDecorationCache.Create;
  _stashes := TAEGitStashes.Create(Self);
  _worktree := TAEGitWorkTree.Create(Self);

  _onblockconflict := nil;
  _onlibgit2call := nil;
  _onmergeconflict := nil;
  _repo := nil;
  _repodir := '';
End;

Function TAEGitRepository.CurrentBranchName: String;
Begin
  If _branches.Current Is TAEGitBranch Then
    Result := TAEGitBranch(_branches.Current).Name
  Else If _branches.Current Is TAEGitCommit Then
    Result := TAEGitCommit(_branches.Current).Hash
  Else
    Result := '';
End;

Destructor TAEGitRepository.Destroy;
Begin
  FreeAndNil(_worktree);
  FreeAndNil(_stashes);
  FreeAndNil(_commitdecorationcache);
  FreeAndNil(_branches);

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

Function TAEGitRepository.GetCommitDecorationCache: TAEGitCommitDecorationCache;
Begin
  If Not _commitdecorationcache.Loaded Then
    RefreshCommitDecoCache;

  Result := _commitdecorationcache;
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

Procedure TAEGitRepository.OpenGitRepository;
Begin
  If Assigned(_repo) Then
    Raise EAEGitException.Create('A repository is already open!');

  HandleLibGit2Output('git_repository_open', git_repository_open(@_repo, PAnsiChar(UTF8String(_repodir))));
End;

Procedure TAEGitRepository.SetRepoDir(Const inRepoDir: String);
Begin
  If inRepoDir = _repodir Then
    Exit;

  If Assigned(_repo) Then
    Self.CloseGitRepository;

  _repodir := inRepoDir;

  Self.OpenGitRepository;
  _branches.Clear;
  _stashes.Clear;
  _worktree.Clear;
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

initialization
  InitLibGit2;

finalization
  ShutdownLibgit2;

End.
