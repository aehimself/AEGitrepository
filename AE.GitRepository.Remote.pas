Unit AE.GitRepository.Remote;

Interface

Uses AE.GitRepository.ContextedObject, AE.GitRepository.Context, AE.GitRepository.RefreshableObject, System.Generics.Collections;

Type
  TAEGitRemote = Class(TAEGitRepositoryContextedObject)
  strict private
    _name: String;
    _url: String;
    Procedure SetName(Const inName: String);
    Procedure SetURL(Const inURL: String);
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inName, inURL: String); ReIntroduce;
    Procedure Delete;
    Procedure Prune;
    Property Name: String Read _name Write SetName;
    Property URL: String Read _url Write SetURL;
  End;

  TAEGitRemotes = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _default: TAEGitRemote;
    _items: TObjectDictionary<String, TAEGitRemote>;
    Function GetDefault: TAEGitRemote;
    Function GetItem(Const inRemoteName: String): TAEGitRemote;
    Function GetNames: TArray<String>;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); Override;
    Destructor Destroy; Override;
    Procedure New(Const inName, inURL: String);
    Property Default: TAEGitRemote Read GetDefault;
    Property Items[Const inRemoteName: String]: TAEGitRemote Read GetItem; Default;
    Property Names: TArray<String> Read GetNames;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.Exception, AE.GitRepository.Libgit2Callbacks;

//
// TAEGitRemote
//

Procedure TAEGitRemote.SetURL(Const inURL: String);
Begin
  If _url = inURL Then
    Exit;

  Context.HandleLibGit2Output('git_remote_set_url', git_remote_set_url(Context.Repository, PAnsiChar(UTF8String(_name)), PAnsiChar(UTF8String(inURL))));

  _url := inURL;
End;

Constructor TAEGitRemote.Create(Const inContext: TAEGitRepositoryContext; Const inName, inURL: String);
Begin
  inherited Create(inContext);

  _name := inName;
  _url := inURL;
End;

Procedure TAEGitRemote.Delete;
Begin
  Context.HandleLibGit2Output('git_remote_delete', git_remote_delete(Context.Repository, PAnsiChar(UTF8String(_name))));

  Context.RefreshRemotes;
End;

Procedure TAEGitRemote.Prune;
Var
  remote: Pgit_remote;
  callbacks: git_remote_callbacks;
Begin
  Context.HandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, Context.Repository, PAnsiChar(UTF8String(_name))));
  Try
    Context.HandleLibGit2Output('git_remote_init_callbacks', git_remote_init_callbacks(@callbacks, GIT_REMOTE_CALLBACKS_VERSION));

    callbacks.payload := Context;
    callbacks.credentials := LibGit2AuthCallback;

    Context.HandleLibGit2Output('git_remote_connect', git_remote_connect(remote, GIT_DIRECTION_FETCH, @callbacks, nil, nil));
    Try
      Context.HandleLibGit2Output('git_remote_prune', git_remote_prune(remote, @callbacks));
    Finally
      Context.HandleLibGit2Output('git_remote_disconnect', git_remote_disconnect(remote));
    End;
  Finally
    git_remote_free(remote);

    Context.DoLibGit2Call('git_remote_free');
  End;
End;

Procedure TAEGitRemote.SetName(Const inName: String);
Var
  problems: git_strarray;
  p: PPAnsiChar;
  a: Integer;
  s: String;
Begin
  If _name = inName Then
    Exit;

  Context.HandleLibGit2Output('git_remote_rename', git_remote_rename(@problems, Context.Repository, PAnsiChar(UTF8String(_name)), PAnsiChar(UTF8String(inName))));
  Try
    _name := inName;

    Context.RefreshRemotes;

    If problems.Count > 0 Then
    Begin
      s := '';
      p := problems.strings;

      For a := 0 To problems.Count - 1 Do
      Begin
        s := s + String(UTF8String(p^)) + ', ';

        Inc(p);
      End;

      If Not s.IsEmpty Then
        Raise EAEGitWarning.Create('The following refspecs could not be updated: ' + s.Substring(0, s.Length - 2));
    End;
  Finally
    git_strarray_dispose(@problems);

    Context.DoLibGit2Call('git_strarray_dispose');
  End;
End;

//
// TAEGitRemotes
//

Constructor TAEGitRemotes.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited;

  _items := TObjectDictionary<String, TAEGitRemote>.Create([doOwnsValues]);
End;

Destructor TAEGitRemotes.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Function TAEGitRemotes.GetDefault: TAEGitRemote;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _default;
End;

Function TAEGitRemotes.GetItem(Const inRemoteName: String): TAEGitRemote;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items[inRemoteName];
End;

Function TAEGitRemotes.GetNames: TArray<String>;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items.Keys.ToArray;

  TArray.Sort<String>(Result);
End;

Procedure TAEGitRemotes.InternalClear;
Begin
  inherited;

  _items.Clear;

  _default := nil;
End;

Procedure TAEGitRemotes.InternalRefresh;
Var
  keystoremove: TList<String>;
  remotes: git_strarray;
  p: PPAnsiChar;
  a: Integer;
  remotename, remoteurl: String;
  aeremote: TAEGitRemote;
  remote: Pgit_remote;
Begin
  Context.HandleLibGit2Output('git_remote_list', git_remote_list(@remotes, Context.Repository));
  Try
    keystoremove := TList<String>.Create;
    Try
      keystoremove.AddRange(_items.Keys.ToArray);
      p := remotes.strings;

      For a := 0 To remotes.Count - 1 Do
      Begin
        remotename := String(UTF8String(p^));

        Context.HandleLibGit2Output('git_remote_lookup', git_remote_lookup(@remote, Context.Repository, p^));
        Try
          remoteurl := String(UTF8String(git_remote_url(remote)));

          Context.DoLibGit2Call('git_remote_url');
        Finally
          git_remote_free(remote);

          Context.DoLibGit2Call('git_remote_free');
        End;

        If Not _items.TryGetValue(remotename, aeremote) Or (aeremote.URL <> remoteurl) Then
        Begin
          If Assigned(aeremote) Then
            _items.Remove(remotename);

          aeremote := TAEGitRemote.Create(Context, remotename, remoteurl);
          _items.Add(remotename, aeremote)
        End
        Else
          keystoremove.Remove(remotename);

        If Not Assigned(_default) Then
          _default := aeremote;

        Inc(p);
      End;

      For remotename In keystoremove Do
        _items.Remove(remotename);
    Finally
      FreeAndNil(keystoremove);
    End;
  Finally
    git_strarray_dispose(@remotes);

    Context.DoLibGit2Call('git_strarray_dispose');
  End;

  Self.Loaded := True;
End;

Procedure TAEGitRemotes.New(Const inName, inURL: String);
Var
  remote: Pgit_remote;
Begin
  Context.HandleLibGit2Output('git_remote_create', git_remote_create(@remote, Context.Repository, PAnsiChar(UTF8String(inName)), PAnsiChar(UTF8String(inURL))));

  git_remote_free(remote);

  Context.DoLibGit2Call('git_remote_free');

  If Self.Loaded Then
    _items.Add(inName, TAEGitRemote.Create(Context, inName, inURL));
End;

End.
