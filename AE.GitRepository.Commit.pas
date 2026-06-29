{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Commit;

Interface

Uses AE.GitRepository.Context, AE.GitRepository.HeadTarget, AE.GitRepository.CommitFile, libgit2;

Type
  TAEGitCommit = Class(TAEGitHeadTarget)
  strict private
    _author: String;
    _authoremail: String;
    _branches: TArray<String>;
    _changedfiles: TAEGitCommitFileList;
    _changedfilesloaded: Boolean;
    _committer: String;
    _committeremail: String;
    _datetime: TDateTime;
    _detailsloaded: Boolean;
    _hash: String;
    _head: Boolean;
    _message: String;
    _original_offset: Integer;
    _original_timestamp: git_time_t;
    _parentcommithashes: TArray<String>;
    _summary: String;
    _tags: TArray<String>;
    Procedure AddUniqueString(Var outArray: TArray<String>; Const inValue: String);
    Procedure LoadDecorations;
    Procedure LoadDetails;
    Procedure LoadFiles;
    Function GetAuthor: String;
    Function GetAuthorEmail: String;
    Function GetBranches: TArray<String>;
    Function GetFileNames: TArray<String>;
    Function GetFile(Const inGitPath: String): TAEGitCommitFile;
    Function GetCommitter: String;
    Function GetCommitterEmail: String;
    Function GetDateTime: TDateTime;
    Function GetHead: Boolean;
    Function GetMessage: String;
    Function GetParentCommitHashes: TArray<String>;
    Function GetSummary: String;
    Function GetTags: TArray<String>;
  strict protected
    Procedure InternalCheckout; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inHash: String); ReIntroduce;
    Destructor Destroy; Override;
    Procedure CherryPick;
    Procedure Clear;
    Function Diff: String;
    Property Author: String Read GetAuthor;
    Property AuthorEmail: String Read GetAuthorEmail;
    Property Branches: TArray<String> Read GetBranches;
    Property Committer: String Read GetCommitter;
    Property CommitterEmail: String Read GetCommitterEmail;
    Property DateTime: TDateTime Read GetDateTime;
    Property Hash: String Read _hash;
    Property Head: Boolean Read GetHead;
    Property FileNames: TArray<String> Read GetFileNames;
    Property Files[Const inGitPath: String]: TAEGitCommitFile Read GetFile; Default;
    Property Message: String Read GetMessage;
    Property ParentCommitHashes: TArray<String> Read GetParentCommitHashes;
    Property Summary: String Read GetSummary;
    Property Tags: TArray<String> Read GetTags;
  End;

Implementation

Uses System.SysUtils, AE.GitRepository.TypeDef, System.DateUtils, System.Generics.Collections;

