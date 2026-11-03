package org.jellyfin.mobile.player.ui

import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import org.jellyfin.mobile.player.PlayerViewModel

/**
 * Player for the [androidx.media3.ui.PlayerView] controls, which handles playback controls as user actions.
 * This way, they are sent as requests to the group while SyncPlay is active, see [PlayerViewModel.userPlay].
 */
class UserActionPlayer(player: Player, private val viewModel: PlayerViewModel) : ForwardingPlayer(player) {
    override fun play() = viewModel.userPlay()

    override fun pause() = viewModel.userPause()

    override fun setPlayWhenReady(playWhenReady: Boolean) {
        if (playWhenReady) viewModel.userPlay() else viewModel.userPause()
    }

    override fun seekTo(positionMs: Long) = viewModel.userSeekTo(positionMs)

    override fun seekTo(mediaItemIndex: Int, positionMs: Long) = viewModel.userSeekTo(positionMs)

    override fun seekBack() = viewModel.userRewind()

    override fun seekForward() = viewModel.userFastForward()

    override fun seekToPrevious() = viewModel.userSkipToPrevious()

    override fun seekToNext() = viewModel.userSkipToNext()
}
