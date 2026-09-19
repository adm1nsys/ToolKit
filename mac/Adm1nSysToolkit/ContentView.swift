import AppKit
import SwiftUI

struct MenuBarStatusView: View {
  @EnvironmentObject private var store: ToolkitStore

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("adm1nsysToolKit").font(.headline)
      if store.isLoading {
        Label("Checking for updates…", systemImage: "arrow.triangle.2.circlepath")
      } else if store.hasUpdates {
        Label("Updates available", systemImage: "arrow.down.circle.fill")
        ForEach(store.products.filter { store.updateAvailable(for: $0) }) { product in
          Button {
            guard
              let release = product.releases.first(where: { $0.version == product.latestVersion })
            else { return }
            Task { await store.install(product, release: release) }
          } label: {
            Label(
              "Update \(product.name) to \(product.latestVersion)",
              systemImage: "arrow.down.circle"
            )
          }
        }
      } else {
        Label("Everything is up to date", systemImage: "checkmark.circle.fill")
      }
      Divider()
      Button("Refresh catalog") { Task { await store.refresh() } }
      Button("Open Toolkit") { NSApp.activate(ignoringOtherApps: true) }
      Button("Quit") { NSApp.terminate(nil) }
    }
    .padding(8)
    .frame(width: 260)
  }
}

struct ContentView: View {
  @EnvironmentObject var store: ToolkitStore
  @EnvironmentObject var settings: SettingsStore
  @State private var showSettings = false
  @State private var expandedProductID: String?
  var body: some View {
    ZStack {
      if settings.animatedBackground {
        ToolkitBackground(animated: true, style: settings.backgroundStyle)
      } else {
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
      }
      VStack(spacing: 0) {
        header
        Spacer()
      }.zIndex(1)

      ScrollView {
        RoundedRectangle(cornerRadius: 0).frame(height: 50).opacity(0)
        LazyVStack(spacing: 14) {
          if let e = store.errorMessage { StatusBanner(text: e) }
          if store.products.isEmpty {
            EmptyState()
          } else {
            ForEach(visibleProducts) { p in
              ProductCard(
                product: p,
                installedVersions: store.installedVersions(for: p),
                update: store.updateAvailable(for: p),
                supported: store.isSupported(p),
                expanded: expandedProductID == p.id
              ) {
                withAnimation(.easeInOut(duration: 0.22)) {
                  expandedProductID = expandedProductID == p.id ? nil : p.id
                }
              }
            }
          }
        }.padding(24)
        RoundedRectangle(cornerRadius: 0).frame(height: 40).opacity(0)
      }
      VStack(spacing: 0) {
        Spacer()
        footer
      }.zIndex(1)

    }
    .preferredColorScheme(settings.theme.colorScheme)
    .sheet(isPresented: $showSettings) { SettingsView() }
    .task { await store.bootstrap() }
  }
  private var visibleProducts: [Product] {
    store.products.filter { product in
      let isSoon = product.availability == "soon"
      let versionOnlyUnsupported =
        store.hasCurrentPlatform(product) && !store.isSupported(product)
      let supportVisible =
        store.isSupported(product)
        || settings.showUnavailable
        || (isSoon && settings.showSoon)
        || versionOnlyUnsupported
      return supportVisible && (!isSoon || settings.showSoon)
    }
  }
  private var header: some View {
    HStack(spacing: 12) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable().scaledToFit().frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 2) {
        Text("adm1nsysToolKit").font(.headline)
        Text("Your applications, one place").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if store.isLoading { ProgressView().controlSize(.small) }

      if settings.backgroundStyle == .liquidGlass {
        Button {
          showSettings = true
        } label: {
          Image(systemName: "text.line.magnify")
            .frame(width: 40, height: 30)
            .toolkitSurface(style: settings.backgroundStyle, radius: 5)
        }
        .buttonStyle(.plain)
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Image(systemName: "escape")
            .foregroundStyle(.red)
            .frame(width: 40, height: 30)
            .toolkitSurface(
              style: settings.backgroundStyle,
              radius: 5
            )
        }
        .buttonStyle(.plain)

      } else {
        Button {
          showSettings = true
        } label: {
          Image(systemName: "text.line.magnify")
            .frame(height: 24)
        }
        .buttonStyle(.bordered)
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Image(systemName: "escape")
            .frame(height: 24)
        }.tint(Color.red)
          .buttonStyle(.bordered)
      }

    }
    .padding(.horizontal, 24).padding(.vertical, 16)
    .padding(.top, 25)
    .toolkitSurface(style: settings.backgroundStyle, radius: 0)
    .ignoresSafeArea()
  }
  private var footer: some View {
    HStack {
      Label(store.lastUpdatedText, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
      Spacer()

      if store.isLoading { ProgressView().controlSize(.small) }

      if settings.backgroundStyle == .liquidGlass {
        Button {
          Task { await store.refresh() }
        } label: {
          Label("Refresh catalog", systemImage: "arrow.clockwise")
            .frame(width: 140, height: 24)
            .toolkitSurface(style: settings.backgroundStyle, radius: 5)
        }
        .buttonStyle(.plain)

      } else {
        Button {
          Task { await store.refresh() }
        } label: {
          Label("Refresh catalog", systemImage: "arrow.clockwise")
        }.buttonStyle(.bordered)
      }
    }
    .padding(.horizontal, 24).padding(.vertical, 12)
    .toolkitSurface(style: settings.backgroundStyle, radius: 0)
  }
}

