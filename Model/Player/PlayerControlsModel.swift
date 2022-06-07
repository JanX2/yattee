import CoreMedia
import Foundation
import SwiftUI

final class PlayerControlsModel: ObservableObject {
    @Published var isLoadingVideo = false
    @Published var isPlaying = true
    @Published var currentTime = CMTime.zero
    @Published var duration = CMTime.zero
    @Published var presentingControls = false { didSet { handlePresentationChange() } }
    @Published var timer: Timer?
    @Published var playingFullscreen = false

    private var throttle = Throttle(interval: 1)

    var player: PlayerModel!

    var playbackTime: String {
        guard let current = currentTime.seconds.formattedAsPlaybackTime(),
              let duration = duration.seconds.formattedAsPlaybackTime()
        else {
            return "--:-- / --:--"
        }

        var withoutSegments = ""
        if let withoutSegmentsDuration = playerItemDurationWithoutSponsorSegments,
           self.duration.seconds != withoutSegmentsDuration
        {
            withoutSegments = " (\(withoutSegmentsDuration.formattedAsPlaybackTime() ?? "--:--"))"
        }

        return "\(current) / \(duration)\(withoutSegments)"
    }

    var playerItemDurationWithoutSponsorSegments: Double? {
        guard let duration = player.playerItemDurationWithoutSponsorSegments else {
            return nil
        }

        return duration.seconds
    }

    func handlePresentationChange() {
        if presentingControls {
            DispatchQueue.main.async { [weak self] in
                self?.player?.backend.startControlsUpdates()
                self?.resetTimer()
            }
        } else {
            player.backend.stopControlsUpdates()
            timer?.invalidate()
            timer = nil
        }
    }

    func show() {
        guard !(player?.currentItem.isNil ?? true) else {
            return
        }

        guard !presentingControls else {
            return
        }

        withAnimation(PlayerControls.animation) {
            presentingControls = true
        }
    }

    func hide() {
        guard let player = player,
              !player.musicMode
        else {
            return
        }

        player.backend.stopControlsUpdates()

        guard !player.currentItem.isNil else {
            return
        }

        guard presentingControls else {
            return
        }
        withAnimation(PlayerControls.animation) {
            presentingControls = false
        }
    }

    func toggle() {
        presentingControls ? hide() : show()
    }

    func reset() {
        currentTime = .zero
        duration = .zero
    }

    func resetTimer() {
        #if os(tvOS)
            if !presentingControls {
                show()
            }
        #endif

        removeTimer()

        guard let player = player, !player.musicMode else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(PlayerControls.animation) { [weak self] in
                self?.presentingControls = false
                self?.player.backend.stopControlsUpdates()
            }
        }
    }

    func startPiP(startImmediately: Bool = true) {
        if player.activeBackend == .mpv {
            player.avPlayerBackend.switchToMPVOnPipClose = true
        }

        #if !os(macOS)
            player.exitFullScreen()
        #endif

        if player.activeBackend != PlayerBackendType.appleAVPlayer {
            player.saveTime { [weak player] in
                player?.changeActiveBackend(from: .mpv, to: .appleAVPlayer)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak player] in
            player?.avPlayerBackend.startPictureInPictureOnPlay = true
            if startImmediately {
                player?.pipController?.startPictureInPicture()
            }
        }
    }

    func removeTimer() {
        timer?.invalidate()
        timer = nil
    }

    func update() {
        throttle.execute { [weak self] in
            self?.player?.backend.updateControls()
        }
    }
}
