{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.TypeDef;

Interface

Uses libgit2;

Type
  TAEGitErrorCode = (
    geOk,                     // GIT_OK
    geError,                  // GIT_ERROR
    geNotFound,               // GIT_ENOTFOUND
    geObjectExists,           // GIT_EEXISTS
    geAmbiguous,              // GIT_EAMBIGUOUS
    geBufTooSmall,            // GIT_EBUFS
    geUser,                   // GIT_EUSER
    geBareRepo,               // GIT_EBAREREPO
    geUnbornBranch,           // GIT_EUNBORNBRANCH
    geUnmerged,               // GIT_EUNMERGED
    geNonFastForward,         // GIT_ENONFASTFORWARD
    geInvalidSpec,            // GIT_EINVALIDSPEC
    geConflict,               // GIT_ECONFLICT
    geLocked,                 // GIT_ELOCKED
    geModified,               // GIT_EMODIFIED
    geAuth,                   // GIT_EAUTH
    geCertificate,            // GIT_ECERTIFICATE
    geAlreadyApplied,         // GIT_EAPPLIED
    gePeel,                   // GIT_EPEEL
    geEOF,                    // GIT_EEOF
    geInvalid,                // GIT_EINVALID
    geUncommitted,            // GIT_EUNCOMMITTED
    geDirectory,              // GIT_EDIRECTORY
    geMergeConflict,          // GIT_EMERGECONFLICT
    gePassthrough,            // GIT_PASSTHROUGH
    geIterationOver,          // GIT_ITEROVER
    geRetry,                  // GIT_RETRY
    geHashMismatch,           // GIT_EMISMATCH
    geIndexDirty,             // GIT_EINDEXDIRTY
    geApplyFailed,            // GIT_EAPPLYFAIL
    geWrongOwner,             // GIT_EOWNER
    geTimeout,                // GIT_TIMEOUT
    geUnchanged,              // GIT_EUNCHANGED
    geNotSupported,           // GIT_ENOTSUPPORTED
    geReadOnly,               // GIT_EREADONLY
    geFalse,                  // Generic "False" result for boolean-style libgit2 calls
    geTrue,                   // Generic "True" result for boolean-style libgit2 calls
    geUnknown
  );

  TAEGitErrorClass = (
    ecNone,             // GIT_ERROR_NONE
    ecNoMemory,         // GIT_ERROR_NOMEMORY
    ecOperatingSystem,  // GIT_ERROR_OS
    ecInvalid,          // GIT_ERROR_INVALID
    ecReference,        // GIT_ERROR_REFERENCE
    ecZlib,             // GIT_ERROR_ZLIB
    ecRepository,       // GIT_ERROR_REPOSITORY
    ecConfig,           // GIT_ERROR_CONFIG
    ecRegex,            // GIT_ERROR_REGEX
    ecObjectDatabase,   // GIT_ERROR_ODB
    ecIndex,            // GIT_ERROR_INDEX
    ecObject,           // GIT_ERROR_OBJECT
    ecNetwork,          // GIT_ERROR_NET
    ecTag,              // GIT_ERROR_TAG
    ecTree,             // GIT_ERROR_TREE
    ecIndexer,          // GIT_ERROR_INDEXER
    ecSsl,              // GIT_ERROR_SSL
    ecSubmodule,        // GIT_ERROR_SUBMODULE
    ecThread,           // GIT_ERROR_THREAD
    ecStash,            // GIT_ERROR_STASH
    ecCheckout,         // GIT_ERROR_CHECKOUT
    ecFetchHead,        // GIT_ERROR_FETCHHEAD
    ecMerge,            // GIT_ERROR_MERGE
    ecSsh,              // GIT_ERROR_SSH
    ecFilter,           // GIT_ERROR_FILTER
    ecRevert,           // GIT_ERROR_REVERT
    ecCallback,         // GIT_ERROR_CALLBACK
    ecCherryPick,       // GIT_ERROR_CHERRYPICK
    ecDescribe,         // GIT_ERROR_DESCRIBE
    ecRebase,           // GIT_ERROR_REBASE
    ecFileSystem,       // GIT_ERROR_FILESYSTEM
    ecPatch,            // GIT_ERROR_PATCH
    ecWorkTree,         // GIT_ERROR_WORKTREE
    ecSha,              // GIT_ERROR_SHA
    ecHttp,             // GIT_ERROR_HTTP
    ecInternal,         // GIT_ERROR_INTERNAL
    ecGrafts,           // GIT_ERROR_GRAFTS
    ecUnknown
  );

  TAEGitAuthType = (
    gaUserPassPlainText,   // GIT_CREDENTIAL_USERPASS_PLAINTEXT
    gaSshKey,              // GIT_CREDENTIAL_SSH_KEY
    gaSshCustom,           // GIT_CREDENTIAL_SSH_CUSTOM
    gaDefault,             // GIT_CREDENTIAL_DEFAULT
    gaSshInteractive,      // GIT_CREDENTIAL_SSH_INTERACTIVE
    gaUsername,            // GIT_CREDENTIAL_USERNAME
    gaSshMemory            // GIT_CREDENTIAL_SSH_MEMORY
  );

  TAEGitAuthTypes = Set Of TAEGitAuthType;

  TAEGitErrorCodes = Set Of TAEGitErrorCode;

  TAELibGit2CallLogEvent = Procedure(Const inSender: TObject; Const inMethod: String; Const inErrorCode: TAEGitErrorCode) Of Object;

  TAELibGit2AuthCallback = Function(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer Of Object;

  TAEGitBlockConflictChoice = ( ccOurs, ccTheirs, ccAbort );

  TAEGitBlockConflictCallback = Procedure(Const inFileName, inOurs, inTheirs: String; Var outChoice: TAEGitBlockConflictChoice) Of Object;

  TAEGitMergeConflictCallback = Procedure(Const inFileName: String; Var outConflictedBuffer: String; Var ConflictSolved: Boolean) Of Object;

  TAEGitFileStatus = ( gfsCurrent, gfsStagedNew, gfsStagedModified, gfsStagedDeleted, gfsStagedRenamed, gfsStagedTypeChange,
    gfsNew, gfsModified, gfsDeleted, gfsTypeChange, gfsRenamed, gfsUnreadable, gfsIgnored, gfsConflicted, gfsCopied, gfsUntracked );

  TAEGitBranchType = ( gbLocal, gbRemote, gbAll );

Const
  AEGITFILESTATUSSTR: Array[TAEGitFileStatus] Of String = ('Current', 'New', 'Modified', 'Deleted', 'Renamed',
    'Type change', 'New', 'Modified', 'Deleted', 'Type change', 'Renamed', 'Unreadable', 'Ignored', 'Conflicted',
    'Copied', 'Untracked');

Function AEGitErrorDescription(Const inErrorCode: TAEGitErrorCode): String;
Function AEGitErrorClassDescription(Const inErrorClass: TAEGitErrorClass): String;

Implementation

Uses System.SysUtils;

Function AEGitErrorDescription(Const inErrorCode: TAEGitErrorCode): String;
Begin
  Case inErrorCode Of
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
    geFalse:
      Result := 'False';
    geTrue:
      Result := 'True';
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

End.
