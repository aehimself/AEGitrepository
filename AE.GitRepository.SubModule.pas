{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.SubModule;

Interface

Uses AE.GitRepository.RefreshableObject, AE.GitRepository.Context, AE.GitRepository.SubModuleCommit, System.Generics.Collections;

Type
  TAEGitSubmodule = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _loaded: Boolean;
    _name: String;
    _path: String;
    _url: String;
    _trackingbranch: String;
    _headhash: String;
    _indexhash: String;
    _workdirhash: String;
    _initialized: Boolean;
    _commitorder: TList<String>;
    _items: TObjectDictionary<String, TAEGitSubmoduleCommit>;
    _commitsloaded: Boolean;
    Procedure LoadDetails;
    Procedure LoadCommits;
    Function GetCurrentCommit: TAEGitSubmoduleCommit;
    Function GetTrackingBranch: String;
    Function GetHeadHash: String;
    Function GetIndexHash: String;
    Function GetInitialized: Boolean;
    Function GetCommit(Const inCommitHash: String): TAEGitSubmoduleCommit;
    Function GetName: String;
    Function GetPath: String;
    Function GetUrl: String;
    Function GetCommitsList: TArray<String>;
    Function GetWorkDirHash: String;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inPath: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure Initialize(Const inOverwrite: Boolean = False);
    Procedure Sync;
    Procedure Update(Const inInit: Boolean = True);
    Property CurrentCommit: TAEGitSubmoduleCommit Read GetCurrentCommit;
    Property Commits[Const inCommitHash: String]: TAEGitSubmoduleCommit Read GetCommit;
    Property CommitsList: TArray<String> Read GetCommitsList;
    Property HeadHash: String Read GetHeadHash;
    Property IndexHash: String Read GetIndexHash;
    Property Initialized: Boolean Read GetInitialized;
    Property Name: String Read GetName;
    Property Path: String Read GetPath;
    Property TrackingBranch: String Read GetTrackingBranch;
    Property Url: String Read GetUrl;
    Property WorkDirHash: String Read GetWorkDirHash;
  End;

Implementation

Uses libgit2, System.SysUtils;

Constructor TAEGitSubmodule.Create(Const inContext: TAEGitRepositoryContext; Const inPath: String);
Begin
  inherited Create(inContext);

  _commitorder := TList<String>.Create;
  _items := TObjectDictionary<String, TAEGitSubmoduleCommit>.Create([doOwnsValues]);
  _path := inPath;
End;

Destructor TAEGitSubmodule.Destroy;
Begin
  FreeAndNil(_items);
  FreeAndNil(_commitorder);

  inherited;
End;

Procedure TAEGitSubmodule.InternalClear;
Begin
  _loaded := False;
  _trackingbranch := '';
  _headhash := '';
  _indexhash := '';
  _initialized := False;
  _name := '';
  _url := '';
  _items.Clear;
  _commitorder.Clear;
  _commitsloaded := False;
  _workdirhash := '';
End;

Procedure TAEGitSubmodule.LoadDetails;
Var
  submodule: Pgit_submodule;
  raw: PAnsiChar;
  oid: Pgit_oid;
  subrepo: Pgit_repository;
Begin
  _loaded := False;

  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_path))));
  Try
    raw := git_submodule_name(submodule);

    Context.DoLibGit2Call('git_submodule_name');

    If Assigned(raw) Then
      _name := String(UTF8String(raw))
    Else
      _name := _path;

    raw := git_submodule_path(submodule);

    Context.DoLibGit2Call('git_submodule_path');

    If Assigned(raw) Then
      _path := String(UTF8String(raw));

    raw := git_submodule_url(submodule);

    Context.DoLibGit2Call('git_submodule_url');

    If Assigned(raw) Then
      _url := String(UTF8String(raw))
    Else
      _url := '';

    raw := git_submodule_branch(submodule);

    Context.DoLibGit2Call('git_submodule_branch');

    If Assigned(raw) Then
      _trackingbranch := String(UTF8String(raw))
    Else
      _trackingbranch := '';

    oid := git_submodule_head_id(submodule);

    Context.DoLibGit2Call('git_submodule_head_id');

    _headhash := Context.OidToString(oid);

    oid := git_submodule_index_id(submodule);

    Context.DoLibGit2Call('git_submodule_index_id');

    _indexhash := Context.OidToString(oid);

    oid := git_submodule_wd_id(submodule);

    Context.DoLibGit2Call('git_submodule_wd_id');

    _workdirhash := Context.OidToString(oid);

    If Context.HandleLibGit2Output('git_submodule_open', git_submodule_open(@subrepo, submodule), False) Then
    Begin
      git_repository_free(subrepo);

      Context.DoLibGit2Call('git_repository_free');

      _initialized := True;
    End
    Else
      _initialized := False;

    _loaded := True;
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;
End;

