Unit AE.GitRepository.CommitDecorationCache;

Interface

Uses System.Generics.Collections;

Type
  TAEGitCommitDecorationType = ( cdtTag, cdtBranch );

  TAEGitCommitDecorationCache = Class
  strict private
    _decorationcache: TObjectDictionary<String, TObjectDictionary<TAEGitCommitDecorationType, TList<String>>>;
    _head: String;
    _loaded: Boolean;
    Procedure AddCommitDecoration(Const inCommitHash: String; Const inDecorationType: TAEGitCommitDecorationType; Const inDecoration: String);
    Function CommitDecorations(Const inCommitHash: String; Const inDecorationType: TAEGitCommitDecorationType): TArray<String>;
  public
    Constructor Create; ReIntroduce;
    Destructor Destroy; Override;
    Procedure AddCommitBranch(Const inCommitHash, inBranch: String);
    Procedure AddCommitTag(Const inCommitHash, inTag: String);
    Procedure Clear;
    Function CommitBranches(Const inCommitHash: String): TArray<String>;
    Function CommitTags(Const inCommitHash: String): TArray<String>;
    Property Head: String Read _head Write _head;
    Property Loaded: Boolean Read _loaded Write _loaded;
  End;

Implementation

Uses System.SysUtils;

Procedure TAEGitCommitDecorationCache.AddCommitBranch(Const inCommitHash, inBranch: String);
Begin
  Self.AddCommitDecoration(inCommitHash, cdtBranch, inBranch);
End;

Procedure TAEGitCommitDecorationCache.AddCommitDecoration(Const inCommitHash: String; Const inDecorationType: TAEGitCommitDecorationType; Const inDecoration: String);
Begin
  If Not _decorationcache.ContainsKey(inCommitHash) Then
    _decorationcache.Add(inCommitHash, TObjectDictionary<TAEGitCommitDecorationType, TList<String>>.Create([doOwnsValues]));

  If Not _decorationcache[inCommitHash].ContainsKey(inDecorationType) Then
    _decorationcache[inCommitHash].Add(inDecorationType, TList<String>.Create);

  If Not _decorationcache[inCommitHash][inDecorationType].Contains(inDecoration) Then
    _decorationcache[inCommitHash][inDecorationType].Add(inDecoration);
End;

Procedure TAEGitCommitDecorationCache.AddCommitTag(Const inCommitHash, inTag: String);
Begin
  Self.AddCommitDecoration(inCommitHash, cdtTag, inTag);
End;

Procedure TAEGitCommitDecorationCache.Clear;
Begin
  _decorationcache.Clear;
  _head := '';
  _loaded := False;
End;

Function TAEGitCommitDecorationCache.CommitBranches(Const inCommitHash: String): TArray<String>;
Begin
  Result := Self.CommitDecorations(inCommitHash, cdtBranch);
End;

Function TAEGitCommitDecorationCache.CommitDecorations(Const inCommitHash: String; Const inDecorationType: TAEGitCommitDecorationType): TArray<String>;
Begin
  If Not _decorationcache.ContainsKey(inCommitHash) Or Not _decorationcache[inCommitHash].ContainsKey(inDecorationType) Then
    Result := []
  Else
    Result := _decorationcache[inCommitHash][inDecorationType].ToArray;
End;

Function TAEGitCommitDecorationCache.CommitTags(Const inCommitHash: String): TArray<String>;
Begin
  Result := Self.CommitDecorations(inCommitHash, cdtTag);
End;

Constructor TAEGitCommitDecorationCache.Create;
Begin
  inherited;

  _decorationcache := TObjectDictionary<String, TObjectDictionary<TAEGitCommitDecorationType, TList<String>>>.Create([doOwnsValues]);
End;

Destructor TAEGitCommitDecorationCache.Destroy;
Begin
  FreeAndNil(_decorationcache);

  inherited;
End;

End.
