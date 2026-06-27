{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.ContextedObject;

Interface

Uses AE.GitRepository.Context;

Type
  TAEGitRepositoryContextedObject = Class
  strict private
    _context: TAEGitRepositoryContext;
  strict protected
    Property Context: TAEGitRepositoryContext Read _context;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext); ReIntroduce; Virtual;
  End;

Implementation

Constructor TAEGitRepositoryContextedObject.Create(Const inContext: TAEGitRepositoryContext);
Begin
  inherited Create;

  _context := inContext;
End;

End.
