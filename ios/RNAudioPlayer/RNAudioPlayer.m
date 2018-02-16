
#import "RNAudioPlayer.h"
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTEventEmitter.h>
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface RNAudioPlayer() {
    float duration;
    float trackDuration;
    bool stalled;
    NSString *rapName;
    NSString *songTitle;
    NSString *albumUrlStr;
    NSURL *albumUrl;
    id<NSObject> playbackTimeObserver;
    MPNowPlayingInfoCenter *center;
    NSDictionary *songInfo;
    MPMediaItemArtwork *albumArt;
}

@end

@implementation RNAudioPlayer

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

- (RNAudioPlayer *)init {
    self = [super init];
    if (self) {
        [self registerRemoteControlEvents];
        [self registerAudioInterruptionNotifications];
        UIImage *defaultArtwork = [UIImage imageNamed:@"default_artwork-t300x300"];
        albumArt = [[MPMediaItemArtwork alloc] initWithImage: defaultArtwork];
        center = [MPNowPlayingInfoCenter defaultCenter];
        NSLog(@"AudioPlayer initialized!");
    }
    
    return self;
}


- (void)dealloc {
    NSLog(@"dealloc!!");
    [self unregisterRemoteControlEvents];
    [self unregisterAudioInterruptionNotifications];
    [self deactivate];
}

#pragma mark - Pubic API

RCT_EXPORT_METHOD(play:(NSString *)url:(NSDictionary *) metadata) {
    if(!([url length]>0)) return;
    
    // if audio is playing, stop the audio first
    if (self.player.rate && duration != 0) {
        [self.player pause];
        CMTime newTime = CMTimeMakeWithSeconds(0, 1);
        [self.player seekToTime:newTime];
    }
    
    // remove playerItem observers if they exist
    @try {
        [self.playerItem removeObserver:self forKeyPath:@"status"];
        [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    } @catch (id exception){
        // do nothing if there were no observers attached
        NSLog(@"No observer to remove");
    }
    
    // metadata to be used in lock screen & control center display
    rapName = metadata[@"artist"];
    songTitle = metadata[@"title"];
    albumUrlStr = metadata[@"album_art_uri"];
    albumUrl = [NSURL URLWithString:albumUrlStr];
    
    // updating lock screen & control center
    [self setNowPlayingInfo:true];
    
    NSURL *soundUrl = [[NSURL alloc] initWithString:url];
    self.playerItem = [AVPlayerItem playerItemWithURL:soundUrl];
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    
    // checking if iOS 10 or newer
    if ([[UIDevice currentDevice].systemVersion floatValue] >= 10) {
        self.player.automaticallyWaitsToMinimizeStalling = false;
    }
    
    // adding observers to check if audio is ready to play or it has an issue
    [self.playerItem addObserver:self forKeyPath:@"status" options:0 context:nil];
    [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    
    soundUrl = nil;
}

RCT_EXPORT_METHOD(pause) {
    [self pauseOrStop:@"PAUSE"];
}

RCT_EXPORT_METHOD(resume) {
    [self playAudio];
}

RCT_EXPORT_METHOD(stop) {
    [self pauseOrStop:@"STOP"];
}

RCT_EXPORT_METHOD(seekTo:(int) nSecond) {
    CMTime newTime = CMTimeMakeWithSeconds(nSecond/1000, 1);
    [self.player seekToTime:newTime];
}

#pragma mark - Audio

-(void) playAudio {
    [self.player play];
    
    // send player state PLAYING to js
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                    body: @{@"state": @"PLAYING" }];
    // if play was stalled
    if (stalled) {
        stalled = false;
    }
    
    // we need a weak self here for in-block access
    __weak typeof(self) weakSelf = self;
    
    // add playbackTimeObserver to send current position to js every 1 second
    playbackTimeObserver =
    [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        
        [weakSelf.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackPositionUpdated"
                                                            body: @{@"currentPosition": @(CMTimeGetSeconds(time)*1000) }];
        songInfo = @{
                     MPMediaItemPropertyTitle: rapName,
                     MPMediaItemPropertyArtist: songTitle,
                     MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithFloat: 1.0f],
                     MPMediaItemPropertyPlaybackDuration: [NSNumber numberWithFloat:duration],
                     MPNowPlayingInfoPropertyElapsedPlaybackTime: [NSNumber numberWithDouble:self.currentPlaybackTime],
                     MPMediaItemPropertyArtwork: albumArt
                     };
        center.nowPlayingInfo = songInfo;
    }];
    
    [self activate];
}

