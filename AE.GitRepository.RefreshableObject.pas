{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.RefreshableObject;

Interface

Uses AE.GitRepository.ContextedObject;

Type
  TAEGitRepositoryRefreshableObject = Class(TAEGitRepositoryContextedObject)
  strict private
    _loaded: Boolean;
  strict protected
    Procedure InternalClear; Virtual; Abstract;
    Procedure InternalRefresh; Virtual; Abstract;
    Property Loaded: Boolean Read _loaded Write _loaded;
  public
    Procedure AfterConstruction; Override;
    Procedure Clear;
    Procedure Refresh(Const inForceLoading: Boolean = True);
  End;

Implementation

Procedure TAEGitRepositoryRefreshableObject.AfterConstruction;
Begin
  inherited;

  Self.Clear;
End;

Procedure TAEGitRepositoryRefreshableObject.Clear;
Begin
  Self.InternalClear;

  _loaded := False;
End;

Procedure TAEGitRepositoryRefreshableObject.Refresh(Const inForceLoading: Boolean = True);
Begin
  If _loaded Or inForceLoading Then
    Self.InternalRefresh;
End;

End.
