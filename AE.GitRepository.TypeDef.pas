{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.TypeDef;

Interface

Uses libgit2, System.Generics.Collections;

Type
  TAEGitErrorCode = (
    geFalse = 1,
    geOk = 0,                 // GIT_OK
    geError = -1,             // GIT_ERROR
    geNotFound = -3,          // GIT_ENOTFOUND
    geObjectExists = -4,      // GIT_EEXISTS
    geAmbiguous = -5,         // GIT_EAMBIGUOUS
    geBufTooSmall = -6,       // GIT_EBUFS
    geUser = -7,              // GIT_EUSER
    geBareRepo = -8,          // GIT_EBAREREPO
    geUnbornBranch = -9,      // GIT_EUNBORNBRANCH
    geUnmerged = -10,         // GIT_EUNMERGED
    geNonFastForward = -11,   // GIT_ENONFASTFORWARD
    geInvalidSpec = -12,      // GIT_EINVALIDSPEC
    geConflict = -13,         // GIT_ECONFLICT
    geLocked = -14,           // GIT_ELOCKED
    geModified = -15,         // GIT_EMODIFIED
    geAuth = -16,             // GIT_EAUTH
    geCertificate = -17,      // GIT_ECERTIFICATE
    geAlreadyApplied = -18,   // GIT_EAPPLIED
    gePeel = -19,             // GIT_EPEEL
    geEOF = -20,              // GIT_EEOF
    geInvalid = -21,          // GIT_EINVALID
    geUncommitted = -22,      // GIT_EUNCOMMITTED
    geDirectory = -23,        // GIT_EDIRECTORY
    geMergeConflict = -24,    // GIT_EMERGECONFLICT
    gePassthrough = -30,      // GIT_PASSTHROUGH
    geIterationOver = -31,    // GIT_ITEROVER
    geRetry = -32,            // GIT_RETRY
    geHashMismatch = -33,     // GIT_EMISMATCH
    geIndexDirty = -34,       // GIT_EINDEXDIRTY
    geApplyFailed = -35,      // GIT_EAPPLYFAIL
    geWrongOwner = -36,       // GIT_EOWNER
    geTimeout = -37,          // GIT_TIMEOUT
    geUnchanged = -38,        // GIT_EUNCHANGED
    geNotSupported = -39,     // GIT_ENOTSUPPORTED
    geReadOnly = -40,         // GIT_EREADONLY
    geUnknown = -999
  );

  TAEGitErrorClass = (
    ecNone            = 0,    // GIT_ERROR_NONE
    ecNoMemory        = 1,    // GIT_ERROR_NOMEMORY
    ecOperatingSystem = 2,    // GIT_ERROR_OS
    ecInvalid         = 3,    // GIT_ERROR_INVALID
    ecReference       = 4,    // GIT_ERROR_REFERENCE
    ecZlib            = 5,    // GIT_ERROR_ZLIB
    ecRepository      = 6,    // GIT_ERROR_REPOSITORY
    ecConfig          = 7,    // GIT_ERROR_CONFIG
    ecRegex           = 8,    // GIT_ERROR_REGEX
    ecObjectDatabase  = 9,    // GIT_ERROR_ODB
    ecIndex           = 10,   // GIT_ERROR_INDEX
    ecObject          = 11,   // GIT_ERROR_OBJECT
    ecNetwork         = 12,   // GIT_ERROR_NET
    ecTag             = 13,   // GIT_ERROR_TAG
    ecTree            = 14,   // GIT_ERROR_TREE
    ecIndexer         = 15,   // GIT_ERROR_INDEXER
    ecSsl             = 16,   // GIT_ERROR_SSL
    ecSubmodule       = 17,   // GIT_ERROR_SUBMODULE
    ecThread          = 18,   // GIT_ERROR_THREAD
    ecStash           = 19,   // GIT_ERROR_STASH
    ecCheckout        = 20,   // GIT_ERROR_CHECKOUT
    ecFetchHead       = 21,   // GIT_ERROR_FETCHHEAD
    ecMerge           = 22,   // GIT_ERROR_MERGE
    ecSsh             = 23,   // GIT_ERROR_SSH
    ecFilter          = 24,   // GIT_ERROR_FILTER
    ecRevert          = 25,   // GIT_ERROR_REVERT
    ecCallback        = 26,   // GIT_ERROR_CALLBACK
    ecCherryPick      = 27,   // GIT_ERROR_CHERRYPICK
    ecDescribe        = 28,   // GIT_ERROR_DESCRIBE
    ecRebase          = 29,   // GIT_ERROR_REBASE
    ecFileSystem      = 30,   // GIT_ERROR_FILESYSTEM
    ecPatch           = 31,   // GIT_ERROR_PATCH
    ecWorkTree        = 32,   // GIT_ERROR_WORKTREE
    ecSha             = 33,   // GIT_ERROR_SHA
    ecHttp            = 34,   // GIT_ERROR_HTTP
    ecInternal        = 35,   // GIT_ERROR_INTERNAL
    ecGrafts          = 36,   // GIT_ERROR_GRAFTS
    ecUnknown         = 999
  );

  TAEGitAuthType = (
    gaUserPassPlainText = 1,   // GIT_CREDENTIAL_USERPASS_PLAINTEXT
    gaSshKey = 2,              // GIT_CREDENTIAL_SSH_KEY
    gaSshCustom = 4,           // GIT_CREDENTIAL_SSH_CUSTOM
    gaDefault = 8,             // GIT_CREDENTIAL_DEFAULT
    gaSshInteractive = 16,     // GIT_CREDENTIAL_SSH_INTERACTIVE
    gaUsername = 32,           // GIT_CREDENTIAL_USERNAME
    gaSshMemory = 64           // GIT_CREDENTIAL_SSH_MEMORY
  );

  TAEGitAuthTypes = Set Of TAEGitAuthType;

  TAEGitLibCallLogEvent = Procedure(Const inSender: TObject; Const inMethod: String; Const inErrorCode: TAEGitErrorCode) Of Object;

  TGitLibAuthCallback = Function(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer Of Object;

  TAEGitFileStatus = ( gfsCurrent, gfsStagedNew, gfsStagedModified, gfsStagedDeleted, gfsStagedRenamed, gfsStagedTypeChange,
    gfsNew, gfsModified, gfsDeleted, gfsTypeChange, gfsRenamed, gfsUnreadable, gfsIgnored, gfsConflicted );

  TAEGitStashList = Class(TList<String>);

  PAEGitStashList = ^TAEGitStashList;

  TAEGitChangedFileList = Class(TDictionary<String, TArray<TAEGitFileStatus>>);

  TAEGitBranchType = ( gbLocal, gbRemote, gbAll );

  TAEGitCommit = Class
  strict private
    _author: String;
    _authoremail: String;
    _branches: TArray<String>;
    _committer: String;
    _committeremail: String;
    _datetime: TDateTime;
    _hash: String;
    _head: Boolean;
    _message: String;
    _parentcommithashes: TArray<String>;
    _summary: String;
    _tags: TArray<String>;
  public
    Constructor Create(Const inAuthor, inAuthorEmail, inCommitter, inCommitterEmail, inHash, inMessage, inSummary: String; Const inDateTime: TDateTime; Const inParentCommitHashes, inTags, inBranches: TArray<String>; Const inHead: Boolean); ReIntroduce;
    Property Author: String Read _author;
    Property AuthorEmail: String Read _authoremail;
    Property Branches: TArray<String> Read _branches;
    Property Committer: String Read _committer;
    Property CommitterEmail: String Read _committeremail;
    Property DateTime: TDateTime Read _datetime;
    Property Hash: String Read _hash;
    Property Head: Boolean Read _head;
    Property Message: String Read _message;
    Property ParentCommitHashes: TArray<String> Read _parentcommithashes;
    Property Summary: String Read _summary;
    Property Tags: TArray<String> Read _tags;
  End;

  TAEGitCommitDecorationType = ( dtTag, dtBranch );

  TAEGitCommitDecorationCache = Class(TObjectDictionary<String, TObjectDictionary<TAEGitCommitDecorationType, TList<String>>>)
  strict private
    _head: String;
  public
    Constructor Create; ReIntroduce;
    Procedure AddItem(Const inHash: String; Const inType: TAEGitCommitDecorationType; Const inItem: String);
    Function Items(Const inHash: String; Const inType: TAEGitCommitDecorationType): TArray<String>;
    Property Head: String Read _head Write _head;
  End;

  TAEGitCommitList = Class(TObjectDictionary<String, TAEGitCommit>)
  strict private
    _order: TList<String>;
    Function GetOrderedList: TArray<TAEGitCommit>;
  protected
    Procedure KeyNotify(Const inKey: String; inAction: TCollectionNotification); Override;
  public
    Constructor Create; ReIntroduce;
    Destructor Destroy; Override;
    Property OrderedList: TArray<TAEGitCommit> Read GetOrderedList;
  End;

Const
  AEGITFILESTATUSSTR: Array[TAEGitFileStatus] Of String = ('Current', 'New', 'Modified', 'Deleted', 'Renamed',
    'Type change', 'New', 'Modified', 'Deleted', 'Type change', 'Renamed', 'Unreadable', 'Ignored', 'Conflicted');

Function AEGitErrorDescription(Const inErrorCode: TAEGitErrorCode): String;
Function AEGitErrorClassDescription(Const inErrorClass: TAEGitErrorClass): String;

Implementation

Uses System.SysUtils;

Function AEGitErrorDescription(Const inErrorCode: TAEGitErrorCode): String;
Begin
  Case inErrorCode Of
    geFalse:
      Result := 'False';
    geOk:
      Result := 'Success';
    geError:
      Result := 'Generic error';
    geNotFound:
      Result := 'Requested object could not be found';
    geObjectExists:
      Result := 'Object exists preventing operation';
    geAmbiguous:
      Result := 'More than one object matches';
    geBufTooSmall:
      Result := 'Output buffer too short to hold data';
    geUser:
      Result := 'Generated by user callback';
    geBareRepo:
      Result := 'Operation not allowed on bare repository';
    geUnbornBranch:
      Result := 'HEAD refers to a branch with no commits';
    geUnmerged:
      Result := 'Merge in progress prevented operation';
    geNonFastForward:
      Result := 'Reference was not fast-forwardable';
    geInvalidSpec:
      Result := 'Name/ref specification is invalid';
    geConflict:
      Result := 'Checkout conflicts prevented operation';
    geLocked:
      Result := 'Lock file prevented operation';
    geModified:
      Result := 'Reference value does not match expected';
    geAuth:
      Result := 'Authentication error';
    geCertificate:
      Result := 'Server certificate is invalid';
    geAlreadyApplied:
      Result := 'Patch or merge has already been applied';
    gePeel:
      Result := 'Requested peel operation is not possible';
    geEOF:
      Result := 'Unexpected end of file';
    geInvalid:
      Result := 'Invalid operation or input';
    geUncommitted:
      Result := 'Uncommitted changes prevented operation';
    geDirectory:
      Result := 'Operation is not valid for a directory';
    geMergeConflict:
      Result := 'Merge conflict exists and cannot continue';
    gePassthrough:
      Result := 'User-configured callback refused to act';
    geIterationOver:
      Result := 'End of iteration';
    geRetry:
      Result := 'Internal retry requested';
    geHashMismatch:
      Result := 'Object hash mismatch';
    geIndexDirty:
      Result := 'Unsaved index changes would be overwritten';
    geApplyFailed:
      Result := 'Patch application failed';
    geWrongOwner:
      Result := 'Object is not owned by the current user';
    geTimeout:
      Result := 'Operation timed out';
    geUnchanged:
      Result := 'There were no changes';
    geNotSupported:
      Result := 'Option is not supported';
    geReadOnly:
      Result := 'Subject is read-only';
    Else // geUnknown
      Result := 'Unknown libgit2 error';
  End;
End;

Function AEGitErrorClassDescription(Const inErrorClass: TAEGitErrorClass): String;
Begin
  Case inErrorClass Of
    ecNone:
      Result := 'No error';
    ecNoMemory:
      Result := 'Out of memory';
    ecOperatingSystem:
      Result := 'Operating system error';
    ecInvalid:
      Result := 'Invalid argument or state';
    ecReference:
      Result := 'Reference error';
    ecZlib:
      Result := 'Zlib compression/decompression error';
    ecRepository:
      Result := 'Repository error';
    ecConfig:
      Result := 'Configuration error';
    ecRegex:
      Result := 'Regular expression error';
    ecObjectDatabase:
      Result := 'Object database (ODB) error';
    ecIndex:
      Result := 'Index error';
    ecObject:
      Result := 'Object error';
    ecNetwork:
      Result := 'Network error';
    ecTag:
      Result := 'Tag error';
    ecTree:
      Result := 'Tree error';
    ecIndexer:
      Result := 'Indexer error';
    ecSsl:
      Result := 'SSL/TLS error';
    ecSubmodule:
      Result := 'Submodule error';
    ecThread:
      Result := 'Threading error';
    ecStash:
      Result := 'Stash error';
    ecCheckout:
      Result := 'Checkout error';
    ecFetchHead:
      Result := 'FETCH_HEAD error';
    ecMerge:
      Result := 'Merge error';
    ecSsh:
      Result := 'SSH error';
    ecFilter:
      Result := 'Filter error';
    ecRevert:
      Result := 'Revert error';
    ecCallback:
      Result := 'Callback error';
    ecCherryPick:
      Result := 'Cherry-pick error';
    ecDescribe:
      Result := 'Describe error';
    ecRebase:
      Result := 'Rebase error';
    ecFileSystem:
      Result := 'File system error';
    ecPatch:
      Result := 'Patch error';
    ecWorkTree:
      Result := 'Worktree error';
    ecSha:
      Result := 'SHA/hash error';
    ecHttp:
      Result := 'HTTP error';
    ecInternal:
      Result := 'Internal libgit2 error';
    ecGrafts:
      Result := 'Grafts error';
    Else // ecUnknown
      Result := 'Unknown or unsupported libgit2 error class';
  End;
End;

//
// TAEGitCommit
//

Constructor TAEGitCommit.Create(Const inAuthor, inAuthorEmail, inCommitter, inCommitterEmail, inHash, inMessage, inSummary: String; Const inDateTime: TDateTime; Const inParentCommitHashes, inTags, inBranches: TArray<String>; Const inHead: Boolean);
Begin
  inherited Create;

  _author := inAuthor;
  _authoremail := inAuthorEmail;
  _branches := inBranches;
  _committer := inCommitter;
  _committeremail := inCommitterEmail;
  _datetime := inDateTime;
  _hash := inHash;
  _head := inHead;
  _message := inMessage;
  _parentcommithashes := inParentCommitHashes;
  _summary := inSummary;
  _tags := inTags;
End;

//
// TAEGitCommitList
//

Constructor TAEGitCommitList.Create;
Begin
  inherited Create([doOwnsValues]);

  _order := TList<String>.Create;
End;

Destructor TAEGitCommitList.Destroy;
Begin
  inherited;

  FreeAndNil(_order);
End;

Function TAEGitCommitList.GetOrderedList: TArray<TAEGitCommit>;
Var
  a: NativeInt;
Begin
  SetLength(Result, _order.Count);

  For a := 0 To _order.Count - 1 Do
    Result[a] := Self[_order[a]];
End;

Procedure TAEGitCommitList.KeyNotify(Const inKey: String; inAction: TCollectionNotification);
Begin
  inherited;

  Case inAction Of
    cnRemoved:
      _order.Remove(inKey);
    cnAdded:
      _order.Add(inKey);
  End;
End;

//
// TAEGitCommitDecorationCache
//

Constructor TAEGitCommitDecorationCache.Create;
Begin
  inherited Create([doOwnsValues]);
End;

Function TAEGitCommitDecorationCache.Items(Const inHash: String; Const inType: TAEGitCommitDecorationType): TArray<String>;
Begin
  If Not Self.ContainsKey(inHash) Or Not Self[inHash].ContainsKey(inType) Then
    Result := []
  Else
    Result := Self[inHash][inType].ToArray;
End;

Procedure TAEGitCommitDecorationCache.AddItem(Const inHash: String; Const inType: TAEGitCommitDecorationType; Const inItem: String);
Begin
  If Not Self.ContainsKey(inHash) Then
    Self.Add(inHash, TObjectDictionary<TAEGitCommitDecorationType, TList<String>>.Create([doOwnsValues]));

  If Not Self[inHash].ContainsKey(inType) Then
    Self[inHash].Add(inType, TList<String>.Create);

  Self[inHash][inType].Add(inItem);
End;

End.
