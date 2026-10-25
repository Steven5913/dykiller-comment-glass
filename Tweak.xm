// ForceDYKillerPrefs v2 — hook NSUserDefaults 读取方法，强制只开评论区玻璃。
// 原理：DYKiller 所有开关本质都是 NSUserDefaults 读(key=BOOL/Integer/Double)。
// 我们 hook 读取方法，凡 DYKiller* 前缀的 key：除 DYKillerCommentGlass(评论液态玻璃·模糊)放行为 YES 外，
// 一律返回 NO/0。抖音优化(siwenjiajia)自身 key 不以 DYKiller 开头，完全不受影响。
// ObjC 层 hook，无 arm64e PAC 问题，且覆盖 DYKiller 可能使用的任意 defaults suite。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

static inline BOOL DKShouldForceOff(NSString *key){
    if (![key hasPrefix:@"DYKiller"]) return NO;          // 非 DYKiller key，放行(抖音优化等)
    if ([key isEqualToString:@"DYKillerCommentGlass"]) return NO; // 评论区玻璃·模糊 放行(下面返回YES)
    return YES;                                          // 其余 DYKiller 功能 一律关
}
static inline BOOL DKIsCommentGlass(NSString *key){
    return [key isEqualToString:@"DYKillerCommentGlass"];
}

static BOOL (*orig_boolForKey)(id,SEL,NSString*);
static BOOL hook_boolForKey(id self, SEL _cmd, NSString *key){
    if (DKIsCommentGlass(key)) return YES;
    if (DKShouldForceOff(key)) return NO;
    return orig_boolForKey(self,_cmd,key);
}
static NSInteger (*orig_integerForKey)(id,SEL,NSString*);
static NSInteger hook_integerForKey(id self, SEL _cmd, NSString *key){
    if (DKShouldForceOff(key)) return 0;
    return orig_integerForKey(self,_cmd,key);
}
static double (*orig_doubleForKey)(id,SEL,NSString*);
static double hook_doubleForKey(id self, SEL _cmd, NSString *key){
    if (DKShouldForceOff(key)) return 0.0;
    return orig_doubleForKey(self,_cmd,key);
}
static float (*orig_floatForKey)(id,SEL,NSString*);
static float hook_floatForKey(id self, SEL _cmd, NSString *key){
    if (DKShouldForceOff(key)) return 0.0f;
    return orig_floatForKey(self,_cmd,key);
}
static id (*orig_objectForKey)(id,SEL,NSString*);
static id hook_objectForKey(id self, SEL _cmd, NSString *key){
    if (DKIsCommentGlass(key)) return @YES;
    if (DKShouldForceOff(key)) return @NO;
    return orig_objectForKey(self,_cmd,key);
}
static NSString *(*orig_stringForKey)(id,SEL,NSString*);
static NSString *hook_stringForKey(id self, SEL _cmd, NSString *key){
    if (DKShouldForceOff(key)) return nil;
    return orig_stringForKey(self,_cmd,key);
}

static void DKInstallHooks(void){
    if(!orig_boolForKey){  MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("boolForKey:"),   (IMP)hook_boolForKey,   (IMP*)&orig_boolForKey); }
    if(!orig_integerForKey){MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("integerForKey:"),(IMP)hook_integerForKey,(IMP*)&orig_integerForKey); }
    if(!orig_doubleForKey){ MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("doubleForKey:"),  (IMP)hook_doubleForKey,  (IMP*)&orig_doubleForKey); }
    if(!orig_floatForKey){  MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("floatForKey:"),   (IMP)hook_floatForKey,   (IMP*)&orig_floatForKey); }
    if(!orig_objectForKey){ MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("objectForKey:"),  (IMP)hook_objectForKey,  (IMP*)&orig_objectForKey); }
    if(!orig_stringForKey){ MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("stringForKey:"),  (IMP)hook_stringForKey,  (IMP*)&orig_stringForKey); }
}

