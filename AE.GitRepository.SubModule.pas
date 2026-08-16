{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.SubModule;

Interface

Uses AE.GitRepository.Base, AE.GitRepository.Context, AE.GitRepository.TypeDef, AE.GitRepository.RefreshableObject,
     System.Generics.Collections;

Type
  TAEGitSubmodule = Class;

  TAEGitSubmodules = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _items: TObjectDictionary<String, TAEGitSubmodule>;
    Function GetItem(Const inSubmodulePath: String): TAEGitSubmodule;
    Function GetPaths: TArray<String>;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure InitializeAll(Const inOverwrite: Boolean = False);
    Procedure UpdateAll(Const inInit: Boolean = True);
    Property Items[Const inSubmodulePath: String]: TAEGitSubmodule Read GetItem; Default;
    Property Paths: TArray<String> Read GetPaths;
  End;

  TAEGitSubmodule = Class(TAEGitRepositoryBase)
  strict private
    _headhash: String;
    _indexhash: String;
    _initialized: Boolean;
    _loaded: Boolean;
    _name: String;
    _parentcontext: TAEGitRepositoryContext;
    _path: String;
    _submodules: TAEGitSubmodules;
    _trackingbranch: String;
    _url: String;
    _workdirhash: String;
    Procedure LoadDetails;
    Function GetHeadHash: String;
    Function GetIndexHash: String;
    Function GetInitialized: Boolean;
    Function GetName: String;
    Function GetPath: String;
    Function GetTrackingBranch: String;
    Function GetUrl: String;
    Function GetWorkDirHash: String;
  protected
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK); Override;
    Procedure RefreshSubmodules; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inPath: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure Initialize(Const inOverwrite: Boolean = False);
    Procedure Refresh;
    Procedure Sync;
    Procedure Update(Const inInit: Boolean = True);
    Property HeadHash: String Read GetHeadHash;
    Property IndexHash: String Read GetIndexHash;
    Property Initialized: Boolean Read GetInitialized;
    Property Name: String Read GetName;
    Property Path: String Read GetPath;
    Property SubModules: TAEGitSubmodules Read _submodules;
    Property TrackingBranch: String Read GetTrackingBranch;
    Property Url: String Read GetUrl;
    Property WorkDirHash: String Read GetWorkDirHash;
  End;

Implementation

Uses System.SysUtils, libgit2, AE.GitRepository.Libgit2Callbacks;

//
// TAEGitSubmodules
//

Constructor TAEGitSubmodules.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited Create(inContext);

  _items := TObjectDictionary<String, TAEGitSubmodule>.Create([doOwnsValues]);
End;

Destructor TAEGitSubmodules.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Procedure TAEGitSubmodules.InternalClear;
Begin
  _items.Clear;
End;

Procedure TAEGitSubmodules.InitializeAll(Const inOverwrite: Boolean = False);
Var
  submodule: TAEGitSubmodule;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  For submodule In _items.Values Do
    submodule.Initialize(inOverwrite);
End;

Procedure TAEGitSubmodules.UpdateAll(Const inInit: Boolean = True);
Var
  submodule: TAEGitSubmodule;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  For submodule In _items.Values Do
    submodule.Update(inInit);
End;

Function TAEGitSubmodules.GetItem(Const inSubmodulePath: String): TAEGitSubmodule;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items[inSubmodulePath];
End;

Function TAEGitSubmodules.GetPaths: TArray<String>;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items.Keys.ToArray;

  TArray.Sort<String>(Result);
End;

Procedure TAEGitSubmodules.InternalRefresh;
Var
  list: TList<String>;
  payload: TAEGitSubmoduleListPayload;
  path: String;
  submodule: TAEGitSubmodule;
  keystoremove: TList<String>;
Begin
  Self.Loaded := False;

  list := TList<String>.Create;
  Try
    payload.List := list;
    payload.Context := Context;

    Context.HandleLibGit2Output('git_submodule_foreach', git_submodule_foreach(Context.Repository, @LibGit2SubmoduleListCallback, @payload));

    keystoremove := TList<String>.Create;
    Try
      keystoremove.AddRange(_items.Keys);

      For path In list Do
      Begin
        If Not _items.TryGetValue(path, submodule) Then
        Begin
          submodule := TAEGitSubmodule.Create(Context, path);

          _items.Add(path, submodule);
        End
        Else
          submodule.Refresh;

        keystoremove.Remove(path);
      End;

      For path In keystoremove Do
        _items.Remove(path);
    Finally
      FreeAndNil(keystoremove);
    End;
  Finally
    FreeAndNil(list);
  End;

  Self.Loaded := True;
End;

//
// TAEGitSubmodule
//

