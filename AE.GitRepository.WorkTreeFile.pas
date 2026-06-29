{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.WorkTreeFile;

Interface

Uses AE.GitRepository.FileObject, AE.GitRepository.TypeDef, AE.GitRepository.Context;

Type
  TAEGitWorkTreeFile = Class(TAEGitRepositoryFile)
  strict private
    Procedure SetStatus(Const inStatus: TArray<TAEGitFileStatus>);
    Function GetStatus: TArray<TAEGitFileStatus>;
  strict protected
    Function GetDiff: String; Override;
    Function GetStagedDiff: String;
  public
    Procedure Revert;
    Procedure Stage;
    Procedure Unstage;
    Property StagedDiff: String Read GetStagedDiff;
    Property Status: TArray<TAEGitFileStatus> Read GetStatus Write SetStatus;
  End;

Implementation

Uses libgit2;

Function TAEGitWorkTreeFile.GetDiff: String;
Begin
  Result := Self.GetPatchFromWorkTree([Self.GitPath], False);
End;

Function TAEGitWorkTreeFile.GetStagedDiff: String;
Begin
  Result := Self.GetPatchFromWorkTree([Self.GitPath], True);
End;

Function TAEGitWorkTreeFile.GetStatus: TArray<TAEGitFileStatus>;
Begin
  Result := Self.InternalStatus;
End;

Procedure TAEGitWorkTreeFile.Revert;
Var
  options: git_checkout_options;
  pathstring: PAnsiChar;
  utf8path: UTF8String;
Begin
  utf8path := UTF8String(Self.GitPath);
  pathstring := PAnsiChar(utf8path);

  Context.ContextHandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_FORCE Or GIT_CHECKOUT_REMOVE_UNTRACKED Or GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH;
  options.paths.count := 1;
  options.paths.strings := @pathstring;

  Context.ContextHandleLibGit2Output('git_checkout_tree', git_checkout_tree(Context.ContextLibGit2Repository, nil, @options));
End;

Procedure TAEGitWorkTreeFile.SetStatus(Const inStatus: TArray<TAEGitFileStatus>);
Begin
  Self.InternalStatus := inStatus;
End;

Procedure TAEGitWorkTreeFile.Stage;
Var
  index: Pgit_index;
Begin
  Context.ContextHandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.ContextLibGit2Repository));
  Try
    Context.ContextHandleLibGit2Output('git_index_add_bypath', git_index_add_bypath(index, PAnsiChar(UTF8String(Self.GitPath))));

    Context.ContextHandleLibGit2Output('git_index_write', git_index_write(index));
  Finally
    git_index_free(index);

    Context.ContextDoLibGit2Call('git_index_free');
  End;
End;

Procedure TAEGitWorkTreeFile.Unstage;
Var
  filename: PAnsiChar;
  pathspec: git_strarray;
  target: Pgit_object;
  utf8filename: UTF8String;
Begin
  Context.ContextHandleLibGit2Output('git_revparse_single', git_revparse_single(@target, Context.ContextLibGit2Repository, 'HEAD'));
  Try
    utf8filename := UTF8String(Self.GitPath);
    filename := PAnsiChar(utf8filename);

    pathspec.count := 1;
    pathspec.strings := @filename;

    Context.ContextHandleLibGit2Output('git_reset_default', git_reset_default(Context.ContextLibGit2Repository, target, @pathspec));
  Finally
    git_object_free(target);

    Context.ContextDoLibGit2Call('git_object_free');
  End;
End;

End.
