// CLIOutputParserTests.swift
// Parser tests written against verbatim device output.
//
// Raw string constants captured live from /dev/cu.usbmodem0010501849051
// at 115200 baud, including command echo and ANSI prompt.
// Last capture: 2026-04-24. Firmware v3 adds firmware_version/patch_count/current_patch to global export.

import Testing
@testable import guitaraccUI

struct CLIOutputParserTests {

    // MARK: - ANSI stripping

    @Test func stripANSIRemovesBoldGreenSequence() {
        // The real prompt ends with ESC[1;32m ... ESC[m
        let raw = "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        #expect(CLIOutputParser.stripANSI(raw) == "GuitarAcc:~$ ")
    }

    @Test func stripANSILeavesPlainTextUnchanged() {
        let plain = "Instance 0: T1 (Simple Linear)"
        #expect(CLIOutputParser.stripANSI(plain) == plain)
    }

    @Test func stripANSIHandlesEmptySequence() {
        // ESC[m (no digits) — used as reset at end of prompt
        let raw = "hello\u{1b}[mworld"
        #expect(CLIOutputParser.stripANSI(raw) == "helloworld")
    }

    // MARK: - Status

    // Verbatim capture of `status` command output (including echoed command and prompt).
    // 2026-04-24: guitar connected, MIDI active, config area B seq=72.
    private let statusRaw =
        "status\r\n" +
        "Config area: B (seq=72)\r\n" +
        "\r\n" +
        "=== GuitarAcc Basestation Status ===\r\n" +
        "Connected devices: 1\r\n" +
        "MIDI output: Active\r\n" +
        "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"

    @Test func statusParsesConfigAreaLetter() {
        #expect(CLIOutputParser.parseStatus(statusRaw).configArea == "B")
    }

    @Test func statusParsesConfigAreaSeq() {
        #expect(CLIOutputParser.parseStatus(statusRaw).configAreaSeq == 72)
    }

    @Test func statusParsesConnectedDevices() {
        #expect(CLIOutputParser.parseStatus(statusRaw).connectedDevices == 1)
    }

    @Test func statusParsesMIDIOutputActive() {
        #expect(CLIOutputParser.parseStatus(statusRaw).midiOutputActive == true)
    }

    @Test func statusParsesMIDIOutputInactive() {
        // Synthetic string — device is currently active, so test inactive path separately.
        let raw = "Connected devices: 0\r\nMIDI output: Inactive\r\n"
        #expect(CLIOutputParser.parseStatus(raw).midiOutputActive == false)
    }

    @Test func statusANSIPromptDoesNotPolluteParsedValues() {
        // ANSI escape in prompt must not be misread as a device count or area.
        let info = CLIOutputParser.parseStatus(statusRaw)
        #expect(info.connectedDevices == 1)
        #expect(info.configArea == "B")
    }

    @Test func statusNoFirmwareVersionInRealOutput() {
        // Real device status has no firmware version line — StatusInfo has no such field.
        // This test documents that omission intentionally.
        let info = CLIOutputParser.parseStatus(statusRaw)
        #expect(info.configArea != nil) // sanity: response was parsed
    }

    // MARK: - Topo Show

