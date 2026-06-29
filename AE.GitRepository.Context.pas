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
    Function ContextAuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
    Function ContextGetDefaultRemoteName: String;
    Function ContextGetSettings: TAEGitRepositorySettings;
    Function ContextGetStashCommit(Const inStashIndex: Integer): Pgit_commit;
    Function ContextHandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
    Function ContextLibGit2Repository: Pgit_repository;
    Function ContextSolveConflicts: Boolean;
    Procedure ContextDoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
    Procedure ContextUpdateCurrentBranch;
    Procedure ContextRefreshBranches;
    Procedure ContextRefreshWorkTree;
    Procedure ContextSplitBranchName(Var outBranchName: String; Var outRemote: String);
  End;

Implementation

Uses System.SysUtils, AE.GitRepository;

Type
  TAEGitRepositoryAccess = Class(TAEGitRepository)
  End;

Function TAEGitRepositoryContextHelper.ContextAuthCallback(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).AuthCallback(outGitCredential, inURL, inUserName, inAllowedTypes);
End;

Function TAEGitRepositoryContextHelper.ContextGetDefaultRemoteName: String;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).GetDefaultRemoteName;
End;

Function TAEGitRepositoryContextHelper.ContextGetSettings: TAEGitRepositorySettings;
Begin
  Result := (Self As TAEGitRepository).Settings;
End;

Function TAEGitRepositoryContextHelper.ContextGetStashCommit(Const inStashIndex: Integer): Pgit_commit;
var
  reflog: Pgit_reflog;
  entry: Pgit_reflog_entry;
  count: NativeUInt;
  oid: Pgit_oid;
begin
  Result := nil;

  ContextHandleLibGit2Output('git_reflog_read', git_reflog_read(@reflog, ContextLibGit2Repository, 'refs/stash'));
  Try
    count := git_reflog_entrycount(reflog);

    ContextDoLibGit2Call('git_reflog_entrycount');

    entry := git_reflog_entry_byindex(reflog, count - 1 - Cardinal(inStashIndex));

    ContextDoLibGit2Call('git_reflog_entry_byindex');

    oid := git_reflog_entry_id_new(entry);

    ContextDoLibGit2Call('git_reflog_entry_id_new');

    ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@Result, ContextLibGit2Repository, oid));
  Finally
    git_reflog_free(reflog);

    ContextDoLibGit2Call('git_reflog_free');
  End;
End;

Function TAEGitRepositoryContextHelper.ContextHandleLibGit2Output(Const inMethod: String; Const inCommandResult: Integer; Const inRaiseException: Boolean = True): Boolean;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).HandleLibGit2Output(inMethod, inCommandResult, inRaiseException);
End;

Function TAEGitRepositoryContextHelper.ContextLibGit2Repository: Pgit_repository;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).LibGit2Repository;
End;

Function TAEGitRepositoryContextHelper.ContextSolveConflicts: Boolean;
Begin
  Result := TAEGitRepositoryAccess(Self As TAEGitRepository).SolveConflicts;
End;

Procedure TAEGitRepositoryContextHelper.ContextDoLibGit2Call(Const inMethod: String; Const inErrorCode: TAEGitErrorCode = geOK);
Begin
  TAEGitRepositoryAccess(Self As TAEGitRepository).DoLibGit2Call(inMethod, inErrorCode);
End;

Procedure TAEGitRepositoryContextHelper.ContextUpdateCurrentBranch;
Begin
  (Self As TAEGitRepository).Branches.UpdateCurrent;
End;

Procedure TAEGitRepositoryContextHelper.ContextRefreshBranches;
Begin
  (Self As TAEGitRepository).Branches.Refresh;
End;

Procedure TAEGitRepositoryContextHelper.ContextRefreshWorkTree;
Begin
  (Self As TAEGitRepository).WorkTree.Refresh;
End;

Procedure TAEGitRepositoryContextHelper.ContextSplitBranchName(Var outBranchName: String; Var outRemote: String);
Begin
  TAEGitRepositoryAccess(Self As TAEGitRepository).SplitBranchName(outBranchName, outRemote);
End;

End.
