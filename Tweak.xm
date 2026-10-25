// ForceDYKillerPrefs v5 — 只开 评论区玻璃 + 聊天页玻璃，其余 DYKiller 全关
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

static inline BOOL DKIsGlass(NSString *key){
    return [key isEqualToString:@"DYKillerCommentGlass"]        // 评论区液态玻璃(模糊)
        || [key isEqualToString:@"DYKillerChatInputGlass"]      // 聊天页输入框玻璃(开)
        || [key isEqualToString:@"DYKillerChatInputGlassClear"]; // 聊天页输入框玻璃(样式:清透=2)
}
static inline BOOL DKShouldForceOff(NSString *key){
    if (![key hasPrefix:@"DYKiller"]) return NO;
    if (DKIsGlass(key)) return NO;
    return YES;
}

static BOOL (*orig_boolForKey)(id,SEL,NSString*);
static BOOL hook_boolForKey(id self, SEL _cmd, NSString *key){
    if (DKIsGlass(key)) return YES;
    if (DKShouldForceOff(key)) return NO;
    return orig_boolForKey(self,_cmd,key);
}
static NSInteger (*orig_integerForKey)(id,SEL,NSString*);
static NSInteger hook_integerForKey(id self, SEL _cmd, NSString *key){
    // 聊天玻璃样式走 display-mode: 0=关 1=模糊 2=清透
    if ([key isEqualToString:@"DYKillerChatInputGlassClear"]) return 2; // 清透
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
    if ([key isEqualToString:@"DYKillerChatInputGlassClear"]) return @(2); // 清透样式
    if (DKIsGlass(key)) return @YES;
    if (DKShouldForceOff(key)) return nil;   // 关键：返回nil，非@NO
    return orig_objectForKey(self,_cmd,key);
}
static NSString *(*orig_stringForKey)(id,SEL,NSString*);
static NSString *hook_stringForKey(id self, SEL _cmd, NSString *key){
    if (DKShouldForceOff(key)) return nil;
    return orig_stringForKey(self,_cmd,key);
}

// ===== 设置入口过滤：把抖音设置里 DYKiller 的区块/条目去掉 =====
static BOOL DKIsDKObj(id o){
    if (!o) return NO;
    NSString *cls = NSStringFromClass([o class]);
    if ([cls hasPrefix:@"DKSettings"]) return YES;      // DKY 自己的设置模型类
    for (NSString *k in @[@"title",@"sectionHeaderTitle",@"sectionHeader",@"name",@"identifier"]) {
        @try {
            id v = [o valueForKey:k];
            if ([v isKindOfClass:[NSString class]] && [v rangeOfString:@"DYKiller"].location != NSNotFound) return YES;
        } @catch(NSException *e){}
    }
    return NO;
}
static id DKFilterArray(id arr){
    if (!arr || ![arr isKindOfClass:[NSArray class]]) return arr;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:[arr count]];
    for (id s in (NSArray*)arr){ if(!DKIsDKObj(s)) [out addObject:s]; }
    return out;
}
// 视图模型区块数组 (AWESettingsViewModel)
static id (*orig_vm_sectionViewModelArray)(id,SEL);
static id hook_vm_sectionViewModelArray(id self, SEL _cmd){ return DKFilterArray(orig_vm_sectionViewModelArray(self,_cmd)); }
static id (*orig_vm_sectionViewModelsArray)(id,SEL);
static id hook_vm_sectionViewModelsArray(id self, SEL _cmd){ return DKFilterArray(orig_vm_sectionViewModelsArray(self,_cmd)); }
static id (*orig_vm_sections)(id,SEL);
static id hook_vm_sections(id self, SEL _cmd){ return DKFilterArray(orig_vm_sections(self,_cmd)); }
// 区块模型条目数组 (AWESettingSectionModel)
static id (*orig_sec_sectionDataArray)(id,SEL);
static id hook_sec_sectionDataArray(id self, SEL _cmd){ return DKFilterArray(orig_sec_sectionDataArray(self,_cmd)); }
static id (*orig_sec_items)(id,SEL);
static id hook_sec_items(id self, SEL _cmd){ return DKFilterArray(orig_sec_items(self,_cmd)); }
// 过滤 replaceBySectionViewModels:sync: 注入的区块 (Douyin 更新设置区块列表)
static id (*orig_vm_replaceBySections)(id,SEL,id,BOOL);
static id hook_vm_replaceBySections(id self, SEL _cmd, id sections, BOOL sync){
    return orig_vm_replaceBySections(self,_cmd, DKFilterArray(sections), sync);
}
// 判断 cell 是否渲染 DKY 内容(类前缀/模型/文本)
static BOOL DKIsDKCell(id cell){
    if (!cell) return NO;
    if ([NSStringFromClass([cell class]) hasPrefix:@"DKSettings"]) return YES;
    id m = nil;
    @try { m = [cell valueForKey:@"model"]; } @catch(NSException*e){}
    if (DKIsDKObj(m)) return YES;
    @try { m = [cell valueForKey:@"itemModel"]; } @catch(NSException*e){}
    if (DKIsDKObj(m)) return YES;
    for (UIView *sv in [[cell contentView] subviews]) {
        if ([sv isKindOfClass:[UILabel class]]) {
            NSString *txt = [(UILabel*)sv text];
            if (txt && [txt rangeOfString:@"DYKiller"].location != NSNotFound) return YES;
        }
    }
    return NO;
}
// 若视图模型即表格数据源，直接过滤 DKY 的 cell
static id (*orig_vm_cellForRow)(id,SEL,id,id);
static id hook_vm_cellForRow(id self, SEL _cmd, id tv, id ip){
    id cell = orig_vm_cellForRow(self,_cmd,tv,ip);
    if (DKIsDKCell(cell)) {
        UITableViewCell *empty = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DKHidden"];
        empty.hidden = YES;
        return empty;
    }
    return cell;
}