    // Verbatim capture of `topo show` output.
    private let topoRaw =
        "topo show\r\n" +
        "Virtual Ports Topology - Patch 0 [ALWAYS ACTIVE]\r\n" +
        "Default Mixer: 2 (0=PASSTHROUGH, 1=SUM, 2=AVERAGE, 3=MAX, 4=MIN)\r\n" +
        "\r\n" +
        "Instance 0: T1 (Simple Linear)\r\n" +
        "  Accel inputs: [0, 0]\r\n" +
        "  Function units: [0, 0]\r\n" +
        "  MIDI CC outputs: [16, 0]\r\n" +
        "Instance 1: T1 (Simple Linear)\r\n" +
        "  Accel inputs: [1, 0]\r\n" +
        "  Function units: [1, 0]\r\n" +
        "  MIDI CC outputs: [17, 0]\r\n" +
        "Instance 2: T1 (Simple Linear)\r\n" +
        "  Accel inputs: [2, 0]\r\n" +
        "  Function units: [2, 0]\r\n" +
        "  MIDI CC outputs: [18, 0]\r\n" +
        "Instance 3: T1 (Simple Linear)\r\n" +
        "  Accel inputs: [3, 0]\r\n" +
        "  Function units: [3, 0]\r\n" +
        "  MIDI CC outputs: [19, 0]\r\n" +
        "Instance 4: T1 (Simple Linear)\r\n" +
        "  Accel inputs: [4, 0]\r\n" +
        "  Function units: [4, 0]\r\n" +
        "  MIDI CC outputs: [20, 0]\r\n" +
        "Instance 5: T1 (Simple Linear)\r\n" +
        "  Accel inputs: [5, 0]\r\n" +
        "  Function units: [5, 0]\r\n" +
        "  MIDI CC outputs: [21, 0]\r\n" +
        "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"

    @Test func topoParsesInstanceCount() {
        #expect(CLIOutputParser.parseTopoShow(topoRaw).instanceCount == 6)
    }

    @Test func topoParsesOnlyT1Types() {
        #expect(CLIOutputParser.parseTopoShow(topoRaw).topoTypes == [1])
    }

    @Test func topoParsesMixerTypeFromDefaultMixerLine() {
        // "Default Mixer: 2" — the "Default " prefix must not confuse the parser.
        #expect(CLIOutputParser.parseTopoShow(topoRaw).mixerType == 2)
    }

    @Test func topoANSIPromptDoesNotInflateInstanceCount() {
        // If ANSI bytes were not stripped, stray digits could be misread as instance indices.
        #expect(CLIOutputParser.parseTopoShow(topoRaw).instanceCount == 6)
    }

    @Test func topoCCOutputLinesDoNotProduceFalseMixerReads() {
        // Lines like "MIDI CC outputs: [16, 0]" contain digits after colons but are not mixer lines.
        #expect(CLIOutputParser.parseTopoShow(topoRaw).mixerType == 2)
    }

    // MARK: - Func Show

    // Verbatim capture of `func show 0` output.
    // Note: "→" is U+2192 RIGHTWARDS ARROW, transmitted literally by device.
    private let funcRaw =
        "func show 0\r\n" +
        "Function Unit 0:\r\n" +
        "  Type: 2 (LINEAR)\r\n" +
        "  Enabled: 1\r\n" +
        "  Parameters: [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "  Linear mapping: [-2000,2000] \u{2192} [0,127]\r\n" +
        "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"

