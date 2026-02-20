import SwiftUI

struct MainView: View {
    @ObservedObject var scanner: ProjectScanner
    @State private var searchText = ""

    private var filtered: [Project] {
        if searchText.isEmpty { return scanner.projects }
        return scanner.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // List
            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No projects found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { project in
                            ProjectRow(project: project) {
                                SessionManager.launch(project: project)
                            } onKill: {
                                SessionManager.kill(project: project)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scanner.refreshStatus()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(scanner.projects.count) projects")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
                Text("Cmd+Shift+D")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(width: 360, height: 440)
    }
}
