// ForceDYKillerPrefs v5 — 只开 评论区玻璃 + 聊天页玻璃，其余 DYKiller 全关
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
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

// ===== 聊天消息气泡清透玻璃：逐字照搬长按倍速玻璃（LJ_MakeEffect + pill 配方）=====
#import <objc/runtime.h>
static char kDKBubbleGlassKey;
// ===== 气泡清透玻璃：彻底去背景 + 玻璃按气泡形状直接垫底（复刻长按倍速 LJ_MakeEffect 配方）=====
// 彻底清掉气泡原有深色渐变/图片背景，露出下方壁纸让玻璃透出
static void DKClearBubbleBackground(UIView *target){
    @try {
        target.backgroundColor = [UIColor clearColor];
        target.layer.backgroundColor = [UIColor clearColor].CGColor;
        target.layer.contents = nil;
        if ([target.layer isKindOfClass:[CAGradientLayer class]]) {
            CAGradientLayer *g = (CAGradientLayer*)target.layer;
            g.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor clearColor].CGColor];
        }
        NSArray *sls = [target.layer.sublayers copy];
        for (CALayer *sl in sls) {
            if ([sl isKindOfClass:[CAGradientLayer class]]) { sl.opacity = 0.0f; }
            else if (sl.contents == nil && sl.backgroundColor && [sl.sublayers count]==0) { sl.opacity = 0.0f; }
        }
    } @catch(NSException *e){}
}
// 复刻长按倍速 LJ_MakeEffect：UIGlassEffect effectWithStyle:{1,0,2} → ultraThin → Light
static UIVisualEffect *DKBubbleGlassEffect(void){
    UIVisualEffect *eff = nil;
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        SEL s = NSSelectorFromString(@"effectWithStyle:");
        if (s) {
            id (*msg)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
            NSInteger styles[] = {1, 0, 2};
            for (int i = 0; i < 3; i++) {
                @try { eff = msg(ge, s, styles[i]); } @catch(...) { eff = nil; }
                if (eff) break;
            }
        }
    }
    if (!eff) { @try { eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]; } @catch(...){ eff=nil; } }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    return eff;
}
// 给气泡套玻璃：玻璃直接作为气泡背景（frame=bounds、clip到气泡形状），文字保持在上
static void DKApplyGlassToView(UIView *target){
    if (!target || objc_getAssociatedObject(target, &kDKBubbleGlassKey)) return;
    if (target.bounds.size.width<10 || target.bounds.size.height<10) return;
    UIVisualEffect *eff = DKBubbleGlassEffect();
    if (!eff) return;
    DKClearBubbleBackground(target);
    // 让玻璃按气泡自身形状裁剪
    target.clipsToBounds = YES;
    // 模糊玻璃垫底
    UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
    vev.frame = target.bounds;
    vev.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    vev.userInteractionEnabled = NO;
    [target insertSubview:vev atIndex:0];
    // 白高光渐变（液态玻璃高光）：白0.10→0.0，locations{0,0.20}，竖向
    CAGradientLayer *gl = [CAGradientLayer layer];
    gl.frame = target.bounds;
    gl.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                  (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations = @[@0.0f, @0.20f];
    gl.startPoint = CGPointMake(0, 0);
    gl.endPoint = CGPointMake(0, 1);
    gl.zPosition = 0.1f;   // 垫在 vev 之上、文字之下
    [target.layer addSublayer:gl];
    // 细边框（液态玻璃描边）
    target.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    target.layer.borderWidth = 0.5;
    objc_setAssociatedObject(target, &kDKBubbleGlassKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// 递归找 cell 内所有气泡视图并逐个套玻璃
static void DKGlassifyCell(UIView *cell){
    if (!cell) return;
    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:cell];
    int guard=0;
    while (stack.count>0 && guard<800) {
        guard++;
        UIView *v = [stack lastObject]; [stack removeLastObject];
        NSString *cn = NSStringFromClass([v class]) ?: @"";
        NSString *lo = cn.lowercaseString;
        BOOL isBubble = [v isKindOfClass:NSClassFromString(@"AWEIMMessageBubbleGradientView")]
                     || [lo containsString:@"bubble"] || [lo containsString:@"skylight"];
        if (isBubble) {
            DKApplyGlassToView(v);
        } else {
            for (UIView *s in v.subviews) [stack addObject:s];
        }
    }
}
static void (*orig_bubbleLayoutSubviews)(id,SEL);
static void hook_bubbleLayoutSubviews(id self, SEL _cmd){
    orig_bubbleLayoutSubviews(self,_cmd);
    @try { DKApplyGlassToView(self); } @catch(NSException *e){}
}
// 兜底：hook 气泡 cell layoutSubviews，递归找气泡套玻璃
static void (*orig_cellLayoutSubviews)(id,SEL);
static void hook_cellLayoutSubviews(id self, SEL _cmd){
    orig_cellLayoutSubviews(self,_cmd);
    @try { DKGlassifyCell(self); } @catch(NSException *e){}
}
// hook 消息表格 cellForRowAtIndexPath → 覆盖所有 cell（对方+自己发的）
static id (*orig_tableCellForRow)(id,SEL,id,id);
static id hook_tableCellForRow(id self, SEL _cmd, id tv, id ip){
    id cell = orig_tableCellForRow(self,_cmd,tv,ip);
    @try { DKGlassifyCell(cell); } @catch(NSException *e){}
    return cell;
}
static BOOL g_bubbleHooksInstalled = NO;
static void DKInstallBubbleHooks(void){
    Class bubble = NSClassFromString(@"AWEIMMessageBubbleGradientView");
    if (bubble && !orig_bubbleLayoutSubviews) {
        MSHookMessageEx(bubble, sel_registerName("layoutSubviews"), (IMP)hook_bubbleLayoutSubviews, (IMP*)&orig_bubbleLayoutSubviews);
    }
    Class cell = NSClassFromString(@"AWEIMReusableCommonCell");
    if (cell && !orig_cellLayoutSubviews) {
        MSHookMessageEx(cell, sel_registerName("layoutSubviews"), (IMP)hook_cellLayoutSubviews, (IMP*)&orig_cellLayoutSubviews);
    }
    Class vc = NSClassFromString(@"AWEIMMessageBaseViewController");
    if (vc && !orig_tableCellForRow) {
        MSHookMessageEx(vc, sel_registerName("tableView:cellForRowAtIndexPath:"), (IMP)hook_tableCellForRow, (IMP*)&orig_tableCellForRow);
    }
    g_bubbleHooksInstalled = (orig_bubbleLayoutSubviews || orig_cellLayoutSubviews || orig_tableCellForRow);
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
    // 聊天气泡清透玻璃：hook 气泡本体视图 + 气泡 cell
    DKInstallBubbleHooks();
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
        if (!g_bubbleHooksInstalled) {
            dispatch_async(dispatch_get_main_queue(), ^{ DKInstallBubbleHooks(); });
        } else {
            dispatch_source_cancel(timer);
        }
    });
    dispatch_resume(timer);
}