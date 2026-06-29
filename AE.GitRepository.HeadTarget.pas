{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.HeadTarget;

Interface

Uses AE.GitRepository.DiffCapableObject;

Type
  TAEGitHeadTarget = Class(TAEGitRepositoryDiffCapableObject)
  strict protected
    Procedure InternalCheckout; Virtual; Abstract;
  public
    Procedure Checkout;
  End;

Implementation

Procedure TAEGitHeadTarget.Checkout;
Begin
  InternalCheckout;
End;

End.