    @Test func funcParsesIndex() {
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.index == 0)
    }

    @Test func funcParsesTypeCode() {
        // Type 2 = LINEAR per device firmware.
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.typeCode == 2)
    }

    @Test func funcParsesEnabled() {
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.enabled == true)
    }

    @Test func funcParsesFullParameterArray() {
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.parameters == [-2000, 2000, 0, 127, 0, 0])
    }

    @Test func funcParsesInMin() {
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.inMin == -2000)
    }

    @Test func funcParsesInMax() {
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.inMax == 2000)
    }

    @Test func funcParsesOutMin() {
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.outMin == 0)
    }

    @Test func funcParsesOutMax() {
        #expect(CLIOutputParser.parseFuncShow(funcRaw)?.outMax == 127)
    }

    @Test func funcReturnsNilForErrorResponse() {
        let errorRaw = "error: invalid index\r\n\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        #expect(CLIOutputParser.parseFuncShow(errorRaw) == nil)
    }

    @Test func funcReturnsNilForEmptyPromptOnly() {
        let promptOnly = "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        #expect(CLIOutputParser.parseFuncShow(promptOnly) == nil)
    }

    // MARK: - JSON Extraction

    // Verbatim capture of `config export patch 0` — 2026-04-24.
    // Firmware now emits pretty-printed JSON (multi-line per topology/function entry).
    // accel_scale / accel_offset belong in GlobalConfig, not per-patch.
    private let patchExportRaw =
        "config export patch 0\r\n" +
        "{\r\n" +
        "  \"version\": 1,\r\n" +
        "  \"config\": {\r\n" +
        "    \"patches\": [\r\n" +
        "      {\r\n" +
        "        \"patch_num\": 0,\r\n" +
        "        \"patch_name\": \"Patch 0\",\r\n" +
        "        \"led_mode\": 0,\r\n" +
        "        \"midi_deadzone\": 1,\r\n" +
        "        \"default_mixer_type\": 2,\r\n" +
        "        \"topologies\": [\r\n" +
        "          {\r\n" +
        "            \"instance\": 0,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"topology_type\": 1,\r\n" +
        "            \"accel_inputs\": [0, 0],\r\n" +
        "            \"func_units\": [0, 0],\r\n" +
        "            \"midi_outputs\": [16, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"instance\": 1,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"topology_type\": 1,\r\n" +
        "            \"accel_inputs\": [1, 0],\r\n" +
        "            \"func_units\": [1, 0],\r\n" +
        "            \"midi_outputs\": [17, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"instance\": 2,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"topology_type\": 1,\r\n" +
        "            \"accel_inputs\": [2, 0],\r\n" +
        "            \"func_units\": [2, 0],\r\n" +
        "            \"midi_outputs\": [18, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"instance\": 3,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"topology_type\": 1,\r\n" +
        "            \"accel_inputs\": [3, 0],\r\n" +
        "            \"func_units\": [3, 0],\r\n" +
        "            \"midi_outputs\": [19, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"instance\": 4,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"topology_type\": 1,\r\n" +
        "            \"accel_inputs\": [4, 0],\r\n" +
        "            \"func_units\": [4, 0],\r\n" +
        "            \"midi_outputs\": [20, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"instance\": 5,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"topology_type\": 1,\r\n" +
        "            \"accel_inputs\": [5, 0],\r\n" +
        "            \"func_units\": [5, 0],\r\n" +
        "            \"midi_outputs\": [21, 0]\r\n" +
        "          }\r\n" +
        "        ],\r\n" +
        "        \"functions\": [\r\n" +
        "          {\r\n" +
        "            \"unit\": 0,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"unit\": 1,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"unit\": 2,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"unit\": 3,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"unit\": 4,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"unit\": 5,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"unit\": 6,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          },\r\n" +
        "          {\r\n" +
        "            \"unit\": 7,\r\n" +
        "            \"enabled\": true,\r\n" +
        "            \"function_type\": 2,\r\n" +
        "            \"param_count\": 4,\r\n" +
        "            \"params\": [-2000, 2000, 0, 127, 0, 0]\r\n" +
        "          }\r\n" +
        "        ]\r\n" +
        "      }\r\n" +
        "    ]\r\n" +
        "  }\r\n" +
        "}\r\n" +
        "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"

    @Test func extractJSONFindsOutermostObject() {
        let json = CLIOutputParser.extractJSON(from: patchExportRaw)
        #expect(json != nil)
        #expect(json?.hasPrefix("{") == true)
        #expect(json?.hasSuffix("}") == true)
    }

    @Test func extractJSONHandlesNestedBraces() {
        // Brace balancing must not stop at an inner closing brace.
        let raw = "{\"a\": {\"b\": 1}}"
        #expect(CLIOutputParser.extractJSON(from: raw) == raw)
    }

    @Test func extractJSONStripsCommandEchoAndPrompt() {
        // The extracted JSON must not include the echoed command or the ANSI prompt.
        let json = CLIOutputParser.extractJSON(from: patchExportRaw)!
        #expect(!json.contains("config export"))
        #expect(!json.contains("GuitarAcc"))
    }

    @Test func extractJSONReturnsNilForPromptOnly() {
        let promptOnly = "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        #expect(CLIOutputParser.extractJSON(from: promptOnly) == nil)
    }

    // MARK: - Patch Export Parsing

    @Test func parsePatchExportPatchNum() {
        #expect(CLIOutputParser.parsePatchExport(from: patchExportRaw)?.patchNum == 0)
    }

    @Test func parsePatchExportPatchName() {
        #expect(CLIOutputParser.parsePatchExport(from: patchExportRaw)?.patchName == "Patch 0")
    }

    @Test func parsePatchExportLedMode() {
        #expect(CLIOutputParser.parsePatchExport(from: patchExportRaw)?.ledMode == 0)
    }

    @Test func parsePatchExportMidiDeadzone() {
        #expect(CLIOutputParser.parsePatchExport(from: patchExportRaw)?.midiDeadzone == 1)
    }

    // New v2 fields
    @Test func parsePatchExportDefaultMixerType() {
        #expect(CLIOutputParser.parsePatchExport(from: patchExportRaw)?.defaultMixerType == 2)
    }

    @Test func parsePatchExportTopologyCount() {
        #expect(CLIOutputParser.parsePatchExport(from: patchExportRaw)?.topologies?.count == 6)
    }

    @Test func parsePatchExportFunctionCount() {
        #expect(CLIOutputParser.parsePatchExport(from: patchExportRaw)?.functions?.count == 8)
    }

    @Test func parsePatchExportFirstTopologyInstance() {
        let topo = CLIOutputParser.parsePatchExport(from: patchExportRaw)?.topologies?.first
        #expect(topo?.instance == 0)
        #expect(topo?.topologyType == 1)
        #expect(topo?.accelInputs == [0, 0])
        #expect(topo?.funcUnits == [0, 0])
        #expect(topo?.midiOutputs == [16, 0])
        #expect(topo?.enabled == true)
    }

    @Test func parsePatchExportLastTopologyInstance() {
        let topo = CLIOutputParser.parsePatchExport(from: patchExportRaw)?.topologies?.last
        #expect(topo?.instance == 5)
        #expect(topo?.accelInputs == [5, 0])
        #expect(topo?.midiOutputs == [21, 0])
    }

    @Test func parsePatchExportFirstFunctionUnit() {
        let func0 = CLIOutputParser.parsePatchExport(from: patchExportRaw)?.functions?.first
        #expect(func0?.unit == 0)
        #expect(func0?.functionType == 2)
        #expect(func0?.paramCount == 4)
        #expect(func0?.params == [-2000, 2000, 0, 127, 0, 0])
        #expect(func0?.inMin == -2000)
        #expect(func0?.inMax == 2000)
        #expect(func0?.outMin == 0)
        #expect(func0?.outMax == 127)
    }

    @Test func parsePatchExportLastFunctionUnit() {
        let func7 = CLIOutputParser.parsePatchExport(from: patchExportRaw)?.functions?.last
        #expect(func7?.unit == 7)
    }

    // accel_scale / accel_offset belong in GlobalConfig, not per-patch.
    // Confirm they are absent from the patch export envelope.
    @Test func parsePatchExportDoesNotContainAccelScale() {
        // accel calibration is a device-wide hardware constant stored in global config.
        let json = CLIOutputParser.extractJSON(from: patchExportRaw) ?? ""
        #expect(!json.contains("accel_scale"))
    }

    @Test func parsePatchExportDoesNotContainAccelOffset() {
        let json = CLIOutputParser.extractJSON(from: patchExportRaw) ?? ""
        #expect(!json.contains("accel_offset"))
    }

    // Backward compatibility: older firmware JSON (no v2 fields) should still decode.
    @Test func parsePatchExportOldFirmwareDecodesGracefully() {
        let legacyRaw =
            "config export patch 1\r\n" +
            "{\"version\": 1,\"config\": {\"patches\": [{\"patch_num\": 1,\"patch_name\": \"Patch 1\",\"led_mode\": 0,\"midi_deadzone\": 1}]}}\r\n" +
            "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        let config = CLIOutputParser.parsePatchExport(from: legacyRaw)
        #expect(config?.patchNum == 1)
        #expect(config?.patchName == "Patch 1")
        #expect(config?.defaultMixerType == nil)  // absent in old firmware
        #expect(config?.topologies == nil)
        #expect(config?.functions == nil)
    }

    // MARK: - Global Export Parsing

    // Verbatim capture of `config export global` — 2026-04-24, pre-v3 firmware.
    // Used as the backward-compat baseline: no firmware_version/patch_count/current_patch fields.
    // accel values are all zeros (factory default / not yet calibrated).
    private let globalExportRaw =
        "config export global\r\n" +
        "{\r\n" +
        "  \"version\": 1,\r\n" +
        "  \"config\": {\r\n" +
        "    \"global\": {\r\n" +
        "      \"default_patch\": 0,\r\n" +
        "      \"midi_channel\": 0,\r\n" +
        "      \"max_guitars\": 4,\r\n" +
        "      \"ble_scan_interval_ms\": 100,\r\n" +
        "      \"led_brightness\": 128,\r\n" +
        "      \"running_average_enable\": true,\r\n" +
        "      \"running_average_depth\": 5,\r\n" +
        "      \"accel_scale\": [0, 0, 0, 0, 0, 0],\r\n" +
        "      \"accel_offset\": [0, 0, 0, 0, 0, 0]\r\n" +
        "    }\r\n" +
        "  }\r\n" +
        "}\r\n" +
        "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"

    @Test func parseGlobalExportReturnsNonNil() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw) != nil)
    }

    @Test func parseGlobalExportDefaultPatch() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.defaultPatch == 0)
    }

    @Test func parseGlobalExportMidiChannel() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.midiChannel == 0)
    }

    @Test func parseGlobalExportMaxGuitars() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.maxGuitars == 4)
    }

    @Test func parseGlobalExportLedBrightness() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.ledBrightness == 128)
    }

    @Test func parseGlobalExportRunningAverageEnabled() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.runningAverageEnable == true)
    }

    @Test func parseGlobalExportRunningAverageDepth() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.runningAverageDepth == 5)
    }

    @Test func parseGlobalExportAccelScaleCount() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.accelScale.count == 6)
    }

    @Test func parseGlobalExportAccelOffsetCount() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.accelOffset.count == 6)
    }

    @Test func parseGlobalExportAccelScaleAllZeroCurrentDevice() {
        // Device is at factory default / not yet calibrated — all scale values are 0.
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.accelScale == [0, 0, 0, 0, 0, 0])
    }

    @Test func parseGlobalExportAccelOffsetAllZeroCurrentDevice() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportRaw)?.global.accelOffset == [0, 0, 0, 0, 0, 0])
    }

    @Test func parseGlobalExportAccelValuesDecodeWithMixedValues() {
        // Synthetic: verify non-zero values decode correctly for calibrated devices.
        let raw =
            "config export global\r\n" +
            "{\"version\":1,\"config\":{\"global\":{" +
            "\"default_patch\":0,\"midi_channel\":1,\"max_guitars\":4," +
            "\"ble_scan_interval_ms\":100,\"led_brightness\":128," +
            "\"running_average_enable\":true,\"running_average_depth\":5," +
            "\"accel_scale\":[2000,2000,2000,2000,2000,2000]," +
            "\"accel_offset\":[0,0,200,-50,0,0]}}}\r\n" +
            "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        let export = CLIOutputParser.parseGlobalExport(from: raw)
        #expect(export?.global.accelScale == [2000, 2000, 2000, 2000, 2000, 2000])
        #expect(export?.global.accelOffset == [0, 0, 200, -50, 0, 0])
    }

    @Test func parseGlobalExportReturnsNilForErrorResponse() {
        let errorRaw = "error: unknown command\r\n\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        #expect(CLIOutputParser.parseGlobalExport(from: errorRaw) == nil)
    }

    // Pre-v3 firmware omits firmware_version/patch_count/current_patch — all should be nil.
    @Test func parseGlobalExportOldFirmwareMissingV3FieldsAreNil() {
        let export = CLIOutputParser.parseGlobalExport(from: globalExportRaw)
        #expect(export?.firmwareVersion == nil)
        #expect(export?.patchCount == nil)
        #expect(export?.currentPatch == nil)
    }

    // Synthetic v3 firmware response — new fields are at the envelope top level, not inside config.global.
    // Format: { "version": 1, "firmware_version": "...", "patch_count": N, "current_patch": N, "config": { "global": {...} } }
    private let globalExportV3Raw =
        "config export global\r\n" +
        "{\"version\":1," +
        "\"firmware_version\":\"1.3.0\"," +
        "\"patch_count\":16," +
        "\"current_patch\":2," +
        "\"config\":{\"global\":{" +
        "\"default_patch\":0,\"midi_channel\":1,\"max_guitars\":4," +
        "\"ble_scan_interval_ms\":100,\"led_brightness\":128," +
        "\"running_average_enable\":true,\"running_average_depth\":5," +
        "\"accel_scale\":[2000,2000,2000,2000,2000,2000]," +
        "\"accel_offset\":[0,0,0,0,0,0]}}}\r\n" +
        "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"

    @Test func parseGlobalExportV3FirmwareVersion() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportV3Raw)?.firmwareVersion == "1.3.0")
    }

    @Test func parseGlobalExportV3PatchCount() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportV3Raw)?.patchCount == 16)
    }

    @Test func parseGlobalExportV3CurrentPatch() {
        #expect(CLIOutputParser.parseGlobalExport(from: globalExportV3Raw)?.currentPatch == 2)
    }

    @Test func parseGlobalExportV3ExistingFieldsStillDecode() {
        // Confirm pre-existing fields are unaffected by the new ones.
        let export = CLIOutputParser.parseGlobalExport(from: globalExportV3Raw)
        #expect(export?.global.midiChannel == 1)
        #expect(export?.global.accelScale == [2000, 2000, 2000, 2000, 2000, 2000])
    }

    // MARK: - VirtualPortConfig derivation

    @Test func virtualPortConfigsCount() {
        let patch = CLIOutputParser.parsePatchExport(from: patchExportRaw)!
        #expect(CLIOutputParser.virtualPortConfigs(from: patch).count == 6)
    }

    @Test func virtualPortConfigsFirstTopologyType() {
        let patch = CLIOutputParser.parsePatchExport(from: patchExportRaw)!
        #expect(CLIOutputParser.virtualPortConfigs(from: patch)[0].topologyType == .t1)
    }

    @Test func virtualPortConfigsFirstInputAxis() {
        let patch = CLIOutputParser.parsePatchExport(from: patchExportRaw)!
        #expect(CLIOutputParser.virtualPortConfigs(from: patch)[0].inputAxis1 == .x)
    }

    @Test func virtualPortConfigsLastInputAxisIsYaw() {
        let patch = CLIOutputParser.parsePatchExport(from: patchExportRaw)!
        #expect(CLIOutputParser.virtualPortConfigs(from: patch)[5].inputAxis1 == .yaw)
    }

    @Test func virtualPortConfigsMIDICCSequential() {
        let patch = CLIOutputParser.parsePatchExport(from: patchExportRaw)!
        let ccs = CLIOutputParser.virtualPortConfigs(from: patch).map { $0.midiCC1 }
        #expect(ccs == [16, 17, 18, 19, 20, 21])
    }

    @Test func virtualPortConfigsLinearParamsFromFunctionExport() {
        let patch = CLIOutputParser.parsePatchExport(from: patchExportRaw)!
        let vp0 = CLIOutputParser.virtualPortConfigs(from: patch)[0]
        #expect(vp0.linearParams1.inputMin == -2000)
        #expect(vp0.linearParams1.inputMax == 2000)
        #expect(vp0.linearParams1.outputMin == 0)
        #expect(vp0.linearParams1.outputMax == 127)
    }

    @Test func virtualPortConfigsEnabledState() {
        let patch = CLIOutputParser.parsePatchExport(from: patchExportRaw)!
        #expect(CLIOutputParser.virtualPortConfigs(from: patch).allSatisfy { $0.enabled })
    }

    @Test func virtualPortConfigsEmptyForLegacyPatch() {
        // Old firmware patch with no topologies field → no VirtualPortConfigs.
        let legacyPatch = PatchConfig(patchNum: 0, patchName: "Patch 0",
                                      ledMode: 0, midiDeadzone: 1)
        #expect(CLIOutputParser.virtualPortConfigs(from: legacyPatch).isEmpty)
    }

    @Test func parsePatchExportReturnsNilForErrorResponse() {
        let errorRaw = "error: invalid patch\r\n\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        #expect(CLIOutputParser.parsePatchExport(from: errorRaw) == nil)
    }

    // MARK: - Topology Instance Parsing

    @Test func parseTopoInstancesCount() {
        #expect(CLIOutputParser.parseTopoInstances(topoRaw).count == 6)
    }

    @Test func parseTopoInstancesAllT1() {
        #expect(CLIOutputParser.parseTopoInstances(topoRaw).allSatisfy { $0.topologyType == .t1 })
    }

    @Test func parseTopoInstancesFirstInputAxis() {
        // Instance 0 Accel inputs: [0, 0] → inputAxis1 = .x
        #expect(CLIOutputParser.parseTopoInstances(topoRaw)[0].inputAxis1 == .x)
    }

    @Test func parseTopoInstancesFirstFunctionUnit() {
        #expect(CLIOutputParser.parseTopoInstances(topoRaw)[0].functionIndex1 == 0)
    }

    @Test func parseTopoInstancesFirstMIDICC() {
        #expect(CLIOutputParser.parseTopoInstances(topoRaw)[0].midiCC1 == 16)
    }

    @Test func parseTopoInstancesLastInputAxisIsYaw() {
        // Instance 5 Accel inputs: [5, 0] → inputAxis1 = .yaw
        #expect(CLIOutputParser.parseTopoInstances(topoRaw)[5].inputAxis1 == .yaw)
    }

    @Test func parseTopoInstancesLastFunctionUnit() {
        #expect(CLIOutputParser.parseTopoInstances(topoRaw)[5].functionIndex1 == 5)
    }

    @Test func parseTopoInstancesLastMIDICC() {
        #expect(CLIOutputParser.parseTopoInstances(topoRaw)[5].midiCC1 == 21)
    }

    @Test func parseTopoInstancesMIDICCSequential() {
        // Instances 0-5 should map to CC 16-21.
        let ccs = CLIOutputParser.parseTopoInstances(topoRaw).map { $0.midiCC1 }
        #expect(ccs == [16, 17, 18, 19, 20, 21])
    }

    @Test func parseTopoInstancesInputAxesSequential() {
        // Instance i should use axis i (X=0, Y=1, Z=2, Roll=3, Pitch=4, Yaw=5).
        let axes = CLIOutputParser.parseTopoInstances(topoRaw).map { $0.inputAxis1.rawValue }
        #expect(axes == [0, 1, 2, 3, 4, 5])
    }

    @Test func parseTopoInstancesEmptyForPromptOnly() {
        let promptOnly = "\u{1b}[1;32mGuitarAcc:~$ \u{1b}[m"
        #expect(CLIOutputParser.parseTopoInstances(promptOnly).isEmpty)
    }
}
