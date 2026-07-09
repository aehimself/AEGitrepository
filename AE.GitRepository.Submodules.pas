{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Submodules;

Interface

Uses AE.GitRepository.RefreshableObject, AE.GitRepository.Context, AE.GitRepository.SubModule, AE.GitRepository.SubModuleCommit, System.Generics.Collections;

Type
  TAEGitSubmodules = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _items: TObjectDictionary<String, TAEGitSubmodule>;
    _loaded: Boolean;
    Function GetCurrentCommit(Const inSubmodulePath: String): TAEGitSubmoduleCommit;
    Function GetCurrentVersion(Const inSubmodulePath: String): TAEGitSubmoduleCommit;
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
    Property CurrentCommit[Const inSubmodulePath: String]: TAEGitSubmoduleCommit Read GetCurrentCommit;
    Property CurrentVersion[Const inSubmodulePath: String]: TAEGitSubmoduleCommit Read GetCurrentVersion;
    Property Items[Const inSubmodulePath: String]: TAEGitSubmodule Read GetItem; Default;
    Property Paths: TArray<String> Read GetPaths;
  End;

Implementation

Uses libgit2, System.SysUtils;

Type
  TAEGitSubmoduleListPayload = Record
    List: TList<String>;
    Context: TAEGitRepositoryContext;
  End;

  PAEGitSubmoduleListPayload = ^TAEGitSubmoduleListPayload;

Function LibGit2SubmoduleListCallback(Submodule: Pgit_submodule; Const Name: PAnsiChar; Payload: Pointer): Integer; Cdecl;
Var
  path: String;
  rawpath: PAnsiChar;
  callbackpayload: PAEGitSubmoduleListPayload;
Begin
  Result := 0;
  callbackpayload := PAEGitSubmoduleListPayload(Payload);

  rawpath := git_submodule_path(Submodule);

  callbackpayload^.Context.DoLibGit2Call('git_submodule_path');

  If Assigned(rawpath) Then
    path := String(UTF8String(rawpath))
  Else If Assigned(Name) Then
    path := String(UTF8String(Name))
  Else
    path := '';

  If Not path.IsEmpty Then
    callbackpayload^.List.Add(path);
End;

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

  _loaded := False;
End;

Procedure TAEGitSubmodules.InitializeAll(Const inOverwrite: Boolean = False);
Var
  submodule: TAEGitSubmodule;
Begin
  If Not _loaded Then
    Self.Refresh;

  For submodule In _items.Values Do
    submodule.Initialize(inOverwrite);
End;

Procedure TAEGitSubmodules.UpdateAll(Const inInit: Boolean = True);
Var
  submodule: TAEGitSubmodule;
Begin
  If Not _loaded Then
    Self.Refresh;

  For submodule In _items.Values Do
    submodule.Update(inInit);
End;

Function TAEGitSubmodules.GetCurrentCommit(Const inSubmodulePath: String): TAEGitSubmoduleCommit;
Begin
  Result := Self.GetItem(inSubmodulePath).CurrentCommit;
End;

Function TAEGitSubmodules.GetCurrentVersion(Const inSubmodulePath: String): TAEGitSubmoduleCommit;
Begin
  Result := Self.GetCurrentCommit(inSubmodulePath);
End;

Function TAEGitSubmodules.GetItem(Const inSubmodulePath: String): TAEGitSubmodule;
Begin
  If Not _loaded Then
    Self.Refresh;

  Result := _items[inSubmodulePath];
End;

Function TAEGitSubmodules.GetPaths: TArray<String>;
Begin
  If Not _loaded Then
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
  _loaded := False;

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

  _loaded := True;
End;

End.