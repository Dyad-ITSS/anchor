import SwiftUI
import AppKit

// True behind-window vibrancy — matches the native macOS sidebar look.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

private enum Pane: String, Hashable, CaseIterable {
    case shares, profiles, about

    var label: String {
        switch self {
        case .shares:   return "Shares"
        case .profiles: return "Profiles"
        case .about:    return "About"
        }
    }

    var icon: String {
        switch self {
        case .shares:   return "externaldrive.connected.to.line.below"
        case .profiles: return "person.2"
        case .about:    return "info.circle"
        }
    }
}

// Hides the sidebar toggle button. Available macOS 14+; no-op on 13.
private struct HideSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

struct SettingsView: View {
    @State private var selectedPane: Pane? = .shares

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPane) {
                Section {
                    ForEach(Pane.allCases, id: \.self) { pane in
                        NavigationLink(value: pane) {
                            Label(pane.label, systemImage: pane.icon)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .modifier(HideSidebarToggle())
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        } detail: {
            switch selectedPane {
            case .shares:   SharesTabView()
            case .profiles: ProfilesTabView()
            case .about:    AboutTabView()
            case nil:       SharesTabView()
            }
        }
    }
}
