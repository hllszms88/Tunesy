import GestureCore
import SwiftUI

/// Instrument settings: key, sound, and the optional gesture locks.
struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    Picker("Key", selection: $model.settings.key) {
                        ForEach(MusicalKey.allCases) { key in
                            Text(key.name).tag(key)
                        }
                    }
                }

                Section {
                    Picker("Sound", selection: $model.settings.voiceID) {
                        ForEach(SynthVoice.all) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $model.settings.volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text(model.settings.voice.blurb)
                }

                Section {
                    Picker("Major / minor", selection: $model.settings.modeControl) {
                        Text("Lean the hand").tag(ModeControl.tilt)
                        Text("Always major").tag(ModeControl.major)
                        Text("Always minor").tag(ModeControl.minor)
                    }
                } header: {
                    Text("Left hand")
                } footer: {
                    Text("Raised fingers choose the chord. By default, leaning the hand to the right makes it minor.")
                }

                Section {
                    Picker("Chord shape", selection: $model.settings.fixedQuality) {
                        Text("Fingers choose").tag(0)
                        Text("Triad").tag(1)
                        Text("1st inversion").tag(2)
                        Text("7th").tag(3)
                        Text("Dominant / diminished 7th").tag(4)
                    }
                    Toggle("Lock the octave", isOn: $model.settings.lockOctave)
                    if model.settings.lockOctave {
                        Stepper("Octave: \(octaveLabel(model.settings.fixedOctave))",
                                value: $model.settings.fixedOctave, in: -2...2)
                    }
                } header: {
                    Text("Right hand")
                } footer: {
                    Text("Height is always volume and leaning is always tone. Unless locked, 1–4 fingers pick the chord shape and the thumb drops an octave. Lessons ignore these locks.")
                }

                Section {
                    Toggle("Show hand tracking", isOn: $model.settings.showSkeleton)
                    Button {
                        model.settings.cameraRotation = (model.settings.cameraRotation + 90) % 360
                    } label: {
                        LabeledContent("Rotate camera picture") {
                            Text(model.settings.cameraRotation == 0 ? "Auto" : "+\(model.settings.cameraRotation)°")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Soft camera")
                        HStack {
                            Image(systemName: "camera")
                                .foregroundStyle(.secondary)
                            Slider(value: $model.settings.softCamera, in: 0...1)
                            Image(systemName: "cloud.fog")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("If the camera picture is sideways, tap Rotate until it is upright. Soft camera gives the picture a misty, gentler look. Neither affects how well your hands are tracked.")
                }

                Section {
                    LabeledContent("Tracking", value: "\(Int(model.live.frame.framesPerSecond.rounded())) fps")
                    LabeledContent("Audio buffer",
                                   value: String(format: "%.1f ms", model.audio.bufferDuration * 1000))
                    LabeledContent("Sample rate", value: "\(Int(model.audio.sampleRate)) Hz")
                    LabeledContent("Camera rotation", value: model.camera.rotationDescription)
                    LabeledContent("Camera frame", value: "\(Int(model.live.frame.imageSize.width))×\(Int(model.live.frame.imageSize.height))")
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Bluetooth headphones add a noticeable delay. Use the speaker or wired headphones.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func octaveLabel(_ octave: Int) -> String {
        if octave == 0 { return "normal" }
        return octave > 0 ? "+\(octave)" : "\(octave)"
    }
}

/// A one-screen explanation of how to play.
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Stand about an arm's length from the camera in good light, and show both palms.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.secondary)

                    helpCard(
                        title: "Left hand picks the chord",
                        color: Theme.cocoa,
                        fingers: FingerState(index: true, middle: true),
                        thumbOnRight: true,
                        lines: [
                            "1–5 raised fingers play chords I–V of the key.",
                            "Index + pinky plays VI. Add the thumb for VII.",
                            "Lean the hand to the right for a minor chord."
                        ])

                    helpCard(
                        title: "Right hand shapes the sound",
                        color: Theme.rose,
                        fingers: FingerState(thumb: true, index: true),
                        thumbOnRight: false,
                        lines: [
                            "Raise it higher to play louder. No fingers = silence.",
                            "1 finger: triad. 2: first inversion. 3 and 4: seventh chords.",
                            "Thumb out drops the chord one octave.",
                            "Lean the hand to sweep the tone darker or brighter."
                        ])

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theremin mode")
                            .font(Theme.label(17, weight: .bold))
                        Text("Right hand height sets the pitch, left hand height sets the volume. Both hands must be visible.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(20)
            }
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func helpCard(title: String, color: Color, fingers: FingerState,
                          thumbOnRight: Bool, lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            HandShapeView(fingers: fingers, color: color, thumbOnRight: thumbOnRight)
                .frame(width: 78, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.label(17, weight: .bold))
                    .foregroundStyle(color)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
