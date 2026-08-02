{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository;

Interface

Uses AE.GitRepository.TypeDef, AE.GitRepository.Base, AE.GitRepository.Submodule;

Type
  TAEGitRepository = Class(TAEGitRepositoryBase)
  strict private
    _onblockconflict: TAEGitBlockConflictCallback;
    _onlibgit2call: TAELibGit2CallLogEvent;
    _onmergeconflict: TAEGitMergeConflictCallback;
    _repodir: String;
    _submodules: TAEGitSubmodules;
    Procedure SetRepoDir(Const inRepoDir: String);
  strict protected
    Procedure CloseGitRepository;
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK); Override;
    Procedure OpenGitRepository;
    Procedure RefreshSubmodules; Override;
    Function ResolveConflictsManually(Const inFileName, inConflictedContent: String): Boolean; Override;
  public
    Constructor Create; Override;
    Destructor Destroy; Override;
    Procedure Clone(Const inRepository: String; Const inLocalFolder: String);
    Property GitRepositoryDirectory: String Read _repodir Write SetRepoDir;
    Property OnBlockConflict: TAEGitBlockConflictCallback Read _onblockconflict Write _onblockconflict;
    Property OnLibGit2Call: TAELibGit2CallLogEvent Read _onlibgit2call Write _onlibgit2call;
    Property OnMergeConflict: TAEGitMergeConflictCallback Read _onmergeconflict Write _onmergeconflict;
    Property Submodules: TAEGitSubmodules Read _submodules;
  End;

Implementation

Uses libgit2, System.SysUtils, AE.GitRepository.Exception, System.IOUtils, AE.GitRepository.Libgit2Callbacks;

Procedure TAEGitRepository.Clone(Const inRepository, inLocalFolder: String);
Var
  cloneoptions: git_clone_options;
Begin
  If Assigned(LibGit2Repository) Then
    Self.CloseGitRepository;

  git_clone_options_init(@cloneoptions, GIT_CLONE_OPTIONS_VERSION);

  cloneoptions.fetch_opts.callbacks.payload := Self;
  cloneoptions.fetch_opts.callbacks.credentials := LibGit2AuthCallback;

  HandleLibGit2Output('git_clone', git_clone(@LibGit2Repository, PAnsiChar(UTF8String(inRepository)), PAnsiChar(UTF8String(inLocalFolder)), @cloneoptions));

  _repodir := inLocalFolder;
End;

Procedure TAEGitRepository.CloseGitRepository;
Begin
  If Not Assigned(LibGit2Repository) Then
    Raise EAEGitException.Create('The repository is not yet open!');

  git_repository_free(LibGit2Repository);

  DoLibGit2Call('git_repository_free');

  LibGit2Repository := nil;

  Self.ClearRepositoryObjects;
  _submodules.Clear;
End;

Constructor TAEGitRepository.Create;
Begin
  inherited;

  _onblockconflict := nil;
  _onlibgit2call := nil;
  _onmergeconflict := nil;
  _repodir := '';
  _submodules := TAEGitSubmodules.Create(Self);
End;

Destructor TAEGitRepository.Destroy;
Begin
  If Assigned(LibGit2Repository) Then
    Self.CloseGitRepository;

  FreeAndNil(_submodules);

  inherited;
End;

Procedure TAEGitRepository.DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  If Assigned(_onlibgit2call) Then
    _onlibgit2call(Self, inMethod, inErrorCode);
End;

Procedure TAEGitRepository.OpenGitRepository;
Begin
  If Assigned(LibGit2Repository) Then
    Raise EAEGitException.Create('A repository is already open!');

  HandleLibGit2Output('git_repository_open', git_repository_open(@LibGit2Repository, PAnsiChar(UTF8String(_repodir))));
End;

Procedure TAEGitRepository.RefreshSubmodules;
Begin
  _submodules.Refresh(False);
End;

Function TAEGitRepository.ResolveConflictsManually(Const inFileName, inConflictedContent: String): Boolean;
Var
  ourindex, separatorindex, theirindex, a: NativeInt;
  ours, separator, theirs, buf, ourpart, theirpart: String;
  choice: TAEGitBlockConflictChoice;

  Procedure SkipToEOL;
  Var
    tmp: NativeInt;
  Begin
    tmp := inConflictedContent.IndexOf(#10, a);

    If tmp > -1 Then
    Begin
      a := tmp;

      If a < inConflictedContent.Length - 1 Then
        Inc(a);
    End;
  End;
Begin
  Result := False;

  If Assigned(_onmergeconflict) Then
  Begin
    buf := inConflictedContent;

    _onmergeconflict(inFileName, buf, Result);

    If Result Then
      TFile.WriteAllText(inFileName, buf);

    Exit;
  End;

  If Not Assigned(_onblockconflict) Then
    Exit;

  ours := String.Create('<', GIT_MERGE_CONFLICT_MARKER_SIZE);
  separator := String.Create('=', GIT_MERGE_CONFLICT_MARKER_SIZE);
  theirs := String.Create('>', GIT_MERGE_CONFLICT_MARKER_SIZE);

  buf := '';
  theirindex := 0;

  Repeat
    a := theirindex;

    ourindex := inConflictedContent.IndexOf(ours, theirindex);
    separatorindex := inConflictedContent.IndexOf(separator, ourindex);
    theirindex := inConflictedContent.IndexOf(theirs, separatorindex);

    If (ourindex = -1) Or (separatorindex = -1) Or (theirindex = -1) Then
    Begin
      buf := buf + inConflictedContent.Substring(a, inConflictedContent.Length - a);

      TFile.WriteAllText(inFileName, buf);

      Break;
    End;

    buf := buf + inConflictedContent.Substring(a, ourindex - a);

    a := ourindex;

    SkipToEOL;

    ourpart := inConflictedContent.Substring(a, separatorindex - a);

    a := separatorindex;

    SkipToEOL;

    theirpart := inConflictedContent.Substring(a, theirindex - a);

    a := theirindex;

    SkipToEOL;

    theirindex := a;

    choice := ccAbort;

    _onblockconflict(inFileName, ourpart, theirpart, choice);

    Case choice Of
      ccTheirs:
        buf := buf + theirpart;
      ccOurs:
        buf := buf + ourpart;
      ccAbort:
        Exit;
    End;
  Until False;

  Result := True;
End;

Procedure TAEGitRepository.SetRepoDir(Const inRepoDir: String);
Begin
  If inRepoDir = _repodir Then
    Exit;

  If Assigned(LibGit2Repository) Then
    Self.CloseGitRepository;

  _repodir := inRepoDir;

  Self.OpenGitRepository;
End;

initialization
  InitLibGit2;

finalization
  ShutdownLibgit2;

End.
