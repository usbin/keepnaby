import MediaPlayer

final class MusicController {
    private let player = MPMusicPlayerController.systemMusicPlayer

    func playPause() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func nextTrack() {
        player.skipToNextItem()
    }

    func previousTrack() {
        player.skipToPreviousItem()
    }
}
