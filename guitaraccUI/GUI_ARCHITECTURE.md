// GuitarAcc Basestation GUI Architecture (macOS)
//
// Overview
// This document describes the architecture for a macOS application (GUI) that interfaces with the GuitarAcc Basestation via its Zephyr Shell CLI over a USB serial (VCOM) connection. The GUI acts as a command center for configuring, monitoring, and managing the basestation. It does not process MIDI data directly; all MIDI communication is handled by the basestation firmware.
//
// Key Responsibilities
// - Discover and connect to the basestation over a USB serial port.
// - Send CLI commands (e.g., set MIDI channel, select MIDI patch, export/import configurations).
// - Parse and present CLI command responses in a user-friendly way.
// - Provide a graphical interface for:
//     - Viewing status and configuration
//     - Changing MIDI and system settings
//     - Exporting/importing configuration
//     - Monitoring runtime state
//
// System Context
// - Basestation: Embedded device running Zephyr Shell on USB VCOM (115200 baud, 8N1, no flow control).
// - GUI (macOS App): Swift/SwiftUI application communicating as a serial terminal client.
// - Clients: BLE guitar devices (not directly managed by the GUI).
//
// Communication Model
// - The GUI opens the correct /dev/tty.usbmodem* serial port.
// - Sends CLI commands as plain text (terminated by \n or \r\n).
// - Reads line-oriented text responses from the basestation.
// - Some commands (e.g., config export) may return multi-line or JSON output.
// - The GUI must maintain stateful interaction, handling prompts, streaming logs, command history, and multi-line input sessions (e.g., for imports).
//
// macOS Implementation Notes
// - Serial Port Discovery and Selection:
//     - On launch or when connecting, the GUI discovers all serial ports matching the pattern `/dev/tty.usbmodem*`.
//     - There are typically two such ports; only the "application interface" should be used for CLI communication (the other is for network connection).
//     - The GUI attempts to connect to the lowest-numbered port first, opening it with the configuration: 115200 baud, timeout=1, rtscts=True.
//     - It sends a known CLI command (such as `status` or `help`) and checks for a valid response.
//     - If a valid CLI response is received, this port is used as the CLI interface.
//     - If not, the GUI disconnects and attempts to connect to the second port, repeating the probe.
//     - The port string will look like `/dev/tty.usbmodem0010501494421` (exact suffix may vary by device).
//     - All connection attempts should handle errors gracefully and notify the user if no valid CLI port is found.
// - Serial Communication: Use ORSSerialPort or equivalent for Swift serial port access, with support for line-based reading and timeouts.
// - UI Technologies: Prefer SwiftUI for all user-facing components; use AppKit bridges only if needed.
// - Concurrency: Leverage Swift Concurrency (async/await) for serial I/O and UI updates.
// - Response Parsing: Implement parsers for both plain CLI output and JSON-formatted responses (for configuration import/export).
// - Device Discovery: Poll /dev/tty.usbmodem* to auto-detect the basestation, allow user selection if multiple devices.
// - State Management: Cache last known device state (config, status) for user feedback.
//
// GUI Functional Areas
// - Connection Management:
//     - Show list of available VCOM ports
//     - Allow connect/disconnect
// - Status Monitoring:
//     - Periodically issue status and midi rx_stats commands
//     - Display connected devices, MIDI state, and runtime stats
// - Configuration Management:
//     - View current config (config show or parsed export)
//     - Change MIDI channel, patch, CC mappings (send config midi_ch <n>, config select <n>, etc.)
//     - Export/import configuration as JSON (with validation and error reporting)
//     - Restore defaults, save changes
// - Command Execution:
//     - Map GUI actions to CLI commands, display output/errors
//     - Provide advanced/terminal view for direct CLI access (optional)
//
// Example Workflow
// 1. User launches GUI
// 2. GUI discovers basestation serial port, user connects
// 3. Status and configuration fetched and shown
// 4. User sets new MIDI channel (GUI issues config midi_ch 2)
// 5. User exports configuration (GUI issues config export, parses JSON)
// 6. User imports configuration (GUI issues config import, streams JSON line-by-line)
// 7. User monitors status and MIDI statistics in real time
//
// Error Handling
// - Notify user of connection failures, timeouts, or unexpected CLI responses
// - Validate responses for success/failure and show errors clearly
// - Handle multi-line command sessions gracefully (e.g., config import)
//
// Extensibility
// - New CLI commands are supported by updating the GUI's mapping and parsers
// - Underlying protocol is text/JSON over serial; robust to CLI enhancements
//
// Security/Permissions
// - macOS app requires user permission to access serial ports
// - Recommend notarization and appropriate entitlements for distribution
//
// References
// - UI_INTERFACE.md — https://github.com/richmaes/guitaracc/blob/main/basestation/UI_INTERFACE.md
// - ARCHITECTURE.md — Overall system architecture of the hardware device - https://github.com/richmaes/guitaracc/blob/main/ARCHITECTURE.md
//
// This architecture provides a modern, robust way to manage and configure the GuitarAcc Basestation from macOS, leveraging the existing CLI for all device communication and logic.
//
// GUI Views
//
// Global Settings View:
// - Purpose:
//     Display and allow editing of global configuration values such as MIDI channel, BLE scan interval, LED brightness, running average settings, and other global parameters.
// - Data Handling:
//     Values are fetched from the basestation using CLI commands and updates are performed by issuing the corresponding CLI commands (e.g., `config midi_ch <n>`).
// - User Interaction:
//     Users can edit fields representing the global settings and apply/save changes via a dedicated button.
//     Validation is performed on input fields, with clear feedback and error reporting in case of invalid values or command failures.
//
// Patch Configuration View:
// - Purpose:
//     Display and allow editing of per-patch configuration settings including patch name, velocity curve, CC mapping, accel minimum/maximum/invert settings, and other patch-specific parameters.
// - Data Handling:
//     This view is reused for all 16 patches. Patch data is fetched and saved using CLI commands such as `config patch <n>`, `config select <n>`, etc.
// - User Interaction:
//     Users select the active patch using a UI control such as a tab bar, dropdown, or segmented control at the top of the view.
//     Edits affect only the currently selected patch and require explicit user confirmation (e.g., via a save/apply button) to persist changes.
//
// Patch Selection & Sync Behavior
// - Overview:
//     The Patch view stays synchronized with the basestation’s currently active patch and updates the device when the user selects a different patch.
// - On View Appear:
//     1. Query the device for the currently selected patch (tries `config show`, then `status`).
//     2. Set the UI’s selected patch to match the device.
//     3. Export the selected patch configuration using `config export patch <n>` and display it in the view (raw text/JSON until structured parsing is implemented).
// - On Patch Change (user taps a different patch):
//     1. Issue `config select <n>` to switch the device’s active patch.
//     2. Issue `config export patch <n>` to retrieve the new patch configuration.
//     3. Update the view with the exported configuration.
// - Error Handling:
//     - If the device is disconnected, the UI disables patch actions until reconnected.
//     - If a command times out or returns an error, the view shows the last known export and a log entry appears in the CLI panel.
// - Concurrency/UX:
//     - The view prevents overlapping operations (debounce/cancellation as needed) to keep the UI responsive when switching patches quickly.
//     - Auto-reconnect attempts continue in the background; when connection is re-established, the view can re-run the export for the currently selected patch.
// - Connection-State Sync:
//     - If the Patch view is visible and the device connection becomes established (after auto-reconnect), the view re-queries the current patch index and re-exports the configuration to ensure the UI reflects the device state.
//
// - No Default Patch Assumption:
//     - The GUI does not blindly assume patch 0 on startup. It queries the device for the current patch index; only if the device does not report a value does the GUI retain the current UI selection.
//
// - Logging / Diagnostics:
//     - During initial sync, the GUI logs: "Sync: querying current patch index…" and then the discovered index and source (e.g., from `config show` or `status`).
//     - If the index cannot be determined, the GUI logs: "Sync: could not determine current patch index." and proceeds using the current UI selection.
//
// Device CLI Contract (Patch)
// - Commands:
//     - `config select <n>`: Makes patch `<n>` the active patch (0–15).
//     - `config export patch <n>`: Outputs the full configuration for patch `<n>` (text/JSON; treated as multi-line output).
//     - `config show` / `status`: Used to infer the currently selected patch when the view appears.
// - Responses:
//     - `config select <n>` should complete quickly; any errors should be surfaced in the CLI output.
//     - `config export patch <n>` may return multi-line output (often JSON); the GUI collects until a quiet period.
// - Notes:
//     - The GUI currently displays the raw export text. A future enhancement will parse this into a structured model for field-by-field editing and saving.
//
// Example: Patch Export Output
// - The device returns JSON for `config export patch <n>`. Below is a real-world example for patch 8. Note that some shells include a trailing prompt and ANSI escape sequences; the GUI should ignore non-JSON lines and strip escape codes when parsing.
//
// ```json
// {
//   "version": 1,
//   "config": {
//     "patches": [
//       {
//         "patch_num": 8,
//         "patch_name": "Patch 8",
//         "velocity_curve": 0,
//         "cc_mapping": [16, 17, 18, 19, 20, 21],
//         "led_mode": 0,
//         "accel_deadzone": 1,
//         "accel_min": [0, 0, 0, 0, 0, 0],
//         "accel_max": [127, 127, 127, 127, 127, 127],
//         "accel_invert": 0
//       }
//     ]
//   }
// }
// ```
//
// Trailing prompt example (to be ignored by parser):
// ```
// [1;32mGuitarAcc:~$ [m
// ```
//
// Parsing considerations:
// - Collect multi-line output and attempt to extract the JSON object by balancing braces `{`/}`.
// - Strip ANSI escape sequences and any trailing prompt line before JSON decoding.
// - Validate that `patch_num` matches the requested export index and surface inconsistencies.
//
// Save/Sync Behavior:
// - Purpose:
//     Provide an explicit action to synchronize the GUI with the currently selected patch on the basestation.
// - Behavior on Press:
//     1. Issue `config select <n>` to instruct the basestation to load/activate the selected patch (where `<n>` is the patch index chosen in the UI).
//     2. Issue `config export patch <n>` to retrieve the full configuration for that patch (typically JSON/multi-line text).
//     3. Parse and display the resulting configuration in the Patch Configuration View so users can review the live settings.
// - Notes:
//     - The GUI may also automatically perform step (2) when the user changes the selected patch, but the explicit Save/Sync button ensures users can refresh on demand.
//     - If the export returns JSON, the GUI should attempt to parse it into a structured model for field-by-field editing; until parsing is implemented, the raw JSON/text can be displayed.
//     - Error cases (timeouts, invalid responses) should be surfaced to the user with clear feedback, leaving the last known configuration visible.
//
// Data Flow:
// - User presses Save/Sync → GUI sends `config select <n>` → GUI sends `config export patch <n>` → GUI collects multi-line output → GUI parses (or displays raw) → Patch view updates.
//
// Implementation Status:
// - [x] Save/Sync button added to Patch view that triggers `config select` and `config export patch`.
// - [x] USBSerialManager helper to execute a command and collect multi-line output with per-line timeout.
// - [ ] Parse exported patch config JSON into a structured model and bind to editable fields.
// - [ ] Persist edits back to device via appropriate `config` commands.
//
// Status & Monitoring View:
// - Purpose:
//     Display real-time system status including number of connected devices, MIDI output state, and configuration area status.
// - Data Handling:
//     Data is fetched with the `status` command and periodically refreshed.
// - User Interaction:
//     Read-only view displaying status fields; may provide a manual refresh button.
//
// MIDI Statistics & Diagnostics View:
// - Purpose:
//     Show live MIDI receive statistics such as total bytes, clock messages, BPM, and message counts.
// - Data Handling:
//     Uses `midi rx_stats` command for data and may offer a reset button (`midi rx_reset`).
// - User Interaction:
//     Real-time or on-demand updates; reset statistics option.
//
// Configuration Import/Export View:
// - Purpose:
//     Manage backup/restore operations for global and per-patch config using JSON import/export.
// - Data Handling:
//     Uses CLI commands (`config export`, `config import`, `config export global`, `config export patch <n>`). Handles multi-line input and output. Provides feedback and error reporting.
// - User Interaction:
//     File chooser, text import/export, validation feedback, progress indication.
//
// Advanced/Terminal View:
// - Purpose:
//     Let experienced users send arbitrary CLI commands or interact with the shell directly. Show live log output as needed.
// - Data Handling:
//     Raw text I/O to/from the CLI. Provides full transparency and flexibility.
// - User Interaction:
//     Command entry field with history, output area, scrollback, and possibly logging toggle.
//
// CLI Interaction Display:
// - Purpose:
//     Floating or dockable panel that shows all CLI commands sent and received, live and in chronological order.
// - Implementation:
//     Can be a detachable window, popover, or sidebar panel. Should display timestamps, sent commands, responses, and errors. Optionally supports filtering or clearing the log.
//
// Note:
// Each view is modular; users can work in one area while keeping the CLI display visible for transparency and debugging. All views are kept synchronized with the parsed CLI state and error events.
//
//
// Implementation To-Do List
//
// - [x] Create USBSerialManager for port discovery, probing, and CLI communication
// - [x] Scaffold GuitarAccApp.swift with main app entry and navigation
// - [x] Add stub views for: Status, Global Settings, Patch Config, MIDI Stats, Import/Export, Terminal, CLI Interaction Display
// - [x] Wire up patch configuration view with patch selector and CLI-driven data flow (auto sync on appear + on change + on reconnect, export display, no default-to-0)
// - [ ] Implement backend command controller for issuing CLI commands and parsing responses
// - [ ] Wire up global settings view with live data binding and CLI-driven updates
// - [ ] Implement status and monitoring view with periodic updates
// - [ ] Implement MIDI statistics and diagnostics view
// - [ ] Complete configuration import/export view with file/text handling and validation
// - [ ] Build advanced/terminal view with full command entry and logging
// - [ ] Enhance CLI interaction display (filtering, clear log, detach)
// - [ ] Integrate robust error handling, notifications, and connection state UI
// - [ ] Polish UI layout, navigation, and macOS app details
// - [ ] Add testing (unit/UI/behavioral as appropriate)
//
// Note: This checklist will be updated as implementation progresses.

