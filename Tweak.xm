// 抖音视频播放页 · 右侧六元素「清透液态玻璃」
// 玻璃配方照搬「长按倍速提示」玻璃（LongPressSpeedGlass 的 LJ_MakeEffect）:
//   UIGlassEffect effectWithStyle → UIVisualEffectView 垫底
//   + 白色高光渐变(0.10→0.0, locations 0/0.20, 竖向)
//   + 0.5pt 白色 0.25 描边
// 目标元素（debug 页面快照确认，都在 AWEPlayInteractionViewController 的
// AWEElementStackView{322,361.67,80,429} 竖排里）:
//   1 头像 AWEPlayInteractionUserProfilePictureView(48x48 圆形头像)
//   2 点赞 AWEFeedVideoButton(icon container 36x36)
//   3 评论 AWEFeedVideoButton
//   4 收藏 AWEFeedVideoButton
//   5 分享 AWEFeedVideoButton
//   6 音乐 AWEMusicCoverButton(44x44 唱片)
// 做法：直接 hook 这六类视图自己的 layoutSubviews，命中「右侧竖排里的那一份」就加玻璃；
//       另外 hook 竖排与 VC 的布局做全页兜底扫描。只插入我们自己创建的玻璃视图(index 0)，
//       不改动 app 任何子视图。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#define DK_TAG 20261106
#define DK_MAX_DEPTH 8

// ===== 长按倍速同款玻璃 effect =====
static UIVisualEffect *DKGlassEffect(void){
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
    if (!eff) { @try { eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]; } @catch(...){ eff = nil; } }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    return eff;
}

// 圆形玻璃盘：玻璃 + 高光 + 描边（与长按倍速一致）
static UIView *DKMakeDisc(CGFloat d){
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, d, d)];
    host.backgroundColor = [UIColor clearColor];
    host.userInteractionEnabled = NO;
    host.tag = DK_TAG;
    host.clipsToBounds = YES;
    host.layer.cornerRadius = d / 2.0;
    host.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    host.layer.borderWidth = 0.5;

    UIVisualEffect *eff = DKGlassEffect();
    if (eff) {
        UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
        vev.frame = host.bounds;
        vev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vev.userInteractionEnabled = NO;
        vev.layer.cornerRadius = d / 2.0;
        vev.clipsToBounds = YES;
        [host addSubview:vev];
    }
    CAGradientLayer *gl = [CAGradientLayer layer];
    gl.frame = host.bounds;
    gl.cornerRadius = d / 2.0;
    gl.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                  (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations = @[@0.0f, @0.20f];
    gl.startPoint = CGPointMake(0, 0);
    gl.endPoint = CGPointMake(0, 1);
    gl.zPosition = 0.1f;
    [host.layer addSublayer:gl];
    return host;
}

// 在 host 上保证存在一块以 (cx,cy) 为圆心、直径 d 的玻璃盘（只插一次，之后只更新位置）
static void DKApplyDiscAt(UIView *host, CGPoint center, CGFloat d){
    if (!host || d < 8) return;
    if (host.bounds.size.width < 16 || host.bounds.size.height < 16) return;
    if (isnan(center.x) || isnan(center.y)) return;
    CGRect r = CGRectMake(center.x - d / 2.0, center.y - d / 2.0, d, d);

    UIView *g = nil;
    for (UIView *sv in host.subviews) {
        if (sv.tag == DK_TAG) { g = sv; break; }
    }
    if (g && fabs((double)g.bounds.size.width - (double)d) > 0.5) { [g removeFromSuperview]; g = nil; }
    if (!g) {
        g = DKMakeDisc(d);
        [host insertSubview:g atIndex:0];
    }
    if (!CGRectEqualToRect(g.frame, r)) g.frame = r;
}

