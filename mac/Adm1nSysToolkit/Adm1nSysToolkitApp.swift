//
//  Adm1nSysToolkitApp.swift
//  Adm1nSysToolkit
//
//  Created by Heorhii on 18.09.26.
//

import AppKit
import Combine
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: String { rawValue }
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
  case liquidGlass = "Liquid Glass"
  case legacy = "Legacy Blur"
  var id: String { rawValue }
}

final class SettingsStore: ObservableObject {
  private let defaults = UserDefaults.standard

  @Published var animatedBackground: Bool {
    didSet { defaults.set(animatedBackground, forKey: Keys.animatedBackground) }
  }
  @Published var enableAutoUpdates: Bool {
    didSet { defaults.set(enableAutoUpdates, forKey: Keys.enableAutoUpdates) }
  }
  @Published var allowRollback: Bool {
    didSet { defaults.set(allowRollback, forKey: Keys.allowRollback) }
  }
  @Published var showUnavailable: Bool {
    didSet { defaults.set(showUnavailable, forKey: Keys.showUnavailable) }
  }
  @Published var showSoon: Bool { didSet { defaults.set(showSoon, forKey: Keys.showSoon) } }
  @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Keys.theme) } }
  @Published var backgroundStyle: BackgroundStyle {
    didSet { defaults.set(backgroundStyle.rawValue, forKey: Keys.backgroundStyle) }
  }

  init() {
    animatedBackground = defaults.object(forKey: Keys.animatedBackground) as? Bool ?? true
    enableAutoUpdates = defaults.object(forKey: Keys.enableAutoUpdates) as? Bool ?? true
    allowRollback = defaults.object(forKey: Keys.allowRollback) as? Bool ?? false
    showUnavailable = defaults.object(forKey: Keys.showUnavailable) as? Bool ?? false
    showSoon = defaults.object(forKey: Keys.showSoon) as? Bool ?? false
    theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
    backgroundStyle =
      BackgroundStyle(rawValue: defaults.string(forKey: Keys.backgroundStyle) ?? "")
      ?? .liquidGlass
  }

  private enum Keys {
    static let animatedBackground = "settings.animatedBackground"
    static let enableAutoUpdates = "settings.enableAutoUpdates"
    static let allowRollback = "settings.allowRollback"
    static let showUnavailable = "settings.showUnavailable"
    static let showSoon = "settings.showSoon"
    static let theme = "settings.theme"
    static let backgroundStyle = "settings.backgroundStyle"
  }
}

@main
struct Adm1nSysToolkitApp: App {
  @StateObject private var settingsStore = SettingsStore()
  @StateObject private var toolkitStore = ToolkitStore()

  var body: some Scene {
    WindowGroup {
      LoadScreenView()
        .environmentObject(settingsStore)
        .environmentObject(toolkitStore)
        .frame(width: 450, height: 800)
        .background(WindowCenterHelper())
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 450, height: 800)
    .windowResizability(.contentSize)
    MenuBarExtra {
      MenuBarStatusView()
        .environmentObject(toolkitStore)
    } label: {
      Image(systemName: toolkitStore.hasUpdates ? "arrow.down.circle" : "checkmark.circle")
    }
  }
}

struct WindowCenterHelper: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      view.window?.center()
      Self.removeStandardMenus()
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  private static func removeStandardMenus() {
    let standardMenus = Set(["File", "Edit", "View", "Window", "Help"])
    NSApplication.shared.mainMenu?.items.removeAll { standardMenus.contains($0.title) }
  }
}

enum AppInfo {
  static let name =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "adm1nsysToolKit"
  static let version =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
  static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
  static var versionLine: String { "Version \(version) (build \(build))" }
}

