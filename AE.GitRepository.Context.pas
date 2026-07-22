{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Context;

Interface

Uses libgit2, AE.GitRepository.TypeDef, AE.GitRepository.Settings, AE.GitRepository.ChangedFileList;

Type
  TAEGitRepositoryContext = Class
  End;

  TAEGitRepositoryContextHelper = Class Helper For TAEGitRepositoryContext
  public
    Procedure ClearCommitDecorationCache;
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
    Procedure UpdateCurrentBranch;
    Procedure RefreshBranches;
    Procedure RefreshCommitDecorationCache;
    Procedure RefreshWorkTree;
    Procedure SplitBranchName(Var outBranchName: String; Var outRemote: String);
    Procedure CollectChangedFiles(Const inChangedFiles: TAEGitChangedFileList; Const inExcludeSubmodules: Boolean);
    Procedure AssertCleanWorkTree;
    Function AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
    Function CommitBranches(COnst inCommitHash: String): TArray<String>;
    Function CommitIsHead(Const inCommitHash: String): Boolean;
    Function CommitTags(Const inCommitHash: String): TArray<String>;
    Function GetCurrentBranchName: String;
    Function GetDefaultRemoteName: String;
    Function GetSettings: TAEGitRepositorySettings;
    Function GetStashCommit(Const inStashIndex: Integer): Pgit_commit;
    Function HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
    Function OidToString(Const inOid: Pgit_oid): String;
    Function Repository: Pgit_repository;
    Function SolveConflicts: Boolean;
  End;

Implementation

Uses System.SysUtils, System.Generics.Collections, AE.GitRepository, AE.GitRepository.Exception;

Type
  TAEGitRepositoryAccess = Class(TAEGitRepository)
  End;

Function TAEGitRepositoryContextHelper.AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).AuthCallback(outGitCredential, inURL, inUserName, inAllowedTypes);
End;

Function TAEGitRepositoryContextHelper.GetCurrentBranchName: String;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).CurrentBranchName;
End;

Function TAEGitRepositoryContextHelper.GetDefaultRemoteName: String;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).GetDefaultRemoteName;
End;

Function TAEGitRepositoryContextHelper.OidToString(Const inOid: Pgit_oid): String;
Var
  sha: Array[0..GIT_OID_SHA1_HEXSIZE + 1] Of AnsiChar;
Begin
  git_oid_tostr(sha, SizeOf(sha), inOid);

  DoLibGit2Call('git_oid_tostr');

  Result := String(UTF8String(sha));
End;

Function TAEGitRepositoryContextHelper.GetSettings: TAEGitRepositorySettings;
Begin
  Result := (Self As TAEGitRepository).Settings;
End;

Function TAEGitRepositoryContextHelper.GetStashCommit(Const inStashIndex: Integer): Pgit_commit;
var
  reflog: Pgit_reflog;
  entry: Pgit_reflog_entry;
  count: NativeUInt;
  oid: Pgit_oid;
begin
  Result := nil;

  HandleLibGit2Output('git_reflog_read', git_reflog_read(@reflog, Repository, 'refs/stash'));
  Try
    count := git_reflog_entrycount(reflog);

    DoLibGit2Call('git_reflog_entrycount');

    If count = 0 Then
      Raise EAEGitException.Create('Stash is empty!');

    If (inStashIndex < 0) Or (Cardinal(inStashIndex) >= count) Then
      Raise EAEGitException.Create('Stash index ' + inStashIndex.ToString + ' is out of range!');

    entry := git_reflog_entry_byindex(reflog, count - 1 - Cardinal(inStashIndex));

    DoLibGit2Call('git_reflog_entry_byindex');

    oid := git_reflog_entry_id_new(entry);

    DoLibGit2Call('git_reflog_entry_id_new');

    HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@Result, Repository, oid));
  Finally
    git_reflog_free(reflog);

    DoLibGit2Call('git_reflog_free');
  End;
End;

Function TAEGitRepositoryContextHelper.HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).HandleLibGit2Output(inMethod, inCommandResult, inRaiseException);
End;

Function TAEGitRepositoryContextHelper.Repository: Pgit_repository;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).LibGit2Repository;
End;

Function TAEGitRepositoryContextHelper.SolveConflicts: Boolean;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).SolveConflicts;
End;

Procedure TAEGitRepositoryContextHelper.ClearCommitDecorationCache;
Begin
  TAEGitRepositoryAccess(Self As TAEGitRepository).ClearCommitDecoCache;
End;

Function TAEGitRepositoryContextHelper.CommitBranches(Const inCommitHash: String): TArray<String>;
Begin
  If Not TAEGitRepositoryAccess(Self As TAEGitRepository).CommitDecoCache.Loaded Then
    TAEGitRepositoryAccess(Self As TAEGitRepository).RefreshCommitDecoCache;

  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).CommitDecoCache.CommitBranches(inCommitHash);
End;

Function TAEGitRepositoryContextHelper.CommitIsHead(Const inCommitHash: String): Boolean;
Begin
  If Not TAEGitRepositoryAccess(Self As TAEGitRepository).CommitDecoCache.Loaded Then
    TAEGitRepositoryAccess(Self As TAEGitRepository).RefreshCommitDecoCache;

  Result := inCommitHash = TAEGitRepositoryAccess(Self As TAEGitRepository).CommitDecoCache.Head;
End;

