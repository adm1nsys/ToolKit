import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

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
  var libc: String?
}

struct Release: Codable, Hashable, Identifiable {
  var id: String { "\(version)-\(platform ?? "generic")-\(libc ?? "")" }
  var version: String
  var publishedAt: Date?
  var downloads: [String: String]
  var platform: String?
  var architectures: [String]?
  var libc: String?
  var availability: String?
}

@MainActor
final class CatalogEditor: ObservableObject {
  @Published var catalog = Catalog(updatedAt: Date(), products: [])
  @Published var sourceText = ""
  @Published var selectedProductID: String?
  @Published var fileURL: URL?
  @Published var errorMessage: String?
  @Published var isCodeMode = false
  @Published private(set) var recentFiles: [URL] = []

  private let recentKey = "maceditor.recentCatalogs"

  init() {
    recentFiles = (UserDefaults.standard.array(forKey: recentKey) as? [String] ?? [])
      .compactMap(URL.init(fileURLWithPath:))
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  var selectedProductIndex: Int? {
    guard let id = selectedProductID else { return nil }
    return catalog.products.firstIndex { $0.id == id }
  }

  func importJSON() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    open(url)
  }

  func open(_ url: URL) {
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      catalog = try decoder.decode(Catalog.self, from: data)
      fileURL = url
      sourceText = try prettyJSON(catalog)
      selectedProductID = catalog.products.first?.id
      errorMessage = nil
      remember(url)
    } catch { errorMessage = "Unable to open catalog: \(error.localizedDescription)" }
  }

  func save() {
    if isCodeMode {
      applyCodeChanges()
      if errorMessage != nil { return }
    }
    guard let url = fileURL else { return saveAs() }
    do {
      let data = try encodedCatalog()
      try data.write(to: url, options: .atomic)
      sourceText = try prettyJSON(catalog)
      remember(url)
      errorMessage = nil
    } catch { errorMessage = "Unable to save catalog: \(error.localizedDescription)" }
  }

  func saveAs() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "catalog.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    fileURL = url
    save()
  }

  func applyCodeChanges() {
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      catalog = try decoder.decode(Catalog.self, from: Data(sourceText.utf8))
      selectedProductID = catalog.products.first?.id
      errorMessage = nil
    } catch { errorMessage = "JSON error: \(error.localizedDescription)" }
  }

  func exportJSON() {
    if isCodeMode {
      applyCodeChanges()
      if errorMessage != nil { return }
    }
    saveAs()
  }

  func addProduct() {
    let product = Product(
      id: "new-product", name: "New Product", summary: "", icon: "shippingbox.fill",
      iconURL: nil, latestVersion: "1.0.0", siteURL: "", platforms: [], bundleIdentifiers: [],
      releases: [], availability: "soon", supportedOS: nil, productType: "application",
      executable: nil, versionArguments: nil, versionedExecutablePrefix: nil,
      applicationNames: nil, targets: nil, isSelf: false)
    catalog.products.append(product)
    selectedProductID = product.id
  }

  func deleteSelectedProduct() {
    guard let index = selectedProductIndex else { return }
    catalog.products.remove(at: index)
    selectedProductID = catalog.products.first?.id
    refreshSourceText()
  }

  func duplicateSelectedProduct() {
    guard let index = selectedProductIndex else { return }
    let original = catalog.products[index]
    var number = 1
    var newID = "\(original.id)-\(number)"
    while catalog.products.contains(where: { $0.id == newID }) {
      number += 1
      newID = "\(original.id)-\(number)"
    }
    var copy = original
    copy.id = newID
    copy.name = "\(original.name) \(number)"
    catalog.products.insert(copy, at: index + 1)
    selectedProductID = copy.id
    refreshSourceText()
  }

  func refreshSourceText() {
    if let text = try? prettyJSON(catalog) { sourceText = text }
  }

  func updateTimestamp() {
    catalog.updatedAt = Date()
    refreshSourceText()
  }

  func deferModelUpdate(_ mutation: @escaping () -> Void) {
    DispatchQueue.main.async { mutation() }
  }

  private func encodedCatalog() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(catalog)
  }

  private func prettyJSON(_ value: Catalog) throws -> String {
    String(data: try encodedCatalog(), encoding: .utf8) ?? ""
  }

  private func remember(_ url: URL) {
    recentFiles.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
    recentFiles.insert(url, at: 0)
    recentFiles = Array(recentFiles.prefix(10))
    UserDefaults.standard.set(recentFiles.map(\.path), forKey: recentKey)
  }
}