static void DKForceAllPrefs(void){
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:NO forKey:@"DYKillerAdjustRangeExtended"];
    [d setBool:NO forKey:@"DYKillerAudioVizPosition"];
    [d setBool:NO forKey:@"DYKillerAudioVizStyle"];
    [d setBool:NO forKey:@"DYKillerAvatarAlpha"];
    [d setBool:NO forKey:@"DYKillerAvatarDisplay"];
    [d setBool:NO forKey:@"DYKillerAvatarScale"];
    [d setBool:NO forKey:@"DYKillerBackup"];
    [d setBool:NO forKey:@"DYKillerBackupExport"];
    [d setBool:NO forKey:@"DYKillerBackupLastExportDate"];
    [d setBool:NO forKey:@"DYKillerBackupReset"];
    [d setBool:NO forKey:@"DYKillerBackupRestore"];
    [d setBool:NO forKey:@"DYKillerBackupUndo"];
    [d setBool:NO forKey:@"DYKillerBlockSideBarSwipe"];
    [d setBool:NO forKey:@"DYKillerBottomBar"];
    [d setBool:NO forKey:@"DYKillerCommentAIParseMode"];
    [d setBool:NO forKey:@"DYKillerCommentCopyWithoutName"];
    [d setBool:NO forKey:@"DYKillerCommentDramaAnchorMode"];
    [d setBool:NO forKey:@"DYKillerCommentDramaReviewMode"];
    [d setBool:NO forKey:@"DYKillerCommentGameAnchorMode"];
    [d setBool:NO forKey:@"DYKillerCommentImageNoWatermark"];
    [d setBool:NO forKey:@"DYKillerCommentLivePhotoNoWatermark"];
    [d setBool:NO forKey:@"DYKillerCommentLocationMode"];
    [d setBool:NO forKey:@"DYKillerCommentLunaAnchorMode"];
    [d setBool:NO forKey:@"DYKillerCommentMediaCleanBottomBar"];
    [d setBool:NO forKey:@"DYKillerCommentMenu"];
    [d setBool:NO forKey:@"DYKillerCommentMenuCatalog"];
    [d setBool:NO forKey:@"DYKillerCommentMenuColumns"];
    [d setBool:NO forKey:@"DYKillerCommentPlayerDiscussionMode"];
    [d setBool:NO forKey:@"DYKillerCommentRemoveAllTabs"];
    [d setBool:NO forKey:@"DYKillerCommentRemoveAllTopTags"];
    [d setBool:NO forKey:@"DYKillerCommentReplyBottomBarMode"];
    [d setBool:NO forKey:@"DYKillerCommentSearchAnchorMode"];
    [d setBool:NO forKey:@"DYKillerCommentSeriesAnchorMode"];
    [d setBool:NO forKey:@"DYKillerCommentStoreReviewMode"];
    [d setBool:NO forKey:@"DYKillerDanmakuColorMode"];
    [d setBool:NO forKey:@"DYKillerDanmakuFixedColor"];
    [d setBool:NO forKey:@"DYKillerDanmakuGradientColors"];
    [d setBool:NO forKey:@"DYKillerDanmakuHexColor"];
    [d setBool:NO forKey:@"DYKillerDebugInspectorEnabled"];
    [d setBool:NO forKey:@"DYKillerDescriptionAlpha"];
    [d setBool:NO forKey:@"DYKillerDescriptionScale"];
    [d setBool:NO forKey:@"DYKillerDetailReturnMode"];
    [d setBool:NO forKey:@"DYKillerDetailSearchMode"];
    [d setBool:NO forKey:@"DYKillerDoubleTapOpenComment"];
    [d setBool:NO forKey:@"DYKillerEnableDanmakuColor"];
    [d setBool:NO forKey:@"DYKillerFeedMenu"];
    [d setBool:NO forKey:@"DYKillerFeedMenuCatalog"];
    [d setBool:NO forKey:@"DYKillerFeedMenuColumns"];
    [d setBool:NO forKey:@"DYKillerFeedMenuGlass"];
    [d setBool:NO forKey:@"DYKillerFeedMenuGlassClear"];
    [d setBool:NO forKey:@"DYKillerFilterAds"];
    [d setBool:NO forKey:@"DYKillerFilterLowLikes"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedArticle"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedCreation"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedEcommerce"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedGame"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedHotspot"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedInterest"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedMerchantNote"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedMicroApp"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedMusic"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedSocial"];
    [d setBool:NO forKey:@"DYKillerFilterRecommendedSpecialCard"];
    [d setBool:NO forKey:@"DYKillerFollowButtonDisplayMode"];
    [d setBool:NO forKey:@"DYKillerFriendAvatarEntryMode"];
    [d setBool:NO forKey:@"DYKillerFriendButtonMode"];
    [d setBool:NO forKey:@"DYKillerFriendDailyMode"];
    [d setBool:NO forKey:@"DYKillerFriendFastReplyMode"];
    [d setBool:NO forKey:@"DYKillerFriendFollowTagMode"];
    [d setBool:NO forKey:@"DYKillerFriendRelationTagMode"];
    [d setBool:NO forKey:@"DYKillerFriendRemoveRecommendCard"];
    [d setBool:NO forKey:@"DYKillerFriendSendMessageMode"];
    [d setBool:NO forKey:@"DYKillerFriendStoryTagMode"];
    [d setBool:NO forKey:@"DYKillerGeoNamesRegister"];
    [d setBool:NO forKey:@"DYKillerGeoNamesUsername"];
    [d setBool:NO forKey:@"DYKillerGeoNamesWebServices"];
    [d setBool:NO forKey:@"DYKillerGlassTabBar"];
    [d setBool:NO forKey:@"DYKillerGlassTabBarClear"];
    [d setBool:NO forKey:@"DYKillerGlassTabBarPadPosition"];
    [d setBool:NO forKey:@"DYKillerHideChatVideoBottomBar"];
    [d setBool:NO forKey:@"DYKillerHideCommentBottomBar"];
    [d setBool:NO forKey:@"DYKillerHideFollowButton"];
    [d setBool:NO forKey:@"DYKillerHideMusicInfo"];
    [d setBool:NO forKey:@"DYKillerHideProfileUGCGuide"];
    [d setBool:NO forKey:@"DYKillerInfoOffset"];
    [d setBool:NO forKey:@"DYKillerInnerNotiCorner"];
    [d setBool:NO forKey:@"DYKillerInnerNotiGlass"];
    [d setBool:NO forKey:@"DYKillerInnerNotiGlassClear"];
    [d setBool:NO forKey:@"DYKillerInteraction"];
    [d setBool:NO forKey:@"DYKillerInteractionCommentIcon"];
    [d setBool:NO forKey:@"DYKillerInteractionCommentStyle"];
    [d setBool:NO forKey:@"DYKillerInteractionDisplay"];
    [d setBool:NO forKey:@"DYKillerInteractionFavoriteAfterIcon"];
    [d setBool:NO forKey:@"DYKillerInteractionFavoriteBeforeIcon"];
    [d setBool:NO forKey:@"DYKillerInteractionFavoriteStyle"];
    [d setBool:NO forKey:@"DYKillerInteractionIconAlpha"];
    [d setBool:NO forKey:@"DYKillerInteractionLabelAlpha"];
    [d setBool:NO forKey:@"DYKillerInteractionLikeAfterIcon"];
    [d setBool:NO forKey:@"DYKillerInteractionLikeBeforeIcon"];
    [d setBool:NO forKey:@"DYKillerInteractionLikeStyle"];
    [d setBool:NO forKey:@"DYKillerInteractionOffset"];
    [d setBool:NO forKey:@"DYKillerInteractionScale"];
    [d setBool:NO forKey:@"DYKillerInteractionShareIcon"];
    [d setBool:NO forKey:@"DYKillerInteractionShareStyle"];
    [d setBool:NO forKey:@"DYKillerMediaSave"];
    [d setBool:NO forKey:@"DYKillerMediaSaveAllImages"];
    [d setBool:NO forKey:@"DYKillerMediaSaveChatSticker"];
    [d setBool:NO forKey:@"DYKillerMediaSaveComment"];
    [d setBool:NO forKey:@"DYKillerMediaSaveCommentSticker"];
    [d setBool:NO forKey:@"DYKillerMediaSaveCover"];
    [d setBool:NO forKey:@"DYKillerMediaSaveCurrentImage"];
    [d setBool:NO forKey:@"DYKillerMediaSaveGlass"];
    [d setBool:NO forKey:@"DYKillerMediaSaveGlassClear"];
    [d setBool:NO forKey:@"DYKillerMediaSaveHaptic"];
    [d setBool:NO forKey:@"DYKillerMediaSaveMusic"];
    [d setBool:NO forKey:@"DYKillerMediaSaveVideo"];
    [d setBool:NO forKey:@"DYKillerMessageDailyMode"];
    [d setBool:NO forKey:@"DYKillerMessageFriendAvatarMode"];
    [d setBool:NO forKey:@"DYKillerMessageInteractionMode"];
    [d setBool:NO forKey:@"DYKillerMessagePlusMode"];
    [d setBool:NO forKey:@"DYKillerMessageSearchMode"];
    [d setBool:NO forKey:@"DYKillerMessageSideBarMode"];
    [d setBool:NO forKey:@"DYKillerMessageSlotMode"];
    [d setBool:NO forKey:@"DYKillerMinimumLikes"];
    [d setBool:NO forKey:@"DYKillerMusicAlpha"];
    [d setBool:NO forKey:@"DYKillerMusicDisplay"];
    [d setBool:NO forKey:@"DYKillerMusicScale"];
    [d setBool:NO forKey:@"DYKillerNicknameAlpha"];
    [d setBool:NO forKey:@"DYKillerNicknameScale"];
    [d setBool:NO forKey:@"DYKillerPageLiquidGlass"];
    [d setBool:NO forKey:@"DYKillerPlayback"];
    [d setBool:NO forKey:@"DYKillerPlaybackAppDownloadMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackChapterHighlightsMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackCoCreatorMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackDanmakuMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackFriendRecommendMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackFriendShareMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackFullscreenMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackGameTagMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackHotspotMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackJianyingMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackLocationMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackMusicAnchorMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackMusicInfoMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackOtherUserRecommendMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackPaidContentMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackPropEffectMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackQuickReplyMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackRelatedSearchMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackRelatedVideoMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackRemoveAllAnchors"];
    [d setBool:NO forKey:@"DYKillerPlaybackRemoveAllBottomBars"];
    [d setBool:NO forKey:@"DYKillerPlaybackRiskNoticeMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackSelectedMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackSlidesTagMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackStoreMode"];
    [d setBool:NO forKey:@"DYKillerPlaybackVideoCollectionMode"];
    [d setBool:NO forKey:@"DYKillerPlusIcon"];
    [d setBool:NO forKey:@"DYKillerPlusStyle"];
    [d setBool:NO forKey:@"DYKillerProfileAddFriendMode"];
    [d setBool:NO forKey:@"DYKillerProfileAvatarPlusMode"];
    [d setBool:NO forKey:@"DYKillerProfileCapsuleMode"];
    [d setBool:NO forKey:@"DYKillerProfileEditMode"];
    [d setBool:NO forKey:@"DYKillerProfileGuideBannerMode"];
    [d setBool:NO forKey:@"DYKillerProfileRemoveDailyTab"];
    [d setBool:NO forKey:@"DYKillerProfileRemoveFavoriteTab"];
    [d setBool:NO forKey:@"DYKillerProfileRemoveFootprintTab"];
    [d setBool:NO forKey:@"DYKillerProfileRemoveLikeTab"];
    [d setBool:NO forKey:@"DYKillerProfileRemovePostTab"];
    [d setBool:NO forKey:@"DYKillerProfileRemoveServiceArea"];
    [d setBool:NO forKey:@"DYKillerProfileSearchMode"];
    [d setBool:NO forKey:@"DYKillerProfileSettingsEntry"];
    [d setBool:NO forKey:@"DYKillerProfileSettingsEntryName"];
    [d setBool:NO forKey:@"DYKillerProfileShowPublishLocation"];
    [d setBool:NO forKey:@"DYKillerProfileShowPublishTime"];
    [d setBool:NO forKey:@"DYKillerProfileSideBarMode"];
    [d setBool:NO forKey:@"DYKillerProfileStatsMode"];
    [d setBool:NO forKey:@"DYKillerProfileSwitchAccountMode"];
    [d setBool:NO forKey:@"DYKillerProfileVisitorMode"];
    [d setBool:NO forKey:@"DYKillerProgressAlwaysVisible"];
    [d setBool:NO forKey:@"DYKillerProgressTimeStyle"];
    [d setBool:NO forKey:@"DYKillerPublishLocationColor"];
    [d setBool:NO forKey:@"DYKillerPublishLocationColorMode"];
    [d setBool:NO forKey:@"DYKillerPublishLocationFixedColor"];
    [d setBool:NO forKey:@"DYKillerPublishLocationGradientColors"];
    [d setBool:NO forKey:@"DYKillerPublishLocationHexColor"];
    [d setBool:NO forKey:@"DYKillerPublishTextColors"];
    [d setBool:NO forKey:@"DYKillerPublishTimeColor"];
    [d setBool:NO forKey:@"DYKillerPublishTimeColorMode"];
    [d setBool:NO forKey:@"DYKillerPublishTimeFixedColor"];
    [d setBool:NO forKey:@"DYKillerPublishTimeGradientColors"];
    [d setBool:NO forKey:@"DYKillerPublishTimeHexColor"];
    [d setBool:NO forKey:@"DYKillerRemoveCommentSurvey"];
    [d setBool:NO forKey:@"DYKillerRemoveRecommendedLive"];
    [d setBool:NO forKey:@"DYKillerSearchCameraMode"];
    [d setBool:NO forKey:@"DYKillerSearchRankCatalog"];
    [d setBool:NO forKey:@"DYKillerSearchRanks"];
    [d setBool:NO forKey:@"DYKillerSearchRemoveAllRanks"];
    [d setBool:NO forKey:@"DYKillerSearchRemoveGuess"];
    [d setBool:NO forKey:@"DYKillerSearchRemoveHistory"];
    [d setBool:NO forKey:@"DYKillerSearchRemoveRankFooter"];
    [d setBool:NO forKey:@"DYKillerSearchRemoveVoice"];
    [d setBool:NO forKey:@"DYKillerShareMenu"];
    [d setBool:NO forKey:@"DYKillerShareMenuCatalog"];
    [d setBool:NO forKey:@"DYKillerSharePanelGlass"];
    [d setBool:NO forKey:@"DYKillerSharePanelGlassClear"];
    [d setBool:NO forKey:@"DYKillerShowPublishLocation"];
    [d setBool:NO forKey:@"DYKillerShowPublishTime"];
    [d setBool:NO forKey:@"DYKillerTabBarStyle"];
    [d setBool:NO forKey:@"DYKillerTipsGlass"];
    [d setBool:NO forKey:@"DYKillerTipsGlassClear"];
    [d setBool:NO forKey:@"DYKillerTopBarAlpha"];
    [d setBool:NO forKey:@"DYKillerTopBarSearchMode"];
    [d setBool:NO forKey:@"DYKillerTopBarSideBarMode"];
    [d setBool:NO forKey:@"DYKillerTopChannelCatalog"];
    [d setBool:NO forKey:@"DYKillerTopChannels"];
    [d setBool:NO forKey:@"DYKillerVideoFullscreen"];
    [d setBool:YES forKey:@"DYKillerCommentGlass"];
    [d setBool:NO  forKey:@"DYKillerCommentGlassClear"];
    [d synchronize];
}

static __attribute__((constructor)) void DKInit(void){
    DKInstallHooks();
    DKForceAllPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{ DKInstallHooks(); DKForceAllPrefs(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKInstallHooks(); DKForceAllPrefs(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKInstallHooks(); DKForceAllPrefs(); });
}