{
  AEGitRepository © 2026 by Akos Eigler is licensed under CC BY 4.0.
  To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/

  This license requires that reusers give credit to the creator. It allows reusers to distribute, remix, adapt,
  and build upon the material in any medium or format, even for commercial purposes.
}

Unit AE.GitRepository.Commit;

Interface

Uses AE.GitRepository.Context, AE.GitRepository.HeadTarget, AE.GitRepository.CommitFile, libgit2, AE.GitRepository.RefreshableObject,
     System.Generics.Collections, AE.GitRepository.Diff;

Type
  TAEGitCommit = Class(TAEGitHeadTarget)
  strict private
    _author: String;
    _authoremail: String;
    _changedfiles: TAEGitCommitFileList;
    _changedfilesloaded: Boolean;
    _committer: String;
    _committeremail: String;
    _datetime: TDateTime;
    _detailsloaded: Boolean;
    _diff: TAEGitDiff;
    _hash: String;
    _message: String;
    _original_offset: Integer;
    _original_timestamp: git_time_t;
    _parentcommithashes: TArray<String>;
    _summary: String;
    Procedure LoadDetails;
    Procedure LoadFiles;
    Function GetAuthor: String;
    Function GetAuthorEmail: String;
    Function GetBranches: TArray<String>;
    Function GetDiff: TAEGitDiff;
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
    Procedure AddTag(Const inTag: String; Const inMessage: String);
    Procedure CherryPick;
    Procedure Clear;
    Procedure RemoveTag(Const inTag: String);
    Procedure Revert(inRevertCommitMessage: String = '');
    Property Author: String Read GetAuthor;
    Property AuthorEmail: String Read GetAuthorEmail;
    Property Branches: TArray<String> Read GetBranches;
    Property Committer: String Read GetCommitter;
    Property CommitterEmail: String Read GetCommitterEmail;
    Property DateTime: TDateTime Read GetDateTime;
    Property Diff: TAEGitDiff Read GetDiff;
    Property Hash: String Read _hash;
    Property Head: Boolean Read GetHead;
    Property FileNames: TArray<String> Read GetFileNames;
    Property Files[Const inGitPath: String]: TAEGitCommitFile Read GetFile; Default;
    Property Message: String Read GetMessage;
    Property ParentCommitHashes: TArray<String> Read GetParentCommitHashes;
    Property Summary: String Read GetSummary;
    Property Tags: TArray<String> Read GetTags;
  End;

  TAEGitCommits = Class(TAEGitRepositoryRefreshableObject)
  strict private
    _branchname: String;
    _items: TObjectDictionary<String, TAEGitCommit>;
    _lastheadhash: String;
    _order: TList<String>;
    Function RefreshFastForward(Const inRef: String): Boolean;
    Procedure RefreshFullReconcile(Const inRef: String);
    Function GetCommitHashes: TArray<String>;
    Function GetItem(Const inCommitHash: String): TAEGitCommit;
  strict protected
    Procedure InternalClear; Override;
    Procedure InternalRefresh; Override;
  public
    Constructor Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String); ReIntroduce; Virtual;
    Destructor Destroy; Override;
    Property CommitHashes: TArray<String> Read GetCommitHashes;
    Property Items[Const inCommitHash: String]: TAEGitCommit Read GetItem; Default;
  End;

Implementation

Uses System.SysUtils, AE.GitRepository.TypeDef, System.DateUtils;

//
// TAEGitCommit
//

Procedure TAEGitCommit.AddTag(Const inTag, inMessage: String);
Var
  commitoid, tagoid: git_oid;
  obj: Pgit_object;
  signature: Pgit_signature;
  found: Boolean;
  s: String;
