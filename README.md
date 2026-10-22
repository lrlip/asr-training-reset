# AI Orchestrator training: reset button

Reset buttons that give a Windows laptop a fresh copy of one or every training session:

| File | Desktop shortcut | Resets |
|---|---|---|
| `reset1.cmd` | **Reset ASR session 1** | `asr-session-1` |
| `reset2.cmd` | **Reset ASR session 2** | `asr-session-2` |
| `resetall.cmd` | **Reset ASR all sessions** | every session |
| `reset.cmd` | (none) | asks: `1`, `2` or `A` for all of them |

Each button:

1. Updates this launcher with `git pull --ff-only`. Without a network connection it warns and resets
   with the version on the laptop. Changes to `reset.ps1` count from this run, changes to the `.cmd`
   files from the next one
2. Starts right away: the buttons do not ask for confirmation. `reset.cmd` asks which session to
   reset, and that answer is the confirmation
3. Per session: stops the processes that use its folder (node, bun or python running from it, VS
   Code opened on it, and everything they started), removes the folder, clones it again from GitHub
   and runs its `setup.ps1`
4. When a folder stays locked: stops every Node.js, Bun, Python, uv and VS Code process, also those
   of the other session, and tries again. A terminal or Explorer window that is only open in the
   folder cannot be found that way; close it and press the button again

| Session | Repository |
|---|---|
| `asr-session-1` | https://github.com/AlexDM0/asr-session-1 |
| `asr-session-2` | https://github.com/AlexDM0/asr-session-2 |

The sessions go on the desktop, next to this launcher. When the desktop cannot be written to, they
go in `C:\training`. Never inside this folder: the session setups refuse to run inside another git
repository.

## Install, once per laptop

Clone this repository to the desktop, from a PowerShell window:

```powershell
git clone https://github.com/lrlip/asr-training-reset.git "$([Environment]::GetFolderPath('Desktop'))\asr-training-reset"
```

`GetFolderPath` finds the desktop also when OneDrive has moved it. A copy from a zip works, but
cannot update itself.

## Update a laptop with an older version

Versions before the self-update do not pull. Pull once by hand; from then on every button does it:

```powershell
git -C "$([Environment]::GetFolderPath('Desktop'))\asr-training-reset" pull --ff-only
```

When git says the folder is not a git repository, or refuses because of local changes, delete the
folder and clone it again as above. It holds no work of the participants.

## Use

Double-click one of the files in the `asr-training-reset` folder on the desktop once: every run adds
the three desktop shortcuts that are missing and brings older ones up to date. From then on the
shortcuts are the buttons. Between two groups: press the one for the session to reset. It starts
without asking, in a small window, and the window closes by itself 5 seconds after the session is
ready. When something goes wrong, the window stays open with the messages.

Resetting deletes all work in the chosen session folders. It does not sign anyone out of GitHub, VS Code
or Copilot, and does not change the git name and email.

Options, from a PowerShell window in this folder:

```powershell
.\reset.cmd -Session 1                      # asr-session-1, asks for confirmation first
.\resetall.cmd -TrainingFolder D:\training  # another folder than the desktop (an absolute path)
```

## Requirements

- Windows with git (https://git-scm.com)
- Internet access to GitHub; behind a proxy the clones pick up the Windows proxy settings, the
  update of this launcher only `HTTPS_PROXY` or the git `http.proxy` setting
- Everything else (uv, Python, Bun) is installed by the session setups