// ===== 调试版：显示当前页面 VC 与消息 cell 类名（用于定位聊天气泡 cell）=====
#import <objc/runtime.h>
static UILabel *g_dbgLabel = nil;
static UIViewController *g_lastVC = nil;
static void DKShowDebugInfo(void){
    @try {
        if (!g_dbgLabel) {
            g_dbgLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 90, 480, 870)];
            g_dbgLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55f];
            g_dbgLabel.textColor = [UIColor yellowColor];
            g_dbgLabel.font = [UIFont boldSystemFontOfSize:9];
            g_dbgLabel.numberOfLines = 0;
            g_dbgLabel.userInteractionEnabled = NO;
            g_dbgLabel.adjustsFontSizeToFitWidth = YES;
            g_dbgLabel.layer.zPosition = 99999;
        }
        if (g_lastVC && g_lastVC.view.window) {
            UIWindow *win = g_lastVC.view.window;
            NSMutableArray *lines = [NSMutableArray array];
            [lines addObject:[NSString stringWithFormat:@"WIN-VC=%@", NSStringFromClass([g_lastVC class])]];
            // 列出 window 内所有 viewController（迭代）
            __block int vcIdx=0;
            UIViewController *root = win.rootViewController;
            NSMutableArray *vcStack = [NSMutableArray array];
            if (root) [vcStack addObject:@[root, @(0)]];
            while (vcStack.count > 0) {
                NSArray *top = [vcStack lastObject]; [vcStack removeLastObject];
                UIViewController *c = top[0]; int d = [top[1] intValue];
                if (d>3) continue;
                NSString *ind = [@"  " stringByPaddingToLength:d*2 withString:@" " startingAtIndex:0];
                [lines addObject:[NSString stringWithFormat:@"%@VC#%d=%@", ind, vcIdx++, NSStringFromClass([c class])]];
                for (UIViewController *ch in c.childViewControllers) [vcStack addObject:@[ch, @(d+1)]];
                if (c.presentedViewController) [vcStack addObject:@[c.presentedViewController, @(d+1)]];
            }
            // 遍历整个 window（含聊天页消息 collection 与气泡 cell），dump 全部子视图
            NSMutableArray *stack = [NSMutableArray array];
            [stack addObject:@[win, @(0)]];
            while (stack.count > 0) {
                NSArray *top = [stack lastObject]; [stack removeLastObject];
                UIView *v = top[0]; int d = [top[1] intValue];
                if (d>7) continue;
                for (UIView *s in v.subviews) {
                    if (s.frame.size.width<15 || s.frame.size.height<15) continue;
                    NSString *cn = NSStringFromClass([s class]) ?: @"?";
                    NSString *ind = [@"  " stringByPaddingToLength:d*2 withString:@" " startingAtIndex:0];
                    [lines addObject:[NSString stringWithFormat:@"%@%@[%.0f,%.0f,%.0f,%.0f]", ind, cn,
                                      s.frame.origin.x,s.frame.origin.y,s.frame.size.width,s.frame.size.height]];
                    [stack addObject:@[s, @(d+1)]];
                }
            }
            g_dbgLabel.text = [lines componentsJoinedByString:@"\n"];
            [win addSubview:g_dbgLabel];
            g_dbgLabel.frame = CGRectMake(0, 90, 480, 870);
        }
    } @catch(NSException *e){}
}
static void (*orig_viewDidAppear)(id,SEL,BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated){
    orig_viewDidAppear(self,_cmd,animated);
    @try {
        g_lastVC = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DKShowDebugInfo();
        });
    } @catch(NSException *e){}
}
static BOOL g_dbgInstalled = NO;
static void DKInstallDebugHooks(void){
    Class vc = NSClassFromString(@"UIViewController");
    if (vc && !orig_viewDidAppear) {
        MSHookMessageEx(vc, sel_registerName("viewDidAppear:"), (IMP)hook_viewDidAppear, (IMP*)&orig_viewDidAppear);
    }
    g_dbgInstalled = (orig_viewDidAppear != NULL);
}

