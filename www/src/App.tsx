import { useState } from "react";
import "./index.css";

type PkgManager = "npm" | "pnpm" | "bun";

const commands: Record<PkgManager, string> = {
  npm: "npm install -g devmux",
  pnpm: "pnpm add -g devmux",
  bun: "bun add -g devmux",
};

const pmOrder: PkgManager[] = ["npm", "pnpm", "bun"];

function GitHubIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

function CopyIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
      <rect x="9" y="9" width="13" height="13" rx="2" />
      <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );
}

const configExample = `{
  <span class="hl-key">"panes"</span>: [
    {
      <span class="hl-key">"name"</span>: <span class="hl-str">"claude"</span>,
      <span class="hl-key">"cmd"</span>: <span class="hl-str">"claude"</span>,
      <span class="hl-key">"size"</span>: <span class="hl-num">60</span>
    },
    {
      <span class="hl-key">"name"</span>: <span class="hl-str">"server"</span>,
      <span class="hl-key">"cmd"</span>: <span class="hl-str">"pnpm dev"</span>
    },
    {
      <span class="hl-key">"name"</span>: <span class="hl-str">"tests"</span>,
      <span class="hl-key">"cmd"</span>: <span class="hl-str">"pnpm test --watch"</span>
    }
  ]
}`;

