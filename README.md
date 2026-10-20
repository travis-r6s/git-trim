<p align="center"><img src="/art/header.png" alt="git-trim header"></p>

---

# git trim
Finds stale branches in a Git repository, lets you pick which to remove, and confirms before deleting anything.

This is a fork of [jasonmccreary/git-trim](https://github.com/jasonmccreary/git-trim) that adds an interactive review step built on [gum](https://github.com/charmbracelet/gum), compares against the default branch rather than whatever you have checked out, and never deletes without a confirmation.

## Usage
```sh
git trim
# Pruned, merged and squash-merged local branches: pick, review, confirm

git trim --pruned        # -p  local branches whose remote branch no longer exists
git trim --merged        # -m  branches merged into the default branch
git trim --squashed      # -q  branches squash-merged into the default branch
git trim --stale         # -s  branches without commits in the last 3 months
git trim --untracked     # -u  local branches not tracking a remote branch
git trim --reset[=remote]   # local branches not on the remote (default: origin)
git trim --all           # every local branch except protected ones
```

Categories combine freely, e.g. `git trim --merged --stale`. Every requested category is checked; a category with no matches does not stop the others.

Modifiers:

- `--remote` (`-r`) removes remote branches instead of local ones. It works with `--merged`, `--squashed`, `--stale` and `--all`, and defaults to merged and squash-merged.
- `--tracked` (`-t`) also removes the remote branch each local branch tracks. It never removes a tracked branch that is protected, such as a branch following `origin/main`.
- `--dry-run` lists what would be removed, in a table, without asking anything or deleting anything.

## How a run works
1. **Fetch.** `git fetch --all --prune` runs first. If it fails, git trim stops rather than work from stale remote data.
2. **Classify.** Every branch is checked against the requested categories. Merged and squash-merged are measured against `origin/<default branch>` (from `origin/HEAD`), so running from a feature branch never offers `main`.
3. **Pick.** A gum picker lists every match with why it matched. Branches are pre-selected unless deleting them would lose commits that exist nowhere else (see below). `tab` or `x` toggles, `enter` continues, `esc` cancels.
4. **At-risk confirmation.** If you selected branches with at-risk commits, they are shown in their own table with a separate confirmation. Declining leaves them out and carries on with the rest.
5. **Final confirmation.** A table of exactly what will be deleted, and how, followed by a yes/no prompt that defaults to **no**. Nothing is deleted before this.
6. **Delete.** Each deletion is logged with the commit it pointed to, so a local branch can be restored with `git branch <name> <was>`. Failures are reported and the rest continue; the exit code is non-zero if any failed.

git trim needs a terminal for every run except `--dry-run`. There is no non-interactive mode.

### At-risk commits
A branch is at risk when deleting it would lose commits:

- **Local branch:** commits not reachable from any remote-tracking branch.
- **Local branch with `--tracked`, or a remote branch:** commits not in the default branch.

Merged and squash-merged branches are never at risk, because their changes are already in the default branch.

### Protected branches
These are never offered, locally or on a remote:

- the default branch (from `origin/HEAD`)
- the branch you have checked out
- branches checked out in another worktree (listed as skipped)
- anything matching `gt.exclude`

Because every deletion is reviewed and its safety is checked up front, local branches are removed with `git branch -D`. `-d` would refuse squash-merged branches, and it judges "merged" against the branch's upstream or `HEAD` rather than the default branch.

## Appearance
Colours live in the palette block at the top of the script: a deep-midnight banner, purple accents, and amber for at-risk warnings. Without `COLORTERM=truecolor`, gum rounds them to the nearest 256-colour match, so the banner becomes plain black. Add `export COLORTERM=truecolor` to your shell profile if they look off.

## Requirements
- [gum](https://github.com/charmbracelet/gum#installation) v2 or newer. On Debian/Ubuntu, add Charm's apt repository and `sudo apt install gum`.
- A remote named `origin` with `origin/HEAD` set. If it is missing, run `git remote set-head origin --auto`.

## Installation

### Oh My Zsh
```sh
git clone https://github.com/travis-r6s/git-trim.git $ZSH_CUSTOM/plugins/git-trim
```

Then add `git-trim` to `plugins=(...)` in `~/.zshrc`. The plugin puts the script on your `PATH`, so it runs as `git trim`, and adds a `gt` alias. The alias hides any `gt` command, such as Graphite's CLI, which `command gt` still reaches.

### Any shell
It is a plain bash script, so zsh is optional. Install it to `~/.local/bin`, which needs to be on your `PATH`:

```sh
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/travis-r6s/git-trim/main/git-trim -o ~/.local/bin/git-trim && chmod +x ~/.local/bin/git-trim
```

## Updating
Oh My Zsh:

```sh
git -C $ZSH_CUSTOM/plugins/git-trim pull
```

Otherwise, re-run the install command.

## Configuration
To protect more branches, set `gt.exclude` to a space-separated list of names or glob patterns, locally or globally:

```sh
git config --global gt.exclude "dev staging save/*"
```

## Tests
```sh
test/run.sh
```

The suite builds throwaway repositories and drives the real gum prompts through a pseudo-terminal with `script`, so it needs `gum` and `script` (util-linux). It takes about a minute because each keystroke waits for the prompt to render.

## Credits
Forked from [git-trim](https://github.com/jasonmccreary/git-trim) by [Jason McCreary](https://github.com/jasonmccreary/), which credits [this Twitter thread](https://twitter.com/gonedark/status/1486721735621677068), [foriequal0/git-trim](https://github.com/foriequal0/git-trim) for the name, and [git-open](https://github.com/paulirish/git-open) as a code reference. Logo by [Caneco](https://twitter.com/caneco).

## License
Copyright [Jason McCreary](https://github.com/jasonmccreary/). Licensed under [MIT](http://opensource.org/licenses/MIT).
