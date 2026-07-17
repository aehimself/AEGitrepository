{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.BranchCommits;

Interface

Uses AE.GitRepository.RefreshableObject, System.Generics.Collections, AE.GitRepository.Context, AE.GitRepository.Commit;

Type
  TAEGitBranchCommits = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _branchname: String;
    _items: TObjectDictionary<String, TAEGitCommit>;
    _lastheadhash: String;
    _loaded: Boolean;
    _order: TList<String>;
    Function RefreshFastForward: Boolean;
    Procedure RefreshFullReconcile;
    Function GetCommitHashes: TArray<String>;
    Function GetItem(Const inCommitHash: String): TAEGitCommit;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Property CommitHashes: TArray<String> Read GetCommitHashes;
    Property Items[Const inCommitHash: String]: TAEGitCommit Read GetItem; Default;
  End;

implementation

Uses libgit2, System.SysUtils;

Procedure TAEGitBranchCommits.InternalClear;
Begin
  _items.Clear;
  _order.Clear;

  _lastheadhash := '';
  _loaded := False;
End;

Constructor TAEGitBranchCommits.Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String);
Begin
  inherited Create(inContext);

  _items := TObjectDictionary<String, TAEGitCommit>.Create([doOwnsValues]);
  _order := TList<String>.Create;

  _branchname := inBranchName;
End;

Destructor TAEGitBranchCommits.Destroy;
Begin
  FreeAndNil(_items);
  FreeAndNil(_order);

  inherited;
End;

Function TAEGitBranchCommits.GetItem(Const inCommitHash: String): TAEGitCommit;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items[inCommitHash];
End;

Function TAEGitBranchCommits.GetCommitHashes: TArray<String>;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _order.ToArray;
End;

Function TAEGitBranchCommits.RefreshFastForward: Boolean;
Var
  walk: Pgit_revwalk;
  oid: git_oid;
  hash: String;
  commit: TAEGitCommit;
  foundoldhead: Boolean;
  newprefix: TList<String>;
  i: Integer;
Begin
  Result := False;

  foundoldhead := False;
  newprefix := TList<String>.Create;
  Try
    Context.HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, Context.Repository));
    Try
      Context.HandleLibGit2Output('git_revwalk_sorting', git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL Or GIT_SORT_TIME));

      Context.HandleLibGit2Output('git_revwalk_push_head', git_revwalk_push_head(walk));

      Context.HandleLibGit2Output('git_revwalk_push_ref', git_revwalk_push_ref(walk, PAnsiChar(UTF8String('refs/remotes/' + Context.GetDefaultRemoteName + '/' + _branchname))));

      While Context.HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@oid, walk), False) Do
      Begin
        hash := Context.OidToString(@oid);

        If hash = _lastheadhash Then
        Begin
          foundoldhead := True;

          Break;
        End;

        newprefix.Add(hash);
      End;
    Finally
      git_revwalk_free(walk);

      Context.DoLibGit2Call('git_revwalk_free');
    End;

    If Not foundoldhead Then
      Exit;

    For i := newprefix.Count - 1 DownTo 0 Do
    Begin
      hash := newprefix[i];

      If Not _items.TryGetValue(hash, commit) Then
      Begin
        commit := TAEGitCommit.Create(Context, hash);

        _items.Add(hash, commit);
      End;

      _order.Insert(0, hash);
    End;

    Result := True;
  Finally
    FreeAndNil(newprefix);
  End;
End;

Procedure TAEGitBranchCommits.RefreshFullReconcile;
Var
  walk: Pgit_revwalk;
  oid: git_oid;
  hash: String;
  commit: TAEGitCommit;
  keystoremove: TList<String>;
Begin
  keystoremove := TList<String>.Create;
  Try
    _order.Clear;
    keystoremove.AddRange(_items.Keys);

    Context.HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, Context.Repository));
    Try
      Context.HandleLibGit2Output('git_revwalk_sorting', git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL Or GIT_SORT_TIME));

      Context.HandleLibGit2Output('git_revwalk_push_head', git_revwalk_push_head(walk));

      Context.HandleLibGit2Output('git_revwalk_push_ref', git_revwalk_push_ref(walk, PAnsiChar(UTF8String('refs/remotes/' + Context.GetDefaultRemoteName + '/' + _branchname))));

      While Context.HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@oid, walk), False) Do
      Begin
        hash := Context.OidToString(@oid);

        If Not _items.TryGetValue(hash, commit) Then
        Begin
          commit := TAEGitCommit.Create(Context, hash);

          _items.Add(hash, commit);
        End;

        _order.Add(hash);
        keystoremove.Remove(hash);
      End;

      For hash In keystoremove Do
        _items.Remove(hash);

      _loaded := True;
    Finally
      git_revwalk_free(walk);

      Context.DoLibGit2Call('git_revwalk_free');
    End;
  Finally
    FreeAndNil(keystoremove);
  End;
End;

Procedure TAEGitBranchCommits.InternalRefresh;
Var
  refname, newheadhash: String;
  newheadoid, oldheadoid: git_oid;
  isfastforward: Boolean;
  commit: TAEGitCommit;
Begin
  _loaded := False;

  If _branchname.Contains('/') Then
  Begin
    Self.Clear;
    _loaded := True;

    Exit;
  End;

  refname := 'refs/heads/' + _branchname;
  refname := 'refs/remotes/' + Context.GetDefaultRemoteName + '/' + _branchname;

  If Not Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@newheadoid, Context.Repository, PAnsiChar(UTF8String(refname))), False) Then
  Begin
    Self.Clear;
    _loaded := True;

    Exit;
  End;

  newheadhash := Context.OidToString(@newheadoid);

  If Not _lastheadhash.IsEmpty And (newheadhash = _lastheadhash) Then
  Begin
    _loaded := True;

    Exit;
  End;

  isfastforward := False;

  If Not _lastheadhash.IsEmpty And Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oldheadoid, PAnsiChar(UTF8String(_lastheadhash))), False) Then
  Begin
    isfastforward := git_graph_descendant_of(Context.Repository, @newheadoid, @oldheadoid) = 1;

    Context.DoLibGit2Call('git_graph_descendant_of');
  End;

  If Not isfastforward Or Not Self.RefreshFastForward Then
    Self.RefreshFullReconcile;

  Context.ClearCommitDecorationCache;

  For commit In _items.Values Do
  Begin
    commit.Branches := Context.CommitBranches(commit.Hash);
    commit.Tags := Context.CommitTags(commit.Hash);
  End;

  _lastheadhash := newheadhash;
  _loaded := True;
End;

End.
