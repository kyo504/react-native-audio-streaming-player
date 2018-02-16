package com.allthatseries.RNAudioPlayer;

import android.app.Service;
import android.content.Intent;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;
import android.os.IBinder;
import android.os.RemoteException;
import android.os.SystemClock;
import android.support.v4.content.LocalBroadcastManager;
import android.support.v4.media.session.MediaButtonReceiver;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;

public class AudioPlayerService extends Service {

    private static final String TAG = AudioPlayerService.class.getSimpleName();

    public static final String SESSION_TAG = "AUDIO_SESSION";

    // The action of the incoming Intent indicating that it contains a command to be executed
    public static final String ACTION_CMD = "com.allthatseries.RNAudioPlayer.ACTION_CMD";
    // The key in the extras of the incoming Intent indicating the command that should be executed
    public static final String CMD_NAME = "CMD_NAME";
    // A value of a CMD_NAME key in the extras of the incoming Intent that indicates that the music playback should be paused
    public static final String CMD_PAUSE = "CMD_PAUSE";

    private MediaSessionCompat mMediaSession;
    private MediaControllerCompat mMediaController;
    private MediaNotificationManager mMediaNotificationManager;
    private Playback mPlayback;

    public class ServiceBinder extends Binder {
        public AudioPlayerService getService() {
            return AudioPlayerService.this;
        }
    }

    private Binder mBinder = new ServiceBinder();

    private MediaSessionCompat.Callback mMediaSessionCallback = new MediaSessionCompat.Callback() {

        @Override
        public void onPlayFromUri(Uri uri, Bundle extras) {
            mMediaSession.setActive(true);
            mPlayback.playFromUri(uri, extras);
        }

        @Override
        public void onPlay() {
            mMediaSession.setActive(true);
            mPlayback.resume();
        }

        @Override
        public void onPause() {
            if (mPlayback.isPlaying()) {
                mPlayback.pause();
                stopForeground(false);
            }
        }

        @Override
        public void onStop() {
            mPlayback.stop();
            mMediaSession.setActive(false);
            stopForeground(true);
        }

        @Override
        public void onSeekTo(long pos) {
            mPlayback.seekTo((int)pos);
        }
    };

    private Playback.Callback mPlaybackCallback = new Playback.Callback() {
        @Override
        public void onCompletion() {
            updatePlaybackState();

            Intent intent = new Intent("change-playback-state-event");
            intent.putExtra("state", 12);
            LocalBroadcastManager.getInstance(getApplicationContext()).sendBroadcast(intent);
        }

        @Override
        public void onError(String error) {
            mMediaNotificationManager.stopNotification();

            Intent intent = new Intent("playback-error-event");
            intent.putExtra("msg", error);
            LocalBroadcastManager.getInstance(getApplicationContext()).sendBroadcast(intent);
        }

        @Override
        public void onPlaybackStateChanged(int state) {
            updatePlaybackState();
        }

        @Override
        public void onMediaMetadataChanged(MediaMetadataCompat metadata) {
            mMediaSession.setMetadata(metadata);
            mMediaNotificationManager.startNotification();
        }
    };

    public MediaSessionCompat.Token getMediaSessionToken() {
        return mMediaSession.getSessionToken();
    }

    public Playback getPlayback() {
        return this.mPlayback;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return mBinder;
    }

    @Override
    public void onCreate() {
        super.onCreate();

        // 1) set up media session and media session callback
        mMediaSession = new MediaSessionCompat(this, SESSION_TAG);
        mMediaSession.setCallback(mMediaSessionCallback);
        mMediaSession.setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS |
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS);

        // 2) Create a Playback instance
        mPlayback = new Playback(this);
        mPlayback.setCallback(mPlaybackCallback);
        updatePlaybackState();

        // 3) Create the media controller
        try {
            mMediaController = new MediaControllerCompat(this, mMediaSession.getSessionToken());
        } catch(RemoteException e) {
            e.printStackTrace();
        }

        // 4) Create notification manager instance
        try {
            mMediaNotificationManager = new MediaNotificationManager(this);
        } catch(RemoteException e) {
            e.printStackTrace();
        }
    }

    @Override
    public int onStartCommand(Intent startIntent, int flags, int startId) {
        if (startIntent != null) {
            String action = startIntent.getAction();
            String command = startIntent.getStringExtra(CMD_NAME);
            if (ACTION_CMD.equals(action)) {
                if (CMD_PAUSE.equals(command)) {
                    mMediaController.getTransportControls().pause();
                }
            } else {
                // Try to handle the intent as a media button event wrapped by MediaButtonReceiver
                MediaButtonReceiver.handleIntent(mMediaSession, startIntent);
            }
        }

        return START_STICKY;
    }

    /**
     * Update the current media player state, optionally showing an error message.
     */
    public void updatePlaybackState() {
        long position = PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN;
        if (mPlayback != null ) {
            position = mPlayback.getCurrentPosition();
        }
        long actions =
                PlaybackStateCompat.ACTION_PLAY_PAUSE |
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS |
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT;

        if (mPlayback != null && mPlayback.isPlaying()) {
            actions |= PlaybackStateCompat.ACTION_PAUSE;
        } else {
            actions |= PlaybackStateCompat.ACTION_PLAY;
        }

        int state = mPlayback.getState();

        //noinspection ResourceType
        PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, position, 1.0f, SystemClock.elapsedRealtime());

        mMediaSession.setPlaybackState(stateBuilder.build());

        Intent intent = new Intent("change-playback-state-event");
        intent.putExtra("state", state);
        LocalBroadcastManager.getInstance(getApplicationContext()).sendBroadcast(intent);
    }
}