## PatchView Layout and Scrolling

To ensure consistent terminology and implementation across the app, PatchView is organized into three top-level vertical areas, followed by feature sections within the control panel.

### Top-Level Areas (Vertical Order)
1. PatchHeaderArea 
   - Purpose: Global actions and status. Includes Save/Load (current and future), undo/redo, global transport or mode toggles.
   - Behavior: Fixed at the top of the PatchView. May include title and global indicators.

2. PatchSelectionArea
   - Purpose: Patch browsing and selection. Includes search, filters, banks/categories, and favorites.
   - Behavior: Updates the active patch context that drives the rest of the UI.

3. ControlPanelArea
   - Purpose: Houses all performance and configuration controls (initially accelerometer controls; expandable to modulation, effects, routing, etc.).
   - Behavior: Typically scrollable. Supports horizontal sections for wide sets of controls.

### Control Panel Sections
- AccelerometerControlsSection: Contains multiple accelerometer modules (e.g., 6 controls in a row).
- ModulationControlsSection: LFOs, envelopes, modulation routing (future).
- EffectsControlsSection: Reverb, delay, distortion, etc. (future).
- RoutingControlsSection: Signal routing and mapping (future).

Each Section may optionally contain one or more Groups (e.g., AccelerometerControlsGroup) when sub-clustering is useful.

