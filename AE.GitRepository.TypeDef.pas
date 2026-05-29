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
  TAEGitErrorCode = ( geOK, geError, geNotFound, geObjectExists, geMultipleMatches, geBufferTooSmall, geUnknown );

  TAEGitAuthType = ( atPlainText, atSSHKey, atSSHCustom, atDefault, atSSHInteractive, atUserName, atSSHMemory );

  TAEGitAuthTypes = Set Of TAEGitAuthType;

  TAEGitLibCallLogEvent = Procedure(Const inSender: TObject; Const inMethod: String; Const inErrorCode: TAEGitErrorCode) Of Object;

  TGitLibAuthCallback = Function(outGitCredential: PPgit_credential; inURL, inUserName: PAnsiChar; inAllowedTypes: TAEGitAuthTypes): Integer Of Object;

  TAEGitFileStatus = ( gfsCurrent, gfsStagedNew, gfsStagedModified, gfsStagedDeleted, gfsStagedRenamed, gfsStagedTypeChange,
    gfsNew, gfsModified, gfsDeleted, gfsTypeChange, gfsRenamed, gfsUnreadable, gfsIgnored, gfsConflicted );

  TAEGitStashList = Class(TDictionary<Integer, String>);

  PAEGitStashList = ^TAEGitStashList;

  TAEGitChangedFileList = Class(TDictionary<String, TArray<TAEGitFileStatus>>);

Const
  AEGITERRORCODESTR: Array[TAEGitErrorCode] Of String = ('OK', 'Error', 'Not found', 'Object already exists',
    'Multiple matches found', 'Buffer too small', 'Unknown');

  AEGITFILESTATUSSTR: Array[TAEGitFileStatus] Of String = ('Current', 'New', 'Modified', 'Deleted', 'Renamed',
    'Type change', 'New', 'Modified', 'Deleted', 'Type change', 'Renamed', 'Unreadable', 'Ignored', 'Conflicted');

Implementation

End.
