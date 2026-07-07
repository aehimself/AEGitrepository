{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Stashes;

Interface

Uses AE.GitRepository.ContextedObject, System.Generics.Collections, AE.GitRepository.Stash, AE.GitRepository.Context;

Type
  TAEGitStashList = Class(TList<String>);

  PAEGitStashList = ^TAEGitStashList;

  TAEGitStashes = Class(TAEGitRepositoryContextedObject)
  strict private
    _items: TObjectDictionary<Integer, TAEGitStash>;
    _loaded: Boolean;
    Function GetCount: Integer;
    Function GetItem(Const inStashIndex: Integer): TAEGitStash;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); Override;
    Destructor Destroy; Override;
    Procedure Clear;
    Procedure Push(Const inStashMessage: String);
    Procedure Refresh;
    Property Count: Integer Read GetCount;
    Property Items[Const inStashIndex: Integer]: TAEGitStash Read GetItem; Default;
  End;

Implementation

Uses libgit2, System.SysUtils;

//
// libgit2 callbacks
//

Function LibGit2StashListCallback(Index: NativeUInt; Const MessageText: PAnsiChar; Const StashId: Pgit_oid; Payload: Pointer): Integer; Cdecl;
Begin
  If PAEGitStashList(Payload)^.Count <= Int64(Index) Then
    PAEGitStashList(Payload)^.Count := Int64(Index) + 1;

  PAEGitStashList(Payload)^[Int64(Index)] := String(UTF8String(MessageText));

  Result := 0;
End;

//
// TAEGitStashes
//

Procedure TAEGitStashes.Clear;
Begin
  _items.Clear;

  _loaded := False;
End;

Constructor TAEGitStashes.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited;

  _items := TObjectDictionary<Integer, TAEGitStash>.Create([doOwnsValues]);
End;

Destructor TAEGitStashes.Destroy;
Begin
  FreeAndNil(_items);

  inherited;
End;

Function TAEGitStashes.GetItem(Const inStashIndex: Integer): TAEGitStash;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items[inStashIndex];
End;

Function TAEGitStashes.GetCount: Integer;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items.Count;
End;

Procedure TAEGitStashes.Push(Const inStashMessage: String);
Var
  signature: Pgit_signature;
  oid: git_oid;
Begin
  Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
  Try
    Context.HandleLibGit2Output('git_stash_save', git_stash_save(@oid, Context.Repository, signature, PAnsiChar(UTF8String(inStashMessage)), GIT_STASH_INCLUDE_UNTRACKED));
  Finally
    git_signature_free(signature);

    Context.DoLibGit2Call('git_signature_free');
  End;

  Context.RefreshWorkTree;

  If _loaded Then
    Self.Refresh;
End;

Procedure TAEGitStashes.Refresh;
Var
  list: TAEGitStashList;
  keystoremove: TList<Integer>;
  idx: Integer;
  stash: TAEGitStash;
Begin
  _loaded := False;

  list := TAEGitStashList.Create;
  Try
    keystoremove := TList<Integer>.Create;
    Try
      Context.HandleLibGit2Output('git_stash_foreach', git_stash_foreach(Context.Repository, @LibGit2StashListCallback, @list));

      keystoremove.AddRange(_items.Keys.ToArray);

      For idx := 0 To list.Count - 1 Do
      Begin
        If Not _items.TryGetValue(idx, stash) Then
        Begin
          stash := TAEGitStash.Create(Context, idx, list[idx], Refresh);

          _items.Add(idx, stash);
        End
        Else
          stash.Message := list[idx];

        keystoremove.Remove(idx);
      End;

      For idx In keystoremove Do
        _items.Remove(idx);
    Finally
      FreeAndNil(keystoremove);
    End;
  Finally
    FreeAndNil(list);
  End;

  _loaded := True;
End;

End.
