package com.allthatseries.RNAudioPlayer;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.net.Uri;
import android.os.Bundle;
import android.os.IBinder;
import android.os.RemoteException;
import android.support.annotation.Nullable;
import android.support.v4.content.LocalBroadcastManager;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import android.util.Log;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.util.HashMap;

public class RNAudioPlayerModule extends ReactContextBaseJavaModule implements ServiceConnection {
    ReactApplicationContext reactContext;

    private MediaControllerCompat mMediaController;
    private AudioPlayerService mService;
    private HashMap<Integer, String> mStateMap = new HashMap<Integer, String>();

    public RNAudioPlayerModule(ReactApplicationContext reactContext) {
        super(reactContext);

        this.reactContext = reactContext;

        // Register receiver
        IntentFilter filter = new IntentFilter();
        filter.addAction("update-position-event");
        filter.addAction("change-playback-action-event");
        filter.addAction("change-playback-state-event");
        filter.addAction("playback-error-event");
        LocalBroadcastManager.getInstance(reactContext).registerReceiver(mLocalBroadcastReceiver, filter);

        mStateMap.put(PlaybackStateCompat.STATE_NONE,       "NONE");
        mStateMap.put(PlaybackStateCompat.STATE_STOPPED,    "STOPPED");
        mStateMap.put(PlaybackStateCompat.STATE_PAUSED,     "PAUSED");
        mStateMap.put(PlaybackStateCompat.STATE_PLAYING,    "PLAYING");
        mStateMap.put(PlaybackStateCompat.STATE_ERROR,      "ERROR");
        mStateMap.put(PlaybackStateCompat.STATE_BUFFERING,  "BUFFERING");
        mStateMap.put(12,                                   "COMPLETED");
    }

    private BroadcastReceiver mLocalBroadcastReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            WritableMap params = Arguments.createMap();

            switch(intent.getAction()) {
                case "update-position-event":
                    int nCurrentPosition = intent.getIntExtra("currentPosition", 0);
                    params.putInt("currentPosition", nCurrentPosition);
                    sendEvent("onPlaybackPositionUpdated", params);
                    break;
                case "change-playback-action-event":
                    String strAction = intent.getStringExtra("action");
                    params.putString("action", strAction);
                    sendEvent("onPlaybackActionChanged", params);
                    break;
                case "change-playback-state-event":
                    int nState = intent.getIntExtra("state", 0);
                    if (mStateMap.containsKey(nState)) {
                        params.putString("state", mStateMap.get(nState));
                        sendEvent("onPlaybackStateChanged", params);
                    }
                    break;
                case "playback-error-event":
                    String strError = intent.getStringExtra("msg");
                    params.putString("msg", strError);
                    sendEvent("onPlaybackError", params);
                default:
                    break;
            }
        }
    };

    @Override
    public String getName() {
    return "RNAudioPlayer";
    }

    private void sendEvent(String eventName, @Nullable WritableMap params) {
        this.reactContext
                .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                .emit(eventName, params);
    }

    @Override
    public void initialize() {
        super.initialize();

        try {
            Intent intent = new Intent(this.reactContext, AudioPlayerService.class);
            this.reactContext.startService(intent);
            this.reactContext.bindService(intent, this, Context.BIND_ADJUST_WITH_ACTIVITY);
        } catch (Exception e) {
            Log.e("ERROR", e.getMessage());
        }
    }

    @Override
    public void onServiceConnected(ComponentName name, IBinder service) {
        if (service instanceof AudioPlayerService.ServiceBinder) {
            try {
                mService = ((AudioPlayerService.ServiceBinder) service).getService();
                mMediaController = new MediaControllerCompat(this.reactContext,
                        ((AudioPlayerService.ServiceBinder) service).getService().getMediaSessionToken());
            } catch (RemoteException e) {
                Log.e("ERROR", e.getMessage());
            }
        }
    }

    @Override
    public void onServiceDisconnected(ComponentName name) {
    }

    @ReactMethod
    public void play(String stream_url, ReadableMap metadata) {
        Bundle bundle = new Bundle();
        bundle.putString(MediaMetadataCompat.METADATA_KEY_TITLE, metadata.getString("title"));
        bundle.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, metadata.getString("album_art_uri"));
        bundle.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, metadata.getString("artist"));
        mMediaController.getTransportControls().playFromUri(Uri.parse(stream_url), bundle);
    }

    @ReactMethod
    public void pause() {
        mMediaController.getTransportControls().pause();
    }

    @ReactMethod
    public void resume() {
        mMediaController.getTransportControls().play();
    }

    @ReactMethod
    public void stop() {
        mMediaController.getTransportControls().stop();
    }

    @ReactMethod
    public void seekTo(int timeMillis) {
        mMediaController.getTransportControls().seekTo(timeMillis);
    }

    @ReactMethod
    public void isPlaying(Callback cb) {
        cb.invoke(mService.getPlayback().isPlaying());
    }

    @ReactMethod
    public void getDuration(Callback cb) {
        cb.invoke(mService.getPlayback().getDuration());
    }

    @ReactMethod
    public void getCurrentPosition(Callback cb) {
        cb.invoke(mService.getPlayback().getCurrentPosition());
    }
}