struct ContentView: View {
  @EnvironmentObject private var editor: CatalogEditor

  var body: some View {
    NavigationSplitView {
      List(selection: $editor.selectedProductID) {
        Section("Products") {
          ForEach(editor.catalog.products) { product in
            Label(product.name, systemImage: product.icon ?? "shippingbox.fill")
              .tag(product.id as String?)
          }
        }
        Section("Recent catalogs") {
          if editor.recentFiles.isEmpty {
            Text("No recent catalogs").foregroundStyle(.secondary)
          }
          ForEach(editor.recentFiles, id: \.self) { url in
            Button {
              editor.open(url)
            } label: {
              Label(url.deletingPathExtension().lastPathComponent, systemImage: "clock")
            }.buttonStyle(.plain)
          }
        }
      }
      .navigationTitle("Catalog")
      .toolbar {
        ToolbarItem { Button(action: editor.addProduct) { Label("Add", systemImage: "plus") } }
        ToolbarItem {
          Button(action: editor.duplicateSelectedProduct) {
            Label("Duplicate", systemImage: "plus.square.on.square")
          }
          .disabled(editor.selectedProductIndex == nil)
        }
      }
    } detail: {
      VStack(spacing: 0) {
        toolbar
        Divider()
        if editor.isCodeMode {
          CodeEditor(text: $editor.sourceText)
        } else {
          ProductEditor(editor: editor)
        }
        if let error = editor.errorMessage {
          Text(error).font(.caption).foregroundStyle(.red).padding(8)
        }
      }
    }
    .frame(minWidth: 980, minHeight: 640)
    .onChange(of: editor.isCodeMode) { _, codeMode in
      if codeMode { editor.refreshSourceText() } else { editor.applyCodeChanges() }
    }
  }

  private var toolbar: some View {
    HStack {
      Picker("Editor", selection: $editor.isCodeMode) {
        Text("UI").tag(false)
        Text("JSON").tag(true)
      }.pickerStyle(.segmented).frame(width: 170)
      Spacer()
      Button("Import", action: editor.importJSON)
      Button("Export", action: editor.exportJSON)
      Button("Update timestamp", action: editor.updateTimestamp)
      Button("Save", action: editor.save).keyboardShortcut("s")
    }.padding(10)
  }
}

struct CodeEditor: View {
  @Binding var text: String
  var body: some View {
    TextEditor(text: $text)
      .font(.system(.body, design: .monospaced))
      .scrollContentBackground(.hidden)
      .padding(12)
      .background(Color(nsColor: .textBackgroundColor))
  }
}