Begin
  found := False;

  For s In Self.Tags Do
    If s = inTag Then
    Begin
      found := True;

      Break;
    End;

  If found Then
    Exit;

  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@commitoid, PAnsiChar(UTF8String(_hash))));

  Context.HandleLibGit2Output('git_object_lookup', git_object_lookup(@obj, Context.Repository, @commitoid, GIT_OBJECT_COMMIT));
  Try
    If inMessage.IsEmpty Then
      Context.HandleLibGit2Output('git_tag_create_lightweight', git_tag_create_lightweight(@tagoid, Context.Repository, PAnsiChar(UTF8String(inTag)), obj, 0))
    Else
    Begin
      Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
      Try
        Context.HandleLibGit2Output('git_tag_create', git_tag_create(@tagoid, Context.Repository, PAnsiChar(UTF8String(inTag)), obj, signature, PAnsiChar(UTF8String(inMessage)), 0));
      Finally
        git_signature_free(signature);

        Context.DoLibGit2Call('git_signature_free');
      End;
    End;
  Finally
    git_object_free(obj);

    Context.DoLibGit2Call('git_object_free');
  End;

  Context.ClearCommitDecorationCache;
End;

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

  Context.AssertCleanWorkTree;

  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.Repository, @oid));
  Try
    Context.HandleLibGit2Output('git_cherrypick_options_init', git_cherrypick_options_init(@options, GIT_CHERRYPICK_OPTIONS_VERSION));

    Context.HandleLibGit2Output('git_cherrypick', git_cherrypick(Context.Repository, commit, @options));

    Context.HandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.Repository));
    Try
      If Not Context.SolveConflicts Then
        Exit;

      Context.HandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeoid, index));

      Context.HandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, Context.Repository, @treeoid));
      Try
        Context.HandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.Repository));
        Try
          parentoid := git_reference_target(headref);

          Context.DoLibGit2Call('git_reference_target');

          Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@parentcommit, Context.Repository, parentoid));
          Try
            Context.HandleLibGit2Output('git_signature_new', git_signature_new(@author, PAnsiChar(UTF8String(_author)), PAnsiChar(UTF8String(_authoremail)), _original_timestamp, _original_offset));
            Try
              Context.HandleLibGit2Output('git_signature_now', git_signature_now(@committer, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
              Try
                Context.HandleLibGit2Output('git_commit_create', git_commit_create(
                  @newcommitoid,
                  Context.Repository,
                  'HEAD',
                  author,
                  committer,
                  nil,
                  PAnsiChar(UTF8String(_message)),
                  tree,
                  1,
                  @parentcommit));

                Context.HandleLibGit2Output('git_repository_state_cleanup', git_repository_state_cleanup(Context.Repository));

                Context.RefreshSubmodules;
              Finally
                git_signature_free(committer);

                Context.DoLibGit2Call('git_signature_free');
              End;
            Finally
              git_signature_free(author);

              Context.DoLibGit2Call('git_signature_free');
            End;
          Finally
            git_commit_free(parentcommit);

            Context.DoLibGit2Call('git_commit_free');
          End;
        Finally
          git_reference_free(headref);

          Context.DoLibGit2Call('git_reference_free');
        End;
      Finally
        git_tree_free(tree);

        Context.DoLibGit2Call('git_tree_free');
      End;
    Finally
      git_index_free(index);

      Context.DoLibGit2Call('git_index_free');
    End;
  Finally
    git_commit_free(commit);

    Context.DoLibGit2Call('git_commit_free');
  End;

  Context.RefreshBranches;
  Context.RefreshActualCommitCount;
End;

Procedure TAEGitCommit.Clear;
Begin
  _changedfiles.Clear;

  _author := '';
  _authoremail := '';
  _changedfilesloaded := False;
  _committer := '';
  _committeremail := '';
  _datetime := 0;
  _detailsloaded := False;
  _message := '';
  _original_offset := 0;
  _original_timestamp := 0;
  _parentcommithashes := [];
  _summary := '';
End;

Constructor TAEGitCommit.Create(Const inContext: TAEGitRepositoryContext; Const inHash: String);
Begin
  inherited Create(inContext);

  _changedfiles := TAEGitCommitFileList.Create([doOwnsValues]);
  _diff := TAEGitDiff.Create;

  _hash := inHash;

  Self.Clear;
End;

Destructor TAEGitCommit.Destroy;
Begin
  FreeAndNil(_changedfiles);
  FreeAndNil(_diff);

  inherited;
End;

Procedure TAEGitCommit.InternalCheckout;
Var
  obj: Pgit_object;
  oid: git_oid;
  options: git_checkout_options;
Begin
  Context.HandleLibGit2Output('git_checkout_options_init', git_checkout_options_init(@options, GIT_CHECKOUT_OPTIONS_VERSION));

  options.checkout_strategy := GIT_CHECKOUT_SAFE;

  Context.HandleLibGit2Output('git_revparse_single', git_revparse_single(@obj, Context.Repository, PAnsiChar(UTF8String(_hash))));
  Try
    Context.HandleLibGit2Output('git_checkout_tree', git_checkout_tree(Context.Repository, obj, @options));
  Finally
    git_object_free(obj);

    Context.DoLibGit2Call('git_object_free');
  End;

  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.HandleLibGit2Output('git_repository_set_head_detached', git_repository_set_head_detached(Context.Repository, @oid));
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

Function TAEGitCommit.GetDiff: TAEGitDiff;
Var
  commit: Pgit_commit;
  commitoid: git_oid;
Begin
  Result := _diff;

  If Not _diff.AsString.IsEmpty Then
    Exit;

  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@commitoid, PAnsiChar(UTF8String(_hash))));

  Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.Repository, @commitoid));
  Try
    _diff.AsString := Self.GetPatchFromCommit(commit, [], Context.Repository);
  Finally
    git_commit_free(commit);

    Context.DoLibGit2Call('git_commit_free');
  End;
