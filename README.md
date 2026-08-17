# AEGitrepository Experimental

TAEGitRepository is a wrapper class to perform basic functionality on local Git repositories with libgit2 in an easy way. You don't need Git to be installed, just build and ship git2.dll with your application and you are good to go!
There are two external components you need to make use of TAEGitRepository.

1, [libgit2](https://github.com/libgit2/libgit2) is the brains of the operation. It contains most functionality available in Git, exposed via C API-s. Can be compiled and called via any Delphi application.

2, [libgit2-delphi](https://github.com/todaysoftware/libgit2-delphi) is the Delphi wrapper for libgit2, where methods, signatures and DLL loading lives. They also ship pre-built git2.dlls if you don't want to build them yourself.

3, Optional, [libssh2](https://github.com/libssh2/libssh2) can be embedded into libgit2 so only a single DLL is needed. Only needed for SSH remote URLs.

I am NOT a C developer. Most of the code here was translated to Delphi from StackOverflow and other sources. They can misbehave, they can cease to function in your usage case. Use at your own risk.
UNC repositories will probably fail to authenticate. Map them as drives to make them work.

Experimental is the fully object-oriented version of the original TAEGitRepository superobject. It should be more intuitive and easier to use.

## In theory what is supported

### General
- Cloning a remote repository
- Initializing a bare or non-bare repository
- Support for user / password and SSH key authentication (requires libssh2 externally or embedded)
- Event handler to log all executed calls to git2.dll and their results
- Lazy loading in every object to minimize blocking calls
### Remotes
- Adding a new remote
- Removing an existing remote
- Renaming remote
- Changing the target URL of a remote
- Pruning remotes from branches with no existing upstream
### Branches
- Rebasing a branch on any local/remote branch. Also includes aborting and continuing previous rebases.
- Merging any local/remote branch into a local one. Also includes aborting and continuing previous merges.
- Checking out a branch or commit, keeping track of actually checked out object
- Listing available local and remote branches
- Get incoming (pull) / outgoing (push) commit count
- Deleting a local branch
- Fetching, including downloading all remote tags
- Reverting last x commits (git reset --soft HEAD~x)
### Commits
- Adding and removing tags, listing tags
- Cherry-picking any commit into the current branch
- Reverting a commit
- Extracting full commit, or individual file diff
### Work tree
- Get the list of changed files
- Getting full worktree patch or individual file diff
- Applying a patch to the working tree
- Commiting staged changes
### Files in work tree
- Revert changes
- Stage / unstage
- Get statuses (removed, changed, new, renamed, etc.)
### Stash
- Pushing work tree changes to stash
- Popping / dropping a stash
- Extracting full stash or individual file diff
### Submodules
- Listing available submodules
- Initializing, syncing, updaitng
- Get full submodule commit or individual file diff

## Usage:

```delphi
var
  repo: TAEGitRepository;
begin
  [...]
  repo.Settings.FullName := 'Committer Name';
  repo.Settings.EMailAddress := 'committer@ema.il';
  repo.Settings.UserName := 'verysecure';
  repo.Settings.Password := 'youll_never_guess_it';

  repo.GitRepositoryDirectory := 'C:\gitrepos\gitrepo1';

  For var branchname In repo.Branches.Names Do
    WriteLn('Available branch: ' + branchname);

  repo.WorkTree.Files['modified.txt'].Stage;
  repo.WorkTree.Commit('New commit, yayy!');

  (repo.Branches.Current As TAEGitBranch).Revert_Last_Commit(1);
  repo.WorkTree.Files['modified.txt'].Unstage;

  repo.Stashes.Push('Modified.txt is now in stash!');
  repo.Stashes[0].Pop;

  repo.WorkTree.Files['modified.txt'].Revert;

  [...]
```
