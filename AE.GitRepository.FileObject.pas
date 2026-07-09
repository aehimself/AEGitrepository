{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.FileObject;

Interface

Uses AE.GitRepository.ContextedObject, AE.GitRepository.TypeDef, AE.Gitrepository.Context;

Type
  TAEGitRepositoryFile = Class(TAEGitRepositoryContextedObject)
  strict private
    _status: TArray<TAEGitFileStatus>;
    _gitpath: String;
  strict protected
    Function GetDiff: String; Virtual; Abstract;
    Property InternalStatus: TArray<TAEGitFileStatus> Read _status Write _status;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String); ReIntroduce; Virtual;
    Property Diff: String Read GetDiff;
    Property GitPath: String Read _gitpath;
  End;

Implementation

Constructor TAEGitRepositoryFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String);
Begin
  inherited Create(inContext);

  _gitpath := inGitPath;
  _status := [];
End;

End.
