//=============================================================================
//  DYKiller Comment Liquid Glass — 评论区输入条「液态玻璃·模糊玻璃模式」
//  移植自 DYKiller（液态玻璃）0.6.6.1
//
//  v1.1 修正：仅作用于「评论区输入条」本身，绝不整屏覆盖。
//   - 玻璃只挂在评论区输入条背景 AWECommentInputBackgroundView 上，
//     视频、评论列表、面板背景完全不受影响。
//   - 默认开启、无开关。
//
//  效果：底部输入条呈现 iOS26 液态玻璃（透明磨砂），优先 UIGlassEffect，
//         不可用时退化为轻量 UIVisualEffectView 模糊，避免整块白膜。
//=============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

static Class clsGlassEffect;            // UIGlassEffect
static Class clsGlassContainerEffect;   // UIGlassContainerEffect
static Class clsBlurEffect;             // UIBlurEffect
static Class clsVisualEffectView;       // UIVisualEffectView

static CGFloat const kDKGBlurRadius   = 20.0;   // 液态玻璃模糊半径（轻透）
static CGFloat const kDKGCornerRadius = 18.0;   // 输入条圆角

//-----------------------------------------------------------------------------
// DKCommentBarGlassView —— 评论区输入条背景上的液态玻璃视图
// 插入到目标视图最底层（不影响其上的输入控件），尺寸跟随目标。
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
    BOOL glassOK = [self _dk_applyLiquidGlass];
    if (!glassOK) {
        // 液态玻璃 API 不可用（非 iOS26 等）才退化为轻量模糊，避免白色整块
        [self _dk_applyLightBlur];
    }
    self.layer.cornerRadius = kDKGCornerRadius;
    self.layer.masksToBounds = YES;
}

// iOS26 液态玻璃：UIGlassContainerEffect + UIGlassEffect
- (BOOL)_dk_applyLiquidGlass {
    clsGlassEffect          = NSClassFromString(@"UIGlassEffect");
    clsGlassContainerEffect = NSClassFromString(@"UIGlassContainerEffect");
    if (!clsGlassEffect || !clsGlassContainerEffect) return NO;

    id glassEffect = [[clsGlassEffect alloc] init];
    if (!glassEffect) return NO;

    @try {
        [glassEffect setValue:@(kDKGBlurRadius) forKey:@"blurRadius"];
        // 让玻璃通透（不给白色），颜色淡
        [glassEffect setValue:UIColor.clearColor forKey:@"tintColor"];
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

// 轻量模糊退化（超薄材质 + 透明白），绝不是白色整块
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
// 工具：把玻璃作为最底层插入目标视图（不遮挡其上的输入控件）
//-----------------------------------------------------------------------------
static void DKGApplyGlassToInputBar(id target) {
    if (!target || ![target isKindOfClass:UIView.class]) return;
    UIView *view = (UIView *)target;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:DKCommentBarGlassView.class]) return;
    }
    DKCommentBarGlassView *glass =
        [[DKCommentBarGlassView alloc] initWithFrame:view.bounds];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 插到最底层：玻璃只做背景，输入控件仍在上面
    [view insertSubview:glass atIndex:0];
}

//-----------------------------------------------------------------------------
// Hook —— 仅评论区输入条背景
//-----------------------------------------------------------------------------
%hook AWECommentInputBackgroundView

- (void)layoutSubviews {
    %orig;
    DKGApplyGlassToInputBar(self);
}

%end

// 输入条容器（Swift，运行时 hook，仅挂背景不挂整屏）
static void (*origInputContainerLayout)(id, SEL);
static void hookInputContainerLayout(id self, SEL _cmd) {
    origInputContainerLayout(self, _cmd);
    // 在容器里找到输入条背景视图，只给它加玻璃
    if ([self isKindOfClass:UIView.class]) {
        UIView *container = (UIView *)self;
        for (UIView *sub in container.subviews) {
            if ([NSStringFromClass(sub.class) containsString:@"AWECommentInputBackgroundView"]) {
                DKGApplyGlassToInputBar(sub);
            }
        }
    }
}

%ctor {
    Class c1 = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputContainerView");
    if (c1) {
        MSHookMessageEx(c1, @selector(layoutSubviews),
            (IMP)&hookInputContainerLayout, (IMP *)&origInputContainerLayout);
    }
}
