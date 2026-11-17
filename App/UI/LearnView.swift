import GestureCore
import SwiftUI

/// Learn Songs: pick a song, then play it chord by chord with real hand tracking.
struct LearnView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let song = model.activeSong {
            LessonView(song: song, live: model.live)
        } else {
            SongListView(progress: model.progress)
        }
    }
}

// MARK: - Song list

struct SongListView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var progress: ProgressStore

    var body: some View {
        ZStack {
            Theme.cream.opacity(0.88).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Learn Songs")
                            .font(Theme.display(36))
                            .foregroundStyle(Theme.cocoa)
                        Text("Follow the hand shapes. Hold each chord until it clicks.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Theme.cocoaSoft)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    ForEach(model.songs) { song in
                        Button {
                            model.startLesson(song)
                        } label: {
                            SongCard(song: song, best: progress.value(for: song.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 110)
            }
        }
    }
}

struct SongCard: View {
    let song: Song
    let best: Double

    private var levelText: String {
        switch song.level {
        case 1: return "Beginner"
        case 2: return "Easy"
        default: return "Intermediate"
        }
    }

    private var levelColor: Color {
        switch song.level {
        case 1: return Theme.sage
        case 2: return Theme.latte
        default: return Theme.rose
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.sand, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, best))))
                    .stroke(levelColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: best >= 0.999 ? "checkmark" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(levelColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(Theme.display(19))
                    .foregroundStyle(Theme.cocoa)
                    .multilineTextAlignment(.leading)
                Text(song.credit)
                    .font(Theme.label(12, weight: .medium))
                    .foregroundStyle(Theme.cocoaSoft)
                Text(song.blurb)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.cocoa.opacity(0.8))
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Pill(text: levelText, color: levelColor)
                    Pill(text: "Key of \(song.key.name)")
                    Pill(text: "\(song.chordCount) chords")
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Lesson

struct LessonView: View {
    @EnvironmentObject private var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState

    var body: some View {
        let snapshot = live.frame.lesson
        VStack(spacing: 10) {
            header(snapshot)
            Spacer(minLength: 0)
            if let snapshot = snapshot {
                if snapshot.phase == .complete {
                    completion(snapshot)
                } else if let target = snapshot.target {
                    guide(snapshot, target: target)
                }
            } else {
                Text("Get ready…")
                    .font(Theme.label(16))
                    .padding(18)
                    .glassCard()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .sensoryFeedback(.success, trigger: snapshot?.pulse ?? 0)
    }

    // MARK: Header

    private func header(_ snapshot: LessonSnapshot?) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                IconButton(systemName: "xmark") { model.endLesson() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(Theme.display(18))
                        .foregroundStyle(Theme.cocoa)
                        .lineLimit(1)
                    Text(positionText(snapshot))
                        .font(Theme.label(12, weight: .medium))
                        .foregroundStyle(Theme.cocoaSoft)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassCard(cornerRadius: 18)
                Spacer(minLength: 0)
                IconButton(systemName: "arrow.triangle.2.circlepath.camera") { model.switchCamera() }
            }
            ProgressView(value: Double(snapshot?.fractionDone ?? 0))
                .tint(Theme.rose)
        }
    }

    private func positionText(_ snapshot: LessonSnapshot?) -> String {
        guard let snapshot = snapshot, snapshot.phase == .playing else {
            return "Key of \(song.key.name)"
        }
        return "Part \(snapshot.sectionIndex + 1)/\(snapshot.sectionCount) · \(snapshot.sectionName) · "
            + "chord \(snapshot.eventIndex + 1)/\(snapshot.eventCount)"
    }

    // MARK: Guide

    private func guide(_ snapshot: LessonSnapshot, target: ChordEvent) -> some View {
        let spec = target.spec
        let color = Theme.rose
        let leftFingers = GestureReader.fingers(forDegree: target.degree)
        let rightFingers = GestureReader.fingers(forQuality: target.quality, thumbOut: target.low)
        let flags = snapshot.flags

        return VStack(spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Theme.sand, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(snapshot.holdProgress))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.5), radius: 6)
                    Text(spec.name(key: song.key))
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.cocoa)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                }
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(spec.roman) · \(spec.qualityName)")
                        .font(Theme.label(15, weight: .semibold))
                        .foregroundStyle(Theme.cocoa)
                    if let lyric = target.lyric {
                        Text("“\(lyric)”")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.cocoa.opacity(0.85))
                    }
                    if let next = snapshot.nextTarget {
                        Text("Next: \(next.spec.name(key: song.key))")
                            .font(Theme.label(12, weight: .medium))
                            .foregroundStyle(Theme.cocoaSoft)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                handCard(title: "Left hand",
                         caption: leftFingers.chordHandDescription + (target.minor ? " · lean right" : " · upright"),
                         fingers: leftFingers, tilt: target.minor ? 18 : 0, color: Theme.cocoa, thumbOnRight: true,
                         ok: flags.map { $0.degree && $0.mode })
                handCard(title: "Right hand",
                         caption: rightCaption(target),
                         fingers: rightFingers, tilt: 0, color: Theme.rose, thumbOnRight: false,
                         ok: flags.map { $0.quality && $0.octave })
            }

            HStack(spacing: 6) {
                chip("Chord", ok: flags?.degree)
                chip(target.minor ? "Minor" : "Major", ok: flags?.mode)
                chip("Shape", ok: flags?.quality)
                chip(target.low ? "Low" : "Octave", ok: flags?.octave)
            }

            Text(hint(flags))
                .font(Theme.label(13, weight: .medium))
                .foregroundStyle(Theme.cocoaSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button("Skip chord") { model.pipeline.skipChord() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Repeat part") { model.pipeline.repeatSection() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Restart") { model.pipeline.restartLesson() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 26)
    }

    private func rightCaption(_ target: ChordEvent) -> String {
        let fingers = target.quality == 1 ? "1 finger" : "\(target.quality) fingers"
        return fingers + (target.low ? " · thumb out" : " · thumb in")
    }

    private func hint(_ flags: MatchFlags?) -> String {
        guard let flags = flags else { return "Show both hands to the camera." }
        if flags.all { return "That's it — hold it…" }
        if !flags.degree { return "Left hand: change the number of raised fingers." }
        if !flags.mode { return "Left hand: lean it right for minor, upright for major." }
        if !flags.quality { return "Right hand: change the number of raised fingers." }
        return "Right hand: thumb out for the low octave, tucked in otherwise."
    }

    private func handCard(title: String, caption: String, fingers: FingerState, tilt: Double,
                          color: Color, thumbOnRight: Bool, ok: Bool?) -> some View {
        VStack(spacing: 4) {
            HandShapeView(fingers: fingers, tiltDegrees: tilt, color: color, thumbOnRight: thumbOnRight)
                .frame(height: 92)
            Text(title)
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(Theme.cocoa)
            Text(caption)
                .font(Theme.label(11, weight: .medium))
                .foregroundStyle(Theme.cocoaSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ok == true ? Theme.sage : Theme.sand, lineWidth: ok == true ? 2 : 1)
        }
    }

    private func chip(_ text: String, ok: Bool?) -> some View {
        let color: Color = ok == nil ? Theme.cocoaSoft : (ok == true ? Theme.sage : Theme.rose)
        return HStack(spacing: 4) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : (ok == nil ? "circle" : "xmark.circle.fill"))
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(Theme.label(11, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: Completion

    private func completion(_ snapshot: LessonSnapshot) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.rose)
            Text("Lesson complete")
                .font(Theme.display(28))
                .foregroundStyle(Theme.cocoa)
            Text("\(snapshot.matched) of \(snapshot.total) chords played"
                 + (snapshot.skipped > 0 ? " · \(snapshot.skipped) skipped" : ""))
                .font(Theme.label(15, weight: .medium))
                .foregroundStyle(Theme.cocoaSoft)
            Button("Play it again") { model.pipeline.restartLesson() }
                .buttonStyle(PrimaryButtonStyle())
            HStack(spacing: 8) {
                Button("Repeat last part") { model.pipeline.repeatSection() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Back to songs") { model.endLesson() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 26)
        .padding(.bottom, 20)
    }
}
