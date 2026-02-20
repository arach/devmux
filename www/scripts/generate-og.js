import { generateOGBatch } from "@arach/og";

await generateOGBatch([
  {
    template: "editor-dark",
    title: "devmux",
    subtitle: "Claude Code + dev server, side by side in tmux",
    accent: "#33c773",
    accentSecondary: "#1a8f4a",
    background: "#111113",
    textColor: "#ebebef",
    tag: "v0.1.0",
    fonts: ["JetBrains Mono:wght@400;500;600", "Space Grotesk:wght@400;500;600;700"],
    output: "public/og.png",
  },
  {
    template: "branded",
    title: "devmux",
    subtitle: "One command to launch Claude Code and your dev server side by side. Auto-detects your stack, fully configurable.",
    accent: "#33c773",
    accentSecondary: "#1a8f4a",
    background: "#111113",
    textColor: "#ebebef",
    tag: "npm install -g devmux",
    fonts: ["JetBrains Mono:wght@400;500;600", "Space Grotesk:wght@400;500;600;700"],
    output: "public/og-branded.png",
  },
]);

console.log("Done!");
