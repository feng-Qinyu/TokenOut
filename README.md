# TokenOut

TokenOut is a macOS WidgetKit app for watching Codex token quota at a glance.

It shows four quota rings:

- Weekly remaining quota
- 5-hour remaining quota
- Today used quota
- Today unused target quota

The app includes both a normal macOS client window and a native WidgetKit widget that can be dragged onto the desktop from the macOS widget picker.

## What It Does

TokenOut reads Codex quota data through the local Codex app server and writes a small snapshot file for the widget to display.

Current UI:

- Green ring: healthy remaining quota
- Red ring: remaining quota below 20%
- Client window: includes metric names, percentages, descriptions, update time, and refresh frequency
- Desktop widget: compact ring view for always-on monitoring

## Data Source

The background fetch script calls:

```text
account/rateLimits/read
```

from the local Codex app server.

The snapshot is written to:

```text
/Applications/TokenOut.app/Contents/Resources/snapshot.json
```

The widget reads that snapshot directly.

## Refresh Behavior

TokenOut installs a LaunchAgent:

```text
local.tokenout.fetch
```

It refreshes every 60 seconds.

The LaunchAgent plist template is:

```text
Scripts/local.tokenout.fetch.plist
```

## Current Metric Meaning

- Weekly remaining: `100 - weekly usedPercent`
- 5-hour remaining: `100 - primary usedPercent`
- Today used: currently displayed as a fixed 12% value
- Today unused: estimated from the weekly reset window, current week day, weekly remaining quota, and daily target budget

Codex currently does not expose a direct "used since local midnight" field through this flow, so the daily metric is an estimate.

## Build

Requirements:

- macOS 14+
- Xcode
- A local Codex app installation

Build from the project directory:

```bash
xcodebuild \
  -project CodexQuota.xcodeproj \
  -scheme CodexQuota \
  -configuration Debug \
  -derivedDataPath /private/tmp/CodexQuotaDerivedData \
  -allowProvisioningUpdates \
  build
```

The built app will be:

```text
/private/tmp/CodexQuotaDerivedData/Build/Products/Debug/TokenOut.app
```

## Install Locally

Copy the app into `/Applications`:

```bash
rm -rf /Applications/TokenOut.app
cp -R /private/tmp/CodexQuotaDerivedData/Build/Products/Debug/TokenOut.app /Applications/TokenOut.app
xattr -cr /Applications/TokenOut.app
```

Install the background fetch script and LaunchAgent:

```bash
mkdir -p "$HOME/Library/Application Support/TokenOut" "$HOME/Library/Logs" "$HOME/Library/LaunchAgents"
cp Scripts/fetch-quota.js "$HOME/Library/Application Support/TokenOut/fetch-quota.js"
cp Scripts/local.tokenout.fetch.plist "$HOME/Library/LaunchAgents/local.tokenout.fetch.plist"
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/local.tokenout.fetch.plist"
launchctl kickstart -k gui/$(id -u)/local.tokenout.fetch
```

Register the widget:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R -trusted /Applications/TokenOut.app
pluginkit -e use -i local.tokenout.app.widget
```

Then open the macOS widget picker and search for:

```text
TokenOut
```

## Notes

This project is currently a local macOS utility. It is not distributed through the Mac App Store.

The Xcode target names still use the original project scaffold names, but the built app and widget are named TokenOut:

- App bundle id: `local.tokenout.app`
- Widget bundle id: `local.tokenout.app.widget`
- LaunchAgent id: `local.tokenout.fetch`
