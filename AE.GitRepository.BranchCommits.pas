{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.BranchCommits;

Interface

Uses AE.GitRepository.ContextedObject, System.Generics.Collections, AE.GitRepository.Context, AE.GitRepository.Commit;

Type
  TAEGitBranchCommits = Class(TAEGitRepositoryContextedObject)
  strict private
    _branchname: String;
    _items: TObjectDictionary<String, TAEGitCommit>;
    _loaded: Boolean;
    _order: TList<String>;
    Function GetCommitHashes: TArray<String>;
    Function GetItem(Const inCommitHash: String): TAEGitCommit;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Procedure Clear;
    Procedure Refresh;
    Property CommitHashes: TArray<String> Read GetCommitHashes;
    Property Items[Const inCommitHash: String]: TAEGitCommit Read GetItem; Default;
  End;

implementation

Uses libgit2, System.SysUtils;

Procedure TAEGitBranchCommits.Clear;
Begin
  _items.Clear;

  _loaded := False;
End;

Constructor TAEGitBranchCommits.Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String);
Begin
  inherited Create(inContext);

  _items := TObjectDictionary<String, TAEGitCommit>.Create([doOwnsValues]);
  _order := TList<String>.Create;

  _branchname := inBranchName;
  _loaded := False;
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

Procedure TAEGitBranchCommits.Refresh;
Var
  walk: Pgit_revwalk;
  oid: git_oid;
  sha: Array[0..GIT_OID_SHA1_HEXSIZE + 1] Of AnsiChar;
  hash: String;
Begin
  _loaded := False;

  _items.Clear;
  _order.Clear;

  If _branchname.Contains('/') Then
  Begin
    _loaded := True;

    Exit;
  End;

  Context.ContextHandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, Context.ContextLibGit2Repository));
  Try
    Context.ContextHandleLibGit2Output('git_revwalk_sorting', git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL Or GIT_SORT_TIME));
    Context.ContextHandleLibGit2Output('git_revwalk_push_ref', git_revwalk_push_ref(walk, PAnsiChar(UTF8String('refs/heads/' + _branchname))));

    While Context.ContextHandleLibGit2Output('git_revwalk_next', git_revwalk_next(@oid, walk), False) Do
    Begin
      git_oid_tostr(sha, SizeOf(sha), @oid);

      Context.ContextDoLibGit2Call('git_oid_tostr');

      hash := String(UTF8String(sha));

      _items.Add(hash, TAEGitCommit.Create(Context, hash));
      _order.Add(hash);
    End;

    _loaded := True;
  Finally
    git_revwalk_free(walk);

    Context.ContextDoLibGit2Call('git_revwalk_free');
  End;
End;

End.