struct Catalog: Codable {
  var updatedAt: Date?
  var products: [Product]
}
struct Product: Codable, Identifiable, Hashable {
  var id: String
  var name: String
  var summary: String
  var icon: String?
  var iconURL: String?
  var latestVersion: String
  var siteURL: String
  var platforms: [String]
  var bundleIdentifiers: [String]
  var releases: [Release]
  var availability: String?
  var supportedOS: [String]?
  var productType: String?
  var executable: String?
  var versionArguments: [String]?
  var versionedExecutablePrefix: String?
  var applicationNames: [String]?
  var targets: [PlatformTarget]?
  var isSelf: Bool?
}
struct PlatformTarget: Codable, Hashable {
  var os: String
  var architectures: [String]
  var minimumVersion: String?
  var downloadKey: String
  var libc: String? = nil
}
struct Release: Codable, Hashable {
  var version: String
  var publishedAt: Date?
  var downloads: [String: String]
  var platform: String? = nil
  var architectures: [String]? = nil
  var libc: String? = nil
  var availability: String? = nil
  var identity: String {
    [platform ?? "generic", libc ?? "", version].filter { !$0.isEmpty }.joined(separator: "-")
  }
}
@MainActor final class ToolkitStore: ObservableObject {
  @Published var products = Product.defaults
  @Published var isLoading = false
  @Published var errorMessage: String?
  @Published var lastUpdated: Date?
  @Published var operationMessage: String?
  @Published private(set) var detectedVersions: [String: [String]] = [:]
  private let catalogURL = URL(
    string: "https://raw.githubusercontent.com/adm1nsys/ToolKit/main/catalog.json")!
  func bootstrap() async {
    await refresh()
    await refreshInstalledProducts()
  }
  func refresh() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      var r = URLRequest(url: catalogURL)
      r.cachePolicy = .reloadIgnoringLocalCacheData
      let (d, _) = try await URLSession.shared.data(for: r)
      let dec = JSONDecoder()
      dec.dateDecodingStrategy = .iso8601
      let c = try dec.decode(Catalog.self, from: d)
      products = deduplicate(c.products)
      lastUpdated = c.updatedAt ?? Date()
    } catch { errorMessage = "Catalog unavailable. Showing the built-in catalog." }
    await refreshInstalledProducts()
  }
  private func deduplicate(_ products: [Product]) -> [Product] {
    var seen = Set<String>()
    return products.filter { seen.insert($0.id).inserted }
  }
  func isInstalled(_ p: Product) -> Bool {
    !installedVersions(for: p).isEmpty
  }
  func installedVersions(for p: Product) -> [String] {
    if p.productType == "cli" || p.executable != nil {
      return detectedVersions[p.id] ?? []
    }
    var versions = p.bundleIdentifiers.compactMap { identifier -> String? in
      let locations = [
        "/Applications/\(identifier).app", "\(NSHomeDirectory())/Applications/\(identifier).app",
      ]
      guard let path = locations.first(where: { FileManager.default.fileExists(atPath: $0) }),
        let bundle = Bundle(path: path),
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      else {
        return nil
      }
      return version
    }
    let names = p.applicationNames ?? [p.name]
    let roots = [
      URL(fileURLWithPath: "/Applications"),
      URL(fileURLWithPath: "\(NSHomeDirectory())/Applications"),
    ]
    for root in roots {
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: root, includingPropertiesForKeys: nil)
      else { continue }
      for entry in entries where entry.pathExtension == "app" {
        let title = entry.deletingPathExtension().lastPathComponent
        guard names.contains(where: { title == $0 || title.hasPrefix("\($0) v") }) else { continue }
        if let bundle = Bundle(url: entry),
          let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        {
          versions.append(version)
        }
      }
    }
    return Array(Set(versions)).sorted()
  }
  func refreshInstalledProducts() async {
    let cliProducts = products.filter { $0.productType == "cli" || $0.executable != nil }
    var found: [String: [String]] = [:]
    for product in cliProducts {
      let versions = await Task.detached(priority: .utility) {
        Self.detectCLI(product: product)
      }.value
      found[product.id] = versions
    }
    detectedVersions = found
  }

  nonisolated private static func detectCLI(product: Product) -> [String] {
    guard let executable = product.executable else { return [] }
    let commonPaths = [
      "/opt/homebrew/bin/\(executable)",
      "/usr/local/bin/\(executable)",
      "\(NSHomeDirectory())/.local/bin/\(executable)",
    ]
    let discoveredPath = commonPaths.first(where: {
      FileManager.default.isExecutableFile(atPath: $0)
    })
    let which = Process()
    let output = Pipe()
    which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    which.arguments = [executable]
    which.standardOutput = output
    which.standardError = output
    try? which.run()
    which.waitUntilExit()
    let whichPath = String(
      data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
    )?.trimmingCharacters(in: .whitespacesAndNewlines)
    var paths = discoveredPath.map { [$0] } ?? []
    if let path = which.terminationStatus == 0 ? whichPath : nil,
      !path.isEmpty, !paths.contains(path)
    {
      paths.append(path)
    }
    if let prefix = product.versionedExecutablePrefix {
      for directory in ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        paths += names.filter { $0.hasPrefix(prefix) }.map { "\(directory)/\($0)" }
      }
    }
    var versions: [String] = []
    for path in Set(paths) where FileManager.default.isExecutableFile(atPath: path) {
      let version = Process()
      let versionOutput = Pipe()
      version.executableURL = URL(fileURLWithPath: path)
      version.arguments = product.versionArguments ?? ["-v"]
      version.standardOutput = versionOutput
      version.standardError = versionOutput
      try? version.run()
      version.waitUntilExit()
      let text =
        String(data: versionOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? ""
      let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
      if let value = tokens.first(where: { $0.first?.isNumber == true }) {
        versions.append(String(value))
      }
    }
    return Array(Set(versions))
  }
  func isSupported(_ p: Product) -> Bool {
    if let targets = p.targets, !targets.isEmpty {
      return targets.contains { target in
        platformMatches(target)
          && (target.minimumVersion.map {
            versionValue(currentOSVersion) >= versionValue($0)
          } ?? true)
      }
    }
    let declaredOS = p.supportedOS ?? []
    let declaredPlatforms = p.platforms
    let osAllowsMac =
      declaredOS.isEmpty
      || declaredOS.contains {
        $0.localizedCaseInsensitiveContains("macos")
      }
    let platformAllowsMac =
      declaredPlatforms.isEmpty
      || declaredPlatforms.contains {
        $0.localizedCaseInsensitiveContains("macos")
      }
    guard osAllowsMac && platformAllowsMac else { return false }
    let systems = declaredOS + declaredPlatforms
    #if arch(arm64)
      if systems.contains(where: { $0.localizedCaseInsensitiveContains("Intel") })
        && !systems.contains(where: {
          $0.localizedCaseInsensitiveContains("Apple Silicon")
            || $0.localizedCaseInsensitiveContains("arm")
        })
      {
        return false
      }
    #elseif arch(x86_64)
      if systems.contains(where: {
        $0.localizedCaseInsensitiveContains("Apple Silicon")
          || $0.localizedCaseInsensitiveContains("arm")
      }) && !systems.contains(where: { $0.localizedCaseInsensitiveContains("Intel") }) {
        return false
      }
    #endif
    return true
  }

  func hasCurrentPlatform(_ p: Product) -> Bool {
    guard let targets = p.targets, !targets.isEmpty else { return isSupported(p) }
    return targets.contains(where: platformMatches)
  }

  private func platformMatches(_ target: PlatformTarget) -> Bool {
    let targetOS = target.os.lowercased().replacingOccurrences(of: "-", with: "")
    guard targetOS == currentOS || (currentOS == "macos" && targetOS == "mac") else {
      return false
    }
    let universal = target.architectures.contains {
      $0.caseInsensitiveCompare("universal") == .orderedSame
        || $0.caseInsensitiveCompare("any") == .orderedSame
    }
    guard universal || target.architectures.contains(where: architectureMatches) else {
      return false
    }
    return target.libc == nil || target.libc == currentLibc
  }
  func releaseSupportsCurrentPlatform(_ release: Release) -> Bool {
    guard let platform = release.platform else { return isSupportedByLegacyFields(release) }
    let normalized = platform.lowercased().replacingOccurrences(of: "-", with: "")
    guard normalized == currentOS || (currentOS == "macos" && normalized == "mac") else {
      return false
    }
    if let architectures = release.architectures,
      !architectures.contains(where: {
        $0.caseInsensitiveCompare("universal") == .orderedSame
          || $0.caseInsensitiveCompare("any") == .orderedSame || architectureMatches($0)
      })
    {
      return false
    }
    if let libc = release.libc, libc != currentLibc { return false }
    return true
  }
  func releases(for product: Product) -> [Release] {
    product.releases.filter(releaseSupportsCurrentPlatform)
  }
  func downloadKey(for release: Release) -> String {
    if currentOS == "macos" { return "macos" }
    if currentOS == "linux" { return release.libc == "musl" ? "linux-musl" : "linux-glibc" }
    return currentOS
  }
  private func isSupportedByLegacyFields(_ release: Release) -> Bool {
    release.downloads.keys.contains(downloadKey(for: release))
  }
  private var currentOS: String {
    #if os(macOS)
      return "macos"
    #elseif os(Linux)
      return "linux"
    #elseif os(Windows)
      return "windows"
    #else
      return "unknown"
    #endif
  }
  private var currentOSVersion: String {
    #if os(macOS)
      let value = ProcessInfo.processInfo.operatingSystemVersion
      return "\(value.majorVersion).\(value.minorVersion).\(value.patchVersion)"
    #else
      return "0"
    #endif
  }
  private var currentLibc: String {
    #if os(Linux)
      let muslPaths = ["/lib/ld-musl-x86_64.so.1", "/lib/ld-musl-aarch64.so.1"]
      return muslPaths.contains(where: { FileManager.default.fileExists(atPath: $0) })
        ? "musl" : "glibc"
    #else
      return ""
    #endif
  }
  private func architectureMatches(_ value: String) -> Bool {
    let normalized = value.lowercased().replacingOccurrences(of: "_", with: "")
    #if arch(arm64)
      return ["arm64", "arm", "universal", "any"].contains(normalized)
    #elseif arch(x86_64)
      return ["x8664", "x86", "intel", "universal", "any"].contains(normalized)
    #else
      return normalized == "any"
    #endif
  }
  func updateAvailable(for p: Product) -> Bool {
    guard isSupported(p) else { return false }
    let installed = installedVersions(for: p)
    guard !installed.isEmpty else { return false }
    return !installed.contains(where: { versionValue($0) == versionValue(p.latestVersion) })
      && installed.contains { versionValue($0) < versionValue(p.latestVersion) }
  }
  func isVersionInstalled(_ version: String, for product: Product) -> Bool {
    installedVersions(for: product).contains { versionValue($0) == versionValue(version) }
  }
  private func versionValue(_ value: String) -> Int {
    let parts = value.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    return (parts + [0, 0, 0]).prefix(3).reduce(0) { $0 * 1000 + $1 }
  }
  var hasUpdates: Bool { products.contains { updateAvailable(for: $0) } }
  func downloadURL(for p: Product) -> URL? {
    p.releases.first?.downloads["macos"].flatMap(URL.init(string:))
  }
  func install(_ product: Product, release: Release) async {
    guard isSupported(product) else {
      operationMessage = "\(product.name) is not supported on this Mac."
      return
    }
    guard releaseSupportsCurrentPlatform(release),
      let value = release.downloads[downloadKey(for: release)], let url = URL(string: value)
    else {
      operationMessage = "No macOS download is listed for this release."
      return
    }
    operationMessage = "Downloading \(product.name) \(release.version)…"
    do {
      let (temporary, _) = try await URLSession.shared.download(from: url)
      let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Toolkit-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
      task.arguments = ["-x", "-k", temporary.path, destination.path]
      try task.run()
      task.waitUntilExit()
      guard task.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
      guard let item = findInstallItem(in: destination, product: product) else {
        throw CocoaError(.fileNoSuchFile)
      }
      if product.productType == "cli" || product.executable != nil,
        let executable = product.executable
      {
        let installedBefore = installedVersions(for: product)
        let isLatest = release.version == product.latestVersion
        let preserveExisting = !isLatest || installedBefore.count > 1
        let targetName =
          preserveExisting
          ? (product.versionedExecutablePrefix ?? "\(executable)-") + release.version
          : executable
        let target = URL(fileURLWithPath: "/opt/homebrew/bin/\(targetName)")
        if !preserveExisting {
          removeCLIExecutables(for: product)
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: item, to: target)
        operationMessage =
          preserveExisting
          ? "\(product.name) \(release.version) installed alongside existing versions."
          : "\(product.name) \(release.version) installed."
      } else {
        let root = URL(fileURLWithPath: "/Applications")
        let installedBeforeUpdate = installedVersions(for: product)
        let preserveLegacyVersions = installedBeforeUpdate.count > 1
        let targetName =
          release.version == product.latestVersion && !preserveLegacyVersions
          ? "\(product.name).app" : "\(product.name) v\(release.version).app"
        let target = root.appendingPathComponent(targetName)
        if release.version == product.latestVersion && !preserveLegacyVersions {
          removeInstalledApplications(for: product)
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: item, to: target)
        operationMessage =
          preserveLegacyVersions && release.version == product.latestVersion
          ? "\(product.name) \(release.version) installed alongside existing versions."
          : "\(product.name) \(release.version) installed."
      }
      await refreshInstalledProducts()
    } catch {
      operationMessage =
        "Installation failed: \(error.localizedDescription). Try opening the archive manually."
    }
  }

  func downloadToChosenLocation(product: Product, release: Release) async {
    let key =
      isSupported(product) ? downloadKey(for: release) : release.downloads.keys.sorted().first
    guard let value = key.flatMap({ release.downloads[$0] }), let url = URL(string: value) else {
      operationMessage = "No downloadable archive is listed for this release."
      return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      url.lastPathComponent.isEmpty
      ? "\(product.name)-\(release.version).zip" : url.lastPathComponent
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    operationMessage = "Downloading \(product.name) \(release.version)…"
    do {
      let (temporary, _) = try await URLSession.shared.download(from: url)
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.copyItem(at: temporary, to: destination)
      operationMessage = "Downloaded to \(destination.lastPathComponent)."
      NSWorkspace.shared.activateFileViewerSelecting([destination])
    } catch {
      operationMessage = "Download failed: \(error.localizedDescription)"
    }
  }

  func remove(_ product: Product, version: String) {
    if product.isSelf == true,
      versionValue(version) == versionValue(AppInfo.version),
      installedVersions(for: product).count <= 1
    {
      operationMessage = "The current Toolkit version cannot be removed."
      return
    }
    if product.productType == "cli" || product.executable != nil {
      removeCLIExecutables(for: product, version: version)
      operationMessage = "Removed \(product.name) \(version)."
      Task { await refreshInstalledProducts() }
      return
    }
    let roots = [
      URL(fileURLWithPath: "/Applications"),
      URL(fileURLWithPath: "\(NSHomeDirectory())/Applications"),
    ]
    for root in roots {
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: root, includingPropertiesForKeys: nil)
      else { continue }
      for entry in entries where entry.pathExtension == "app" {
        guard let bundle = Bundle(url: entry),
          let installed = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String,
          versionValue(installed) == versionValue(version)
        else { continue }
        try? FileManager.default.removeItem(at: entry)
      }
    }
    operationMessage = "Removed \(product.name) \(version)."
  }

  private func removeCLIExecutables(for product: Product, version: String? = nil) {
    guard let executable = product.executable else { return }
    let directories = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
    for directory in directories {
      var names = [executable]
      if let version {
        names.append("\(product.versionedExecutablePrefix ?? "\(executable)-")\(version)")
      } else if let prefix = product.versionedExecutablePrefix {
        names += ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
          .filter { $0.hasPrefix(prefix) }
      }
      for name in Set(names) {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: "\(directory)/\(name)"))
      }
    }
  }

  private func removeInstalledApplications(for product: Product) {
    let roots = [
      URL(fileURLWithPath: "/Applications"),
      URL(fileURLWithPath: "\(NSHomeDirectory())/Applications"),
    ]
    for root in roots {
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: root, includingPropertiesForKeys: nil)
      else { continue }
      for entry in entries where entry.pathExtension == "app" {
        let title = entry.deletingPathExtension().lastPathComponent
        let names = product.applicationNames ?? [product.name]
        if names.contains(where: { title == $0 || title.hasPrefix("\($0) v") }) {
          try? FileManager.default.removeItem(at: entry)
        }
      }
    }
  }
  private func findInstallItem(in directory: URL, product: Product) -> URL? {
    let enumerator = FileManager.default.enumerator(
      at: directory, includingPropertiesForKeys: [.isDirectoryKey])
    guard let enumerator else { return nil }
    for case let url as URL in enumerator {
      if product.productType == "cli" || product.executable != nil {
        if url.lastPathComponent == "servermaster"
          && FileManager.default.isExecutableFile(atPath: url.path)
        {
          return url
        }
      } else if url.pathExtension == "app" {
        return url
      }
    }
    return nil
  }
  var lastUpdatedText: String {
    lastUpdated.map { "Catalog updated \($0.formatted(date: .abbreviated, time: .shortened))" }
      ?? "Using built-in catalog"
  }
}
extension Product {
  static let defaults: [Product] = [
    Product(
      id: "adm1nsys-toolkit", name: "adm1nsysToolKit",
      summary: "The application hub for adm1nsys products.", icon: "shippingbox.fill",
      iconURL: nil, latestVersion: AppInfo.version,
      siteURL: "https://github.com/adm1nsys/ToolKit",
      platforms: ["macOS 14+", "Windows", "Linux glibc", "Linux musl", "Apple Silicon", "Intel"],
      bundleIdentifiers: ["com.adm1nsys.Adm1nSysToolkit"], releases: [], availability: "available",
      supportedOS: ["macOS 14+"], productType: "application",
      applicationNames: ["Adm1nSysToolkit"],
      targets: [
        PlatformTarget(
          os: "macos", architectures: ["universal"], minimumVersion: "14.0", downloadKey: "macos")
      ], isSelf: true),
    Product(
      id: "servermaster-macos", name: "ServerMaster · macOS",
      summary: "A visual control center for local servers.", icon: "server.rack",
      iconURL: "https://adm1nsys.github.io/ServerMaster/assets/icon.png",
      latestVersion: "2.0.0", siteURL: "https://adm1nsys.github.io/ServerMaster/",
      platforms: ["macOS 14+", "Apple Silicon", "Intel"],
      bundleIdentifiers: ["ServerMaster", "com.adm1nsys.ServerMaster"],
      releases: [
        Release(
          version: "2.0.0", publishedAt: nil,
          downloads: [
            "macos":
              "https://github.com/adm1nsys/ServerMaster/releases/download/macos-v2.0.0/ServerMaster-v2.0.0.app.zip"
          ]
        ),
        Release(
          version: "1.2.0", publishedAt: nil,
          downloads: [
            "macos":
              "https://github.com/adm1nsys/ServerMaster/releases/download/macos-v1.2.0/ServerMaster.v1.2.app.zip"
          ]),
        Release(
          version: "1.1.0", publishedAt: nil,
          downloads: [
            "macos":
              "https://github.com/adm1nsys/ServerMaster/releases/download/macos-v1.1.0/ServerMaster.v1.1.app.zip"
          ]),
        Release(
          version: "1.0.0", publishedAt: nil,
          downloads: [
            "macos":
              "https://github.com/adm1nsys/ServerMaster/releases/download/macos-v1.0.0/ServerMaster.v1.0.app.zip"
          ]),
      ], availability: "available", supportedOS: ["macOS 14+"], productType: "application",
      applicationNames: ["ServerMaster"],
      targets: [
        PlatformTarget(
          os: "macos", architectures: ["arm64", "x86_64", "universal"], minimumVersion: "14.0",
          downloadKey: "macos")
      ]),
    Product(
      id: "servermaster-windows", name: "ServerMaster · Windows",
      summary: "A visual control center for local servers.", icon: "server.rack",
      iconURL: "https://adm1nsys.github.io/ServerMaster/assets/icon.png",
      latestVersion: "2.0.0", siteURL: "https://adm1nsys.github.io/ServerMaster/",
      platforms: ["Windows", "x86_64"], bundleIdentifiers: [],
      releases: [
        Release(
          version: "2.0.0", publishedAt: nil, downloads: [:], platform: "windows",
          architectures: ["x86_64"], availability: "soon")
      ], availability: "soon", supportedOS: ["Windows"], productType: "application",
      applicationNames: ["ServerMaster"],
      targets: [
        PlatformTarget(
          os: "windows", architectures: ["x86_64"], minimumVersion: nil,
          downloadKey: "windows")
      ]),
    Product(
      id: "servermaster-cli-macos", name: "ServerMaster CLI · macOS",
      summary: "A fast terminal companion for automation.", icon: "terminal",
      iconURL: "https://adm1nsys.github.io/ServerMaster/assets/icon.png",
      latestVersion: "1.0.0", siteURL: "https://adm1nsys.github.io/ServerMaster/",
      platforms: ["macOS 14+", "Apple Silicon"], bundleIdentifiers: [],
      releases: [
        Release(
          version: "1.0.0", publishedAt: nil,
          downloads: [
            "macos":
              "https://github.com/adm1nsys/ServerMaster/releases/download/cli-v1.0.0/servermaster-macos-universal.zip"
          ])
      ], availability: "available", supportedOS: ["macOS 14+"],
      productType: "cli", executable: "servermaster", versionArguments: ["-v"],
      versionedExecutablePrefix: "servermaster-v",
      targets: [
        PlatformTarget(
          os: "macos", architectures: ["arm64"], minimumVersion: "14.0", downloadKey: "macos")
      ]),
    Product(
      id: "servermaster-cli-linux-glibc", name: "ServerMaster CLI · Linux glibc",
      summary: "A fast terminal companion for automation.", icon: "terminal",
      iconURL: "https://adm1nsys.github.io/ServerMaster/assets/icon.png",
      latestVersion: "1.0.0", siteURL: "https://github.com/adm1nsys/ServerMaster",
      platforms: ["Linux glibc", "x86_64", "ARM64"], bundleIdentifiers: [],
      releases: [
        Release(
          version: "1.0.0", publishedAt: nil, downloads: [:], platform: "linux",
          architectures: ["arm64", "x86_64"], libc: "glibc", availability: "soon")
      ],
      availability: "soon", supportedOS: ["Linux glibc"], productType: "cli",
      executable: "servermaster", versionArguments: ["-v"],
      versionedExecutablePrefix: "servermaster-v",
      targets: [
        PlatformTarget(
          os: "linux", architectures: ["arm64", "x86_64"], minimumVersion: nil,
          downloadKey: "linux-glibc", libc: "glibc")
      ]),
    Product(
      id: "servermaster-cli-linux-musl", name: "ServerMaster CLI · Linux musl",
      summary: "A fast terminal companion for automation.", icon: "terminal",
      iconURL: "https://adm1nsys.github.io/ServerMaster/assets/icon.png",
      latestVersion: "1.0.0", siteURL: "https://github.com/adm1nsys/ServerMaster",
      platforms: ["Linux musl", "x86_64", "ARM64"], bundleIdentifiers: [],
      releases: [
        Release(
          version: "1.0.0", publishedAt: nil, downloads: [:], platform: "linux",
          architectures: ["arm64", "x86_64"], libc: "musl", availability: "soon")
      ],
      availability: "soon", supportedOS: ["Linux musl"], productType: "cli",
      executable: "servermaster", versionArguments: ["-v"],
      versionedExecutablePrefix: "servermaster-v",
      targets: [
        PlatformTarget(
          os: "linux", architectures: ["arm64", "x86_64"], minimumVersion: nil,
          downloadKey: "linux-musl", libc: "musl")
      ]),
  ]
}
