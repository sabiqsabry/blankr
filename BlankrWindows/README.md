# Blankr. for Windows

Zero-distraction note-taking — faithful Windows port of the macOS original.

## Requirements

- Windows 10 1809+ or Windows 11
- Visual Studio 2022 17.8+ with:
  - **.NET Desktop Development** workload
  - **Windows App SDK C# Templates** component
- .NET 8 SDK

## Build & Run

1. Open `Blankr.sln` in Visual Studio 2022.
2. Set platform to **x64** (or ARM64 for ARM machines).
3. Press **F5** to build and run.

If NuGet packages fail to restore, right-click the solution → **Restore NuGet Packages**, or run:

```
dotnet restore --runtime win-x64
```

## Produce MSIX Package

### Via Visual Studio

1. Right-click the **Blankr** project → **Publish** → **Create App Packages**.
2. Choose **Sideloading**, click Next.
3. Select **Yes, use the current certificate** (or create a test certificate).
4. Pick x64 (and optionally ARM64), Release configuration.
5. Click **Create**. The `.msix` will be in `Blankr\AppPackages\`.

### Via CLI

```
dotnet publish -c Release -r win-x64 -p:Platform=x64
```

The output MSIX lands in `Blankr\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\AppX\`.

## Distribution Notes

- For sideloading without SmartScreen warnings, sign the MSIX with a trusted certificate.
- Users install by double-clicking the `.msix` file (they may need to enable sideloading in Windows Settings → Developer settings).