End;

Function TAEGitCommit.GetHead: Boolean;
Begin
  Result := Context.CommitIsHead(_hash);
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
  Result := Context.CommitTags(_hash);
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
  Result := Context.CommitBranches(_hash);
End;

Function TAEGitCommit.GetFile(Const inGitPath: String): TAEGitCommitFile;
Begin
  If Not _changedfilesloaded Then
    Self.LoadFiles;

  Result := _changedfiles[inGitPath];
End;

Procedure TAEGitCommit.LoadDetails;
Var
  oid: git_oid;
  commit: Pgit_commit;
  signature: Pgit_signature;
  parentcount: Cardinal;
  parentoid: Pgit_oid;
  i: Integer;
Begin
  _detailsloaded := False;

  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.Repository, @oid));
  Try
    signature := git_commit_author(commit);

    Context.DoLibGit2Call('git_commit_author');

    _author := String(UTF8String(signature^.name_));
    _authoremail := String(UTF8String(signature^.email));

    signature := git_commit_committer(commit);

    Context.DoLibGit2Call('git_commit_committer');

    _committer := String(UTF8String(signature^.name_));
    _committeremail := String(UTF8String(signature^.email));

    _summary := String(UTF8String(git_commit_summary(commit)));

    Context.DoLibGit2Call('git_commit_summary');

    _message := String(UTF8String(git_commit_message(commit)));

    Context.DoLibGit2Call('git_commit_message');

    If _message.Trim = _summary Then
      _message := '';

    _original_timestamp := git_commit_time(commit);

    Context.DoLibGit2Call('git_commit_time');

    _original_offset := git_commit_time_offset(commit);

    Context.DoLibGit2Call('git_commit_time_offset');

    _datetime := IncMinute(UnixToDateTime(_original_timestamp, True), _original_offset);

    parentcount := git_commit_parentcount(commit);

    Context.DoLibGit2Call('git_commit_parentcount');

    SetLength(_parentcommithashes, parentcount);

    For i := 0 To Integer(parentcount) - 1 Do
    Begin
      parentoid := git_commit_parent_id(commit, i);

      Context.DoLibGit2Call('git_commit_parent_id');

      _parentcommithashes[i] := Context.OidToString(parentoid);
    End;
  Finally
    git_commit_free(commit);

    Context.DoLibGit2Call('git_commit_free');
  End;

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

  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.Repository, @oid));
  Try
    Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@tree, commit));
    Try
      count := git_commit_parentcount(commit);

      Context.DoLibGit2Call('git_commit_parentcount');

      parent := nil;
      parenttree := nil;

      If count > 0 Then
      Begin
        Context.HandleLibGit2Output('git_commit_parent', git_commit_parent(@parent, commit, 0));

        Context.HandleLibGit2Output('git_commit_tree', git_commit_tree(@parenttree, parent));
      End;

      Try
        Context.HandleLibGit2Output('git_diff_tree_to_tree', git_diff_tree_to_tree(@diff, Context.Repository, parenttree, tree, nil));
        Try
          filecount := git_diff_num_deltas(diff);

          Context.DoLibGit2Call('git_diff_num_deltas');

          If filecount > 0 Then
            For a := 0 To filecount - 1 Do
            Begin
              delta := git_diff_get_delta(diff, a);

              Context.DoLibGit2Call('git_diff_get_delta');

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

          Context.DoLibGit2Call('git_diff_free');
        End;
      Finally
        If Assigned(parenttree) Then
        Begin
          git_tree_free(parenttree);

          Context.DoLibGit2Call('git_tree_free');
        End;

        If Assigned(parent) Then
        Begin
          git_commit_free(parent);

          Context.DoLibGit2Call('git_commit_free');
        End;
      End;
    Finally
      git_tree_free(tree);

      Context.DoLibGit2Call('git_tree_free');
    End;
  Finally
    git_commit_free(commit);

    Context.DoLibGit2Call('git_commit_free');
  End;

  _changedfilesloaded := True;