struct ProductEditor: View {
  @ObservedObject var editor: CatalogEditor
  var body: some View {
    if let index = editor.selectedProductIndex,
      editor.catalog.products.indices.contains(index)
    {
      Form {
        Section("Product") {
          TextField("ID", text: binding(index, \.id))
          TextField("Name", text: binding(index, \.name))
          TextField("Summary", text: binding(index, \.summary))
          TextField("Icon", text: optionalStringBinding(index, \.icon))
          TextField("Icon URL", text: optionalStringBinding(index, \.iconURL))
          TextField("Latest version", text: binding(index, \.latestVersion))
          TextField("Product site", text: binding(index, \.siteURL))
          TextField("Platforms (comma separated)", text: stringArrayBinding(index, \.platforms))
          TextField(
            "Bundle identifiers (comma separated)",
            text: stringArrayBinding(index, \.bundleIdentifiers))
          TextField(
            "Supported OS (comma separated)", text: optionalArrayBinding(index, \.supportedOS))
          TextField("Product type", text: optionalStringBinding(index, \.productType))
          TextField("Executable", text: optionalStringBinding(index, \.executable))
          TextField(
            "Version arguments (comma separated)",
            text: optionalArrayBinding(index, \.versionArguments))
          TextField(
            "Versioned executable prefix",
            text: optionalStringBinding(index, \.versionedExecutablePrefix))
          TextField(
            "Application names (comma separated)",
            text: optionalArrayBinding(index, \.applicationNames))
          Toggle("This is Toolkit", isOn: optionalBoolBinding(index, \.isSelf))
          Picker(
            "Availability",
            selection: optionalStringBinding(index, \.availability, default: "available")
          ) {
            Text("Available").tag("available")
            Text("Soon").tag("soon")
          }
        }
        Section("Platform targets") {
          ForEach(Array((editor.catalog.products[index].targets ?? []).indices), id: \.self) {
            targetIndex in
            TargetRow(editor: editor, productIndex: index, targetIndex: targetIndex)
          }
          Button("Add target") {
            if editor.catalog.products[index].targets == nil {
              editor.catalog.products[index].targets = []
            }
            editor.catalog.products[index].targets?.append(
              PlatformTarget(
                os: "macos", architectures: ["universal"], minimumVersion: "14.0",
                downloadKey: "macos", libc: nil))
          }
        }
        Section("Releases") {
          ForEach(editor.catalog.products[index].releases) { release in
            ReleaseRow(editor: editor, productIndex: index, releaseID: release.id)
          }
          Button("Add release") {
            editor.catalog.products[index].releases.append(
              Release(version: "1.0.0", publishedAt: nil, downloads: [:]))
          }
        }
        Section {
          Button("Duplicate product", action: editor.duplicateSelectedProduct)
          Button("Delete product", role: .destructive, action: editor.deleteSelectedProduct)
        }
      }.formStyle(.grouped)
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 0)
          .fill(Color.gray.opacity(0))
        ContentUnavailableView("No product selected", systemImage: "shippingbox")
      }
    }
  }

  private func binding<T>(_ index: Int, _ keyPath: WritableKeyPath<Product, T>) -> Binding<T> {
    let fallback = editor.catalog.products[index][keyPath: keyPath]
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(index) else { return fallback }
        return editor.catalog.products[index][keyPath: keyPath]
      },
      set: {
        guard editor.catalog.products.indices.contains(index) else { return }
        let value = $0
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(index) else { return }
          editor.catalog.products[index][keyPath: keyPath] = value
        }
      })
  }

  private func stringArrayBinding(_ index: Int, _ keyPath: WritableKeyPath<Product, [String]>)
    -> Binding<String>
  {
    let fallback = editor.catalog.products[index][keyPath: keyPath].joined(separator: ", ")
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(index) else { return fallback }
        return editor.catalog.products[index][keyPath: keyPath].joined(separator: ", ")
      },
      set: {
        guard editor.catalog.products.indices.contains(index) else { return }
        let value = $0.split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespaces)
        }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(index) else { return }
          editor.catalog.products[index][keyPath: keyPath] = value
        }
      })
  }

  private func optionalStringBinding(
    _ index: Int, _ keyPath: WritableKeyPath<Product, String?>, default defaultValue: String = ""
  )
    -> Binding<String>
  {
    let fallback = editor.catalog.products[index][keyPath: keyPath] ?? defaultValue
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(index) else { return fallback }
        return editor.catalog.products[index][keyPath: keyPath] ?? defaultValue
      },
      set: {
        guard editor.catalog.products.indices.contains(index) else { return }
        let value = $0
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(index) else { return }
          editor.catalog.products[index][keyPath: keyPath] = value
        }
      })
  }

  private func optionalArrayBinding(_ index: Int, _ keyPath: WritableKeyPath<Product, [String]?>)
    -> Binding<String>
  {
    let fallback = editor.catalog.products[index][keyPath: keyPath]?.joined(separator: ", ") ?? ""
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(index) else { return fallback }
        return editor.catalog.products[index][keyPath: keyPath]?.joined(separator: ", ") ?? ""
      },
      set: { value in
        guard editor.catalog.products.indices.contains(index) else { return }
        let array: [String]? =
          value.isEmpty
          ? nil
          : value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
          }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(index) else { return }
          editor.catalog.products[index][keyPath: keyPath] = array
        }
      })
  }

  private func optionalBoolBinding(_ index: Int, _ keyPath: WritableKeyPath<Product, Bool?>)
    -> Binding<Bool>
  {
    let fallback = editor.catalog.products[index][keyPath: keyPath] ?? false
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(index) else { return fallback }
        return editor.catalog.products[index][keyPath: keyPath] ?? false
      },
      set: { value in
        guard editor.catalog.products.indices.contains(index) else { return }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(index) else { return }
          editor.catalog.products[index][keyPath: keyPath] = value
        }
      })
  }
}

