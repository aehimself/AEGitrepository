Unit AE.GitRepository.Libgit2Callbacks;

Interface

Uses libgit2, AE.GitRepository.Context, System.Generics.Collections;

Type
  TAEGitSubmoduleListPayload = Record
    List: TList<String>;
    Context: TAEGitRepositoryContext;
  End;

Function LibGit2AuthCallback(out_: PPgit_credential; url, username_from_url: PAnsiChar; allowed_types: Cardinal; payload: Pointer): Integer; Cdecl;
Function LibGit2StashListCallback(Index: NativeUInt; Const MessageText: PAnsiChar; Const StashId: Pgit_oid; Payload: Pointer): Integer; Cdecl;
Function LibGit2SubmoduleListCallback(Submodule: Pgit_submodule; Const Name: PAnsiChar; Payload: Pointer): Integer; Cdecl;

Implementation

Uses AE.GitREpository.TypeDef, AE.GitRepository.Stash, AE.GitRepository.SubModule, System.SysUtils;

Type
  PAEGitStashList = ^TAEGitStashList;
  PAEGitSubmoduleListPayload = ^TAEGitSubmoduleListPayload;

Function LibGit2AuthCallback(out_: PPgit_credential; url, username_from_url: PAnsiChar; allowed_types: Cardinal; payload: Pointer): Integer; Cdecl;
Var
  types: TAEGitAuthTypes;
Begin
  types := [];

  If (allowed_types And GIT_CREDENTIAL_USERPASS_PLAINTEXT_) <> 0 Then
    Include(types, gaUserPassPlainText);

  If (allowed_types And GIT_CREDENTIAL_SSH_KEY_) <> 0 Then
    Include(types, gaSshKey);

  If (allowed_types And GIT_CREDENTIAL_SSH_CUSTOM_) <> 0 Then
    Include(types, gaSshCustom);

  If (allowed_types And GIT_CREDENTIAL_DEFAULT_) <> 0 Then
    Include(types, gaDefault);

  If (allowed_types And GIT_CREDENTIAL_SSH_INTERACTIVE_) <> 0 Then
    Include(types, gaSshInteractive);

  If (allowed_types And GIT_CREDENTIAL_USERNAME_) <> 0 Then
    Include(types, gaUsername);

  If (allowed_types And GIT_CREDENTIAL_SSH_MEMORY) <> 0 Then
    Include(types, gaSshMemory);

  Result := TAEGitRepositoryContext(payload).AuthCallback(out_, url, username_from_url, types);
End;

Function LibGit2StashListCallback(Index: NativeUInt; Const MessageText: PAnsiChar; Const StashId: Pgit_oid; Payload: Pointer): Integer; Cdecl;
Begin
  If PAEGitStashList(Payload)^.Count <= Int64(Index) Then
    PAEGitStashList(Payload)^.Count := Int64(Index) + 1;

  PAEGitStashList(Payload)^[Int64(Index)] := String(UTF8String(MessageText));

  Result := 0;
End;

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

End.
