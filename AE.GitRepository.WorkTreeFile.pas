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
  strict protected
    Function CacheDiffs: Boolean; Override;
    Function GetDiffString: String; Override;
    Function GetOriginalContent: String; Override;
    Function InternalGetOriginalContent: String; Override;
  public
    Procedure Revert;
    Procedure Stage;
    Procedure Unstage;
  End;

Implementation

Uses libgit2, System.SysUtils;

Function TAEGitWorkTreeFile.GetDiffString: String;
Begin
  Result := Self.GetPatchFromWorkTree([Self.GitPath], Self.Status In AEGITSTAGEDFILESTATUSES);
End;

Function TAEGitWorkTreeFile.GetOriginalContent: String;
Begin
  // Skip caching

  Result := InternalGetOriginalContent;
End;

Function TAEGitWorkTreeFile.InternalGetOriginalContent: String;
Var
  index: Pgit_index;
  entry: Pgit_index_entry;
Begin
  Result := '';

  Context.HandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.Repository));
  Try
    entry := git_index_get_bypath(index, PAnsiChar(UTF8String(Self.GitPath)), 0);

    Context.DoLibGit2Call('git_index_get_bypath');

    If Assigned(entry) Then
      Result := Self.GetBlobContent(@entry.id, Context.Repository);
  Finally
    git_index_free(index);

    Context.DoLibGit2Call('git_index_free');
  End;
End;

Function TAEGitWorkTreeFile.CacheDiffs: Boolean;
Begin
  Result := False;
End;

Procedure TAEGitWorkTreeFile.Revert;
Begin
  Context.RevertFile(Self.GitPath);
End;

Procedure TAEGitWorkTreeFile.Stage;
Begin
  Context.StageFile(Self.GitPath);
End;

Procedure TAEGitWorkTreeFile.Unstage;
Begin
  Context.UnstageFile(Self.GitPath);
End;

End.
