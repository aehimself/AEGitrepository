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
    Procedure AssertCleanWorkTree;
    Procedure ClearCommitDecorationCache;
    Procedure CollectChangedFiles(Const inChangedFiles: TAEGitChangedFileList; Const inExcludeSubmodules: Boolean);
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
    Procedure UpdateCurrentBranch;
    Procedure RefreshBranches;
    Procedure RefreshActualCommitCount;
    Procedure RefreshCommitDecorationCache;
    Procedure RefreshCurrentBranchCommits;
    Procedure RefreshStashes;
    Procedure RefreshSubmodules;
    Procedure RefreshWorkTree;
    Procedure RevertFile(Const inFileName: String);
    Procedure SplitBranchName(Var outBranchName: String; Var outRemote: String);
    Procedure StageFile(Const inFileName: String);
    Procedure UnstageFile(Const inFileName: String);
    Function AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
    Function CommitBranches(COnst inCommitHash: String): TArray<String>;
    Function CommitIsHead(Const inCommitHash: String): Boolean;
    Function CommitTags(Const inCommitHash: String): TArray<String>;
    Function GetCurrentBranchName: String;
    Function GetDefaultRemoteName: String;
    Function GetSettings: TAEGitRepositorySettings;
    Function GetStashCommit(Const inStashHash: String): Pgit_commit;
    Function HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inAcceptableErrorCodes: TAEGitErrorCodes = []): Boolean;
    Function OidToString(Const inOid: Pgit_oid): String;
    Function Repository: Pgit_repository;
    Function StashIndexByHash(Const inStashHash: String): Integer;
    Function SolveConflicts: Boolean;
  End;

Implementation

Uses System.SysUtils, System.Generics.Collections, AE.GitRepository.Base, AE.GitRepository.Exception, AE.GitRepository.HeadTarget,
     AE.GitRepository.Branch;

Type
  TAEGitRepositoryBaseAccess = Class(TAEGitRepositoryBase)
  End;

Function TAEGitRepositoryContextHelper.AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
Begin
  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).AuthCallback(outGitCredential, inURL, inUserName, inAllowedTypes);
End;

Function TAEGitRepositoryContextHelper.GetCurrentBranchName: String;
Begin
  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).CurrentBranchName;
End;

Function TAEGitRepositoryContextHelper.GetDefaultRemoteName: String;
Begin
  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).GetDefaultRemoteName;
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
  Result := (Self As TAEGitRepositoryBase).Settings;
End;

Function TAEGitRepositoryContextHelper.GetStashCommit(Const inStashHash: String): Pgit_commit;
Var
  reflog: Pgit_reflog;
  entry: Pgit_reflog_entry;
  count, a: NativeUInt;
  oid: Pgit_oid;
Begin
  Result := nil;

  HandleLibGit2Output('git_reflog_read', git_reflog_read(@reflog, Repository, 'refs/stash'));
  Try
    count := git_reflog_entrycount(reflog);

    DoLibGit2Call('git_reflog_entrycount');

    If count = 0 Then
      Raise EAEGitException.Create('Stash is empty!');

    For a := 0 To count - 1 Do
    Begin
      entry := git_reflog_entry_byindex(reflog, a);

      DoLibGit2Call('git_reflog_entry_byindex');

      oid := git_reflog_entry_id_new(entry);

      DoLibGit2Call('git_reflog_entry_id_new');

      If OidToString(oid).ToLower = inStashHash.ToLower Then
      Begin
        HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@Result, Repository, oid));

        Break;
      End;
    End;

    If Not Assigned(Result) Then
      Raise EAEGitException.Create('Stash ' + inStashHash + ' can not be found!');
  Finally
    git_reflog_free(reflog);

    DoLibGit2Call('git_reflog_free');
  End;
End;

Function TAEGitRepositoryContextHelper.StashIndexByHash(Const inStashHash: String): Integer;
Var
  reflog: Pgit_reflog;
  entry: Pgit_reflog_entry;
  count, a: NativeUInt;
Begin
  Result := -1;

  If inStashHash.IsEmpty Then
    Exit;

  HandleLibGit2Output('git_reflog_read', git_reflog_read(@reflog, Repository, 'refs/stash'));
  Try
    count := git_reflog_entrycount(reflog);

    DoLibGit2Call('git_reflog_entrycount');

    If count = 0 Then
      Exit;

    For a := 0 To count - 1 Do
    Begin
      entry := git_reflog_entry_byindex(reflog, a);

      DoLibGit2Call('git_reflog_entry_byindex');

      If OidToString(git_reflog_entry_id_new(entry)).ToLower = inStashHash.ToLower Then
      Begin
        // Reflog entries are stored in reverse order compared to stash indexes
        Result := Integer(count - 1 - a);

        Break;
      End;
    End;
  Finally
    git_reflog_free(reflog);

    DoLibGit2Call('git_reflog_free');
  End;