Constructor TAEGitSubmodule.Create(Const inContext: TAEGitRepositoryContext; Const inPath: String);
Begin
  inherited Create;

  _submodules := TAEGitSubmodules.Create(Self);

  _headhash := '';
  _indexhash := '';
  _initialized := False;
  _loaded := False;
  _name := '';
  _parentcontext := inContext;
  _path := inPath;
  _trackingbranch := '';
  _url := '';
  _workdirhash := '';

  Self.Refresh;
End;

Destructor TAEGitSubmodule.Destroy;
Begin
  FreeAndNil(_submodules);

  inherited;
End;

Procedure TAEGitSubmodule.DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  _parentcontext.DoLibGit2Call(inMethod, inErrorCode);
End;

Procedure TAEGitSubmodule.RefreshSubmodules;
Begin
  _submodules.Refresh(False);
End;

Procedure TAEGitSubmodule.LoadDetails;
Var
  submodule: Pgit_submodule;
  raw: PAnsiChar;
  oid: Pgit_oid;
  subrepo: Pgit_repository;
Begin
  _loaded := False;

  If Assigned(LibGit2Repository) Then
  Begin
    git_repository_free(LibGit2Repository);

    _parentcontext.DoLibGit2Call('git_repository_free');

    LibGit2Repository := nil;
  End;

  _parentcontext.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, _parentcontext.Repository, PAnsiChar(UTF8String(_path))));
  Try
    raw := git_submodule_name(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_name');

    If Assigned(raw) Then
      _name := String(UTF8String(raw))
    Else
      _name := _path;

    raw := git_submodule_path(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_path');

    If Assigned(raw) Then
      _path := String(UTF8String(raw));

    raw := git_submodule_url(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_url');

    If Assigned(raw) Then
      _url := String(UTF8String(raw))
    Else
      _url := '';

    raw := git_submodule_branch(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_branch');

    If Assigned(raw) Then
      _trackingbranch := String(UTF8String(raw))
    Else
      _trackingbranch := '';

    oid := git_submodule_head_id(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_head_id');

    If Assigned(oid) Then
      _headhash := _parentcontext.OidToString(oid)
    Else
      _headhash := '';

    oid := git_submodule_index_id(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_index_id');

    If Assigned(oid) Then
      _indexhash := _parentcontext.OidToString(oid)
    Else
      _indexhash := '';

    oid := git_submodule_wd_id(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_wd_id');

    If Assigned(oid) Then
      _workdirhash := _parentcontext.OidToString(oid)
    Else
      _workdirhash := '';

    If _parentcontext.HandleLibGit2Output('git_submodule_open', git_submodule_open(@subrepo, submodule), [geNotFound]) Then
    Begin
      LibGit2Repository := subrepo;
      _initialized := True;
    End
    Else
    Begin
      LibGit2Repository := nil;
      _initialized := False;
    End;
  Finally
    git_submodule_free(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_free');
  End;

  Self.ClearRepositoryObjects;

  _submodules.Refresh(False);

  Self.ClearCommitDecoCache;

  _loaded := True;
End;

Procedure TAEGitSubmodule.Refresh;
Begin
  Self.LoadDetails;
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

Function TAEGitSubmodule.GetTrackingBranch: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _trackingbranch;
End;

Function TAEGitSubmodule.GetUrl: String;
Begin
  If Not _loaded Then
    Self.LoadDetails;

  Result := _url;
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
  _parentcontext.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, _parentcontext.Repository, PAnsiChar(UTF8String(_path))));
  Try
    _parentcontext.HandleLibGit2Output('git_submodule_init', git_submodule_init(submodule, Ord(inOverwrite)));
  Finally
    git_submodule_free(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_free');
  End;

  Self.Refresh;
End;

Procedure TAEGitSubmodule.Sync;
Var
  submodule: Pgit_submodule;
Begin
  _parentcontext.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, _parentcontext.Repository, PAnsiChar(UTF8String(_path))));
  Try
    _parentcontext.HandleLibGit2Output('git_submodule_sync', git_submodule_sync(submodule));
  Finally
    git_submodule_free(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_free');
  End;

  Self.Refresh;
End;

Procedure TAEGitSubmodule.Update(Const inInit: Boolean = True);
Var
  submodule: Pgit_submodule;
  options: git_submodule_update_options;
Begin
  _parentcontext.HandleLibGit2Output('git_submodule_update_options_init', git_submodule_update_options_init(@options, GIT_SUBMODULE_UPDATE_OPTIONS_VERSION));

  options.fetch_opts.callbacks.payload := _parentcontext;
  options.fetch_opts.callbacks.credentials := LibGit2AuthCallback;

  _parentcontext.HandleLibGit2Output('git_submodule_lookup', git_submodule_lookup(@submodule, _parentcontext.Repository, PAnsiChar(UTF8String(_path))));
  Try
    _parentcontext.HandleLibGit2Output('git_submodule_update', git_submodule_update(submodule, Ord(inInit), @options));
  Finally
    git_submodule_free(submodule);

    _parentcontext.DoLibGit2Call('git_submodule_free');
  End;

  Self.Refresh;
End;

End.
