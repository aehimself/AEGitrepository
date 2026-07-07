{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Context;

Interface

Uses libgit2, AE.GitRepository.TypeDef, AE.GitRepository.Settings;

Type
  TAEGitRepositoryContext = Class
  End;

  TAEGitRepositoryContextHelper = Class Helper For TAEGitRepositoryContext
  public
    Function AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
    Function GetDefaultRemoteName: String;
    Function OidToString(Const inOid: Pgit_oid): String;
    Function GetSettings: TAEGitRepositorySettings;
    Function GetStashCommit(Const inStashIndex: Integer): Pgit_commit;
    Function HandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
    Function Repository: Pgit_repository;
    Function SolveConflicts: Boolean;
    Procedure DoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
    Procedure UpdateCurrentBranch;
    Procedure RefreshBranches;
    Procedure RefreshWorkTree;
    Procedure SplitBranchName(Var outBranchName: String; Var outRemote: String);
  End;

Implementation

Uses System.SysUtils, AE.GitRepository;

Type
  TAEGitRepositoryAccess = Class(TAEGitRepository)
  End;

Function TAEGitRepositoryContextHelper.AuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).AuthCallback(outGitCredential, inURL, inUserName, inAllowedTypes);
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

Procedure TAEGitRepositoryContextHelper.RefreshWorkTree;
Begin
  (Self As TAEGitRepository).WorkTree.Refresh;
End;

Procedure TAEGitRepositoryContextHelper.SplitBranchName(Var outBranchName: String; Var outRemote: String);
Begin
  TAEGitRepositoryAccess(Self As TAEGitRepository).SplitBranchName(outBranchName, outRemote);
End;

End.