struct LoadScreenView: View {
  @EnvironmentObject private var settings: SettingsStore
  @State private var finished = false
  @State private var progress = 0.0
  @State private var status = "Preparing your workspace…"
  @State private var visible = false
  @State private var rotation = -18.0
  @State private var glow = false
  var body: some View {
    Group {
      if finished {
        ContentView().transition(.opacity)
      } else {
        ZStack {
          if settings.animatedBackground {
            ToolkitBackground(animated: true, style: settings.backgroundStyle)
          } else {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
          }
          VStack(spacing: 22) {
            ZStack {
              Circle().fill(.cyan.opacity(glow ? 0.35 : 0.12)).frame(width: 142, height: 142).blur(
                radius: 22)
              Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit().frame(width: 92, height: 92)
                .foregroundStyle(
                  LinearGradient(
                    colors: [.white, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                ).rotationEffect(.degrees(rotation)).scaleEffect(visible ? 1 : 0.35).opacity(
                  visible ? 1 : 0)
            }
            VStack(spacing: 5) {
              Text("adm1nsysToolKit").font(.system(size: 25, weight: .bold, design: .rounded))
              Text(AppInfo.versionLine).font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
              ProgressView(value: progress).tint(.cyan).frame(width: 280)
              Text(status).font(.caption).foregroundStyle(.secondary)
            }
          }
          .padding(42)
          .toolkitSurface(style: settings.backgroundStyle, radius: 30)
          .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.12)))
        }
      }
    }.task { await start() }.animation(.easeInOut(duration: 0.7), value: finished)
  }
  private func start() async {
    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { visible = true }
    withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
      glow = true
      rotation = 18
    }
    let stages = [
      "Finding installed products…", "Checking the latest catalog…", "Preparing your toolkit…",
    ]
    for (i, s) in stages.enumerated() {
      status = s
      for step in 1...3 {
        try? await Task.sleep(for: .milliseconds(100))
        progress = Double(i * 3 + step) / 9
      }
    }
    try? await Task.sleep(for: .milliseconds(280))
    finished = true
  }
}

struct ToolkitBackground: View {
  let animated: Bool
  let style: BackgroundStyle
  @State private var start = Date()
  private let palette: [Color] = [
    Color(hue: 0.62, saturation: 0.45, brightness: 0.52),
    Color(hue: 0.62, saturation: 0.58, brightness: 0.44),
    Color(hue: 0.62, saturation: 0.68, brightness: 0.37),
    Color(hue: 0.62, saturation: 0.74, brightness: 0.30),
    Color(hue: 0.62, saturation: 0.62, brightness: 0.40),
    Color(hue: 0.62, saturation: 0.50, brightness: 0.48),
  ]