-(void) pauseOrStop:(NSString *)value {
    [self.player pause];
    
    if ([value isEqualToString:@"STOP"]) {
        // send player state STOPPED to js
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                        body: @{@"state": @"STOPPED" }];
        CMTime newTime = CMTimeMakeWithSeconds(0, 1);
        [self.player seekToTime:newTime];
        duration = 0;
    } else {
        // send player state PAUSED to js
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                        body: @{@"state": @"PAUSED" }];
        songInfo = @{
                     MPMediaItemPropertyTitle: rapName,
                     MPMediaItemPropertyArtist: songTitle,
                     MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithFloat: 0.0],
                     MPMediaItemPropertyPlaybackDuration: [NSNumber numberWithFloat:duration],
                     MPNowPlayingInfoPropertyElapsedPlaybackTime: [NSNumber numberWithDouble:self.currentPlaybackTime],
                     MPMediaItemPropertyArtwork: albumArt
                     };
        center.nowPlayingInfo = songInfo;
    }
    
    [self deactivate];
    
    // remove playbackTimeObserver if it exists
    @try {
        [self.player removeTimeObserver:playbackTimeObserver];
        playbackTimeObserver = nil;
    } @catch (id exception){
        // do nothing if playbackTimeObserver doesn't exist
    }
    
}

- (NSTimeInterval)currentPlaybackTime {
    CMTime time = self.player.currentTime;
    if (CMTIME_IS_VALID(time)) {
        return time.value / time.timescale;
    }
    return 0;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    
    if (object == self.player.currentItem && [keyPath isEqualToString:@"status"]) {
        // if current item status is ready to play && player has not begun playing
        if (self.player.currentItem.status == AVPlayerItemStatusReadyToPlay
            && CMTIME_COMPARE_INLINE(self.player.currentItem.currentTime, ==, kCMTimeZero)) {
            
            // set duration to be displayed in control center
            duration = CMTimeGetSeconds(self.player.currentItem.duration);
            [self playAudio];
            
        } else if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
            if (self.player.currentItem.error) {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackError"
                                                                body: @{@"desc": self.player.currentItem.error.localizedDescription }];
            } else {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackError"
                                                                body: @{@"desc": @"" }];
            }
        }
    } else if (object == self.player.currentItem && [keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        // check if player has paused && player has begun playing
        if (stalled && !self.player.rate && CMTIME_COMPARE_INLINE(self.player.currentItem.currentTime, >, kCMTimeZero)) {
            [self playAudio];
        }
    }
}


#pragma mark - Audio Session

-(void)playFinished:(NSNotification *)notification {
    [self.playerItem seekToTime:kCMTimeZero];
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                    body: @{@"state": @"COMPLETED" }];
}

-(void)playStalled:(NSNotification *)notification {
    stalled = true;
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                    body: @{@"state": @"PAUSED" }];
}

-(void)activate {
    NSError *categoryError = nil;
    
    [[AVAudioSession sharedInstance] setActive:YES error:&categoryError];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&categoryError];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playFinished:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playStalled:)
                                                 name:AVPlayerItemPlaybackStalledNotification
                                               object:self.playerItem];
    
    if (categoryError) {
        NSLog(@"Error setting category in activate %@", [categoryError description]);
    }
}

- (void)deactivate {
    NSError *categoryError = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionRouteChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:self.playerItem];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemPlaybackStalledNotification
                                                  object:self.playerItem];
    
    [[AVAudioSession sharedInstance] setActive:NO error:&categoryError];
    
    if (categoryError) {
        NSLog(@"Error setting category in deactivate %@", [categoryError description]);
    }
}

