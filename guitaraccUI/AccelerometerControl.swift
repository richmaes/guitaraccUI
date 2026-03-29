import SwiftUI
import CoreMIDI

/// A reusable accelerometer control view composed of a MIDI channel picker and two knobs (Max and Min).
struct AccelerometerControlView: View {
    /// The selected MIDI channel (1-16).
    @Binding var midiChannel: Int
    /// The maximum value knob (0-127).
    @Binding var maxValue: Int
    /// The minimum value knob (0-127).
    @Binding var minValue: Int

    var body: some View {
        VStack(spacing: 20) {
            Picker("MIDI Channel", selection: $midiChannel) {
                ForEach(1...16, id: \.self) { channel in
                    Text("\(channel)").tag(channel)
                }
            }
#if os(iOS)
            .pickerStyle(.wheel)
#else
            .pickerStyle(.segmented)
#endif
            .frame(height: 100)
            .clipped()

            Knob(value: $maxValue, label: "Max")
            Knob(value: $minValue, label: "Min")
        }
        .frame(width: 120)
    }
}

/// A knob control that allows the user to drag to set a value between 0 and 127.
struct Knob: View {
    /// The current value of the knob (0-127).
    @Binding var value: Int
    /// The label displayed below the knob.
    var label: String

    @State private var dragAngle: Angle = .zero

    private let knobSize: CGFloat = 80
    private let minValue: Double = 0
    private let maxValue: Double = 127

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 4)
                    .foregroundColor(.gray.opacity(0.5))
                    .frame(width: knobSize, height: knobSize)

                Circle()
                    .trim(from: 0, to: CGFloat(Double(value) / maxValue))
                    .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .foregroundColor(.blue)
                    .rotationEffect(Angle(degrees: -90))
                    .frame(width: knobSize, height: knobSize)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize * 0.6, height: knobSize * 0.6)
                    .shadow(radius: 2)

                // Indicator line
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 2, height: knobSize * 0.3)
                    .offset(y: -knobSize * 0.15)
                    .rotationEffect(Angle(degrees: Double(value) / maxValue * 270 - 135))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let vector = CGVector(dx: drag.location.x - knobSize / 2, dy: drag.location.y - knobSize / 2)
                        let angle = atan2(vector.dy, vector.dx) * 180 / .pi + 135
                        let fixedAngle = angle < 0 ? angle + 360 : angle
                        let cappedAngle = min(max(fixedAngle, 0), 270)
                        let newValue = cappedAngle / 270 * maxValue
                        value = Int(newValue)
                    }
            )
            .frame(width: knobSize, height: knobSize)

            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

/// Example view using six accelerometer controls horizontally.
struct PatchConfigDemo: View {
    @State private var midiChannels: [Int] = Array(repeating: 1, count: 6)
    @State private var maxValues: [Int] = Array(repeating: 64, count: 6)
    @State private var minValues: [Int] = Array(repeating: 0, count: 6)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 30) {
                ForEach(0..<6, id: \.self) { index in
                    AccelerometerControlView(
                        midiChannel: $midiChannels[index],
                        maxValue: $maxValues[index],
                        minValue: $minValues[index]
                    )
                }
            }
            .padding()
        }
        .frame(height: 200)
    }
}

struct AccelerometerControl_Previews: PreviewProvider {
    static var previews: some View {
        PatchConfigDemo()
            .previewLayout(.sizeThatFits)
    }
}