End;

Procedure TAEGitCommit.RemoveTag(Const inTag: String);
Var
  s: String;
  found: Boolean;
Begin
  found := False;

  For s In Self.Tags Do
    If s = inTag Then
    Begin
      found := True;

      Break;
    End;

  If Not found Then
    Exit;

  Context.HandleLibGit2Output('git_tag_delete', git_tag_delete(Context.Repository, PAnsiChar(UTF8String(inTag))));

  Context.ClearCommitDecorationCache;
End;

Procedure TAEGitCommit.Revert(inRevertCommitMessage: String = '');
var
  revertoptions: git_revert_options;
  commit, headcommit: Pgit_commit;
  index: Pgit_index;
  tree: Pgit_tree;
  oid, treeoid, commitoid: git_oid;
  headref: Pgit_reference;
  signature: Pgit_signature;
  parents: Array[0..0] Of Pgit_commit;
  tmpoid: Pgit_oid;
Begin
  If inRevertCommitMessage.IsEmpty Then
    inRevertCommitMessage := 'Revert "' + _summary + '"';

  Context.AssertCleanWorkTree;

  Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oid, PAnsiChar(UTF8String(_hash))));

  Context.HandleLibGit2Output('git_revert_options_init', git_revert_options_init(@revertoptions, GIT_REVERT_OPTIONS_VERSION));

  Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@commit, Context.Repository, @oid));
  Try
    Context.HandleLibGit2Output('git_revert', git_revert(Context.Repository, commit, @revertoptions));

    If Not Context.SolveConflicts Then
      Exit;

    Context.HandleLibGit2Output('git_repository_index', git_repository_index(@index, Context.Repository));
    Try
      Context.HandleLibGit2Output('git_index_write_tree', git_index_write_tree(@treeOid, index));

      Context.HandleLibGit2Output('git_tree_lookup', git_tree_lookup(@tree, Context.Repository, @treeoid));
      Try
        Context.HandleLibGit2Output('git_repository_head', git_repository_head(@headref, Context.Repository));
        Try
          tmpoid := git_reference_target(headref);

          Context.DoLibGit2Call('git_reference_target');

          Context.HandleLibGit2Output('git_commit_lookup', git_commit_lookup(@headcommit, Context.Repository, tmpoid));
          Try
            Context.HandleLibGit2Output('git_signature_now', git_signature_now(@signature, PAnsiChar(UTF8String(Context.GetSettings.FullName)), PAnsiChar(UTF8String(Context.GetSettings.EMailAddress))));
            Try
              parents[0] := headcommit;

              Context.HandleLibGit2Output('git_commit_create', git_commit_create(
                @commitoid,
                Context.Repository,
                'HEAD',
                signature,
                signature,
                nil,
                PAnsiChar(UTF8String(inRevertCommitMessage)),
                tree,
                1,
                @parents));

              Context.HandleLibGit2Output('git_repository_state_cleanup', git_repository_state_cleanup(Context.Repository));

              Context.RefreshSubmodules;
            Finally
              git_signature_free(Signature);

              Context.DoLibGit2Call('git_signature_free');
            End;
          Finally
            git_commit_free(HeadCommit);

            Context.DoLibGit2Call('git_commit_free');
          End;
        Finally
          git_reference_free(HeadRef);

          Context.DoLibGit2Call('git_reference_free');
        End;
      Finally
        git_tree_free(Tree);

        Context.DoLibGit2Call('git_tree_free');
      End;
    Finally
      git_index_free(Index);

      Context.DoLibGit2Call('git_index_free');
    End;
  Finally
    git_commit_free(Commit);
  End;

  Context.RefreshActualCommitCount;
