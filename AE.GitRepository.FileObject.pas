{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.FileObject;

Interface

Uses AE.GitRepository.ContextedObject, AE.GitRepository.TypeDef, AE.Gitrepository.Context, AE.GitRepository.Diff;

Type
  TAEGitRepositoryFile = Class(TAEGitRepositoryContextedObject)
  strict private
    _diff: TAEGitDiff;
    _gitpath: String;
    _originalcontent: String;
    _status: TAEGitFileStatus;
  strict protected
    Function CacheDiffs: Boolean; Virtual;
    Function GetDiff: TAEGitDiff; Virtual;
    Function GetDiffString: String; Virtual; Abstract;
    Function GetOriginalContent: String; Virtual;
    Function InternalGetOriginalContent: String; Virtual; Abstract;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStatus: TAEGitFileStatus); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Property Diff: TAEGitDiff Read GetDiff;
    Property GitPath: String Read _gitpath;
    Property OriginalContent: String Read GetOriginalContent;
    Property Status: TAEGitFileStatus Read _status;
  End;

Implementation

Uses System.SysUtils;

Constructor TAEGitRepositoryFile.Create(Const inContext: TAEGitRepositoryContext; Const inGitPath: String; Const inStatus: TAEGitFileStatus);
Begin
  inherited Create(inContext);

  _diff := TAEGitDiff.Create(Self.CacheDiffs);
  _gitpath := inGitPath;
  _status := inStatus;
End;

Function TAEGitRepositoryFile.CacheDiffs: Boolean;
Begin
  Result := True;
End;

Destructor TAEGitRepositoryFile.Destroy;
Begin
  FreeAndNil(_diff);

  inherited;
End;

Function TAEGitRepositoryFile.GetDiff: TAEGitDiff;
Begin
  If Not _diff.IsCached Then
    _diff.AsString := Self.GetDiffString;

  Result := _diff;
End;

Function TAEGitRepositoryFile.GetOriginalContent: String;
Begin
  If _originalcontent.IsEmpty Then
    _originalcontent := InternalGetOriginalContent;

  Result := _originalcontent;
End;

End.