- (void)registerAudioInterruptionNotifications
{
    // Register for audio interrupt notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAudioInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
}

- (void)unregisterAudioInterruptionNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionRouteChangeNotification
                                                  object:nil];
}

- (void)onAudioInterruption:(NSNotification *)notification
{
    // getting interruption type as int value from AVAudioSessionInterruptionTypeKey
    int interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue];
    
    switch (interruptionType)
    {
        case AVAudioSessionInterruptionTypeBegan:
            // if duration exists
            if (duration != 0) {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackStateChanged"
                                                                body: @{@"state": @"PAUSED" }];
            }
            break;
            
        case AVAudioSessionInterruptionTypeEnded:
            // if duration exists && AVAudioSessionInterruptionOptionShouldResume (phone call)
            if (duration != 0 && [notification.userInfo[AVAudioSessionInterruptionOptionKey] intValue] == AVAudioSessionInterruptionOptionShouldResume) {
                [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                                body: @{@"action": @"PLAY" }];
            }
            break;
            
        default:
            NSLog(@"Audio Session Interruption Notification case default.");
            break;
    }
}


#pragma mark - Remote Control Events

- (void)audioRouteChangeListenerCallback:(NSNotification*)notification {
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    // when headphone was pulled (AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
    if (routeChangeReason == 2) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                        body: @{@"action": @"PAUSE" }];
    }
}

- (void)registerRemoteControlEvents {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand addTarget:self action:@selector(didReceivePlayCommand:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(didReceivePauseCommand:)];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(didReceiveToggleCommand:)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(didReceiveNextTrackCommand:)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(didReceivePreviousTrackCommand:)];
    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;
    commandCenter.stopCommand.enabled = NO;
}

- (void)didReceivePlayCommand:(MPRemoteCommand *)event {
    // check if player is not nil & duration is not 0 (0 means player is not initialized or stopped)
    if (self.player && duration != 0) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                        body: @{@"action": @"PLAY" }];
    }
    
}

- (void)didReceivePauseCommand:(MPRemoteCommand *)event {
    // check if player is not nil & duration is not 0 (0 means player is not initialized or stopped)
    if (self.player && duration != 0) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                        body: @{@"action": @"PAUSE" }];
    }
}

- (void)didReceiveToggleCommand:(MPRemoteCommand *)event {
    // if duration exists 0 & audio is playing
    if (duration != 0 && self.player.rate) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                        body: @{@"action": @"PAUSE" }];
    } else if (duration != 0 && !self.player.rate) {
        [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                        body: @{@"action": @"PLAY" }];
    }
}

- (void)didReceiveNextTrackCommand:(MPRemoteCommand *)event {
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                    body: @{@"action": @"SKIP_TO_NEXT" }];
}

- (void)didReceivePreviousTrackCommand:(MPRemoteCommand *)event {
    [self.bridge.eventDispatcher sendDeviceEventWithName: @"onPlaybackActionChanged"
                                                    body: @{@"action": @"SKIP_TO_PREVIOUS" }];
}

- (void)unregisterRemoteControlEvents {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.togglePlayPauseCommand removeTarget:self];
    [commandCenter.nextTrackCommand removeTarget:self];
    [commandCenter.previousTrackCommand removeTarget:self];
}

- (void)setNowPlayingInfo:(bool)isPlaying {
    NSData *data = [NSData dataWithContentsOfURL:albumUrl];
    
    if (data) {
        UIImage *artWork = [UIImage imageWithData:data];
        albumArt = [[MPMediaItemArtwork alloc] initWithImage: artWork];
    }
    
    songInfo = @{
                 MPMediaItemPropertyTitle: rapName,
                 MPMediaItemPropertyArtist: songTitle,
                 MPNowPlayingInfoPropertyPlaybackRate: [NSNumber numberWithFloat:isPlaying ? 1.0f : 0.0],
                 MPMediaItemPropertyArtwork: albumArt
                 };
    center.nowPlayingInfo = songInfo;
}


@end
