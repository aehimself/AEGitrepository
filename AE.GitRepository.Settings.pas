{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Settings;

Interface

Uses System.SysUtils;

Type
  TAEGitRepositorySettings = Class
  strict private
    _email: String;
    _fullname: String;
    _password: String;
    _sshprivatekey: String;
    _sshpublickey: String;
    _username: String;
    _usesshkeyauth: Boolean;
  strict protected
    Procedure SetEmail(Const inEmail: String); Virtual;
    Procedure SetFullName(Const inFullName: String); Virtual;
    Procedure SetPassword(Const inPassword: String); Virtual;
    Procedure SetSSHPrivateKey(Const inSSHPrivateKey: String); Virtual;
    Procedure SetSSHPublicKey(Const inSSHPublicKey: String); Virtual;
    Procedure SetUserName(Const inUserName: String); Virtual;
    Procedure SetUseSSHKeyAuth(Const inUseSSHKeyAuth: Boolean); Virtual;
  public
    Constructor Create; ReIntroduce;
    Property EMailAddress: String Read _email Write SetEmail;
    Property FullName: String Read _fullname Write SetFullName;
    Property Password: String Read _password Write SetPassword;
    Property SSHPrivateKey: String Read _sshprivatekey Write SetSSHPrivateKey;
    Property SSHPublicKey: String Read _sshpublickey Write SetSSHPublicKey;
    Property UserName: String Read _username Write SetUserName;
    Property UseSSHKeyAuth: Boolean Read _usesshkeyauth Write SetUseSSHKeyAuth;
  End;

Implementation

Constructor TAEGitRepositorySettings.Create;
Begin
  inherited Create;

  _email := '';
  _fullname := '';
  _password := '';
  _sshprivatekey := '';
  _sshpublickey := '';
  _username := '';
  _usesshkeyauth := False;
End;

Procedure TAEGitRepositorySettings.SetFullName(Const inFullName: String);
Begin
  If _fullname = inFullName Then
    Exit;

  _fullname := inFullName;
End;

Procedure TAEGitRepositorySettings.SetPassword(Const inPassword: String);
Begin
  If _password = inPassword Then
    Exit;

  _password := inPassword;
End;

Procedure TAEGitRepositorySettings.SetSSHPrivateKey(Const inSSHPrivateKey: String);
Begin
  If _sshprivatekey = inSSHPrivateKey Then
    Exit;

  _sshprivatekey := inSSHPrivateKey;
End;

Procedure TAEGitRepositorySettings.SetSSHPublicKey(Const inSSHPublicKey: String);
Begin
  If _sshpublickey = inSSHPublicKey Then
    Exit;

  _sshpublickey := inSSHPublicKey;
End;

Procedure TAEGitRepositorySettings.SetUserName(Const inUserName: String);
Begin
  If _username = inUserName Then
    Exit;

  _username := inUserName;
End;

Procedure TAEGitRepositorySettings.SetUseSSHKeyAuth(Const inUseSSHKeyAuth: Boolean);
Begin
  If _usesshkeyauth = inUseSSHKeyAuth Then
    Exit;

  _usesshkeyauth := inUseSSHKeyAuth;
End;

Procedure TAEGitRepositorySettings.SetEmail(Const inEmail: String);
Begin
  If _email = inEmail Then
    Exit;

  _email := inEmail;
End;

End.