// 以 icon 为中心套玻璃盘
static void DKApplyDisc(UIView *host, UIView *icon, CGFloat d){
    if (!host || !icon || d < 8) return;
    CGRect iconRect;
    if (icon == host) {
        iconRect = host.bounds;
    } else {
        @try { iconRect = [icon convertRect:icon.bounds toView:host]; } @catch(...) { return; }
    }
    if (CGRectIsEmpty(iconRect)) return;
    if (isnan(iconRect.origin.x) || isnan(iconRect.origin.y)) return;
    DKApplyDiscAt(host, CGPointMake(CGRectGetMidX(iconRect), CGRectGetMidY(iconRect)), d);
}

// ===== 六元素识别 =====
static BOOL DKIsElementClass(NSString *cn){
    if (!cn) return NO;
    if ([cn isEqualToString:@"AWEFeedVideoButton"]) return YES;
    if ([cn isEqualToString:@"AWEPlayInteractionUserProfilePictureView"]) return YES;
    if ([cn isEqualToString:@"AWEMusicCoverButton"]) return YES;
    return NO;
}

// 统计家里是否有 >=3 个六元素类（用来认定"这是右侧竖排"，而不是别的页面上的同类按钮）
static int DKCountElements(UIView *root, int depth){
    if (!root || depth > 3) return 0;
    int n = 0;
    for (UIView *s in root.subviews) {
        if (DKIsElementClass(NSStringFromClass([s class]))) n++;
        n += DKCountElements(s, depth + 1);
        if (n >= 3) return n;
    }
    return n;
}

// 从某元素往上找右侧竖排（AWEElementStackView 且够高、且里面确实有多个六元素）
static UIView *DKFindRail(UIView *v){
    UIView *p = v;
    for (int i = 0; i < DK_MAX_DEPTH && p; i++) {
        NSString *cn = NSStringFromClass([p class]) ?: @"";
        if ([cn isEqualToString:@"AWEElementStackView"]) {
            if (p.bounds.size.height >= 150 && p.bounds.size.width >= 55 && p.bounds.size.width <= 130) {
                if (DKCountElements(p, 0) >= 3) return p;
            }
        }
        p = p.superview;
    }
    return nil;
}

// 去掉视图（及其一层子视图/子图层）上的描边——用来干掉抖音头像那圈细白线
static void DKClearBorder(UIView *v){
    if (!v) return;
    @try {
        v.layer.borderWidth = 0;
        for (CALayer *l in v.layer.sublayers) {
            if (l.borderWidth > 0) l.borderWidth = 0;
            for (CALayer *ll in l.sublayers) {
                if (ll.borderWidth > 0) ll.borderWidth = 0;
            }
        }
    } @catch(...) {}
}

// 头像专治：去掉头像自带白描边、藏掉「日常」彩环、头像这块玻璃不留描边
static void DKAvatarClean(UIView *host, UIView *btn){
    DKClearBorder(btn);
    if (btn) {
        for (UIView *s in btn.subviews) DKClearBorder(s);
    }
    for (UIView *s in host.subviews) {
        NSString *scn = NSStringFromClass([s class]) ?: @"";
        // AFDColorRingView / AFDColorRingGradientView / AFDColorRingCircleAnimationView = 日常彩环
        if ([scn hasPrefix:@"AFDColorRing"]) {
            s.hidden = YES;
            for (UIView *c in s.subviews) c.hidden = YES;
            continue;
        }
        if (s.tag == DK_TAG) s.layer.borderWidth = 0; // 头像玻璃不画白描边
    }
}

