{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Branches;

Interface

Uses AE.GitRepository.RefreshableObject, System.Generics.Collections, AE.GitRepository.HeadTarget, AE.GitRepository.Branch, AE.GitRepository.Context;

Type
  TAEGitBranches = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _current: TAEGitHeadTarget;
    _currentowned: Boolean;
    _items: TObjectDictionary<String, TAEGitBranch>;
    _order: TList<String>;
    Procedure FreeCurrent;
    Function GetCurrent: TAEGitHeadTarget;
    Function GetItem(Const inBranchName: String): TAEGitBranch;
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
    Property Items[Const inBranchName: String]: TAEGitBranch Read GetItem; Default;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.Commit;

Procedure TAEGitBranches.InternalClear;
Begin
  Self.FreeCurrent;

  _items.Clear;
End;

Constructor TAEGitBranches.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited;

  _items := TObjectDictionary<String, TAEGitBranch>.Create([doOwnsValues]);
  _order := TList<String>.Create;
End;

Destructor TAEGitBranches.Destroy;
Begin
  Self.FreeCurrent;

  FreeAndNil(_order);
  FreeAndNil(_items);

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
  ref, branchRef: Pgit_reference;
  commit: Pgit_commit;
Begin
  Context.HandleLibGit2Output('git_repository_head', git_repository_head(@ref, Context.Repository));
  Try
    Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.Repository, git_reference_target(ref)));
    Try
      Context.HandleLibGit2Output('git_branch_create', git_branch_create(@branchRef, Context.Repository, PAnsiChar(UTF8String(inBranchName)), commit, Ord(False)));

      git_reference_free(branchRef);

      Context.DoLibGit2Call('git_reference_free');
    Finally
      git_commit_free(commit);

      Context.DoLibGit2Call('git_commit_free');
    End;
  Finally
    git_reference_free(ref);

    Context.DoLibGit2Call('git_reference_free');
  End;

  Refresh;
End;

Function TAEGitBranches.GetCurrent: TAEGitHeadTarget;
Begin
  If Not Assigned(_current) Then
    Self.UpdateCurrent;

  Result := _current;
End;

Function TAEGitBranches.GetItem(Const inBranchName: String): TAEGitBranch;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items[inBranchName];
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
  idx: Integer;
Begin
  Self.FreeCurrent;

  Self.Loaded := False;
  SetLength(names, 0);

  Context.HandleLibGit2Output('git_branch_iterator_new', git_branch_iterator_new(@iterator, Context.Repository, GIT_BRANCH_ALL));
  Try
    Repeat
      If Not Context.HandleLibGit2Output('git_branch_next', git_branch_next(@ref, @branchtypeoutput, iterator), False) Then
        Break;

      Try
        If Context.HandleLibGit2Output('git_branch_name', git_branch_name(@branchname, ref), False) Then
        Begin
          idx := Length(names);
          SetLength(names, idx + 1);

          names[idx] := String(UTF8String(branchname));
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

    keystoremove.AddRange(_items.Keys);

    For name In names Do
    Begin
      If Not _items.TryGetValue(name, branch) Then
      Begin
        branch := TAEGitBranch.Create(Context, name);

        _items.Add(name, branch);
      End
      Else
      Begin
        branch.Commits.Refresh(False);
        branch.Submodules.Refresh(False);
      End;

      _order.Add(name);

      keystoremove.Remove(name);
    End;

    For name In keystoremove Do
      _items.Remove(name);
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

  If Context.HandleLibGit2Output('git_repository_head', git_repository_head(@ref, Context.Repository), False) Then
  Try
    isBranch := git_reference_is_branch(ref);

    Context.DoLibGit2Call('git_reference_is_branch');

    If isBranch <> 0 Then
    Begin
      If Context.HandleLibGit2Output('git_branch_name', git_branch_name(@branchname, ref), False) Then
        name := String(UTF8String(branchname))
      Else
        name := '';

      If Not Self.Loaded Then
        Self.Refresh;

      If _items.ContainsKey(name) Then
        _current := _items[name]
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
