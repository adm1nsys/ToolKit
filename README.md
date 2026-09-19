# adm1nsys Toolkit

The desktop installer and update hub for adm1nsys applications.

Toolkit is catalog-driven: product metadata, compatible platforms, release history and download links live in `catalog.json`. The app keeps a built-in fallback catalog, detects installed products by bundle identifier, and continues to show local information when the network is unavailable.

## Repository layout

- `mac/` — SwiftUI macOS application.
- `catalog.json` — remote catalog source of truth.
- `web/` — public landing page, installation guide and 404 page; changes deploy automatically through GitHub Pages.
- `maceditor/` — private-use catalog editor; it is included for maintaining `catalog.json` and is not shipped to Toolkit users.

GitHub Actions deploys `web/` to Pages and builds the Toolkit macOS app as an unsigned universal (`arm64` + `x86_64`) artifact. The catalog editor has no release workflow.

Each platform variant has its own product card in the catalog. `targets` describes the operating
system, CPU architecture and (for Linux) libc; `releases` contains the version history for that card.
Linux CLI builds are intentionally separate cards for glibc and musl, while unreleased Windows and
Linux cards are marked `soon` and have no download URL until they are published.
