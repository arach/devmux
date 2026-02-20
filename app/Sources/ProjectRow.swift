import SwiftUI

struct ProjectRow: View {
    let project: Project
    let onLaunch: () -> Void
    let onKill: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Running indicator
            Circle()
                .fill(project.isRunning ? Color.green : Color.gray.opacity(0.25))
                .frame(width: 7, height: 7)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if !project.projectType.rawValue.isEmpty {
                        Text(project.projectType.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }

                    if project.hasConfig {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .help(".devmux.json configured")
                    }
                }

                if let cmd = project.devCommand {
                    Text(cmd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions (show on hover or when running)
            if isHovered || project.isRunning {
                HStack(spacing: 6) {
                    if project.isRunning {
                        Button(action: onKill) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Kill session")
                    }

                    Button(action: onLaunch) {
                        Text(project.isRunning ? "Attach" : "Launch")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(project.isRunning ? Color.blue : Color.green)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onLaunch() }
    }
}