struct TargetRow: View {
  @ObservedObject var editor: CatalogEditor
  let productIndex: Int
  let targetIndex: Int

  var body: some View {
    if editor.catalog.products.indices.contains(productIndex),
      let targets = editor.catalog.products[productIndex].targets,
      targets.indices.contains(targetIndex)
    {
      VStack(alignment: .leading) {
        TextField("OS", text: binding(\.os))
        TextField("Architectures (comma separated)", text: arrayBinding(\.architectures))
        TextField("Minimum OS version", text: optionalBinding(\.minimumVersion))
        TextField("Download key", text: binding(\.downloadKey))
        TextField("Libc", text: optionalBinding(\.libc))
      }
      .padding(.vertical, 4)
    }
  }

  private func binding<T>(_ keyPath: WritableKeyPath<PlatformTarget, T>) -> Binding<T> {
    let fallback = editor.catalog.products[productIndex].targets![targetIndex][keyPath: keyPath]
    return Binding(
      get: {
        guard let target = currentTarget else { return fallback }
        return target[keyPath: keyPath]
      },
      set: { value in
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].targets?.indices.contains(targetIndex) == true
          else { return }
          editor.catalog.products[productIndex].targets![targetIndex][keyPath: keyPath] = value
        }
      })
  }

  private func arrayBinding(_ keyPath: WritableKeyPath<PlatformTarget, [String]>) -> Binding<String>
  {
    let fallback = editor.catalog.products[productIndex].targets![targetIndex][keyPath: keyPath]
      .joined(separator: ", ")
    return Binding(
      get: { currentTarget?[keyPath: keyPath].joined(separator: ", ") ?? fallback },
      set: { value in
        let array = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].targets?.indices.contains(targetIndex) == true
          else { return }
          editor.catalog.products[productIndex].targets![targetIndex][keyPath: keyPath] = array
        }
      })
  }

  private func optionalBinding(_ keyPath: WritableKeyPath<PlatformTarget, String?>) -> Binding<
    String
  > {
    let fallback =
      editor.catalog.products[productIndex].targets![targetIndex][keyPath: keyPath] ?? ""
    return Binding(
      get: { currentTarget?[keyPath: keyPath] ?? fallback },
      set: { value in
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].targets?.indices.contains(targetIndex) == true
          else { return }
          editor.catalog.products[productIndex].targets![targetIndex][keyPath: keyPath] =
            value.isEmpty ? nil : value
        }
      })
  }

  private var currentTarget: PlatformTarget? {
    guard editor.catalog.products.indices.contains(productIndex),
      let targets = editor.catalog.products[productIndex].targets,
      targets.indices.contains(targetIndex)
    else { return nil }
    return targets[targetIndex]
  }
}

