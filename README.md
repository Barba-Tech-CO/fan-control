# Fan Control

A small native macOS app to watch your Mac's chip temperature and control the fan on Apple Silicon.
Built with SwiftUI. No third-party dependencies.

## Features

- Live chip temperature and fan RPM, with a 6-minute graph.
- Three modes:
  - **Auto** — macOS controls the fan.
  - **Hold** — keeps the chip inside a temperature band you choose (for example 80–85 °C). The fan speeds up above the max and relaxes below the min.
  - **Manual** — fixed fan speed from the hardware minimum to maximum, shown in RPM and percent.
- Menu bar item with the fan icon and current temperature, plus a regular window.
- Safety net: at 95 °C the helper forces full speed in any mode, and returns control to macOS when it stops.

## Requirements

- Apple Silicon Mac with a fan (developed and tested on a Mac mini M4 Pro, macOS 27).
- macOS 14 or later.
- Swift toolchain with SwiftUI and Charts (Xcode or Command Line Tools) to build from source.

## Build and install

```sh
./build.sh
sudo cp -R FanControl.app /Applications/
sudo chown -R root:wheel /Applications/FanControl.app
open /Applications/FanControl.app
```

Then click **Install helper** in the window and allow Fan Control in System Settings → General → Login Items & Extensions → Allow in the Background.

Reading temperature and RPM needs no privileges. Writing the fan speed does, so a small root helper (`fanctld`) ships inside the app and is registered as a launch daemon with `SMAppService`. The helper runs as root from inside the app bundle, so the app refuses to register it unless the bundle is not writable by your user (hence the root-owned copy in `/Applications`).

To uninstall: click **Remove helper** in the app (or switch it off in Login Items), then delete the app.

## How it works

| Part | Role |
| --- | --- |
| `Core.swift` | Talks to the AppleSMC IOKit service (fan keys `F0Ac`, `F0Tg`, `F0Md`, `F0Mn`, `F0Mx`) and reads SoC temperature from the HID sensor service. |
| `daemon/main.swift` | Root helper (launch daemon from the app bundle). Applies the active mode every 2 s and listens on `/var/run/fanctl.sock`. |
| `FanApp.swift` | SwiftUI menu bar item and window. Reads sensors directly and sends mode commands to the helper. |

The helper socket accepts one line per connection: `mode`, `auto`, `hold <lo> <hi>`, `fixed <rpm>`. Values are validated and clamped to the fan's range.

## Caveats

- The SMC is an undocumented interface. Keys and behavior can change between Mac models and macOS versions; only one machine has been tested.
- The app is ad-hoc signed, so it runs on the machine that built it but is not notarized for distribution. Because there is no Developer ID / Team ID to pin, a process with admin-group rights could still replace the root-owned bundle in `/Applications`; with a paid Developer ID you would add a signing requirement to the daemon.
- The helper socket is connectable by any local user, but state-changing commands are accepted only from root or the user logged in at the console (checked with `getpeereid`); anyone can read the current mode. Commands only set fan mode and speed, limited to the hardware range.
- Clients get a 1 s read timeout so a stalled connection cannot block the thermal control loop.
- Running the fan faster lowers temperature but adds noise. It does not raise performance unless the chip was thermally throttling.
- Use at your own risk.

## Offscreen preview

`preview/main.swift` renders the main view to a PNG without screen capture, useful for UI work:

```sh
swiftc -D PREVIEW -swift-version 5 Core.swift FanApp.swift preview/main.swift -o preview-bin
./preview-bin out.png hold 1
```

## License

MIT — see [LICENSE](LICENSE).