## Scrolling Strategy

The PatchView supports scrolling to adapt to content that exceeds the available space. Use the following patterns:

1) Vertical scroll for entire PatchView
- Wrap the full vertical stack in `ScrollView(.vertical)`.
- Show indicators via `.scrollIndicators(.visible)` when appropriate.
- Recommended when the combined height of header, selection, and control panel can overflow.

2) Static header + scrolling content
- Keep `PatchHeaderArea` and `PatchSelectionArea` fixed in a parent `VStack`.
- Wrap `ControlPanelArea` in a `ScrollView(.vertical)` to allow the main content to scroll independently.
- Useful when the control area is the primary growth region.

3) Horizontal scrolling inside ControlPanelArea
- For wide collections (e.g., many accelerometer modules), use `ScrollView(.horizontal)` around a horizontal stack of modules.
- Combine with a vertical scroll at the top level, if needed.

4) Bidirectional overflow (advanced)
- Prefer vertical scrolling at the top level and horizontal scrolling within sections to avoid gesture conflicts.
- Avoid nesting scroll views with the same axis.

### Platform Considerations
- iOS/iPadOS:
  - Use `.scrollIndicators(.visible)` for discoverability.
  - Prefer material backgrounds (e.g., `.thinMaterial`, `.ultraThinMaterial`) for layered look.