Procedure TAEGitCommit.CherryPick;
Var
  oid, treeoid, newcommitoid: git_oid;
  commit, parentcommit: Pgit_commit;
  options: git_cherrypick_options;
  index: Pgit_index;
  tree: Pgit_tree;
  headref: Pgit_reference;
  parentoid: Pgit_oid;
  author, committer: Pgit_signature;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Context.ContextHandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.ContextLibGit2Repository, @oid));
  Try
    Context.ContextHandleLibGit2Output('git_cherrypick_options_init', git_cherrypick_options_init(@options, GIT_CHERRYPICK_OPTIONS_VERSION));

    Context.ContextHandleLibGit2Output('git_cherrypick', git_cherrypick(Context.ContextLibGit2Repository, commit, @options));

    Context.ContextHandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.ContextLibGit2Repository));
    Try
      If Not Context.ContextSolveConflicts Then
        Exit;

      Context.ContextHandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeoid, index));

      Context.ContextHandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, Context.ContextLibGit2Repository, @treeoid));
      Try
        Context.ContextHandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.ContextLibGit2Repository));
        Try
          parentoid := git_reference_target(headref);

          Context.ContextDoLibGit2Call('git_reference_target');

          Context.ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@parentcommit, Context.ContextLibGit2Repository, parentoid));
          Try
            Context.ContextHandleLibGit2Output('git_signature_new', git_signature_new(@author, PAnsiChar(UTF8String(_author)), PAnsiChar(UTF8String(_authoremail)), _original_timestamp, _original_offset));
            Try
              Context.ContextHandleLibGit2Output('git_signature_now', git_signature_now(@committer, PAnsiChar(UTF8String(Context.ContextGetSettings.FullName)), PAnsiChar(UTF8String(Context.ContextGetSettings.EMailAddress))));
              Try
                Context.ContextHandleLibGit2Output('git_commit_create', git_commit_create(
                  @newcommitoid,
                  Context.ContextLibGit2Repository,
                  'HEAD',
                  author,
                  committer,
                  nil,
                  PAnsiChar(UTF8String(_message)),
                  tree,
                  1,
                  @parentcommit));
              Finally
                git_signature_free(committer);

                Context.ContextDoLibGit2Call('git_signature_free');
              End;
            Finally
              git_signature_free(author);

              Context.ContextDoLibGit2Call('git_signature_free');
            End;
          Finally
            git_commit_free(parentcommit);

            Context.ContextDoLibGit2Call('git_commit_free');
          End;
        Finally
          git_reference_free(headref);

          Context.ContextDoLibGit2Call('git_reference_free');
        End;
      Finally
        git_tree_free(tree);

        Context.ContextDoLibGit2Call('git_tree_free');
      End;
    Finally
      git_index_free(index);

      Context.ContextDoLibGit2Call('git_index_free');
    End;
  Finally
    git_commit_free(commit);

    Context.ContextDoLibGit2Call('git_commit_free');
  End;
End;

Procedure TAEGitCommit.Clear;
Begin
  _changedfiles.Clear;

  _author := '';
  _authoremail := '';
  _branches := [];
  _changedfilesloaded := False;
  _committer := '';
  _committeremail := '';
  _datetime := 0;
  _detailsloaded := False;
  _head := False;
  _message := '';
  _original_offset := 0;
  _original_timestamp := 0;
  _parentcommithashes := [];
  _summary := '';
  _tags := [];
End;

Constructor TAEGitCommit.Create(Const inContext: TAEGitRepositoryContext; Const inHash: String);
Begin
  inherited Create(inContext);

  _changedfiles := TAEGitCommitFileList.Create([doOwnsValues]);

  _hash := inHash;

  Self.Clear;
End;

Destructor TAEGitCommit.Destroy;
Begin
  FreeAndNil(_changedfiles);

  inherited;
End;

Procedure TAEGitCommit.AddUniqueString(Var outArray: TArray<String>; Const inValue: String);
Var
  s: String;
Begin
  For s In outArray DO
    If s = inValue Then
      Exit;

  SetLength(outArray, Length(outArray) + 1);
  outArray[High(outArray)] := inValue;
End;

Procedure TAEGitCommit.InternalCheckout;
Var
  obj: Pgit_object;
  oid: git_oid;
  options: git_checkout_options;
Begin
  Context.ContextHandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_SAFE;

  Context.ContextHandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, Context.ContextLibGit2Repository, PAnsiChar(UTF8String(_hash))));
  Try
    Context.ContextHandleLibGit2Output('git_checkout_tree', git_checkout_tree(Context.ContextLibGit2Repository, obj, @options));
  Finally
    git_object_free(obj);

    Context.ContextDoLibGit2Call('git_object_free');
  End;

  Context.ContextHandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.ContextHandleLibGit2Output('git_repository_set_head_detached', git_repository_set_head_detached(Context.ContextLibGit2Repository, @oid));

  Context.ContextUpdateCurrentBranch;
End;

Function TAEGitCommit.GetFileNames: TArray<String>;
Begin
  If Not _changedfilesloaded Then
    Self.LoadFiles;

  Result := _changedfiles.Keys.ToArray;

  TArray.Sort<String>(Result);
