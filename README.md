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
./build.sh                      # builds FanControl.app (UI) and the bundled helper
open FanControl.app
sudo ./install-helper.sh        # installs the root helper as a launchd service
```

You can also click **Install helper** inside the app instead of running the script; it asks for your admin password once.

Reading temperature and RPM needs no privileges. Writing the fan speed does, so a small root helper (`fanctld`) is installed to `/usr/local/libexec` with a launch daemon in `/Library/LaunchDaemons`.

To uninstall:

```sh
sudo launchctl bootout system/com.local.fanctld
sudo rm /Library/LaunchDaemons/com.local.fanctld.plist /usr/local/libexec/fanctld
```

## How it works

| Part | Role |
| --- | --- |
| `Core.swift` | Talks to the AppleSMC IOKit service (fan keys `F0Ac`, `F0Tg`, `F0Md`, `F0Mn`, `F0Mx`) and reads SoC temperature from the HID sensor service. |
| `daemon/main.swift` | Root helper. Applies the active mode every 2 s and listens on `/var/run/fanctl.sock`. |
| `FanApp.swift` | SwiftUI menu bar item and window. Reads sensors directly and sends mode commands to the helper. |

The helper socket accepts one line per connection: `mode`, `auto`, `hold <lo> <hi>`, `fixed <rpm>`. Values are validated and clamped to the fan's range.

## Caveats

- The SMC is an undocumented interface. Keys and behavior can change between Mac models and macOS versions; only one machine has been tested.
- The app is ad-hoc signed, so it runs on the machine that built it but is not notarized for distribution.
- The helper socket is world-writable so the unprivileged app can send commands. It only accepts fan mode and speed, limited to hardware range.
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
