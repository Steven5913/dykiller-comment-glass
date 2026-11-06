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

// ===== 图标风格：移植「奶蛙 / 红果短剧」右侧图标（柔彩双色）=====
// 奶蛙那套是闭源 dylib 里用 UIBezierPath 现画的矢量图标（无图片资源），
// 这里按它的配色与形态重绘同一套：未选中=线框，已选中=实心，柔彩双色（主色+提亮色）。
//   点赞 #E86880 / 评论 #78B8F8 / 收藏 #F0C058 / 分享 #88D0B8
typedef NS_ENUM(NSInteger, DKIconKind){ DKIconNone = 0, DKIconLike, DKIconComment, DKIconCollect, DKIconShare };

static UIView *DKFindRail(UIView *v);

static DKIconKind DKKindFromName(NSString *name){
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return DKIconNone;
    NSString *s = [name lowercaseString];
    if ([s rangeOfString:@"like"].location != NSNotFound) return DKIconLike;
    if ([s rangeOfString:@"comment"].location != NSNotFound) return DKIconComment;
    if ([s rangeOfString:@"collect"].location != NSNotFound) return DKIconCollect;
    if ([s rangeOfString:@"favorite"].location != NSNotFound) return DKIconCollect;
    if ([s rangeOfString:@"share"].location != NSNotFound) return DKIconShare;
    return DKIconNone;
}

static UIColor *DKHexColor(NSUInteger hex){
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                            green:((hex >> 8) & 0xFF) / 255.0
                             blue:(hex & 0xFF) / 255.0
                            alpha:1.0];
}

static UIColor *DKIconColor(DKIconKind k){
    switch (k) {
        case DKIconLike:    return DKHexColor(0xE86880);
        case DKIconComment: return DKHexColor(0x78B8F8);
        case DKIconCollect: return DKHexColor(0xF0C058);
        case DKIconShare:   return DKHexColor(0x88D0B8);
        default: return [UIColor whiteColor];
    }
}

// 柔彩第二色：同色相提亮
static UIColor *DKSoften(UIColor *c){
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return c;
    return [UIColor colorWithRed:MIN(1.0, r + 0.30) green:MIN(1.0, g + 0.30) blue:MIN(1.0, b + 0.30) alpha:a];
}

static UIBezierPath *DKHeartPath(void){
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(17, 29.5)];
    [p addCurveToPoint:CGPointMake(2.6, 12.2) controlPoint1:CGPointMake(12.4, 25.4) controlPoint2:CGPointMake(2.6, 20.4)];
    [p addCurveToPoint:CGPointMake(11.4, 4.2) controlPoint1:CGPointMake(2.6, 6.8) controlPoint2:CGPointMake(6.4, 4.2)];
    [p addCurveToPoint:CGPointMake(17, 7.4) controlPoint1:CGPointMake(14.4, 4.2) controlPoint2:CGPointMake(16.2, 5.4)];
    [p addCurveToPoint:CGPointMake(22.6, 4.2) controlPoint1:CGPointMake(17.8, 5.4) controlPoint2:CGPointMake(19.6, 4.2)];
    [p addCurveToPoint:CGPointMake(31.4, 12.2) controlPoint1:CGPointMake(27.6, 4.2) controlPoint2:CGPointMake(31.4, 6.8)];
    [p addCurveToPoint:CGPointMake(17, 29.5) controlPoint1:CGPointMake(31.4, 20.4) controlPoint2:CGPointMake(21.6, 25.4)];
    [p closePath];
    p.lineJoinStyle = kCGLineJoinRound;
    return p;
}

static UIBezierPath *DKBubblePath(void){
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.2, 5.6, 27.6, 19.2) cornerRadius:6.4];
    UIBezierPath *tail = [UIBezierPath bezierPath];
    [tail moveToPoint:CGPointMake(11.6, 24.4)];
    [tail addLineToPoint:CGPointMake(11.6, 29.6)];
    [tail addLineToPoint:CGPointMake(17.4, 24.4)];
    [tail closePath];
    [p appendPath:tail];
    p.lineJoinStyle = kCGLineJoinRound;
    return p;
}

