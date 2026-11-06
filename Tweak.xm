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
// 只往这个竖排里插"我们自己创建的玻璃视图"(index 0)，不改动 app 任何子视图。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#define DK_TAG 20261106

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

// 在 host 上保证存在一块以 icon 为中心、直径 d 的玻璃盘（只插一次，之后只更新位置）
static void DKApplyDisc(UIView *host, UIView *icon, CGFloat d){
    if (!host || !icon || d < 8) return;
    if (host.bounds.size.width < 16 || host.bounds.size.height < 16) return;
    CGRect iconRect;
    if (icon == host) {
        iconRect = host.bounds;
    } else {
        @try { iconRect = [icon convertRect:icon.bounds toView:host]; } @catch(...) { return; }
    }
    if (CGRectIsEmpty(iconRect)) return;
    if (isnan(iconRect.origin.x) || isnan(iconRect.origin.y)) return;
    CGFloat cx = CGRectGetMidX(iconRect);
    CGFloat cy = CGRectGetMidY(iconRect);
    CGRect r = CGRectMake(cx - d / 2.0, cy - d / 2.0, d, d);

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

// 右侧竖排容器识别：AWEElementStackView，x 靠右、窄、够高
static BOOL DKIsRightRail(id v){
    if (!v || ![v isKindOfClass:[UIView class]]) return NO;
    if (![NSStringFromClass([(UIView *)v class]) isEqualToString:@"AWEElementStackView"]) return NO;
    UIView *uv = (UIView *)v;
    CGRect f = uv.frame;
    if (f.origin.x < 250) return NO;
    if (f.size.width < 55 || f.size.width > 130) return NO;
    if (f.size.height < 150) return NO;
    return YES;
}

// 遍历竖排，给六元素套玻璃
static void DKGlassRail(UIView *rail){
    if (!rail) return;
    if (rail.bounds.size.height < 100) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:rail];
    int guard = 0;
    while (stack.count > 0 && guard < 600) {
        guard++;
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        NSString *cn = NSStringFromClass([v class]) ?: @"";

        if ([cn isEqualToString:@"AWEFeedVideoButton"]) {
            // 点赞/评论/收藏/分享：icon 容器 36x36，玻璃盘 42（底边落在数字上方，不切字）
            UIView *icon = nil;
            @try { icon = (UIView *)[v valueForKey:@"containerView"]; } @catch(...) { icon = nil; }
            if (!icon || ![icon isKindOfClass:[UIView class]] || icon.bounds.size.width < 14) {
                icon = nil;
                for (UIView *s in v.subviews) {
                    if (s.bounds.size.width >= 24 && s.bounds.size.width <= 48 &&
                        s.bounds.size.height >= 24 && s.bounds.size.height <= 48) { icon = s; break; }
                }
            }
            DKApplyDisc(v, icon ?: v, 42.0);
        } else if ([cn isEqualToString:@"AWEPlayInteractionUserProfilePictureView"]) {
            // 头像：48x48 圆形头像本体，玻璃盘 64（留 8pt 玻璃边）
            UIView *icon = nil;
            for (UIView *s in v.subviews) {
                if (s.bounds.size.width >= 40 && s.bounds.size.width <= 60 &&
                    s.bounds.size.height >= 40 && s.bounds.size.height <= 60) { icon = s; break; }
            }
            DKApplyDisc(v, icon ?: v, 64.0);
        } else if ([cn isEqualToString:@"AWEMusicCoverButton"]) {
            // 音乐唱片：44x44，玻璃盘 56
            DKApplyDisc(v, v, 56.0);
        }

        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

// 在页面根视图里找竖排（可能有多个 cell 的副本，全部处理）
static void DKGlassRoot(UIView *root){
    if (!root) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    while (stack.count > 0 && guard < 2000) {
        guard++;
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if (DKIsRightRail(v)) DKGlassRail(v);
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

// ===== hooks =====
static void (*orig_railLayout)(id, SEL);
static void hook_railLayout(id self, SEL _cmd){
    if (orig_railLayout) orig_railLayout(self, _cmd);
    @try {
        if (DKIsRightRail(self)) {
            UIView *rail = (UIView *)self;
            DKGlassRail(rail);
            // 子元素可能稍后才布局完，再补一次玻璃位置（不动 app 视图）
            __weak UIView *wr = rail;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (wr) DKGlassRail(wr);
            });
        }
    } @catch (NSException *e) {}
}

static void (*orig_piLayout)(id, SEL);
static void hook_piLayout(id self, SEL _cmd){
    if (orig_piLayout) orig_piLayout(self, _cmd);
    @try {
        UIViewController *vc = (UIViewController *)self;
        UIView *root = nil;
        if ([vc isKindOfClass:[UIViewController class]] && [vc isViewLoaded]) root = vc.view;
        if (root) DKGlassRoot(root);
    } @catch (NSException *e) {}
}

static BOOL g_railHooked = NO;

static void DKTryInstall(void){
    if (g_railHooked) return;
    @try {
        Class railCls = NSClassFromString(@"AWEElementStackView");
        Class piCls = NSClassFromString(@"AWEPlayInteractionViewController");
        if (railCls && !orig_railLayout) {
            MSHookMessageEx(railCls, sel_registerName("layoutSubviews"), (IMP)hook_railLayout, (IMP *)&orig_railLayout);
        }
        if (piCls && !orig_piLayout) {
            MSHookMessageEx(piCls, sel_registerName("viewDidLayoutSubviews"), (IMP)hook_piLayout, (IMP *)&orig_piLayout);
        }
    } @catch (NSException *e) {}
    if (orig_railLayout || orig_piLayout) g_railHooked = YES;
}

static __attribute__((constructor)) void DKInit(void){
    DKTryInstall();
    dispatch_async(dispatch_get_main_queue(), ^{ DKTryInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKTryInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKTryInstall(); });
}