- macOS:
  - System scrollbars appear automatically on scroll; `.scrollIndicators(.visible)` is still supported.
  - Consider `.pickerStyle(.menu)` or `.segmented)` instead of wheel styles.

## Accessibility and UI Testing Identifiers
Use stable identifiers derived from the same vocabulary:
- PatchHeaderArea.SaveButton
- PatchSelectionArea.SearchField
- ControlPanelArea.AccelerometerControlsSection.AccelerometerControl.<index>

These identifiers should be applied via `.accessibilityIdentifier("…")` where applicable.

## View and ViewModel Naming Conventions
- Views: PatchHeaderArea, PatchSelectionArea, ControlPanelArea, AccelerometerControlsSection
- ViewModels: PatchHeaderViewModel, PatchSelectionViewModel, ControlPanelViewModel, AccelerometerControlsViewModel

This naming scheme aligns code, documentation, and team communication.

## Example Structure (SwiftUI Sketch)
```swift
struct PatchView: View {
    var body: some View {
        VStack(spacing: 12) {
            PatchHeaderArea()
                .accessibilityIdentifier("PatchHeaderArea")

            PatchSelectionArea()
                .accessibilityIdentifier("PatchSelectionArea")

            // Either scroll the entire area here, or scroll within sections
            ScrollView(.vertical) {
                ControlPanelArea()
                    .accessibilityIdentifier("ControlPanelArea")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            .scrollIndicators(.visible)
        }
        .padding()
    }
}

struct ControlPanelArea: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                AccelerometerControlsSection()
                // Future: ModulationControlsSection(), EffectsControlsSection(), etc.
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.visible)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

