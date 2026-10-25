//=============================================================================
//  DYKiller Comment Liquid Glass — 评论面板「液态玻璃·模糊玻璃模式」
//  移植自 DYKiller（液态玻璃）0.6.6.1
//
//  v1.2 修正（对照原版评论区）：
//   - 目标 = 整个评论面板（CommentContainerInnerViewController 内层容器），
//     玻璃作为最底层背景，评论列表浮在玻璃之上、清晰可读。
//   - 绝不挂全屏容器（AWECommentContainerViewController /
//     AWECommentFullScreenContainerViewController），避免盖住视频。
//   - 材质通透（UIGlassEffect 优先；退化用超薄模糊），绝不是白色实心整块。
//   - 默认开启、无开关。
//=============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

static Class clsGlassEffect;            // UIGlassEffect
static Class clsGlassContainerEffect;   // UIGlassContainerEffect
static Class clsBlurEffect;             // UIBlurEffect
static Class clsVisualEffectView;       // UIVisualEffectView

static CGFloat const kDKGBlurRadius   = 24.0;   // 液态玻璃模糊半径
static CGFloat const kDKGCornerRadius = 0.0;    // 面板贴边，不圆角

//-----------------------------------------------------------------------------
// DKCommentBarGlassView —— 评论面板背景的液态玻璃视图
// 插入到目标视图最底层，评论列表仍在上面。
//-----------------------------------------------------------------------------
@interface DKCommentBarGlassView : UIView
@end

@implementation DKCommentBarGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        [self _dk_applyGlassMaterial];
    }
    return self;
}

- (void)_dk_applyGlassMaterial {
    if (![self _dk_applyLiquidGlass]) {
        // 液态玻璃 API 不可用（非 iOS26 等）才退化为轻量模糊
        [self _dk_applyLightBlur];
    }
    self.layer.cornerRadius = kDKGCornerRadius;
    self.layer.masksToBounds = YES;
}

// iOS26 液态玻璃：UIGlassContainerEffect + UIGlassEffect（通透、非白色）
- (BOOL)_dk_applyLiquidGlass {
    clsGlassEffect          = NSClassFromString(@"UIGlassEffect");
    clsGlassContainerEffect = NSClassFromString(@"UIGlassContainerEffect");
    if (!clsGlassEffect || !clsGlassContainerEffect) return NO;

    id glassEffect = [[clsGlassEffect alloc] init];
    if (!glassEffect) return NO;

    @try {
        [glassEffect setValue:@(kDKGBlurRadius) forKey:@"blurRadius"];
        [glassEffect setValue:UIColor.clearColor forKey:@"tintColor"];   // 通透，不遮评论
    } @catch (NSException *e) {}

    id container = nil;
    SEL selEWG = NSSelectorFromString(@"effectWithGlassEffect:insideView:");
    if ([clsGlassContainerEffect respondsToSelector:selEWG]) {
        container = ((id (*)(id, SEL, id, id))objc_msgSend)(
            clsGlassContainerEffect, selEWG, glassEffect, self);
    } else {
        SEL selEW = NSSelectorFromString(@"effectWithGlassEffect:");
        if ([clsGlassContainerEffect respondsToSelector:selEW]) {
            container = ((id (*)(id, SEL, id))objc_msgSend)(
                clsGlassContainerEffect, selEW, glassEffect);
        }
    }
    if (!container) return NO;

    UIView *containerView = [container valueForKey:@"containerView"];
    if ([containerView isKindOfClass:UIView.class]) {
        containerView.frame = self.bounds;
        containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:containerView];
        return YES;
    }
    return NO;
}

// 轻量模糊退化（超薄材质，通透）
- (void)_dk_applyLightBlur {
    clsBlurEffect       = NSClassFromString(@"UIBlurEffect");
    clsVisualEffectView = NSClassFromString(@"UIVisualEffectView");
    if (!clsBlurEffect || !clsVisualEffectView) return;

    id blurEffect = [clsBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    UIVisualEffectView *blur = [[clsVisualEffectView alloc] initWithEffect:blurEffect];
    blur.frame = self.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:blur];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIView *sub in self.subviews) {
        sub.frame = self.bounds;
    }
}

@end

//-----------------------------------------------------------------------------
// 工具：把液态玻璃作为最底层插入目标视图
//-----------------------------------------------------------------------------
static void DKGApplyGlassToPanel(id target) {
    if (!target || ![target isKindOfClass:UIView.class]) return;
    UIView *view = (UIView *)target;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:DKCommentBarGlassView.class]) return;
    }
    DKCommentBarGlassView *glass =
        [[DKCommentBarGlassView alloc] initWithFrame:view.bounds];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 最底层：玻璃只做面板背景，评论列表仍在其上
    [view insertSubview:glass atIndex:0];
}

//-----------------------------------------------------------------------------
// Hook —— 评论面板内层容器（整个评论面板的玻璃背景）
//-----------------------------------------------------------------------------
static void (*origPanelLoad)(id, SEL);
static void hookPanelLoad(id self, SEL _cmd) {
    origPanelLoad(self, _cmd);
    id v = ((id(*)(id,SEL))objc_msgSend)(self, @selector(view));
    if (v) DKGApplyGlassToPanel(v);
}

static void (*origPanelLayout)(id, SEL);
static void hookPanelLayout(id self, SEL _cmd) {
    origPanelLayout(self, _cmd);
    id v = ((id(*)(id,SEL))objc_msgSend)(self, @selector(view));
    if (v) DKGApplyGlassToPanel(v);
}

%ctor {
    Class panel = NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController");
    if (panel) {
        MSHookMessageEx(panel, @selector(viewDidLoad),
            (IMP)&hookPanelLoad, (IMP *)&origPanelLoad);
        MSHookMessageEx(panel, @selector(viewDidLayoutSubviews),
            (IMP)&hookPanelLayout, (IMP *)&origPanelLayout);
    }
}