  var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation(minimumInterval: animated ? 1.0 / 30.0 : nil)) { timeline in
        let time = animated ? timeline.date.timeIntervalSince(start) / 20.0 : 0
        Canvas { context, canvas in
          context.fill(
            Rectangle().path(in: CGRect(origin: .zero, size: canvas)), with: .color(palette[0]))
          for (index, color) in palette.enumerated() {
            let phase = Double(index) * 2.4
            let x = 0.5 + 0.45 * sin(time * .pi * 2 + phase)
            let y = 0.5 + 0.40 * cos(time * .pi * 2 * 0.73 + phase * 1.3)
            let radius = min(canvas.width, canvas.height) * 0.7
            let center = CGPoint(x: x * canvas.width, y: y * canvas.height)
            let rect = CGRect(
              x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(
              Circle().path(in: rect),
              with: .radialGradient(
                Gradient(colors: [color, color.opacity(0)]), center: center, startRadius: 0,
                endRadius: radius))
          }
        }.blur(radius: min(geometry.size.width, geometry.size.height) * 0.10)
      }
    }
    .opacity(style == .legacy ? 0.82 : 1)
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

struct ProductCard: View {
  @EnvironmentObject private var store: ToolkitStore
  @EnvironmentObject private var settings: SettingsStore
  let product: Product
  let installedVersions: [String]
  let update: Bool
  let supported: Bool
  let expanded: Bool
  let open: () -> Void
  var body: some View {
    VStack(spacing: 0) {
      Button(action: open) {
        HStack(spacing: 16) {
          Group {
            if product.isSelf == true {
              Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit()
            } else {
              AsyncImage(url: URL(string: product.iconURL ?? "")) {
                $0.resizable().scaledToFit()
              } placeholder: {
                Image(systemName: product.icon ?? "shippingbox.fill").font(.title)
              }
            }
          }
          .frame(width: 52, height: 52).background(
            .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              Text(product.name).font(.headline)
              if !supported {

              } else if !installedVersions.isEmpty {
                Text(
                  installedVersions.count > 1
                    ? "Installed \(installedVersions.count) versions"
                    : "Installed \(installedVersions[0])"
                )
                .font(.caption2).padding(.horizontal, 7).padding(.vertical, 3)
                .background(.green.opacity(0.2), in: Capsule())
              }
            }
            Text(product.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text(
              product.availability == "soon"
                ? "Coming soon"
                : "Latest \(product.latestVersion)  •  \(product.platforms.joined(separator: ", "))"
            )
            .font(.caption).foregroundStyle(.tertiary)
            if settings.allowRollback && product.releases.count > 1 {
              Text("\(product.releases.count) releases · click to manage versions")
                .font(.caption2).foregroundStyle(.cyan.opacity(0.85))
            }
            if !supported {
              Text("Not supported on this OS").font(.caption2).padding(.horizontal, 7).padding(
                .vertical, 3
              )
              .background(.orange.opacity(0.2), in: Capsule())
            }
          }
          Spacer()
          Image(systemName: update ? "arrow.down.circle.fill" : "chevron.right")
            .foregroundStyle(update ? .cyan : .secondary)
        }.padding(18)
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
      if expanded {
        ProductDetail(product: product, store: store, onClose: open)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .toolkitSurface(style: settings.backgroundStyle, radius: 20)
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1)))
  }
}

extension View {
  @ViewBuilder
  func toolkitSurface(style: BackgroundStyle, radius: CGFloat) -> some View {
    if style == .liquidGlass, #available(macOS 26.0, *) {
      self.glassEffect(.regular, in: .rect(cornerRadius: radius))
    } else {
      self.background(
        style == .liquidGlass
          ? AnyShapeStyle(.ultraThinMaterial)
          : AnyShapeStyle(.regularMaterial),
        in: RoundedRectangle(cornerRadius: radius)
      )
    }
  }
}

struct ProductDetail: View {
  @EnvironmentObject private var settings: SettingsStore
  let product: Product
  @ObservedObject var store: ToolkitStore
  let onClose: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Divider()