Procedure TAEGitSubmodule.LoadCommits;
Var
  submodule: Pgit_submodule;
  subrepo: Pgit_repository;
  walk: Pgit_revwalk;
  oid: git_oid;
  hash: String;
  commit: TAEGitSubmoduleCommit;
  keystoremove: TList<String>;
Begin
  _commitsloaded := False;

  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_path))));
  Try
    Context.HandleLibGit2Output('git_submodule_open', git_submodule_open(@subrepo, submodule));
    Try
      Context.HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, subrepo));
      Try
        Context.HandleLibGit2Output('git_revwalk_sorting', git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL Or GIT_SORT_TIME));

        Context.HandleLibGit2Output('git_revwalk_push_head', git_revwalk_push_head(walk));

        keystoremove := TList<String>.Create;
        Try
          _commitorder.Clear;

          keystoremove.AddRange(_items.Keys);

          While Context.HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@oid, walk), False) Do
          Begin
            hash := Context.OidToString(@oid);

            If Not _items.TryGetValue(hash, commit) Then
            Begin
              commit := TAEGitSubmoduleCommit.Create(Context, _path, hash);

              _items.Add(hash, commit);
            End;

            _commitorder.Add(hash);

            keystoremove.Remove(hash);
          End;

          For hash In keystoremove Do
            _items.Remove(hash);
        Finally
          FreeAndNil(keystoremove);
        End;
      Finally
        git_revwalk_free(walk);

        Context.DoLibGit2Call('git_revwalk_free');
      End;
    Finally
      git_repository_free(subrepo);

      Context.DoLibGit2Call('git_repository_free');
    End;
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;

  _commitsloaded := True;
End;

Procedure TAEGitSubmodule.InternalRefresh;
Begin
  _commitsloaded := False;

  Self.LoadDetails;
End;

Function TAEGitSubmodule.GetCurrentCommit: TAEGitSubmoduleCommit;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  If Not _commitsloaded Then
    Self.LoadCommits;

  If (Not _indexhash.IsEmpty) And _items.ContainsKey(_indexhash) Then
    Exit(_items[_indexhash]);

  If (Not _headhash.IsEmpty) And _items.ContainsKey(_headhash) Then
    Exit(_items[_headhash]);

  Result := nil;
End;

Function TAEGitSubmodule.GetTrackingBranch: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _trackingbranch;
End;

Function TAEGitSubmodule.GetHeadHash: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _headhash;
End;

Function TAEGitSubmodule.GetIndexHash: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _indexhash;
End;

Function TAEGitSubmodule.GetInitialized: Boolean;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _initialized;
End;

Function TAEGitSubmodule.GetCommit(Const inCommitHash: String): TAEGitSubmoduleCommit;
Begin
  If Not _commitsloaded Then
    Self.LoadCommits;

  Result := _items[inCommitHash];
End;

Function TAEGitSubmodule.GetName: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _name;
End;

Function TAEGitSubmodule.GetPath: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _path;
End;

Function TAEGitSubmodule.GetUrl: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _url;
End;

Function TAEGitSubmodule.GetCommitsList: TArray<String>;
Begin
  If Not _commitsloaded Then
    Self.LoadCommits;

  Result := _commitorder.ToArray;
End;

Function TAEGitSubmodule.GetWorkDirHash: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _workdirhash;
End;

Procedure TAEGitSubmodule.Initialize(Const inOverwrite: Boolean = False);
Var
  submodule: Pgit_submodule;
Begin
  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_path))));
  Try
    Context.HandleLibGit2Output('git_submodule_init', git_submodule_init(submodule, Ord(inOverwrite)));
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;

  Self.LoadDetails;
  _commitsloaded := False;
End;

Procedure TAEGitSubmodule.Sync;
Var
  submodule: Pgit_submodule;
Begin
  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_path))));
  Try
    Context.HandleLibGit2Output('git_submodule_sync', git_submodule_sync(submodule));
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;

  Self.LoadDetails;
  _commitsloaded := False;
End;

Procedure TAEGitSubmodule.Update(Const inInit: Boolean = True);
Var
  submodule: Pgit_submodule;
Begin
  Context.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, Context.Repository, PAnsiChar(UTF8String(_path))));
  Try
    Context.HandleLibGit2Output('git_submodule_update', git_submodule_update(submodule, Ord(inInit), nil));
  Finally
    git_submodule_free(submodule);

    Context.DoLibGit2Call('git_submodule_free');
  End;

  Self.LoadDetails;
  _commitsloaded := False;
End;

End.
