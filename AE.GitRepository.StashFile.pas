{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.StashFile;

Interface

Uses AE.GitRepository.FileObject, AE.GitRepository.TypeDef, AE.GitRepository.Context;

Type
  TAEGitStashFile = Class(TAEGitRepositoryFile)
  strict private
    _stashindex: Integer;
    Function GetStatus: TAEGitFileStatus;
  strict protected
    Function GetDiff: String; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashIndex: Integer; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
    Property Status: TAEGitFileStatus Read GetStatus;
  End;

Implementation

Uses libgit2;

Constructor TAEGitStashFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStashIndex: Integer; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext, inGitPath);

  _stashindex := inStashIndex;


  Self.InternalStatus := [inStatus];
End;

Function TAEGitStashFile.GetDiff: String;
Begin
  Result := Context.ContextGetStashPatch([Self.GitPath], _stashindex);
End;

Function TAEGitStashFile.GetStatus: TAEGitFileStatus;
Begin
  Result := Self.InternalStatus[0];
End;

End.