End;

Function TAEGitRepositoryContextHelper.HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inAcceptableErrorCodes: TAEGitErrorCodes = []): Boolean;
Begin
  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).HandleLibGit2Output(inMethod, inCommandResult, inAcceptableErrorCodes);
End;

Function TAEGitRepositoryContextHelper.Repository: Pgit_repository;
Begin
  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).LibGit2Repository;
End;

Procedure TAEGitRepositoryContextHelper.RevertFile(Const inFileName: String);
Begin
  (Self As TAEGitRepositoryBase).WorkTree.RevertFiles([inFileName]);
End;

Function TAEGitRepositoryContextHelper.SolveConflicts: Boolean;
Begin
  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).SolveConflicts;
End;

Procedure TAEGitRepositoryContextHelper.ClearCommitDecorationCache;
Begin
  TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).ClearCommitDecoCache;
End;

Function TAEGitRepositoryContextHelper.CommitBranches(Const inCommitHash: String): TArray<String>;
Begin
  If Not TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).CommitDecoCache.Loaded Then
    TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).RefreshCommitDecoCache;

  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).CommitDecoCache.CommitBranches(inCommitHash);
End;

Function TAEGitRepositoryContextHelper.CommitIsHead(Const inCommitHash: String): Boolean;
Begin
  If Not TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).CommitDecoCache.Loaded Then
    TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).RefreshCommitDecoCache;

  Result := inCommitHash = TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).CommitDecoCache.Head;
End;

Function TAEGitRepositoryContextHelper.CommitTags(Const inCommitHash: String): TArray<String>;
Begin
  If Not TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).CommitDecoCache.Loaded Then
    TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).RefreshCommitDecoCache;

  Result := TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).CommitDecoCache.CommitTags(inCommitHash);
End;

Procedure TAEGitRepositoryContextHelper.DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).DoLibGit2Call(inMethod, inErrorCode);
End;

Procedure TAEGitRepositoryContextHelper.UnstageFile(Const inFileName: String);
Begin
  (Self As TAEGitRepositoryBase).WorkTree.UnstageFiles([inFileName]);
End;

Procedure TAEGitRepositoryContextHelper.UpdateCurrentBranch;
Begin
  (Self As TAEGitRepositoryBase).Branches.UpdateCurrent;
End;

Procedure TAEGitRepositoryContextHelper.RefreshActualCommitCount;
Var
  target: TAEGitHeadTarget;
Begin
  target := (Self As TAEGitRepositoryBase).Branches.Current;

  If Not (target Is TAEGitBranch) Then
    Exit;

  TAEGitBranch(target).UpdateCommitCount;
End;

Procedure TAEGitRepositoryContextHelper.RefreshBranches;
Begin
  (Self As TAEGitRepositoryBase).Branches.Refresh(False);
End;

Procedure TAEGitRepositoryContextHelper.RefreshCommitDecorationCache;
Begin
  TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).RefreshCommitDecoCache;
End;

Procedure TAEGitRepositoryContextHelper.RefreshCurrentBranchCommits;
Var
  target: TAEGitHeadTarget;
Begin
  target := (Self As TAEGitRepositoryBase).Branches.Current;

  If Not (target Is TAEGitBranch) Then
    Exit;

  TAEGitBranch(target).Commits.Refresh(False);
  TAEGitBranch(target).UpdateCommitCount;
End;

Procedure TAEGitRepositoryContextHelper.RefreshStashes;
Begin
  (Self As TAEGitRepositoryBase).Stashes.Refresh(False);
End;

Procedure TAEGitRepositoryContextHelper.RefreshSubmodules;
Begin
  TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).RefreshSubmodules;
End;

Procedure TAEGitRepositoryContextHelper.RefreshWorkTree;
Begin
  (Self As TAEGitRepositoryBase).WorkTree.Refresh(False);
End;

Procedure TAEGitRepositoryContextHelper.SplitBranchName(Var outBranchName: String; Var outRemote: String);
Begin
  TAEGitRepositoryBaseAccess(Self As TAEGitRepositoryBase).SplitBranchName(outBranchName, outRemote);
End;

Procedure TAEGitRepositoryContextHelper.StageFile(Const inFileName: String);
Begin
  (Self As TAEGitRepositoryBase).WorkTree.StageFiles([inFileName]);
End;

Procedure TAEGitRepositoryContextHelper.CollectChangedFiles(Const inChangedFiles: TAEGitChangedFileList; Const inExcludeSubmodules: Boolean);
Var
  statuslist: Pgit_status_list;
  options: git_status_options;
  count, a: Integer;
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

    For a := 0 To count - 1 Do
    Begin
      status := git_status_byindex(statuslist, a);

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