// 单个元素套玻璃
static void DKGlassOne(UIView *v){
    NSString *cn = NSStringFromClass([v class]) ?: @"";
    if ([cn isEqualToString:@"AWEFeedVideoButton"]) {
        // 点赞/评论/收藏/分享：icon 容器 36x36，玻璃盘 44
        UIView *icon = nil;
        @try { icon = (UIView *)[v valueForKey:@"containerView"]; } @catch(...) { icon = nil; }
        if (!icon || ![icon isKindOfClass:[UIView class]] || icon.bounds.size.width < 14) {
            icon = nil;
            for (UIView *s in v.subviews) {
                if (s.bounds.size.width >= 24 && s.bounds.size.width <= 48 &&
                    s.bounds.size.height >= 24 && s.bounds.size.height <= 48) { icon = s; break; }
            }
        }
        DKApplyDisc(v, icon ?: v, 44.0);
    } else if ([cn isEqualToString:@"AWEPlayInteractionUserProfilePictureView"]) {
        // 头像：多数视频 48x48、少部分 44x44；玻璃盘 56（与音乐唱片同尺寸）
        // 圆心必须取头像本体（AWEButton），跳过我们自己插的玻璃与「日常」彩环，
        // 否则会把玻璃自己当圆心，越摆越偏（29.44 之前部分视频不同心就是这个原因）
        UIView *icon = nil;
        for (UIView *s in v.subviews) {
            if (s.tag == DK_TAG) continue;
            NSString *scn = NSStringFromClass([s class]) ?: @"";
            if ([scn hasPrefix:@"AFDColorRing"]) continue;
            if ([scn isEqualToString:@"AWEButton"]) { icon = s; break; }
        }
        if (!icon) {
            for (UIView *s in v.subviews) {
                if (s.tag == DK_TAG) continue;
                NSString *scn = NSStringFromClass([s class]) ?: @"";
                if ([scn hasPrefix:@"AFDColorRing"]) continue;
                if (s.bounds.size.width >= 36 && s.bounds.size.width <= 60 &&
                    s.bounds.size.height >= 36 && s.bounds.size.height <= 60) { icon = s; break; }
            }
        }
        if (icon) {
            // 用头像本体的绝对矩形直接定圆心，避免二次换算误差
            CGRect btnRect = [icon convertRect:icon.bounds toView:v];
            DKApplyDiscAt(v, CGPointMake(CGRectGetMidX(btnRect), CGRectGetMidY(btnRect)), 56.0);
        } else {
            DKApplyDisc(v, v, 56.0);
        }
        DKAvatarClean(v, icon);
    } else if ([cn isEqualToString:@"AWEMusicCoverButton"]) {
        // 音乐唱片：44x44，玻璃盘 56
        DKApplyDisc(v, v, 56.0);
    }
}

