# AEGitrepository

TAEGitRepository is a wrapper class to perform basic functionality on local Git repositories with libgit2 in an easy way. You don't need Git to be installed, just build and ship git2.dll with your application and you are good to go!
There are two external components you need to make use of TAEGitRepository.

1, [libgit2](https://github.com/libgit2/libgit2) is the brains of the operation. It contains most functionality available in Git, exposed via C API-s. Can be compiled and called via any Delphi application.

2, [libgit2-delphi](https://github.com/todaysoftware/libgit2-delphi) is the Delphi wrapper for libgit2, where methods, signatures and DLL loading lives. They also ship pre-built git2.dlls if you don't want to build them yourself.

3, Optional, [libssh2](https://github.com/libssh2/libssh2) can be embedded into libgit2 so only a single DLL is needed. Only needed for SSH remote URLs.

I am NOT a C developer. Most of the code here was translated to Delphi from StackOverflow and other sources. They can misbehave, they can cease to function in your usage case. Use at your own risk.
UNC repositories will probably fail to authenticate. Map them as drives to make them work.

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

  repo.StageFile('modified.txt');
  repo.CommitStagedFiles('New commit, yayy!');

  repo.Revert_Last_Commit(1);
  repo.UnstageFile('modified.txt');

  repo.Stash_Push('Modified.txt is now in stash!');
  repo.Stash_Pop(0);

  repo.RevertFileModifications('Modified.txt');

  [...]
```