static void DKInstallHooks(void){
    if(!orig_boolForKey){  MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("boolForKey:"),   (IMP)hook_boolForKey,   (IMP*)&orig_boolForKey); }
    if(!orig_integerForKey){MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("integerForKey:"),(IMP)hook_integerForKey,(IMP*)&orig_integerForKey); }
    if(!orig_doubleForKey){ MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("doubleForKey:"),  (IMP)hook_doubleForKey,  (IMP*)&orig_doubleForKey); }
    if(!orig_floatForKey){  MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("floatForKey:"),   (IMP)hook_floatForKey,   (IMP*)&orig_floatForKey); }
    if(!orig_objectForKey){ MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("objectForKey:"),  (IMP)hook_objectForKey,  (IMP*)&orig_objectForKey); }
    if(!orig_stringForKey){ MSHookMessageEx(NSClassFromString(@"NSUserDefaults"), sel_registerName("stringForKey:"),  (IMP)hook_stringForKey,  (IMP*)&orig_stringForKey); }
    Class dkvm = NSClassFromString(@"AWESettingsViewModel");
    if (dkvm){
        if(!orig_vm_sectionViewModelArray) MSHookMessageEx(dkvm, sel_registerName("sectionViewModelArray"), (IMP)hook_vm_sectionViewModelArray, (IMP*)&orig_vm_sectionViewModelArray);
        if(!orig_vm_sectionViewModelsArray) MSHookMessageEx(dkvm, sel_registerName("sectionViewModelsArray"), (IMP)hook_vm_sectionViewModelsArray, (IMP*)&orig_vm_sectionViewModelsArray);
        if(!orig_vm_sections) MSHookMessageEx(dkvm, sel_registerName("sections"), (IMP)hook_vm_sections, (IMP*)&orig_vm_sections);
        if(!orig_vm_replaceBySections) MSHookMessageEx(dkvm, sel_registerName("replaceBySectionViewModels:sync:"), (IMP)hook_vm_replaceBySections, (IMP*)&orig_vm_replaceBySections);
        if(!orig_vm_cellForRow) MSHookMessageEx(dkvm, sel_registerName("tableView:cellForRowAtIndexPath:"), (IMP)hook_vm_cellForRow, (IMP*)&orig_vm_cellForRow);
    }
    Class dksm = NSClassFromString(@"AWESettingSectionModel");
    if (dksm){
        if(!orig_sec_sectionDataArray) MSHookMessageEx(dksm, sel_registerName("sectionDataArray"), (IMP)hook_sec_sectionDataArray, (IMP*)&orig_sec_sectionDataArray);
        if(!orig_sec_items) MSHookMessageEx(dksm, sel_registerName("items"), (IMP)hook_sec_items, (IMP*)&orig_sec_items);
    }
    // 聊天气泡清透玻璃：hook 聊天消息 cell + 聊天页 VC 的 cell 回调
    DKInstallDebugHooks();
}

