//=============================================================================
//  DYKiller Comment Liquid Glass — 评论区液态玻璃「模糊玻璃模式」
//  移植自 DYKiller（液态玻璃）0.6.6.1
//
//  行为还原（自逆向）：
//   - 用一个包裹 UIGlassContainerEffect + UIGlassEffect(iOS 26 液态玻璃) 的自定义
//     玻璃视图，覆盖到评论区输入条 / 评论面板背景上；
//   - 「模糊玻璃模式」= 玻璃材质带模糊(blur)，对应 DYKiller 的 DYKillerCommentGlass；
//   - 默认开启、无开关（不做任何偏好读取）。
//
//  挂载点（DYKiller 实际 hook 的抖音类）：
//   - AWECommentInputBackgroundView                         评论区输入条背景（ObjC）
//   - AWECommentInputViewSwiftImpl.CommentInputContainerView（Swift，运行时 hook）
//   - AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController（Swift，运行时 hook）
//   - AWECommentContainerViewController                     （ObjC）
//   - AWECommentFullScreenContainerViewController           （ObjC）
//=============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

//-----------------------------------------------------------------------------
// iOS 26 私有液态玻璃类（运行时解析，避免头文件/链接依赖）
//-----------------------------------------------------------------------------
static Class clsGlassEffect;            // UIGlassEffect
static Class clsGlassContainerEffect;   // UIGlassContainerEffect
static Class clsBlurEffect;             // UIBlurEffect
static Class clsVisualEffectView;       // UIVisualEffectView

// 与 DYKiller 一致的模糊参数
static CGFloat const kDKGBlurRadius   = 28.0;   // 玻璃模糊半径
static CGFloat const kDKGCornerRadius = 16.0;   // 评论区输入条圆角

//-----------------------------------------------------------------------------
// DKCommentBarGlassView —— 评论区输入条的液态玻璃容器视图
// 忠实还原 DYKiller 的 DKCommentBarGlassView / DKGlassFlexView 结构：
//   自身是一个 UIView，内部持有一个 UIGlassContainerEffect 的 containerView，
//   并叠加一层 UIVisualEffectView 模糊层作为 fallback / 加强模糊。
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

// 核心：把液态玻璃容器效果挂到自身，并保证模糊
- (void)_dk_applyGlassMaterial {
    [self _dk_applyLiquidGlass];   // iOS 26 液态玻璃
    [self _dk_applyBlurBackdrop];  // 模糊玻璃模式的核心模糊层
    self.layer.cornerRadius = kDKGCornerRadius;
    self.layer.masksToBounds = YES;
}

// 应用 UIGlassContainerEffect + UIGlassEffect（iOS 26 液态玻璃）
- (BOOL)_dk_applyLiquidGlass {
    clsGlassEffect          = NSClassFromString(@"UIGlassEffect");
    clsGlassContainerEffect = NSClassFromString(@"UIGlassContainerEffect");
    if (!clsGlassEffect || !clsGlassContainerEffect) return NO;

    id glassEffect = [[clsGlassEffect alloc] init];
    if (!glassEffect) return NO;

    // 设置模糊（KVC 方式兼容不同系统版本；不可用则忽略）
    @try {
        [glassEffect setValue:@(kDKGBlurRadius) forKey:@"blurRadius"];
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

// 叠加一层 UIVisualEffectView 模糊层（模糊玻璃模式）
- (void)_dk_applyBlurBackdrop {
    clsBlurEffect       = NSClassFromString(@"UIBlurEffect");
    clsVisualEffectView = NSClassFromString(@"UIVisualEffectView");
    if (!clsBlurEffect || !clsVisualEffectView) return;

    id blurEffect = [clsBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
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
// 工具：确保视图被液态玻璃覆盖（已加过则不重复）
// 参数用 id，避免 forward class 类型转换问题
//-----------------------------------------------------------------------------
static void DKGApplyGlassToView(id target) {
    if (!target || ![target isKindOfClass:UIView.class]) return;
    UIView *view = (UIView *)target;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:DKCommentBarGlassView.class]) return;
    }
    DKCommentBarGlassView *glass =
        [[DKCommentBarGlassView alloc] initWithFrame:view.bounds];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:glass];
}

//-----------------------------------------------------------------------------
// Hooks —— ObjC 类用 Logos
//-----------------------------------------------------------------------------
%hook AWECommentInputBackgroundView

- (void)layoutSubviews {
    %orig;
    DKGApplyGlassToView(self);
}

%end

%hook AWECommentContainerViewController

- (void)viewDidLoad {
    %orig;
    DKGApplyGlassToView(((id(*)(id,SEL))objc_msgSend)(self, @selector(view)));
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKGApplyGlassToView(((id(*)(id,SEL))objc_msgSend)(self, @selector(view)));
}

%end

%hook AWECommentFullScreenContainerViewController

- (void)viewDidLoad {
    %orig;
    DKGApplyGlassToView(((id(*)(id,SEL))objc_msgSend)(self, @selector(view)));
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKGApplyGlassToView(((id(*)(id,SEL))objc_msgSend)(self, @selector(view)));
}

%end

//-----------------------------------------------------------------------------
// Hooks —— Swift 类用运行时 MSHookMessageEx（避免 Logos Swift warning）
//-----------------------------------------------------------------------------
static void (*origContainerLayout)(id, SEL);
static void hookContainerLayout(id self, SEL _cmd) {
    origContainerLayout(self, _cmd);
    DKGApplyGlassToView(self);
}

static void (*origInnerVCLoad)(id, SEL);
static void hookInnerVCLoad(id self, SEL _cmd) {
    origInnerVCLoad(self, _cmd);
    if ([self respondsToSelector:@selector(view)])
        DKGApplyGlassToView(((id(*)(id,SEL))objc_msgSend)(self, @selector(view)));
}

static void (*origInnerVCLayout)(id, SEL);
static void hookInnerVCLayout(id self, SEL _cmd) {
    origInnerVCLayout(self, _cmd);
    if ([self respondsToSelector:@selector(view)])
        DKGApplyGlassToView(((id(*)(id,SEL))objc_msgSend)(self, @selector(view)));
}

static void DKGHookClassMethod(Class cls, SEL sel, IMP hook, IMP *orig) {
    if (!cls || !sel) return;
    MSHookMessageEx(cls, sel, hook, orig);
}

%ctor {
    Class c1 = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputContainerView");
    if (c1) DKGHookClassMethod(c1, @selector(layoutSubviews),
        (IMP)&hookContainerLayout, (IMP *)&origContainerLayout);

    Class c2 = NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController");
    if (c2) {
        DKGHookClassMethod(c2, @selector(viewDidLoad), (IMP)&hookInnerVCLoad, (IMP *)&origInnerVCLoad);
        DKGHookClassMethod(c2, @selector(viewDidLayoutSubviews), (IMP)&hookInnerVCLayout, (IMP *)&origInnerVCLayout);
    }
}
