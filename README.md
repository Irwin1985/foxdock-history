# foxdock-history

The `history` plugin of FoxDock, the plugin system for the Visual FoxPro 9 IDE. Keeps the previous version of each form, class library, report, label and menu you edit, with diff and restore.

> Also in Spanish ([README_ES.md](README_ES.md)) and German ([README_DE.md](README_DE.md)).

## Install

You need FoxDock and [FoxPack](https://irwinrodriguez.dev/products/foxpack).

- In FoxDock: **FoxDock > Plugins > Plugin center...**, **Available**, choose `history` and press **Install**.
- From a console: `foxpack plugin add history`.

If `history` came with your FoxDock installer, the plugin center shows its new versions in **Updates**.

## The `history` plugin

Each time you edit a form, a class, a report, a label or a menu, FoxDock keeps how it was before. If the
change goes wrong, you take it back to an earlier version with one button.

**What it keeps.** The binaries with a memo: `.scx`, `.vcx`, `.frx`, `.lbx` and `.mnx`, **always with
their memo** (`.sct`, `.vct`, `.frt`, `.lbt`, `.mnt`). It never keeps one without the other. If FoxKit
is installed, it also keeps the FoxBin2Prg text (`.SC2`, `.VC2`...), which is what lets you see what
changed. Not the `.pjx`, because it changes all the time. The text is made in the background, without
making you wait: the version is there from the first moment, and meanwhile its text says `being made`. A
big form can take a minute; if you ask for the diff before that, **Diff** waits for it.

**Where.** In `%LOCALAPPDATA%\FoxDock\history\`, one folder per folder of your sources and, inside, one
per file and one per version, named after its date and time:

```
history\c-proyectos-ventas-forms\clientes.scx\20261029-194004\
    clientes.scx   clientes.sct   clientes.SC2   version.txt
```

`version.txt` says which file it is from, when and why it was taken, and what happened with the text.
**FoxDock > History > Open history folder** opens the folder.

**When.**

- **If you open the file from the Project Manager**, the version is taken before the designer opens.
- **When a project opens**, FoxDock copies the binaries of the project that do not have an identical
  version yet (same size, date and time): a few at a time, without you noticing, and without text, which
  is made when you ask for a diff. This is the **baseline**, and when it finishes the log says how many it
  copied and how many were already there. With a big project, the first time takes a few minutes; after
  that it only checks, and takes seconds. A file that is in use at that moment (in a designer, or a class
  library of a form open in its own) is skipped, and tried again the next time the project opens.
- **If you type `MODIFY FORM` in the Command window**, the designer opens the file and locks it before
  FoxDock knows, and it can no longer be copied. The version before is then the kept one that is
  identical to the file (same size, date and time), also an old one you took it back to with **Restore**;
  for a file in an open project, the baseline already
  has it. If there is none (a loose file, outside a project, that never went through FoxDock), the state
  before is lost, and the log says so.
- **When the designer closes.** If you changed nothing, the version taken when it opened is dropped:
  opening and closing does not fill the history. If you changed something, how it is now is kept too, so
  the newest version is always what is on disk.

It keeps 20 versions per file; past that, the oldest one is deleted.

**How to restore.** **FoxDock > History > History of the current file...** shows the versions of the file
in the designer in front, or of the one you choose from the list.

- **Diff** opens in an editor the lines that changed between that version and the file as it is now.
- **Restore** copies that version, binary and memo, over the file. Before that, it keeps the state it is
  about to overwrite as one more version, so a restore can be undone the same way: you restore that one.

It does not ask for confirmation: the button is the confirmation. The notice at the top right of VFP and the log say what it
did.

**What it does not do.**

- **It does not restore with the designer open.** Close it first; otherwise it says so and touches
  nothing.
- **Without FoxKit there is no diff.** The versions are kept anyway (binary and memo), and
  `version.txt` says `text: none (FoxKit not installed)`.
- **It does not follow files it cannot find.** A `MODIFY FORM` of a file that is not in an open project
  nor in `SET PATH` cannot be found from the window title, and the log says so.

**The options** (`config.json`, `"options": { "history": { ... } }`): `extensions` (the list of
extensions, `"scx,vcx,frx,lbx,mnx"` by default), `maxVersions` (20), `baseline` (`true`: the baseline
when a project opens) and `settleSeconds` (3: when a designer closes and the file still looks unchanged, how
long history keeps looking before it decides there was no change, for a save that reaches the disk late).

For the agent there are three tools, `ide_history_list`, `ide_history_diff` and `ide_history_restore`:
AGENT-TOOLS_EN.md § 5.

## About this manual

This text is the section about `history` of the FoxDock plugin manual. The references to other sections (§) and to AGENT-TOOLS point to the documents FoxDock installs in its `docs` folder.

## License

MIT. See [LICENSE](LICENSE).