End;

Function TAEGitCommit.GetCommitter: String;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _committer;
End;

Function TAEGitCommit.GetCommitterEmail: String;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _committeremail;
End;

Function TAEGitCommit.GetDateTime: TDateTime;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _datetime;
End;

Function TAEGitCommit.Diff: String;
Var
  commit: Pgit_commit;
  commitoid: git_oid;
Begin
  Context.ContextHandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@commitoid, PAnsiChar(UTF8String(_hash))));

  Context.ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.ContextLibGit2Repository, @commitoid));
  Try
    Result := Self.GetPatchFromCommit(commit, []);
  Finally
    git_commit_free(commit);

    Context.ContextDoLibGit2Call('git_commit_free');
  End;
End;

Function TAEGitCommit.GetHead: Boolean;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _head;
End;

Function TAEGitCommit.GetMessage: String;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _message;
End;

Function TAEGitCommit.GetParentCommitHashes: TArray<String>;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _parentcommithashes;
End;

Function TAEGitCommit.GetSummary: String;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _summary;
End;

Function TAEGitCommit.GetTags: TArray<String>;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _tags;
End;

Function TAEGitCommit.GetAuthor: String;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _author;
End;

Function TAEGitCommit.GetAuthorEmail: String;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _authoremail;
End;

Function TAEGitCommit.GetBranches: TArray<String>;
Begin
  If Not _detailsloaded Then
    Self.LoadDetails;

  Result := _branches;
End;

Function TAEGitCommit.GetFile(Const inGitPath: String): TAEGitCommitFile;
Begin
  If Not _changedfilesloaded Then
    Self.LoadFiles;

  Result := _changedfiles[inGitPath];
End;

Procedure TAEGitCommit.LoadDecorations;
Var
  iterator: Pgit_reference_iterator;
  ref, headref: Pgit_reference;
  shortname: PAnsiChar;
  name, hash: String;
  oid: Pgit_oid;
  obj: Pgit_object;
  sha: Array[0..GIT_OID_SHA1_HEXSIZE + 1] Of AnsiChar;

  Function TryGetCommitHashFromReference(Const inRef: Pgit_reference; out outHash: String): Boolean;
  Begin
    Result := False;
    outHash := '';

    oid := git_reference_target(inRef);
    Context.ContextDoLibGit2Call('git_reference_target');

    If Assigned(oid) Then
    Begin
      git_oid_tostr(sha, SizeOf(sha), oid);
      Context.ContextDoLibGit2Call('git_oid_tostr');

      outHash := String(UTF8String(sha));
      Exit(True);
    End;

    If Context.ContextHandleLibGit2Output('git_reference_peel', git_reference_peel(@obj, inRef, GIT_OBJECT_COMMIT), False) Then
    Try
      oid := git_object_id(obj);
      Context.ContextDoLibGit2Call('git_object_id');

      If Assigned(oid) Then
      Begin
        git_oid_tostr(sha, SizeOf(sha), oid);
        Context.ContextDoLibGit2Call('git_oid_tostr');

        outHash := String(UTF8String(sha));
        Result := True;
      End;
    Finally
      git_object_free(obj);
      Context.ContextDoLibGit2Call('git_object_free');
    End;
  End;
