{
  AEGitRepository (©) 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Base;

Interface

Uses libgit2, AE.GitRepository.TypeDef, AE.GitRepository.Context, AE.GitRepository.Settings, AE.GitRepository.Branch,
     AE.GitRepository.Stash, AE.GitRepository.WorkTree, AE.GitRepository.CommitDecorationCache;

Type
  TAEGitRepositoryBase = Class(TAEGitRepositoryContext)
  strict private
    _branches: TAEGitBranches;
    _commitdecorationcache: TAEGitCommitDecorationCache;
    _repo: Pgit_repository;
    _settings: TAEGitRepositorySettings;
    _stashes: TAEGitStashes;
    _worktree: TAEGitWorkTree;
    Function GetCommitDecorationCache: TAEGitCommitDecorationCache;
  strict protected
    Procedure ClearRepositoryObjects;
  protected
    Procedure ClearCommitDecoCache; Virtual;
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK); Virtual;
    Procedure RefreshCommitDecoCache; Virtual;
    Procedure RefreshSubmodules; Virtual;
    Procedure SplitBranchName(Var outBranchName: String; Var outRemote: String); Virtual;
    Function AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer; Virtual;
    Function CurrentBranchName: String; Virtual;
    Function GetDefaultRemoteName: String; Virtual;
    Function HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
    Function ResolveConflictsManually(Const inFileName, inConflictedContent: String): Boolean; Virtual;
    Function SolveConflicts: Boolean; Virtual;
    Property CommitDecoCache: TAEGitCommitDecorationCache Read GetCommitDecorationCache;
    Property LibGit2Repository: Pgit_repository Read _repo Write _repo;
  public
    Constructor Create; ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Function RemoteURL(inRemote: String = ''): String;
    Property Branches: TAEGitBranches Read _branches;
    Property Settings: TAEGitRepositorySettings Read _settings;
    Property Stashes: TAEGitStashes Read _stashes;
    Property WorkTree: TAEGitWorkTree Read _worktree;
  End;

Implementation

Uses System.SysUtils, System.IOUtils, AE.GitRepository.Exception, System.Generics.Collections, AE.GitRepository.Commit;

Function TAEGitRepositoryBase.HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
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

Function TAEGitRepositoryBase.AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
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

Procedure TAEGitRepositoryBase.ClearCommitDecoCache;
Begin
  If _commitdecorationcache.Loaded Then
    _commitdecorationcache.Clear;
End;

Procedure TAEGitRepositoryBase.RefreshCommitDecoCache;
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

Function TAEGitRepositoryBase.ResolveConflictsManually(Const inFileName, inConflictedContent: String): Boolean;
Begin
  Result := False;
End;

Constructor TAEGitRepositoryBase.Create;
Begin
  inherited;

  _branches := TAEGitBranches.Create(Self);
  _commitdecorationcache := TAEGitCommitDecorationCache.Create;
  _repo := nil;
  _settings := TAEGitRepositorySettings.Create;
  _stashes := TAEGitStashes.Create(Self);
  _worktree := TAEGitWorkTree.Create(Self);
End;

Function TAEGitRepositoryBase.CurrentBranchName: String;
Begin
  If _branches.Current Is TAEGitBranch Then
    Result := TAEGitBranch(_branches.Current).Name
  Else If _branches.Current Is TAEGitCommit Then
    Result := TAEGitCommit(_branches.Current).Hash
  Else
    Result := '';
End;

Destructor TAEGitRepositoryBase.Destroy;
Begin
  If Assigned(_repo) Then
  Begin
    git_repository_free(_repo);

    DoLibGit2Call('git_repository_free');

    _repo := nil;
  End;

  FreeAndNil(_worktree);
  FreeAndNil(_stashes);
  FreeAndNil(_settings);
  FreeAndNil(_commitdecorationcache);
  FreeAndNil(_branches);

  inherited;
End;

Procedure TAEGitRepositoryBase.DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  // Descendants can override this method to forward low-level call logs.
End;

Function TAEGitRepositoryBase.GetCommitDecorationCache: TAEGitCommitDecorationCache;
Begin
  If Not _commitdecorationcache.Loaded Then
    RefreshCommitDecoCache;

  Result := _commitdecorationcache;
End;

Function TAEGitRepositoryBase.GetDefaultRemoteName: String;
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

Procedure TAEGitRepositoryBase.RefreshSubmodules;
Begin
  // Submodule collection ownership is implemented in descendants.
End;

Function TAEGitRepositoryBase.RemoteURL(inRemote: String): String;
Var
  remote: Pgit_remote;
Begin
  If inRemote.IsEmpty Then
    inRemote := GetDefaultRemoteName;

  HandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, _repo, PAnsiChar(UTF8String(inRemote))));
  Try
    Result := String(UTF8String(git_remote_url(remote)));

    DoLibGit2Call('git_remote_url');
  Finally
    git_remote_free(remote);

    DoLibGit2Call('git_remote_free');
  End;
End;

Procedure TAEGitRepositoryBase.ClearRepositoryObjects;
Begin
  _branches.Clear;
  _stashes.Clear;
  _worktree.Clear;
End;

Function TAEGitRepositoryBase.SolveConflicts: Boolean;
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

Procedure TAEGitRepositoryBase.SplitBranchName(Var outBranchName: String; Var outRemote: String);
Begin
  If outBranchName.Contains('/') Then
  Begin
    outRemote := outBranchName.Substring(0, outBranchName.IndexOf('/'));

    outBranchName := outBranchName.Substring(outBranchName.IndexOf('/') + 1);
  End
  Else
    outRemote := Self.GetDefaultRemoteName;
End;

End.
