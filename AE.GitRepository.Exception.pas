{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Exception;

Interface

Uses System.SysUtils, AE.GitRepository.TypeDef;

Type
  EAEGitException = Class(Exception)
  strict private
    _errorcode: TAEGitErrorCode;
    _lasterrorclass: Integer;
    _method: String;
  public
    Constructor Create(Const inErrorCode: TAEGitErrorCode; Const inMethod: String; Const inErrorClass: Integer; Const inMessage: String); ReIntroduce;
    Property ErrorCode: TAEGitErrorCode Read _errorcode;
    Property Method: String Read _method;
    Property LastErrorClass: Integer Read _lasterrorclass;
  End;

Implementation

Constructor EAEGitException.Create(Const inErrorCode: TAEGitErrorCode; Const inMethod: String; Const inErrorClass: Integer; Const inMessage: String);
Begin
  inherited Create(inMessage);

  _errorcode := inErrorCode;
  _method := inMethod;
  _lasterrorclass := inErrorClass;
End;

End.