Function TAEGitRepositoryContextHelper.CommitTags(Const inCommitHash: String): TArray<String>;
Begin
  If Not TAEGitRepositoryAccess(Self As TAEGitRepository).CommitDecoCache.Loaded Then
    TAEGitRepositoryAccess(Self As TAEGitRepository).RefreshCommitDecoCache;

  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).CommitDecoCache.CommitTags(inCommitHash);
End;

Procedure TAEGitRepositoryContextHelper.DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  TAEGitRepositoryAccess(Self As TAEGitRepository).DoLibGit2Call(inMethod, inErrorCode);
End;

Procedure TAEGitRepositoryContextHelper.UpdateCurrentBranch;
Begin
  (Self As TAEGitRepository).Branches.UpdateCurrent;
End;

Procedure TAEGitRepositoryContextHelper.RefreshBranches;
Begin
  (Self As TAEGitRepository).Branches.Refresh;
End;

Procedure TAEGitRepositoryContextHelper.RefreshCommitDecorationCache;
Begin
  TAEGitRepositoryAccess(Self As TAEGitRepository).RefreshCommitDecoCache;
End;

Procedure TAEGitRepositoryContextHelper.RefreshWorkTree;
Begin
  (Self As TAEGitRepository).WorkTree.Refresh;
End;

Procedure TAEGitRepositoryContextHelper.SplitBranchName(Var outBranchName: String; Var outRemote: String);
Begin
  TAEGitRepositoryAccess(Self As TAEGitRepository).SplitBranchName(outBranchName, outRemote);
End;

Procedure TAEGitRepositoryContextHelper.CollectChangedFiles(Const inChangedFiles: TAEGitChangedFileList; Const inExcludeSubmodules: Boolean);
Var
  statuslist: Pgit_status_list;
  options: git_status_options;
  count, idx: Integer;
  status: Pgit_status_entry;
Begin
  HandleLibGit2Output('git_status_options_init', git_status_options_init(@options, GIT_STATUS_OPTIONS_VERSION));

  options.flags := GIT_STATUS_OPT_INCLUDE_UNTRACKED Or GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS;

  If inExcludeSubmodules Then
    options.flags := options.flags Or GIT_STATUS_OPT_EXCLUDE_SUBMODULES;

  HandleLibGit2Output('git_status_list_new', git_status_list_new(@statuslist, Self.Repository, @options));
  Try
    count := git_status_list_entrycount(statuslist);

    DoLibGit2Call('git_status_list_entrycount');

    For idx := 0 To count - 1 Do
    Begin
      status := git_status_byindex(statuslist, idx);

      DoLibGit2Call('git_status_byindex');

      If status.status = GIT_STATUS_IGNORED Then
        Continue;

      If (status.status And GIT_STATUS_INDEX_NEW) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedNew);

      If (status.status And GIT_STATUS_INDEX_MODIFIED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedModified);

      If (status.status And GIT_STATUS_INDEX_DELETED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.old_file.path)), gfsStagedDeleted);

      If (status.status And GIT_STATUS_INDEX_RENAMED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedRenamed);

      If (status.status And GIT_STATUS_INDEX_TYPECHANGE) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsStagedTypeChange);

      If (status.status And GIT_STATUS_WT_NEW) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsNew);

      If (status.status And GIT_STATUS_WT_MODIFIED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsModified);

      If (status.status And GIT_STATUS_WT_DELETED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.old_file.path)), gfsDeleted);

      If (status.status And GIT_STATUS_WT_RENAMED) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsRenamed);

      If (status.status And GIT_STATUS_WT_TYPECHANGE) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsTypeChange);

      If (status.status And GIT_STATUS_WT_UNREADABLE) <> 0 Then
        inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsUnreadable);

      If (status.status And GIT_STATUS_CONFLICTED) <> 0 Then
        If Assigned(status.index_to_workdir) Then
          inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsConflicted)
        Else
          inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsConflicted);

      If status.status = GIT_STATUS_CURRENT Then
        If Assigned(status.index_to_workdir) Then
          inChangedFiles.AddFileStatus(String(UTF8String(status.index_to_workdir.new_file.path)), gfsCurrent)
        Else
          inChangedFiles.AddFileStatus(String(UTF8String(status.head_to_index.new_file.path)), gfsCurrent);
    End;
  Finally
    git_status_list_free(statuslist);

    DoLibGit2Call('git_status_list_free');
  End;
End;

Procedure TAEGitRepositoryContextHelper.AssertCleanWorkTree;
Var
  changedfiles: TAEGitChangedFileList;
  paths: TList<String>;
  filestatus: TAEGitFileStatus;
  hasblocking: Boolean;
  s, pathsummary: String;
Begin
  changedfiles := TAEGitChangedFileList.Create;
  Try
    Self.CollectChangedFiles(changedfiles, False);

    paths := TList<String>.Create;
    Try
      For s In changedfiles.Keys Do
      Begin
        hasblocking := False;

        For filestatus In changedfiles[s] Do
          If Not (filestatus In [gfsCurrent, gfsIgnored]) Then
          Begin
            hasblocking := True;

            Break;
          End;

        If hasblocking Then
          paths.Add(s);
      End;

      If paths.Count = 0 Then
        Exit;

      pathsummary := '';

      For s in paths Do
        pathsummary := pathsummary + s + ', ';

      If Not pathsummary.IsEmpty Then
        pathsummary := pathsummary.Substring(0, pathsummary.Length - 2);

      Raise EAEGitException.Create('Unstaged changes exist in workdir: ' + pathsummary);
    Finally
      FreeAndNil(paths);
    End;
  Finally
    FreeAndNil(changedfiles);
  End;
End;

End.