static void DKForceAllPrefs(void){
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // 评论玻璃(模糊) + 聊天玻璃(开 + 清透样式=2) 显式设置
    [d setBool:YES forKey:@"DYKillerCommentGlass"];          // 评论: 模糊
    [d setBool:YES forKey:@"DYKillerChatInputGlass"];        // 聊天: 玻璃开
    [d setInteger:2 forKey:@"DYKillerChatInputGlassClear"];  // 聊天: 清透样式
    // 其余 DYKiller 功能：彻底删除key，保证 objectForKey 返回 nil / boolForKey 返回 NO
    [d removeObjectForKey:@"DYKillerAdjustRangeExtended"];
    [d removeObjectForKey:@"DYKillerAudioVizPosition"];
    [d removeObjectForKey:@"DYKillerAudioVizStyle"];
    [d removeObjectForKey:@"DYKillerAvatarAlpha"];
    [d removeObjectForKey:@"DYKillerAvatarDisplay"];
    [d removeObjectForKey:@"DYKillerAvatarScale"];
    [d removeObjectForKey:@"DYKillerBackup"];
    [d removeObjectForKey:@"DYKillerBackupExport"];
    [d removeObjectForKey:@"DYKillerBackupLastExportDate"];
    [d removeObjectForKey:@"DYKillerBackupReset"];
    [d removeObjectForKey:@"DYKillerBackupRestore"];
    [d removeObjectForKey:@"DYKillerBackupUndo"];
    [d removeObjectForKey:@"DYKillerBlockSideBarSwipe"];
    [d removeObjectForKey:@"DYKillerBottomBar"];
    [d removeObjectForKey:@"DYKillerCommentAIParseMode"];
    [d removeObjectForKey:@"DYKillerCommentCopyWithoutName"];
    [d removeObjectForKey:@"DYKillerCommentDramaAnchorMode"];
    [d removeObjectForKey:@"DYKillerCommentDramaReviewMode"];
    [d removeObjectForKey:@"DYKillerCommentGameAnchorMode"];
    [d removeObjectForKey:@"DYKillerCommentImageNoWatermark"];
    [d removeObjectForKey:@"DYKillerCommentLivePhotoNoWatermark"];
    [d removeObjectForKey:@"DYKillerCommentLocationMode"];
    [d removeObjectForKey:@"DYKillerCommentLunaAnchorMode"];
    [d removeObjectForKey:@"DYKillerCommentMediaCleanBottomBar"];
    [d removeObjectForKey:@"DYKillerCommentMenu"];
    [d removeObjectForKey:@"DYKillerCommentMenuCatalog"];
    [d removeObjectForKey:@"DYKillerCommentMenuColumns"];
    [d removeObjectForKey:@"DYKillerCommentPlayerDiscussionMode"];
    [d removeObjectForKey:@"DYKillerCommentRemoveAllTabs"];
    [d removeObjectForKey:@"DYKillerCommentRemoveAllTopTags"];
    [d removeObjectForKey:@"DYKillerCommentReplyBottomBarMode"];
    [d removeObjectForKey:@"DYKillerCommentSearchAnchorMode"];
    [d removeObjectForKey:@"DYKillerCommentSeriesAnchorMode"];
    [d removeObjectForKey:@"DYKillerCommentStoreReviewMode"];
    [d removeObjectForKey:@"DYKillerDanmakuColorMode"];
    [d removeObjectForKey:@"DYKillerDanmakuFixedColor"];
    [d removeObjectForKey:@"DYKillerDanmakuGradientColors"];
    [d removeObjectForKey:@"DYKillerDanmakuHexColor"];
    [d removeObjectForKey:@"DYKillerDebugInspectorEnabled"];
    [d removeObjectForKey:@"DYKillerDescriptionAlpha"];
    [d removeObjectForKey:@"DYKillerDescriptionScale"];
    [d removeObjectForKey:@"DYKillerDetailReturnMode"];
    [d removeObjectForKey:@"DYKillerDetailSearchMode"];
    [d removeObjectForKey:@"DYKillerDoubleTapOpenComment"];
    [d removeObjectForKey:@"DYKillerEnableDanmakuColor"];
    [d removeObjectForKey:@"DYKillerFeedMenu"];
    [d removeObjectForKey:@"DYKillerFeedMenuCatalog"];
    [d removeObjectForKey:@"DYKillerFeedMenuColumns"];
    [d removeObjectForKey:@"DYKillerFeedMenuGlass"];
    [d removeObjectForKey:@"DYKillerFeedMenuGlassClear"];
    [d removeObjectForKey:@"DYKillerFilterAds"];
    [d removeObjectForKey:@"DYKillerFilterLowLikes"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedArticle"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedCreation"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedEcommerce"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedGame"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedHotspot"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedInterest"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedMerchantNote"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedMicroApp"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedMusic"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedSocial"];
    [d removeObjectForKey:@"DYKillerFilterRecommendedSpecialCard"];
    [d removeObjectForKey:@"DYKillerFollowButtonDisplayMode"];
    [d removeObjectForKey:@"DYKillerFriendAvatarEntryMode"];
    [d removeObjectForKey:@"DYKillerFriendButtonMode"];
    [d removeObjectForKey:@"DYKillerFriendDailyMode"];
    [d removeObjectForKey:@"DYKillerFriendFastReplyMode"];
    [d removeObjectForKey:@"DYKillerFriendFollowTagMode"];
    [d removeObjectForKey:@"DYKillerFriendRelationTagMode"];
    [d removeObjectForKey:@"DYKillerFriendRemoveRecommendCard"];
    [d removeObjectForKey:@"DYKillerFriendSendMessageMode"];
    [d removeObjectForKey:@"DYKillerFriendStoryTagMode"];
    [d removeObjectForKey:@"DYKillerGeoNamesRegister"];
    [d removeObjectForKey:@"DYKillerGeoNamesUsername"];
    [d removeObjectForKey:@"DYKillerGeoNamesWebServices"];
    [d removeObjectForKey:@"DYKillerGlassTabBar"];
    [d removeObjectForKey:@"DYKillerGlassTabBarClear"];
    [d removeObjectForKey:@"DYKillerGlassTabBarPadPosition"];
    [d removeObjectForKey:@"DYKillerHideChatVideoBottomBar"];
    [d removeObjectForKey:@"DYKillerHideCommentBottomBar"];
    [d removeObjectForKey:@"DYKillerHideFollowButton"];
    [d removeObjectForKey:@"DYKillerHideMusicInfo"];
    [d removeObjectForKey:@"DYKillerHideProfileUGCGuide"];
    [d removeObjectForKey:@"DYKillerInfoOffset"];
    [d removeObjectForKey:@"DYKillerInnerNotiCorner"];
    [d removeObjectForKey:@"DYKillerInnerNotiGlass"];
    [d removeObjectForKey:@"DYKillerInnerNotiGlassClear"];
    [d removeObjectForKey:@"DYKillerInteraction"];
    [d removeObjectForKey:@"DYKillerInteractionCommentIcon"];
    [d removeObjectForKey:@"DYKillerInteractionCommentStyle"];
    [d removeObjectForKey:@"DYKillerInteractionDisplay"];
    [d removeObjectForKey:@"DYKillerInteractionFavoriteAfterIcon"];
    [d removeObjectForKey:@"DYKillerInteractionFavoriteBeforeIcon"];
    [d removeObjectForKey:@"DYKillerInteractionFavoriteStyle"];
    [d removeObjectForKey:@"DYKillerInteractionIconAlpha"];
    [d removeObjectForKey:@"DYKillerInteractionLabelAlpha"];
    [d removeObjectForKey:@"DYKillerInteractionLikeAfterIcon"];
    [d removeObjectForKey:@"DYKillerInteractionLikeBeforeIcon"];
    [d removeObjectForKey:@"DYKillerInteractionLikeStyle"];
    [d removeObjectForKey:@"DYKillerInteractionOffset"];
    [d removeObjectForKey:@"DYKillerInteractionScale"];
    [d removeObjectForKey:@"DYKillerInteractionShareIcon"];
    [d removeObjectForKey:@"DYKillerInteractionShareStyle"];
    [d removeObjectForKey:@"DYKillerMediaSave"];
    [d removeObjectForKey:@"DYKillerMediaSaveAllImages"];
    [d removeObjectForKey:@"DYKillerMediaSaveChatSticker"];
    [d removeObjectForKey:@"DYKillerMediaSaveComment"];
    [d removeObjectForKey:@"DYKillerMediaSaveCommentSticker"];
    [d removeObjectForKey:@"DYKillerMediaSaveCover"];
    [d removeObjectForKey:@"DYKillerMediaSaveCurrentImage"];
    [d removeObjectForKey:@"DYKillerMediaSaveGlass"];
    [d removeObjectForKey:@"DYKillerMediaSaveGlassClear"];
    [d removeObjectForKey:@"DYKillerMediaSaveHaptic"];
    [d removeObjectForKey:@"DYKillerMediaSaveMusic"];
    [d removeObjectForKey:@"DYKillerMediaSaveVideo"];
    [d removeObjectForKey:@"DYKillerMessageDailyMode"];
    [d removeObjectForKey:@"DYKillerMessageFriendAvatarMode"];
    [d removeObjectForKey:@"DYKillerMessageInteractionMode"];
    [d removeObjectForKey:@"DYKillerMessagePlusMode"];
    [d removeObjectForKey:@"DYKillerMessageSearchMode"];
    [d removeObjectForKey:@"DYKillerMessageSideBarMode"];
    [d removeObjectForKey:@"DYKillerMessageSlotMode"];
    [d removeObjectForKey:@"DYKillerMinimumLikes"];
    [d removeObjectForKey:@"DYKillerMusicAlpha"];
    [d removeObjectForKey:@"DYKillerMusicDisplay"];
    [d removeObjectForKey:@"DYKillerMusicScale"];
    [d removeObjectForKey:@"DYKillerNicknameAlpha"];
    [d removeObjectForKey:@"DYKillerNicknameScale"];
    [d removeObjectForKey:@"DYKillerPageLiquidGlass"];
    [d removeObjectForKey:@"DYKillerPlayback"];
    [d removeObjectForKey:@"DYKillerPlaybackAppDownloadMode"];
    [d removeObjectForKey:@"DYKillerPlaybackChapterHighlightsMode"];
    [d removeObjectForKey:@"DYKillerPlaybackCoCreatorMode"];
    [d removeObjectForKey:@"DYKillerPlaybackDanmakuMode"];
    [d removeObjectForKey:@"DYKillerPlaybackFriendRecommendMode"];
    [d removeObjectForKey:@"DYKillerPlaybackFriendShareMode"];
    [d removeObjectForKey:@"DYKillerPlaybackFullscreenMode"];
    [d removeObjectForKey:@"DYKillerPlaybackGameTagMode"];
    [d removeObjectForKey:@"DYKillerPlaybackHotspotMode"];
    [d removeObjectForKey:@"DYKillerPlaybackJianyingMode"];
    [d removeObjectForKey:@"DYKillerPlaybackLocationMode"];
    [d removeObjectForKey:@"DYKillerPlaybackMusicAnchorMode"];
    [d removeObjectForKey:@"DYKillerPlaybackMusicInfoMode"];
    [d removeObjectForKey:@"DYKillerPlaybackOtherUserRecommendMode"];
    [d removeObjectForKey:@"DYKillerPlaybackPaidContentMode"];
    [d removeObjectForKey:@"DYKillerPlaybackPropEffectMode"];
    [d removeObjectForKey:@"DYKillerPlaybackQuickReplyMode"];
    [d removeObjectForKey:@"DYKillerPlaybackRelatedSearchMode"];
    [d removeObjectForKey:@"DYKillerPlaybackRelatedVideoMode"];
    [d removeObjectForKey:@"DYKillerPlaybackRemoveAllAnchors"];
    [d removeObjectForKey:@"DYKillerPlaybackRemoveAllBottomBars"];
    [d removeObjectForKey:@"DYKillerPlaybackRiskNoticeMode"];
    [d removeObjectForKey:@"DYKillerPlaybackSelectedMode"];
    [d removeObjectForKey:@"DYKillerPlaybackSlidesTagMode"];
    [d removeObjectForKey:@"DYKillerPlaybackStoreMode"];
    [d removeObjectForKey:@"DYKillerPlaybackVideoCollectionMode"];
    [d removeObjectForKey:@"DYKillerPlusIcon"];
    [d removeObjectForKey:@"DYKillerPlusStyle"];
    [d removeObjectForKey:@"DYKillerProfileAddFriendMode"];
    [d removeObjectForKey:@"DYKillerProfileAvatarPlusMode"];
    [d removeObjectForKey:@"DYKillerProfileCapsuleMode"];
    [d removeObjectForKey:@"DYKillerProfileEditMode"];
    [d removeObjectForKey:@"DYKillerProfileGuideBannerMode"];
    [d removeObjectForKey:@"DYKillerProfileRemoveDailyTab"];
    [d removeObjectForKey:@"DYKillerProfileRemoveFavoriteTab"];
    [d removeObjectForKey:@"DYKillerProfileRemoveFootprintTab"];
    [d removeObjectForKey:@"DYKillerProfileRemoveLikeTab"];
    [d removeObjectForKey:@"DYKillerProfileRemovePostTab"];
    [d removeObjectForKey:@"DYKillerProfileRemoveServiceArea"];
    [d removeObjectForKey:@"DYKillerProfileSearchMode"];
    [d removeObjectForKey:@"DYKillerProfileSettingsEntry"];
    [d removeObjectForKey:@"DYKillerProfileSettingsEntryName"];
    [d removeObjectForKey:@"DYKillerProfileShowPublishLocation"];
    [d removeObjectForKey:@"DYKillerProfileShowPublishTime"];
    [d removeObjectForKey:@"DYKillerProfileSideBarMode"];
    [d removeObjectForKey:@"DYKillerProfileStatsMode"];
    [d removeObjectForKey:@"DYKillerProfileSwitchAccountMode"];
    [d removeObjectForKey:@"DYKillerProfileVisitorMode"];
    [d removeObjectForKey:@"DYKillerProgressAlwaysVisible"];
    [d removeObjectForKey:@"DYKillerProgressTimeStyle"];
    [d removeObjectForKey:@"DYKillerPublishLocationColor"];
    [d removeObjectForKey:@"DYKillerPublishLocationColorMode"];
    [d removeObjectForKey:@"DYKillerPublishLocationFixedColor"];
    [d removeObjectForKey:@"DYKillerPublishLocationGradientColors"];
    [d removeObjectForKey:@"DYKillerPublishLocationHexColor"];
    [d removeObjectForKey:@"DYKillerPublishTextColors"];
    [d removeObjectForKey:@"DYKillerPublishTimeColor"];
    [d removeObjectForKey:@"DYKillerPublishTimeColorMode"];
    [d removeObjectForKey:@"DYKillerPublishTimeFixedColor"];
    [d removeObjectForKey:@"DYKillerPublishTimeGradientColors"];
    [d removeObjectForKey:@"DYKillerPublishTimeHexColor"];
    [d removeObjectForKey:@"DYKillerRemoveCommentSurvey"];
    [d removeObjectForKey:@"DYKillerRemoveRecommendedLive"];
    [d removeObjectForKey:@"DYKillerSearchCameraMode"];
    [d removeObjectForKey:@"DYKillerSearchRankCatalog"];
    [d removeObjectForKey:@"DYKillerSearchRanks"];
    [d removeObjectForKey:@"DYKillerSearchRemoveAllRanks"];
    [d removeObjectForKey:@"DYKillerSearchRemoveGuess"];
    [d removeObjectForKey:@"DYKillerSearchRemoveHistory"];
    [d removeObjectForKey:@"DYKillerSearchRemoveRankFooter"];
    [d removeObjectForKey:@"DYKillerSearchRemoveVoice"];
    [d removeObjectForKey:@"DYKillerShareMenu"];
    [d removeObjectForKey:@"DYKillerShareMenuCatalog"];
    [d removeObjectForKey:@"DYKillerSharePanelGlass"];
    [d removeObjectForKey:@"DYKillerSharePanelGlassClear"];
    [d removeObjectForKey:@"DYKillerShowPublishLocation"];
    [d removeObjectForKey:@"DYKillerShowPublishTime"];
    [d removeObjectForKey:@"DYKillerTabBarStyle"];
    [d removeObjectForKey:@"DYKillerTipsGlass"];
    [d removeObjectForKey:@"DYKillerTipsGlassClear"];
    [d removeObjectForKey:@"DYKillerTopBarAlpha"];
    [d removeObjectForKey:@"DYKillerTopBarSearchMode"];
    [d removeObjectForKey:@"DYKillerTopBarSideBarMode"];
    [d removeObjectForKey:@"DYKillerTopChannelCatalog"];
    [d removeObjectForKey:@"DYKillerTopChannels"];
    [d removeObjectForKey:@"DYKillerVideoFullscreen"];
    // ===== 新版新增的聊天相关功能：全部关闭 =====
    // 注意：DYKillerChatInputGlass / DYKillerChatInputGlassClear 是我们要开的玻璃，已在上面 setBool:YES，不移除
    [d removeObjectForKey:@"DYKillerChatRemoveEmojiSuggestions"];
    [d removeObjectForKey:@"DYKillerChatPlayEntryMode"];
    [d removeObjectForKey:@"DYKillerChatRemovePlusPhotos"];
    [d removeObjectForKey:@"DYKillerChatRemoveBack"];
    [d removeObjectForKey:@"DYKillerChatRemoveUnread"];
    [d removeObjectForKey:@"DYKillerChatRemoveMenu"];
    [d removeObjectForKey:@"DYKillerChatTopBlur"];
    [d removeObjectForKey:@"DYKillerChatTopCenter"];
    [d removeObjectForKey:@"DYKillerChatTopStreakPosition"];
    [d removeObjectForKey:@"DYKillerChatTopOnlinePosition"];
    [d removeObjectForKey:@"DYKillerChatRemoveOnline"];
    [d removeObjectForKey:@"DYKillerChatRemoveCall"];
    [d removeObjectForKey:@"DYKillerChatGroupZoneNoAutoExpand"];
    [d removeObjectForKey:@"DYKillerChatTopCustomPage"];
    [d removeObjectForKey:@"DYKillerMediaSaveChatSticker"];
    [d synchronize];
}

static __attribute__((constructor)) void DKInit(void){
    DKInstallHooks();
    DKForceAllPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{ DKInstallHooks(); DKForceAllPrefs(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKInstallHooks(); DKForceAllPrefs(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKInstallHooks(); DKForceAllPrefs(); });
    // 聊天页 cell/VC 类加载较晚：每秒重试安装气泡 hook，直到装好
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,q);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW,0), 1.0*NSEC_PER_SEC, 0.5*NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (!g_dbgInstalled) {
            dispatch_async(dispatch_get_main_queue(), ^{ DKInstallDebugHooks(); });
        } else {
            dispatch_source_cancel(timer);
        }
    });
    dispatch_resume(timer);
}