struct ReleaseRow: View {
  @ObservedObject var editor: CatalogEditor
  let productIndex: Int
  let releaseID: String
  var body: some View {
    if editor.catalog.products.indices.contains(productIndex),
      let index = editor.catalog.products[productIndex].releases.firstIndex(where: {
        $0.id == releaseID
      })
    {
      VStack(alignment: .leading) {
        TextField("Version", text: releaseBinding(index, \.version))
        TextField("Platform", text: optionalReleaseBinding(index, \.platform))
        TextField(
          "Architectures (comma separated)", text: releaseArrayBinding(index, \.architectures))
        TextField("Libc", text: optionalReleaseBinding(index, \.libc))
        TextField("Minimum availability", text: optionalReleaseBinding(index, \.availability))
        TextField("Published at (ISO 8601)", text: dateBinding(index))
        TextField("Downloads JSON", text: downloadsBinding(index))
      }
      .padding(.vertical, 4)
    }
  }
  private func releaseBinding<T>(_ index: Int, _ keyPath: WritableKeyPath<Release, T>) -> Binding<T>
  {
    let fallback = editor.catalog.products[productIndex].releases[index][keyPath: keyPath]
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return fallback }
        return editor.catalog.products[productIndex].releases[index][keyPath: keyPath]
      },
      set: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return }
        let value = $0
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].releases.indices.contains(index)
          else { return }
          editor.catalog.products[productIndex].releases[index][keyPath: keyPath] = value
        }
      })
  }
  private func optionalReleaseBinding(_ index: Int, _ keyPath: WritableKeyPath<Release, String?>)
    -> Binding<String>
  {
    let fallback = editor.catalog.products[productIndex].releases[index][keyPath: keyPath] ?? ""
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return fallback }
        return editor.catalog.products[productIndex].releases[index][keyPath: keyPath] ?? ""
      },
      set: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return }
        let value = $0.isEmpty ? nil : $0
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].releases.indices.contains(index)
          else { return }
          editor.catalog.products[productIndex].releases[index][keyPath: keyPath] = value
        }
      })
  }
  private func downloadBinding(_ index: Int) -> Binding<String> {
    let fallback =
      editor.catalog.products[productIndex].releases[index].downloads.keys.first ?? "macos"
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return fallback }
        return editor.catalog.products[productIndex].releases[index].downloads.keys.first ?? "macos"
      },
      set: { value in
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].releases.indices.contains(index)
          else { return }
          let current =
            editor.catalog.products[productIndex].releases[index].downloads.values.first ?? ""
          editor.catalog.products[productIndex].releases[index].downloads = [value: current]
        }
      })
  }

  private func releaseArrayBinding(_ index: Int, _ keyPath: WritableKeyPath<Release, [String]?>)
    -> Binding<String>
  {
    let fallback =
      editor.catalog.products[productIndex].releases[index][keyPath: keyPath]?.joined(
        separator: ", ") ?? ""
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return fallback }
        return editor.catalog.products[productIndex].releases[index][keyPath: keyPath]?.joined(
          separator: ", ") ?? ""
      },
      set: { value in
        let array: [String]? =
          value.isEmpty
          ? nil : value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].releases.indices.contains(index)
          else { return }
          editor.catalog.products[productIndex].releases[index][keyPath: keyPath] = array
        }
      })
  }

  private func dateBinding(_ index: Int) -> Binding<String> {
    let fallback = isoString(editor.catalog.products[productIndex].releases[index].publishedAt)
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return fallback }
        return isoString(editor.catalog.products[productIndex].releases[index].publishedAt)
      },
      set: { value in
        let date = parseDate(value)
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].releases.indices.contains(index)
          else { return }
          editor.catalog.products[productIndex].releases[index].publishedAt = date
        }
      })
  }

  private func downloadsBinding(_ index: Int) -> Binding<String> {
    let fallback = downloadsText(editor.catalog.products[productIndex].releases[index].downloads)
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return fallback }
        return downloadsText(editor.catalog.products[productIndex].releases[index].downloads)
      },
      set: { value in
        guard let data = value.data(using: .utf8),
          let downloads = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].releases.indices.contains(index)
          else { return }
          editor.catalog.products[productIndex].releases[index].downloads = downloads
        }
      })
  }

  private func isoString(_ date: Date?) -> String {
    guard let date else { return "" }
    return ISO8601DateFormatter().string(from: date)
  }

  private func parseDate(_ value: String) -> Date? {
    guard !value.isEmpty else { return nil }
    return ISO8601DateFormatter().date(from: value)
  }

  private func downloadsText(_ downloads: [String: String]) -> String {
    guard let data = try? JSONEncoder().encode(downloads) else { return "{}" }
    return String(data: data, encoding: .utf8) ?? "{}"
  }
  private func urlBinding(_ index: Int) -> Binding<String> {
    let fallback =
      editor.catalog.products[productIndex].releases[index].downloads.values.first ?? ""
    return Binding(
      get: {
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return fallback }
        return editor.catalog.products[productIndex].releases[index].downloads.values.first ?? ""
      },
      set: { value in
        guard editor.catalog.products.indices.contains(productIndex),
          editor.catalog.products[productIndex].releases.indices.contains(index)
        else { return }
        editor.deferModelUpdate {
          guard editor.catalog.products.indices.contains(productIndex),
            editor.catalog.products[productIndex].releases.indices.contains(index)
          else { return }
          let key =
            editor.catalog.products[productIndex].releases[index].downloads.keys.first ?? "macos"
          editor.catalog.products[productIndex].releases[index].downloads = [key: value]
        }
      })
  }
}

#Preview { ContentView() }