static UIBezierPath *DKBookmarkPath(void){
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(8.6, 4.6)];
    [p addLineToPoint:CGPointMake(25.4, 4.6)];
    [p addLineToPoint:CGPointMake(25.4, 29.4)];
    [p addLineToPoint:CGPointMake(17.0, 23.4)];
    [p addLineToPoint:CGPointMake(8.6, 29.4)];
    [p closePath];
    p.lineJoinStyle = kCGLineJoinRound;
    return p;
}

static void DKPaperPlaneParts(UIBezierPath **outWing, UIBezierPath **outTail){
    UIBezierPath *w = [UIBezierPath bezierPath];
    [w moveToPoint:CGPointMake(30.6, 4.4)];
    [w addLineToPoint:CGPointMake(3.4, 15.6)];
    [w addLineToPoint:CGPointMake(15.0, 19.2)];
    [w closePath];
    w.lineJoinStyle = kCGLineJoinRound;
    UIBezierPath *t = [UIBezierPath bezierPath];
    [t moveToPoint:CGPointMake(30.6, 4.4)];
    [t addLineToPoint:CGPointMake(15.0, 19.2)];
    [t addLineToPoint:CGPointMake(13.2, 29.6)];
    [t closePath];
    t.lineJoinStyle = kCGLineJoinRound;
    if (outWing) *outWing = w;
    if (outTail) *outTail = t;
}

static void DKGradientFillPath(CGContextRef c, UIBezierPath *p, UIColor *from, UIColor *to){
    CGContextSaveGState(c);
    [p addClip];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *cols = @[(id)from.CGColor, (id)to.CGColor];
    CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
    if (g) {
        CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(0, 34), 0);
        CGGradientRelease(g);
    }
    CGColorSpaceRelease(cs);
    CGContextRestoreGState(c);
}

static void DKStrokePath(UIBezierPath *p, UIColor *color, CGFloat width){
    p.lineWidth = width;
    p.lineJoinStyle = kCGLineJoinRound;
    p.lineCapStyle = kCGLineCapRound;
    [color setStroke];
    [p stroke];
}

static UIImage *DKIconImage(DKIconKind k, BOOL filled){
    CGFloat side = 34.0;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc){
        CGContextRef c = rc.CGContext;
        UIColor *main = DKIconColor(k);
        UIColor *soft = DKSoften(main);
        if (k == DKIconLike) {
            UIBezierPath *p = DKHeartPath();
            if (filled) { DKGradientFillPath(c, p, soft, main); DKStrokePath(p, main, 1.0); }
            else { DKStrokePath(p, main, 2.2); }
        } else if (k == DKIconComment) {
            UIBezierPath *p = DKBubblePath();
            DKStrokePath(p, main, 2.2);
            [main setFill];
            CGFloat xs[3] = {10.8, 17.0, 23.2};
            for (int i = 0; i < 3; i++) {
                UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(xs[i] - 1.75, 13.4, 3.5, 3.5)];
                [dot fill];
            }
        } else if (k == DKIconCollect) {
            UIBezierPath *p = DKBookmarkPath();
            if (filled) { DKGradientFillPath(c, p, soft, main); DKStrokePath(p, main, 1.0); }
            else { DKStrokePath(p, main, 2.2); }
        } else if (k == DKIconShare) {
            UIBezierPath *w = nil, *t = nil;
            DKPaperPlaneParts(&w, &t);
            if (filled) {
                DKGradientFillPath(c, w, soft, main);
                DKStrokePath(w, main, 0.8);
                [main setFill];
                [t fill];
            } else {
                DKStrokePath(w, main, 2.2);
                DKStrokePath(t, main, 2.2);
            }
        }
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static const void *DKIconAppliedKey = &DKIconAppliedKey;

static UIImageView *DKIconImageView(UIView *btn){
    UIImageView *iv = nil;
    @try { iv = (UIImageView *)[btn valueForKey:@"aweImageView"]; } @catch(...) { iv = nil; }
    if ([iv isKindOfClass:[UIImageView class]]) return iv;
    @try {
        UIView *cv = (UIView *)[btn valueForKey:@"containerView"];
        for (UIView *s in cv.subviews) {
            if ([s isKindOfClass:[UIImageView class]]) return (UIImageView *)s;
        }
    } @catch(...) {}
    for (UIView *s in btn.subviews) {
        if ([s isKindOfClass:[UIImageView class]]) return (UIImageView *)s;
    }
    return nil;
}

