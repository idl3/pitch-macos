import AppKit
import AVFAudio
import Foundation

@MainActor
final class YouTubeAudioPlayer: ObservableObject {
    @Published var urlString = ""
    @Published var status = ""
    @Published var pitchCents: Float = 0
    @Published var volume: Float = 1.0
    @Published var isPlaying = false

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var timePitch: AVAudioUnitTimePitch?
    private var currentFile: AVAudioFile?
    private var currentTempDirectory: URL?

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.stop()
            }
        }
    }

    func load() {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            status = "Invalid URL"
            return
        }
        status = "Downloading…"
        stop()
        Task.detached(priority: .userInitiated) { [weak self, url] in
            guard let (file, directory) = Self.downloadAudio(url: url) else {
                await MainActor.run { [weak self] in
                    self?.status = "Download failed. Is yt-dlp installed?"
                }
                return
            }
            await MainActor.run { [weak self] in
                self?.currentTempDirectory = directory
                self?.setup(file: file)
            }
        }
    }

    nonisolated private static func downloadAudio(url: URL) -> (file: URL, directory: URL)? {
        guard let downloader = Self.ytDlpPath() else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = downloader
            process.arguments = [
                "-f", "bestaudio[ext=m4a]/bestaudio",
                "--no-playlist",
                "-o", "\(tmp.path)/%(title)s.%(ext)s",
                url.absoluteString
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let file = Self.firstAudioFile(in: tmp) else { return nil }
            return (file, tmp)
        } catch {
            return nil
        }
    }

    private func setup(file: URL) {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        timePitch = AVAudioUnitTimePitch()
        guard let engine, let player, let timePitch else {
            status = "Could not create audio engine"
            return
        }

        do {
            let audioFile = try AVAudioFile(forReading: file)
            currentFile = audioFile
            engine.attach(player)
            engine.attach(timePitch)
            let format = player.outputFormat(forBus: 0)
            engine.connect(player, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            timePitch.pitch = pitchCents
            timePitch.rate = 1.0
            engine.mainMixerNode.volume = volume

            player.scheduleFile(audioFile, at: nil) { [weak self] in
                Task {
                    await MainActor.run { [weak self] in
                        self?.isPlaying = false
                        self?.status = "Finished"
                    }
                }
            }
            try engine.start()
            player.play()
            isPlaying = true
            status = "Playing"
        } catch {
            status = "Playback error: \(error.localizedDescription)"
            cleanupTempDirectory()
        }
    }

    private func cleanupTempDirectory() {
        if let directory = currentTempDirectory {
            try? FileManager.default.removeItem(at: directory)
            currentTempDirectory = nil
        }
    }

    func togglePlay() {
        guard let player, let engine else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            status = "Paused"
        } else {
            do {
                try engine.start()
            } catch {}
            player.play()
            isPlaying = true
            status = "Playing"
        }
    }

    func stop() {
        player?.stop()
        engine?.stop()
        player = nil
        timePitch = nil
        engine = nil
        currentFile = nil
        cleanupTempDirectory()
        isPlaying = false
        status = "Stopped"
    }

    func updatePitch() {
        timePitch?.pitch = pitchCents
    }

    func updateVolume() {
        engine?.mainMixerNode.volume = volume
    }

    nonisolated private static func ytDlpPath() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    nonisolated private static func firstAudioFile(in directory: URL) -> URL? {
        let extensions = ["m4a", "mp3", "wav", "aiff", "caf", "flac"]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        let audioFiles = contents.filter { extensions.contains($0.pathExtension.lowercased()) }
        return audioFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first
    }
}