End;

//
// TAEGitCommits
//

Procedure TAEGitCommits.InternalClear;
Begin
  _items.Clear;
  _order.Clear;

  _lastheadhash := '';
End;

Constructor TAEGitCommits.Create(Const inContext: TAEGitRepositoryContext; Const inBranchName: String);
Begin
  inherited Create(inContext);

  _items := TObjectDictionary<String, TAEGitCommit>.Create([doOwnsValues]);
  _order := TList<String>.Create;

  _branchname := inBranchName;
End;

Destructor TAEGitCommits.Destroy;
Begin
  FreeAndNil(_items);
  FreeAndNil(_order);

  inherited;
End;

Function TAEGitCommits.GetItem(Const inCommitHash: String): TAEGitCommit;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _items[inCommitHash];
End;

Function TAEGitCommits.GetCommitHashes: TArray<String>;
Begin
  If Not Self.Loaded Then
    Self.Refresh;

  Result := _order.ToArray;
End;

Function TAEGitCommits.RefreshFastForward(Const inRef: String): Boolean;
Var
  walk: Pgit_revwalk;
  oid: git_oid;
  hash: String;
  commit: TAEGitCommit;
  foundoldhead: Boolean;
  newprefix: TList<String>;
  i: Integer;
Begin
  Result := False;

  foundoldhead := False;
  newprefix := TList<String>.Create;
  Try
    Context.HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, Context.Repository));
    Try
      Context.HandleLibGit2Output('git_revwalk_sorting', git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL Or GIT_SORT_TIME));

      Context.HandleLibGit2Output('git_revwalk_push_head', git_revwalk_push_head(walk));

      Context.HandleLibGit2Output('git_revwalk_push_ref', git_revwalk_push_ref(walk, PAnsiChar(UTF8String(inRef))));

      While Context.HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@oid, walk), [geIterationOver]) Do
      Begin
        hash := Context.OidToString(@oid);

        If hash = _lastheadhash Then
        Begin
          foundoldhead := True;

          Break;
        End;

        newprefix.Add(hash);
      End;
    Finally
      git_revwalk_free(walk);

      Context.DoLibGit2Call('git_revwalk_free');
    End;

    If Not foundoldhead Then
      Exit;

    For i := newprefix.Count - 1 DownTo 0 Do
    Begin
      hash := newprefix[i];

      If Not _items.TryGetValue(hash, commit) Then
      Begin
        commit := TAEGitCommit.Create(Context, hash);

        _items.Add(hash, commit);
      End;

      _order.Insert(0, hash);
    End;

    Result := True;
  Finally
    FreeAndNil(newprefix);
  End;