      if !store.installedVersions(for: product).isEmpty {
        Label(
          "Installed: \(store.installedVersions(for: product).joined(separator: ", "))",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
      }
      if let u = URL(string: product.siteURL) { Link("Open product site", destination: u) }
      VStack(alignment: .leading, spacing: 8) {
        Text("Version control").font(.headline)
        ForEach(visibleReleases, id: \.identity) { release in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(release.version)
              if release.version == product.latestVersion {
                Text("Latest release").font(.caption2).foregroundStyle(.green)
              }
            }
            Spacer()
            if release.availability == "soon" {
              Text("Soon")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if store.isSupported(product), store.releaseSupportsCurrentPlatform(release),
              release.downloads[store.downloadKey(for: release)] != nil
            {
              Button {
                if store.isVersionInstalled(release.version, for: product) {
                  let isProtectedCurrent =
                    product.isSelf == true
                    && versionValue(release.version) == versionValue(AppInfo.version)
                  if !isProtectedCurrent {
                    store.remove(product, version: release.version)
                  }
                } else {
                  Task { await store.install(product, release: release) }
                }
              } label: {
                Text(
                  actionTitle(for: release.version)
                )
              }
              .buttonStyle(.borderedProminent)
              .disabled(
                product.isSelf == true
                  && store.isVersionInstalled(release.version, for: product)
                  && versionValue(release.version) == versionValue(AppInfo.version)
              )
            } else if downloadURL(for: release) != nil {
              Button("Download") {
                Task { await store.downloadToChosenLocation(product: product, release: release) }
              }
              .buttonStyle(.bordered)
            }
          }
        }
      }
      if let message = store.operationMessage {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.horizontal, 18).padding(.bottom, 18)
  }

  private func actionTitle(for version: String) -> String {
    if store.isVersionInstalled(version, for: product) {
      return product.isSelf == true && versionValue(version) == versionValue(AppInfo.version)
        ? "Installed" : "Delete"
    }
    if version == product.latestVersion, store.updateAvailable(for: product) { return "Update" }
    if versionValue(version) < versionValue(product.latestVersion) { return "Roll back" }
    return "Install"
  }

  private var visibleReleases: [Release] {
    let releases = store.isSupported(product) ? store.releases(for: product) : product.releases
    return settings.allowRollback
      ? releases
      : releases.filter { $0.version == product.latestVersion }
  }

  private func versionValue(_ value: String) -> Int {
    let parts = value.split(separator: ".").map { Int($0) ?? 0 }
    return (parts + [0, 0, 0]).prefix(3).reduce(0) { $0 * 1000 + $1 }
  }

  private func downloadURL(for release: Release) -> URL? {
    let key =
      store.isSupported(product)
      ? store.downloadKey(for: release)
      : release.downloads.keys.sorted().first
    return key.flatMap { release.downloads[$0] }.flatMap(URL.init(string:))
  }
}
struct EmptyState: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "shippingbox").font(.system(size: 42)).foregroundStyle(.secondary)
      Text("No products found").font(.headline)
      Text("Installed products will appear here.").font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity).padding(80)
  }
}
struct StatusBanner: View {
  let text: String
  var body: some View {
    Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(
      .orange
    ).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(
      .orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
  }
}
struct SettingsView: View {
  @EnvironmentObject var settings: SettingsStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    Form {
      Section("Appearance") {
        Toggle("Animated background", isOn: $settings.animatedBackground)
        Picker("Background", selection: $settings.backgroundStyle) {
          ForEach(BackgroundStyle.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Theme", selection: $settings.theme) {
          ForEach(AppTheme.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
      }
      Section("Updates") {
        Toggle("Check catalog automatically", isOn: $settings.enableAutoUpdates)
        Toggle("Enable rollback versions", isOn: $settings.allowRollback)
        Toggle("Show unavailable products", isOn: $settings.showUnavailable)
        Toggle("Show soon products", isOn: $settings.showSoon)
        Text("New releases can be added to the catalog without updating Toolkit.").font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Links") {
        Link("Repo", destination: URL(string: "https://github.com/adm1nsys/ToolKit")!)
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 360)
    .padding()
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Close") { dismiss() }
      }
    }
  }
}