export default function App() {
  const [pm, setPm] = useState<PkgManager>("npm");
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    await navigator.clipboard.writeText(commands[pm]);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <>
      {/* Nav */}
      <nav className="nav">
        <div className="nav-inner">
          <a href="/" className="nav-brand">
            <span className="nav-dot" />
            <span className="nav-name">devmux</span>
          </a>
          <div className="nav-links">
            <a href="#features" className="nav-link">
              Features
            </a>
            <a href="#config" className="nav-link">
              Config
            </a>
            <a href="#app" className="nav-link">
              Menu Bar
            </a>
            <a
              href="https://github.com/arach/devmux"
              target="_blank"
              rel="noopener noreferrer"
              className="nav-github"
            >
              <GitHubIcon />
              <span>GitHub</span>
            </a>
          </div>
        </div>
      </nav>

      {/* Hero */}
      <div className="shell">
        <section className="hero fade-in">
          <div className="hero-badge">
            <span className="hero-badge-dot" />
            v0.1.0 — now on npm
          </div>
          <h1>
            Claude Code + dev server,
            <br />
            <span className="accent">side by side.</span>
          </h1>
          <p className="hero-sub">
            One command to launch a tmux session with Claude Code and your dev
            server. Auto-detects your stack, fully configurable.
          </p>

          <div className="install fade-in fade-in-delay-1">
            <div className="install-tabs">
              {pmOrder.map((p) => (
                <button
                  key={p}
                  className={`install-tab ${pm === p ? "active" : ""}`}
                  onClick={() => setPm(p)}
                >
                  {p}
                </button>
              ))}
            </div>
            <div className="install-cmd">
              <code>
                <span className="prompt">$</span>
                {commands[pm]}
              </code>
              <button className="install-copy" onClick={copy}>
                {copied ? <CheckIcon /> : <CopyIcon />}
              </button>
            </div>
          </div>
        </section>

        {/* Features */}
        <section className="features fade-in fade-in-delay-2" id="features">
          <div className="feature">
            <span className="feature-icon">&#9654;</span>
            <h3>One command</h3>
            <p>
              Run <code>devmux</code> in any project. It creates a tmux session
              with Claude Code and your dev server ready to go.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9881;</span>
            <h3>Auto-detect</h3>
            <p>
              Reads your <code>package.json</code> and lock files to pick the
              right dev command and package manager automatically.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9635;</span>
            <h3>Configurable</h3>
            <p>
              Drop a <code>.devmux.json</code> in your project root to customize
              panes, commands, and layout.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#8644;</span>
            <h3>Attach / detach</h3>
            <p>
              Sessions persist in the background. Come back to exactly where you
              left off — processes keep running.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9000;</span>
            <h3>Menu bar app</h3>
            <p>
              Optional macOS companion app. See all projects, launch or attach
              with a click, global hotkey.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9734;</span>
            <h3>Zero dependencies</h3>
            <p>
              Pure Node.js CLI — no runtime deps. Just needs tmux installed.
              Works with any Node 18+ setup.
            </p>
          </div>
        </section>

        {/* How it works */}
        <section className="section">
          <div className="section-header">
            <h2>How it works</h2>
          </div>
          <div className="steps">
            <div className="step">
              <span className="step-num">1</span>
              <div className="step-text">
                <h3>Run devmux</h3>
                <p>
                  In your project directory, run <code>devmux</code>. It scans
                  for config or auto-detects your dev command.
                </p>
              </div>
            </div>
            <div className="step">
              <span className="step-num">2</span>
              <div className="step-text">
                <h3>tmux session starts</h3>
                <p>
                  A named tmux session is created with your panes configured —
                  Claude Code on the left, dev server on the right.
                </p>
              </div>
            </div>
            <div className="step">
              <span className="step-num">3</span>
              <div className="step-text">
                <h3>Code away</h3>
                <p>
                  Detach anytime with <code>Ctrl+b d</code>. Reattach by running{" "}
                  <code>devmux</code> again. Sessions persist until you kill
                  them.
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* Config */}
        <section className="section" id="config">
          <div className="section-header">
            <h2>Configure your workspace</h2>
            <p>
              Drop a <code>.devmux.json</code> in your project root. Define any
              number of panes with custom commands.
            </p>
          </div>

          <div className="code-block">
            <div className="code-header">
              <span className="code-dot code-dot-red" />
              <span className="code-dot code-dot-yellow" />
              <span className="code-dot code-dot-green" />
              <span className="code-filename">.devmux.json</span>
            </div>
            <pre
              className="code-pre"
              dangerouslySetInnerHTML={{ __html: configExample }}
            />
          </div>

          <div className="layouts">
            <div className="layout-card">
              <h3>2 panes</h3>
              <p>Side-by-side split</p>
              <div className="layout-diagram layout-2">
                <div className="layout-pane main">claude</div>
                <div className="layout-pane">server</div>
              </div>
            </div>
            <div className="layout-card">
              <h3>3+ panes</h3>
              <p>Main-vertical layout</p>
              <div className="layout-diagram layout-3">
                <div className="layout-pane main">claude</div>
                <div className="layout-pane">server</div>
                <div className="layout-pane">tests</div>
              </div>
            </div>
          </div>
        </section>

        {/* Menu bar app */}
        <section className="app-section" id="app">
          <div className="section-header">
            <h2>Menu bar companion</h2>
            <p>
              A lightweight macOS menu bar app for managing your devmux sessions
              without touching the terminal.
            </p>
          </div>
          <div className="app-grid">
            <div>
              <ul className="app-features">
                <li>See all projects and their session status</li>
                <li>Launch, attach, or detach with a click</li>
                <li>
                  Global hotkey (<code>Cmd+Shift+D</code>)
                </li>
                <li>Auto-scans your project directories</li>
                <li>Reads .devmux.json for pane info</li>
                <li>Built with SwiftUI, runs natively on macOS</li>
              </ul>
            </div>
            <div className="app-preview">
              <div className="app-preview-bar">
                <span className="app-preview-icon">$</span>
                <span className="app-preview-title">devmux</span>
              </div>
              <div className="app-preview-row">
                <span className="app-preview-name">
                  <span className="app-preview-dot running" />
                  my-app
                </span>
                <span className="app-preview-btn attach">Attach</span>
              </div>
              <div className="app-preview-row">
                <span className="app-preview-name">
                  <span className="app-preview-dot running" />
                  api-server
                </span>
                <span className="app-preview-btn attach">Attach</span>
              </div>
              <div className="app-preview-row">
                <span className="app-preview-name">
                  <span className="app-preview-dot idle" />
                  docs-site
                </span>
                <span className="app-preview-btn launch">Launch</span>
              </div>
            </div>
          </div>
        </section>

        {/* CTA */}
        <section className="cta">
          <h2>Ready to devmux?</h2>
          <p>Install in seconds. Works with any Node.js project.</p>
          <div className="cta-actions">
            <a
              href="https://github.com/arach/devmux"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-primary"
            >
              View on GitHub
            </a>
            <a
              href="https://www.npmjs.com/package/devmux"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
            >
              npm package
            </a>
          </div>
        </section>

        {/* Footer */}
        <footer className="footer">
          <span>
            Built by{" "}
            <a
              href="https://github.com/arach"
              target="_blank"
              rel="noopener noreferrer"
            >
              @arach
            </a>
          </span>
          <span>macOS only. Requires tmux.</span>
        </footer>
      </div>
    </>
  );
}