End;

Procedure TAEGitCommits.RefreshFullReconcile(Const inRef: String);
Var
  walk: Pgit_revwalk;
  oid: git_oid;
  hash: String;
  commit: TAEGitCommit;
  keystoremove: TList<String>;
Begin
  keystoremove := TList<String>.Create;
  Try
    _order.Clear;
    keystoremove.AddRange(_items.Keys);

    Context.HandleLibGit2Output('git_revwalk_new', git_revwalk_new(@walk, Context.Repository));
    Try
      Context.HandleLibGit2Output('git_revwalk_sorting', git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL Or GIT_SORT_TIME));

      Context.HandleLibGit2Output('git_revwalk_push_head', git_revwalk_push_head(walk));

      Context.HandleLibGit2Output('git_revwalk_push_ref', git_revwalk_push_ref(walk, PAnsiChar(UTF8String(inRef))));

      While Context.HandleLibGit2Output('git_revwalk_next', git_revwalk_next(@oid, walk), [geIterationOver]) Do
      Begin
        hash := Context.OidToString(@oid);

        If Not _items.TryGetValue(hash, commit) Then
        Begin
          commit := TAEGitCommit.Create(Context, hash);

          _items.Add(hash, commit);
        End;

        _order.Add(hash);
        keystoremove.Remove(hash);
      End;

      For hash In keystoremove Do
        _items.Remove(hash);

      Self.Loaded := True;
    Finally
      git_revwalk_free(walk);

      Context.DoLibGit2Call('git_revwalk_free');
    End;
  Finally
    FreeAndNil(keystoremove);
  End;
End;

Procedure TAEGitCommits.InternalRefresh;
Var
  refname, newheadhash, localrefname, localheadhash: String;
  newheadoid, localheadoid, oldheadoid: git_oid;
  isfastforward,remotechanged, localchanged: Boolean;
Begin
  Self.Loaded := False;

  If _branchname.Contains('/') Then
  Begin
    Self.Clear;
    Self.Loaded := True;

    Exit;
  End;

  localrefname := 'refs/heads/' + _branchname;

  Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@localheadoid, Context.Repository, PAnsiChar(UTF8String(localrefname))));

  localheadhash := Context.OidToString(@localheadoid);

  refname := 'refs/remotes/' + Context.GetDefaultRemoteName + '/' + _branchname;

  If Context.HandleLibGit2Output('git_reference_name_to_id', git_reference_name_to_id(@newheadoid, Context.Repository, PAnsiChar(UTF8String(refname))), [geNotFound]) Then
    newheadhash := Context.OidToString(@newheadoid)
  Else
  Begin
    refname := localrefname;
    newheadoid := localheadoid;
    newheadhash := localheadhash;
  End;

  remotechanged := _lastheadhash.IsEmpty or (newheadhash <> _lastheadhash);
  localchanged := _lastheadhash.IsEmpty or (localheadhash <> _lastheadhash);

  If Not remotechanged And Not localchanged Then
  Begin
    Self.Loaded := True;
    Exit;
  End;

  isfastforward := False;

  If Not _lastheadhash.IsEmpty And Context.HandleLibGit2Output('git_oid_fromstr', git_oid_fromstr(@oldheadoid, PAnsiChar(UTF8String(_lastheadhash))), [geInvalid]) Then
  Begin
    isfastforward := git_graph_descendant_of(Context.Repository, @localheadoid, @oldheadoid) = 1;

    Context.DoLibGit2Call('git_graph_descendant_of');
  End;

  If Not isfastforward Or Not Self.RefreshFastForward(refname) Then
    Self.RefreshFullReconcile(refname);

  Context.ClearCommitDecorationCache;

  _lastheadhash := localheadhash;
  Self.Loaded := True;
End;

End.
