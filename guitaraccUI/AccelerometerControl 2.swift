// AccelerometerControl.swift
// Reusable SwiftUI control for accelerometer settings (MIDI channel + Max/Min knobs)

import SwiftUI

/// A simple knob control mapping a 0...127 value to an angle sweep and supporting drag interaction.
struct MIDIKnob: View {
    @Binding var value: Int // 0...127
    var label: String
    var size: CGFloat = 80

    private let minAngle: Double = -135
    private let maxAngle: Double = 135

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .overlay(Circle().stroke(.secondary.opacity(0.6), lineWidth: 1))
                // Indicator
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: size * 0.35)
                    .offset(y: -size * 0.18)
                    .rotationEffect(.degrees(angleForValue(Double(value))))
            }
            .frame(width: size, height: size)
            .gesture(dragGesture())
            .accessibilityLabel(Text("\(label) knob"))
            .accessibilityValue(Text("\(value)"))

            Text("\(label): \(value)")
                .font(.caption)
        }
    }

    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                // Convert the drag location into an angle relative to the center
                // Use a GeometryReader-less approach by normalizing in the knob's square bounds
                // We approximate the center at (size/2, size/2) within the view's local space
                let location = gesture.location
                let center = CGPoint(x: size / 2, y: size / 2)
                let dx = location.x - center.x
                let dy = location.y - center.y
                let radians = atan2(dy, dx) // -pi ... pi, 0 at +X axis
                var degrees = radians * 180 / .pi - 90 // rotate so 0 is at top
                if degrees < -180 { degrees += 360 }
                if degrees > 180 { degrees -= 360 }
                // Clamp to the sweep
                let clamped = min(max(degrees, minAngle), maxAngle)
                let t = (clamped - minAngle) / (maxAngle - minAngle) // 0...1
                let newVal = Int(round(t * 127))
                value = min(max(newVal, 0), 127)
            }
    }

    private func angleForValue(_ v: Double) -> Double {
        let t = v / 127.0
        return minAngle + (maxAngle - minAngle) * t
    }
}

/// AccelerometerControl: MIDI channel picker + Max and Min MIDI value knobs arranged vertically.
struct AccelerometerControl: View {
    @Binding var midiChannel: Int // 1...16
    @Binding var minValue: Int // 0...127
    @Binding var maxValue: Int // 0...127

    var title: String = "Accel"

    var body: some View {
        VStack(spacing: 8) {
            // Title + MIDI Channel
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Picker("MIDI Channel", selection: $midiChannel) {
                    ForEach(1...16, id: \.self) { ch in
                        Text("Ch \(ch)").tag(ch)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 120)
            }

            // Max knob above Min knob
            MIDIKnob(value: $maxValue, label: "Max", size: 80)
            MIDIKnob(value: $minValue, label: "Min", size: 80)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
        .frame(width: 140)
    }
}

#Preview {
    VStack {
        HStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { i in
                AccelerometerControl(
                    midiChannel: .constant(1 + i % 3),
                    minValue: .constant(0),
                    maxValue: .constant(127),
                    title: "Accel \(i+1)"
                )
            }
        }
        .padding()
    }
}
