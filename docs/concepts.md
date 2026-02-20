# Concepts

## What is devmux?

devmux is a developer workspace launcher. It creates pre-configured
terminal layouts for your projects using tmux, so you can go from
"I want to work on X" to a full development environment in one click.

## Glossary

### Session
A tmux session is a persistent workspace that lives in the background.
It survives terminal crashes, disconnects, and even closing your laptop.
Think of it as a virtual desktop for a single project.

### Pane
A pane is a single terminal view inside a session. A typical devmux
setup has two panes side by side — one running Claude Code and one
running your dev server. You can have up to four or more.

### Attach / Detach
Attaching connects your terminal window to an existing session.
Detaching disconnects your terminal but keeps the session alive.
Your dev server keeps running, Claude keeps thinking — nothing is lost.

### tmux
tmux (terminal multiplexer) is the engine behind devmux. It manages
sessions, panes, and layouts. devmux configures tmux for you so you
don't need to learn tmux commands — but knowing a few shortcuts helps.

### Multiplexer
A program that lets you run multiple terminal sessions inside a single
window and switch between them. tmux is the most popular one.

## How it works

1. You create a `.devmux.json` file in your project root
2. devmux reads the config and creates a tmux session with your layout
3. Each pane gets its command (claude, dev server, tests, etc.)
4. The session persists in the background until you kill it
5. You can attach/detach from any terminal at any time

## Key shortcuts (inside tmux)

These work when you're inside a tmux session:

| Shortcut       | Action                |
|----------------|-----------------------|
| Ctrl+B  D      | Detach from session   |
| Ctrl+B  X      | Kill current pane     |
| Ctrl+B  Left   | Move to left pane     |
| Ctrl+B  Right  | Move to right pane    |
| Ctrl+B  Up     | Move to pane above    |
| Ctrl+B  Down   | Move to pane below    |
| Ctrl+B  Z      | Zoom pane (toggle)    |
| Ctrl+B  [      | Scroll mode (q exits) |

The prefix `Ctrl+B` means: hold Control, press B, release both,
then press the next key.