// 遍历竖排，把里面的六元素全部套上玻璃
static void DKGlassRail(UIView *rail){
    if (!rail) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:rail];
    int guard = 0;
    while (stack.count > 0 && guard < 600) {
        guard++;
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if (DKIsElementClass(NSStringFromClass([v class]))) DKGlassOne(v);
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

// 全页兜底扫描：按"窗口坐标靠右 + 够高 + 内含多个六元素"认定竖排，不依赖类名与 frame.x
static void DKScanRoot(UIView *root){
    if (!root) return;
    UIView *win = root.window;
    if (!win) win = root;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    while (stack.count > 0 && guard < 2500) {
        guard++;
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        CGRect wr = v.frame;
        @try { wr = [v convertRect:v.bounds toView:win]; } @catch(...) { wr = v.frame; }
        if (wr.size.height >= 150 && wr.size.height <= 760 &&
            wr.size.width >= 55 && wr.size.width <= 130 &&
            wr.origin.x >= 250 && DKCountElements(v, 0) >= 3) {
            DKGlassRail(v);
            continue; // 已处理这棵子树
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

// ===== hooks =====
// 六元素自己的 layoutSubviews：只要它在右侧竖排里，就直接上玻璃（最可靠，不依赖竖排何时布局）
static void (*orig_elemLayout)(id, SEL);
static void hook_elemLayout(id self, SEL _cmd){
    if (orig_elemLayout) orig_elemLayout(self, _cmd);
    @try {
        UIView *v = (UIView *)self;
        UIView *rail = DKFindRail(v);
        if (rail) {
            DKGlassOne(v);
            DKGlassRail(rail); // 其它元素这次不一定触发布局，一起补
        }
    } @catch (NSException *e) {}
}

// 「日常」彩环：只要它布局一次就再藏起来，防止 app 在刷新时重新显示
static void (*orig_ringLayout)(id, SEL);
static void hook_ringLayout(id self, SEL _cmd){
    if (orig_ringLayout) orig_ringLayout(self, _cmd);
    @try { ((UIView *)self).hidden = YES; } @catch(...) {}
}

static void (*orig_railLayout)(id, SEL);
static void hook_railLayout(id self, SEL _cmd){
    if (orig_railLayout) orig_railLayout(self, _cmd);
    @try { DKGlassRail((UIView *)self); } @catch (NSException *e) {}
}

static void (*orig_piLayout)(id, SEL);
static void hook_piLayout(id self, SEL _cmd){
    if (orig_piLayout) orig_piLayout(self, _cmd);
    @try {
        UIViewController *vc = (UIViewController *)self;
        if ([vc isKindOfClass:[UIViewController class]] && [vc isViewLoaded]) DKScanRoot(vc.view);
    } @catch (NSException *e) {}
}

static void (*orig_piAppear)(id, SEL, BOOL);
static void hook_piAppear(id self, SEL _cmd, BOOL animated){
    if (orig_piAppear) orig_piAppear(self, _cmd, animated);
    @try {
        UIViewController *vc = (UIViewController *)self;
        if ([vc isKindOfClass:[UIViewController class]] && [vc isViewLoaded]) {
            UIView *root = vc.view;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                DKScanRoot(root);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                DKScanRoot(root);
            });
        }
    } @catch (NSException *e) {}
}

static BOOL g_hooked = NO;

static void DKTryInstall(void){
    if (g_hooked) return;
    @try {
        // 六元素自身
        Class btn = NSClassFromString(@"AWEFeedVideoButton");
        if (btn && !orig_elemLayout) {
            MSHookMessageEx(btn, sel_registerName("layoutSubviews"), (IMP)hook_elemLayout, (IMP *)&orig_elemLayout);
        }
        Class avatar = NSClassFromString(@"AWEPlayInteractionUserProfilePictureView");
        if (avatar && !orig_elemLayout) {
            MSHookMessageEx(avatar, sel_registerName("layoutSubviews"), (IMP)hook_elemLayout, (IMP *)&orig_elemLayout);
        }
        Class music = NSClassFromString(@"AWEMusicCoverButton");
        if (music && !orig_elemLayout) {
            MSHookMessageEx(music, sel_registerName("layoutSubviews"), (IMP)hook_elemLayout, (IMP *)&orig_elemLayout);
        }
        // 竖排兜底
        Class ring = NSClassFromString(@"AFDColorRingView");
        if (ring && !orig_ringLayout) {
            MSHookMessageEx(ring, sel_registerName("layoutSubviews"), (IMP)hook_ringLayout, (IMP *)&orig_ringLayout);
        }
        Class rail = NSClassFromString(@"AWEElementStackView");
        if (rail && !orig_railLayout) {
            MSHookMessageEx(rail, sel_registerName("layoutSubviews"), (IMP)hook_railLayout, (IMP *)&orig_railLayout);
        }
        // 页面级兜底
        Class pi = NSClassFromString(@"AWEPlayInteractionViewController");
        if (pi) {
            if (!orig_piLayout) MSHookMessageEx(pi, sel_registerName("viewDidLayoutSubviews"), (IMP)hook_piLayout, (IMP *)&orig_piLayout);
            if (!orig_piAppear) MSHookMessageEx(pi, sel_registerName("viewDidAppear:"), (IMP)hook_piAppear, (IMP *)&orig_piAppear);
        }
    } @catch(NSException *e) {}
    if (orig_elemLayout || orig_railLayout || orig_piLayout) g_hooked = YES;
}

static __attribute__((constructor)) void DKInit(void){
    DKTryInstall();
    dispatch_async(dispatch_get_main_queue(), ^{ DKTryInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKTryInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKTryInstall(); });
}
