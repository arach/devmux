---
title: Workspace Layers
description: Group projects into switchable layers for context switching
order: 4
---

# Workspace Layers

Layers let you group projects into switchable contexts. Instead of
juggling six terminal windows at once, define two or three layers and
switch between them instantly — the target layer's windows come to the
front and tile into position, while the previous layer's windows fall
behind.

All tmux sessions stay alive across switches. Nothing is detached or
killed — layers only control which windows are focused.

## Configuration

Create `~/.devmux/workspace.json`:

```json
{
  "name": "my-setup",
  "layers": [
    {
      "id": "web",
      "label": "Web",
      "projects": [
        { "path": "/Users/you/dev/frontend", "tile": "left" },
        { "path": "/Users/you/dev/api", "tile": "right" }
      ]
    },
    {
      "id": "mobile",
      "label": "Mobile",
      "projects": [
        { "path": "/Users/you/dev/ios-app", "tile": "left" },
        { "path": "/Users/you/dev/backend", "tile": "right" }
      ]
    }
  ]
}
```

### Fields

| Field             | Type     | Description                              |
|-------------------|----------|------------------------------------------|
| `name`            | string   | Workspace name (for your reference)      |
| `layers`          | array    | List of layer definitions                |
| `layers[].id`     | string   | Unique identifier (e.g. `"web"`)         |
| `layers[].label`  | string   | Display name shown in the UI             |
| `layers[].projects` | array  | Projects in this layer                   |
| `projects[].path` | string   | Absolute path to project directory       |
| `projects[].tile` | string?  | Tile position (optional, see below)      |

### Tile values

Any tile position from the [config reference](/docs/config#tile-positions)
works: `left`, `right`, `top-left`, `top-right`, `bottom-left`,
`bottom-right`, `maximize`, `center`.

## Switching layers

Three ways to switch:

| Method               | How                                      |
|----------------------|------------------------------------------|
| **Hotkey**           | Cmd+Option+1, Cmd+Option+2, Cmd+Option+3... |
| **Layer bar**        | Click a layer pill in the menu bar panel |
| **Command palette**  | Search "Switch to Layer" in Cmd+Shift+M  |

When you switch to a layer:

1. Each project's terminal window is **raised and focused**
2. If a project isn't running yet, it gets **launched** automatically
3. Windows with a `tile` value are **tiled** to that position
4. The previous layer's windows stay open behind the new ones

The app remembers which layer was last active across restarts.

## Layer bar

When a workspace config is loaded, a layer bar appears between the
header and search field in the menu bar panel:

```
 devmux  2 sessions              [↔] [⟳]
┌────────────────────────────────────────┐
│  ● Web          ○ Mobile               │
│  ⌥1             ⌥2                     │
└────────────────────────────────────────┘
 Search projects...
```

- Active layer: filled green dot
- Inactive layers: dim outline dot
- Hotkey hints shown below each label

## Layout examples

### Two-project split

```json
{
  "projects": [
    { "path": "/Users/you/dev/app", "tile": "left" },
    { "path": "/Users/you/dev/api", "tile": "right" }
  ]
}
```

### Three-project layout

```json
{
  "projects": [
    { "path": "/Users/you/dev/main", "tile": "left" },
    { "path": "/Users/you/dev/web", "tile": "top-right" },
    { "path": "/Users/you/dev/server", "tile": "bottom-right" }
  ]
}
```

### Four quadrants

```json
{
  "projects": [
    { "path": "/Users/you/dev/frontend", "tile": "top-left" },
    { "path": "/Users/you/dev/backend", "tile": "top-right" },
    { "path": "/Users/you/dev/mobile", "tile": "bottom-left" },
    { "path": "/Users/you/dev/infra", "tile": "bottom-right" }
  ]
}
```

## Tips

- Projects don't need a `.devmux.json` config to be in a layer — any
  directory path works. If the project has a config, devmux uses it; if
  not, it opens a plain terminal in that directory.
- You can have up to 9 layers (Cmd+Option+1 through Cmd+Option+9).
- Edit `workspace.json` by hand — the app re-reads it on launch. Use
  the Refresh Projects button or restart the app to pick up changes.
- The `tile` field is optional. Omit it if you just want the window
  focused without repositioning.
