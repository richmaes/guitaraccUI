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
// - UI_INTERFACE.md — Basestation CLI command set
// - ARCHITECTURE.md — Overall system architecture
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

