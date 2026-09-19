//
//  maceditorApp.swift
//  maceditor
//
//  Created by Heorhii on 19.09.26.
//

import SwiftUI

@main
struct maceditorApp: App {
  @StateObject private var editor = CatalogEditor()

  var body: some Scene {
    WindowGroup {
      ContentView().environmentObject(editor)
    }
    .commands {
      CommandGroup(after: .newItem) {
        Button("Import Catalog…", action: editor.importJSON)
          .keyboardShortcut("o")
        Button("Save Catalog", action: editor.save)
          .keyboardShortcut("s")
        Button("Export Catalog…", action: editor.exportJSON)
          .keyboardShortcut("e", modifiers: [.command, .shift])
      }
      CommandGroup(after: .pasteboard) {
        Button("Duplicate Product", action: editor.duplicateSelectedProduct)
          .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Delete Product", role: .destructive, action: editor.deleteSelectedProduct)
          .keyboardShortcut(.delete, modifiers: [.command])
      }
      CommandMenu("Catalog") {
        Button("Update Catalog Timestamp", action: editor.updateTimestamp)
        Button("Add Product", action: editor.addProduct)
      }
    }
  }
}