Begin
  _tags := [];
  _branches := [];
  _head := False;

  Context.ContextHandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@iterator, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/tags/*'))));
  Try
    While Context.ContextHandleLibGit2Output('git_reference_next', git_reference_next(@ref, iterator), False) Do
    Begin
      Try
        If TryGetCommitHashFromReference(ref, hash) And (hash = _hash) Then
        Begin
          shortname := git_reference_shorthand(ref);
          Context.ContextDoLibGit2Call('git_reference_shorthand');

          name := String(UTF8String(shortname));
          AddUniqueString(_tags, name);
        End;
      Finally
        git_reference_free(ref);
        Context.ContextDoLibGit2Call('git_reference_free');
      End;
    End;
  Finally
    git_reference_iterator_free(iterator);
    Context.ContextDoLibGit2Call('git_reference_iterator_free');
  End;

  Context.ContextHandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@iterator, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/heads/*'))));
  Try
    While Context.ContextHandleLibGit2Output('git_reference_next', git_reference_next(@ref, iterator), False) Do
    Begin
      Try
        If TryGetCommitHashFromReference(ref, hash) And (hash = _hash) Then
        Begin
          shortname := git_reference_shorthand(ref);
          Context.ContextDoLibGit2Call('git_reference_shorthand');

          name := String(UTF8String(shortname));
          AddUniqueString(_branches, name);
        End;
      Finally
        git_reference_free(ref);
        Context.ContextDoLibGit2Call('git_reference_free');
      End;
    End;
  Finally
    git_reference_iterator_free(iterator);
    Context.ContextDoLibGit2Call('git_reference_iterator_free');
  End;

  Context.ContextHandleLibGit2Output('git_reference_iterator_glob_new', git_reference_iterator_glob_new(@iterator, Context.ContextLibGit2Repository, PAnsiChar(UTF8String('refs/remotes/*'))));
  Try
    While Context.ContextHandleLibGit2Output('git_reference_next', git_reference_next(@ref, iterator), False) Do
    Begin
      Try
        If TryGetCommitHashFromReference(ref, hash) And (hash = _hash) Then
        Begin
          shortname := git_reference_shorthand(ref);
          Context.ContextDoLibGit2Call('git_reference_shorthand');

          name := String(UTF8String(shortname));
          AddUniqueString(_branches, name);
        End;
      Finally
        git_reference_free(ref);
        Context.ContextDoLibGit2Call('git_reference_free');
      End;
    End;
  Finally
    git_reference_iterator_free(iterator);
    Context.ContextDoLibGit2Call('git_reference_iterator_free');
  End;

  If Context.ContextHandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.ContextLibGit2Repository), False) Then
  Try
    If TryGetCommitHashFromReference(headref, hash) Then
      _head := hash = _hash;
  Finally
    git_reference_free(headref);
    Context.ContextDoLibGit2Call('git_reference_free');
  End;
End;

Procedure TAEGitCommit.LoadDetails;
Var
  oid: git_oid;
  commit: Pgit_commit;
  signature: Pgit_signature;
  parentcount: Cardinal;
  parentoid: Pgit_oid;
  sha: Array[0..GIT_OID_SHA1_HEXSIZE + 1] Of AnsiChar;
  i: Integer;
Begin
  _detailsloaded := False;

  Context.ContextHandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.ContextLibGit2Repository, @oid));
  Try
    signature := git_commit_author(commit);
    Context.ContextDoLibGit2Call('git_commit_author');
    _author := String(UTF8String(signature^.name_));
    _authoremail := String(UTF8String(signature^.email));

    signature := git_commit_committer(commit);
    Context.ContextDoLibGit2Call('git_commit_committer');
    _committer := String(UTF8String(signature^.name_));
    _committeremail := String(UTF8String(signature^.email));

    _summary := String(UTF8String(git_commit_summary(commit)));
    Context.ContextDoLibGit2Call('git_commit_summary');

    _message := String(UTF8String(git_commit_message(commit)));
    Context.ContextDoLibGit2Call('git_commit_message');

    If _message = _summary Then
      _message := '';

    _original_timestamp := git_commit_time(commit);
    Context.ContextDoLibGit2Call('git_commit_time');

    _original_offset := git_commit_time_offset(commit);
    Context.ContextDoLibGit2Call('git_commit_time_offset');

    _datetime := IncMinute(UnixToDateTime(_original_timestamp, True), _original_offset);

    parentcount := git_commit_parentcount(commit);
    Context.ContextDoLibGit2Call('git_commit_parentcount');

    SetLength(_parentcommithashes, parentcount);
    For i := 0 To Integer(parentcount) - 1 Do
    Begin
      parentoid := git_commit_parent_id(commit, i);
      Context.ContextDoLibGit2Call('git_commit_parent_id');

      git_oid_tostr(sha, SizeOf(sha), parentoid);
      Context.ContextDoLibGit2Call('git_oid_tostr');

      _parentcommithashes[i] := String(UTF8String(sha));
    End;
  Finally
    git_commit_free(commit);

    Context.ContextDoLibGit2Call('git_commit_free');
  End;

  LoadDecorations;

  _detailsloaded := True;
End;

Procedure TAEGitCommit.LoadFiles;
Var
  oid: git_oid;
  commit, parent: Pgit_commit;
  tree, parenttree: Pgit_tree;
  count: Cardinal;
  diff: Pgit_diff;
  filecount: size_t;
  a: NativeUInt;
  delta: Pgit_diff_delta;
  filename: String;
  filestatus: TAEGitFileStatus;
Begin
  _changedfiles.Clear;
  _changedfilesloaded := False;

  Context.ContextHandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.ContextHandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.ContextLibGit2Repository, @oid));
  Try
    Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
    Try
      count := git_commit_parentcount(commit);

      Context.ContextDoLibGit2Call('git_commit_parentcount');

      parent := nil;
      parenttree := nil;

      If count > 0 Then
      Begin
        Context.ContextHandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));
        Context.ContextHandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
      End;

      Try
        Context.ContextHandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.ContextLibGit2Repository, parenttree, tree, nil));
        Try
          filecount := git_diff_num_deltas(diff);

          Context.ContextDoLibGit2Call('git_diff_num_deltas');

          For a := 0 To filecount - 1 Do
          Begin
            delta := git_diff_get_delta(diff, a);

            Context.ContextDoLibGit2Call('git_diff_get_delta');

            If Length(delta.new_file.path) <> 0 Then
              filename := String(UTF8String(delta.new_file.path))
            Else
              filename := String(UTF8String(delta.old_file.path));

            Case delta.status Of
              GIT_DELTA_UNMODIFIED:
                filestatus := gfsCurrent;
              GIT_DELTA_ADDED:
                filestatus := gfsNew;
              GIT_DELTA_DELETED:
                filestatus := gfsDeleted;
              GIT_DELTA_MODIFIED:
                filestatus := gfsModified;
              GIT_DELTA_RENAMED:
                filestatus := gfsRenamed;
              GIT_DELTA_COPIED:
                filestatus := gfsCopied;
              GIT_DELTA_IGNORED:
                filestatus := gfsIgnored;
              GIT_DELTA_UNTRACKED:
                filestatus := gfsUntracked;
              GIT_DELTA_TYPECHANGE:
                filestatus := gfsTypeChange;
              GIT_DELTA_UNREADABLE:
                filestatus := gfsUnreadable;
              Else
                filestatus := gfsConflicted;
            End;

            _changedfiles.Add(filename, TAEGitCommitFile.Create(Context, _hash, filename, filestatus));
          End;
        Finally
          git_diff_free(diff);

          Context.ContextDoLibGit2Call('git_diff_free');
        End;
      Finally
        If Assigned(parenttree) Then
        Begin
          git_tree_free(parenttree);

          Context.ContextDoLibGit2Call('git_tree_free');
        End;

        If Assigned(parent) Then
        Begin
          git_commit_free(parent);

          Context.ContextDoLibGit2Call('git_commit_free');
        End;
      End;
    Finally
      git_tree_free(tree);

      Context.ContextDoLibGit2Call('git_tree_free');
    End;
  Finally
    git_commit_free(commit);

    Context.ContextDoLibGit2Call('git_commit_free');
  End;

  _changedfilesloaded := True;
End;

End.