// 把抖音原有的白色图标换成柔彩双色图标（只换图，不碰布局与交互）
static void DKRestyleIcon(UIView *btn){
    if (!btn) return;
    NSString *name = nil;
    @try { name = [btn valueForKey:@"imageNameString"]; } @catch(...) { name = nil; }
    DKIconKind k = DKKindFromName(name);
    if (k == DKIconNone) return;
    NSString *low = [name lowercaseString];
    BOOL on = ([low rangeOfString:@"selected"].location != NSNotFound) ||
              ([low rangeOfString:@"active"].location != NSNotFound) ||
              ([low rangeOfString:@".on"].location != NSNotFound);
    UIImageView *iv = DKIconImageView(btn);
    if (!iv) return;
    NSString *key = [NSString stringWithFormat:@"%ld|%d", (long)k, (int)on];
    NSString *old = objc_getAssociatedObject(btn, DKIconAppliedKey);
    if (old && [old isEqualToString:key] && iv.image) return;
    UIImage *img = DKIconImage(k, on);
    if (!img) return;
    @try {
        iv.image = img;
        objc_setAssociatedObject(btn, DKIconAppliedKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    } @catch(...) {}
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
        DKRestyleIcon(v); // 顺手换成「柔彩双色」图标
    } else if ([cn isEqualToString:@"AWEPlayInteractionUserProfilePictureView"]) {
        // 头像：48x48 圆形头像本体，玻璃盘 56（与音乐唱片同尺寸）
        UIView *icon = nil;
        for (UIView *s in v.subviews) {
            if (s.bounds.size.width >= 40 && s.bounds.size.width <= 60 &&
                s.bounds.size.height >= 40 && s.bounds.size.height <= 60) { icon = s; break; }
        }
        DKApplyDisc(v, icon ?: v, 56.0);
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

// app 自己重设图标时，清掉「已换过」的标记再重新上色，避免被覆盖回白色原图标
static void (*orig_setImage)(id, SEL, id);
static void hook_setImage(id self, SEL _cmd, id img){
    if (orig_setImage) orig_setImage(self, _cmd, img);
    @try {
        objc_setAssociatedObject(self, DKIconAppliedKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        UIView *v = (UIView *)self;
        if (DKFindRail(v)) DKRestyleIcon(v);
    } @catch (NSException *e) {}
}

static void (*orig_setImageName)(id, SEL, id);
static void hook_setImageName(id self, SEL _cmd, id name){
    if (orig_setImageName) orig_setImageName(self, _cmd, name);
    @try {
        objc_setAssociatedObject(self, DKIconAppliedKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        UIView *v = (UIView *)self;
        if (DKFindRail(v)) DKRestyleIcon(v);
    } @catch (NSException *e) {}
}

static void (*orig_setImageNameHDR)(id, SEL, id, id);
static void hook_setImageNameHDR(id self, SEL _cmd, id name, id hdr){
    if (orig_setImageNameHDR) orig_setImageNameHDR(self, _cmd, name, hdr);
    @try {
        objc_setAssociatedObject(self, DKIconAppliedKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        UIView *v = (UIView *)self;
        if (DKFindRail(v)) DKRestyleIcon(v);
    } @catch (NSException *e) {}
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
        if (btn) {
            if (!orig_setImage)
                MSHookMessageEx(btn, sel_registerName("setImage:"), (IMP)hook_setImage, (IMP *)&orig_setImage);
            if (!orig_setImageName)
                MSHookMessageEx(btn, sel_registerName("setImageNameString:"), (IMP)hook_setImageName, (IMP *)&orig_setImageName);
            if (!orig_setImageNameHDR)
                MSHookMessageEx(btn, sel_registerName("setImageNameString:hdrColor:"), (IMP)hook_setImageNameHDR, (IMP *)&orig_setImageNameHDR);
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
