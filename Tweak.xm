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
// 需要强制开启的功能：玻璃 + 长按不弹出长按面板
static inline BOOL DKShouldForceOn(NSString *key){
    return DKIsGlass(key)
        || [key isEqualToString:@"DYKillerFeedMenuNoPanel"];    // 长按不弹出长按面板
}
static inline BOOL DKShouldForceOff(NSString *key){
    if (![key hasPrefix:@"DYKiller"]) return NO;
    if (DKShouldForceOn(key)) return NO;
    return YES;
}

static BOOL (*orig_boolForKey)(id,SEL,NSString*);
static BOOL hook_boolForKey(id self, SEL _cmd, NSString *key){
    if (DKShouldForceOn(key)) return YES;
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
    if (DKShouldForceOn(key)) return @YES;
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
static char kDKGlassGradKey;
// ===== 气泡清透玻璃：彻底去背景 + 玻璃按气泡形状直接垫底（复刻长按倍速 LJ_MakeEffect 配方）=====
// 彻底清掉气泡原有深色渐变/图片背景，露出下方壁纸让玻璃透出
// 判断颜色是否"深色"(亮度低且不透明)——用于只清深色背衬, 不动浅色内容层
static BOOL DKIsDarkColor(CGColorRef c){
    if (!c) return NO;
    if (CGColorGetAlpha(c) < 0.05) return NO;
    const CGFloat *cp = CGColorGetComponents(c);
    size_t n = CGColorGetNumberOfComponents(c);
    if (n >= 3) {
        CGFloat lum = 0.299*cp[0] + 0.587*cp[1] + 0.114*cp[2];
        return lum < 0.45;
    }
    return NO;
}
static void DKClearBubbleBackground(UIView *target){
    @try {
        target.backgroundColor = [UIColor clearColor];
        target.layer.backgroundColor = [UIColor clearColor].CGColor;
        // 注意: 不再清 target.layer.contents —— 分享评论卡片的大图(图文预览)是放在
        // 手势视图 layer.contents 里的, 清了会把卡片图片整个擦掉
        if ([target.layer isKindOfClass:[CAGradientLayer class]]) {
            CAGradientLayer *g = (CAGradientLayer*)target.layer;
            g.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor clearColor].CGColor];
        }
        NSArray *sls = [target.layer.sublayers copy];
        for (CALayer *sl in sls) {
            // 只清"深色"背衬子图层(气泡深色底), 不清浅色/内容图层, 避免误伤卡片内容
            if ([sl isKindOfClass:[CAGradientLayer class]]) {
                CAGradientLayer *g = (CAGradientLayer*)sl;
                if (g.colors.count && DKIsDarkColor((__bridge CGColorRef)g.colors[0])) sl.opacity = 0.0f;
            } else if (sl.contents == nil && sl.backgroundColor && [sl.sublayers count]==0) {
                if (DKIsDarkColor(sl.backgroundColor)) sl.opacity = 0.0f;
            }
        }
        // 隐藏气泡内的背景图片子视图(如自己消息的蓝色 UIImageView 背景)，保留玻璃/文字/已知容器
        // 注意: 不隐藏普通 UIView(回复/引用框等可能是普通 UIView)，避免误伤
        NSArray *subs = [target.subviews copy];
        for (UIView *sv in subs) {
            if (sv.hidden) continue;
            NSString *scn = NSStringFromClass([sv class]) ?: @"";
            BOOL isGlass = [sv isKindOfClass:[UIVisualEffectView class]];
            BOOL isText = [scn containsString:@"Label"] || [scn containsString:@"Text"] || [scn containsString:@"Button"];
            BOOL isKnown = [scn containsString:@"Bubble"] || [scn containsString:@"Gradient"]
                        || [scn containsString:@"Gesture"] || [scn containsString:@"Cell"];
            if (isGlass || isText || isKnown) continue;
            if ([sv isKindOfClass:[UIImageView class]]) {
                // 只隐藏"铺满目标"的背景图片(如自己消息的蓝色背景图)；
                // 保留卡片内的小预览图(分享评论卡片里的图/视频封面), 避免内容被隐藏
                CGFloat rw = sv.bounds.size.width / MAX(target.bounds.size.width,1.0f);
                CGFloat rh = sv.bounds.size.height / MAX(target.bounds.size.height,1.0f);
                if (rw >= 0.85 && rh >= 0.85) {
                    sv.hidden = YES;
                    sv.alpha = 0.0f;
                }
            }
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
// 给气泡套玻璃：真正的深色圆角气泡是内层(AWEIMMessageBubbleGradientView)的父视图(圆角容器 r8)
// 深色背景 = 渐变视图.backgroundColor(动态深色) + 父视图一个深色子图层；app 每次 layout 会重设
// → 每次 layoutSubviews 都无条件清背景(对抗重设)，玻璃只插一次
static BOOL DKIsFullCellGesture(UIView *v) __attribute__((unused));   // 前置声明
static void DKRemoveGlass(UIView *v) __attribute__((unused));         // 前置声明
static void DKApplyGlassToView(UIView *target){
    if (!target) return;
    // 目标本身是整格外层手势 → 只清+移除其上玻璃, 不套新玻璃(去掉大的那层)
    if (DKIsFullCellGesture(target)) { DKRemoveGlass(target); return; }
    UIView *container = target.superview;
    // 整格外层手势不当作圆角容器(避免把玻璃套到整格)
    BOOL useContainer = NO;
    if (container && container.layer.cornerRadius > 0 &&
        container.bounds.size.width >= 10 && container.bounds.size.height >= 10 &&
        !DKIsFullCellGesture(container)) {
        useContainer = YES;
    }
    UIView *glassTarget = useContainer ? container : target;
    if (glassTarget.bounds.size.width<10 || glassTarget.bounds.size.height<10) return;
    // 若容器是整格外层手势, 清掉它上面可能残留的旧玻璃(消息层继续照常套)
    if (DKIsFullCellGesture(container)) DKRemoveGlass(container);
    // ★ 每次都清背景：对抗 app 在 layoutSubviews 里重设深色背景
    if (useContainer) {
        DKClearBubbleBackground(container);
        DKClearBubbleBackground(target);
    } else {
        DKClearBubbleBackground(target);
    }
    // 玻璃按气泡形状裁剪：胶囊圆角(高度/2，与长按倍速玻璃一致)
    CGFloat radius = glassTarget.bounds.size.height / 2.0;
    if (radius > 22) radius = 22;   // 多行长气泡限制圆角上限，避免过度胶囊
    // 已有一层匹配玻璃且无残留 → 直接返回(背景已清)，避免重复/叠加
    BOOL hasMatch = NO;
    for (UIView *sv in glassTarget.subviews) {
        if ([sv isKindOfClass:[UIVisualEffectView class]] &&
            CGRectEqualToRect(sv.frame, glassTarget.bounds) &&
            fabs(sv.layer.cornerRadius - radius) < 0.5) { hasMatch = YES; break; }
    }
    if (hasMatch) {
        // 检查 GV/容器 另一处是否有残留旧玻璃(useContainer 翻转残留)
        BOOL hasStale = NO;
        for (UIView *base in @[target, container]) {
            if (!base || base == glassTarget) continue;
            for (UIView *sv in base.subviews)
                if ([sv isKindOfClass:[UIVisualEffectView class]]) { hasStale = YES; break; }
        }
        if (!hasStale) return;
    }
    // 存在残留/不匹配 → 移除 GV 与容器上所有旧玻璃与旧高光，保证只插一层
    for (UIView *base in @[target, container]) {
        if (!base) continue;
        NSArray *subs2 = [base.subviews copy];
        for (UIView *sv in subs2) {
            if ([sv isKindOfClass:[UIVisualEffectView class]]) [sv removeFromSuperview];
        }
        NSArray *sls2 = [base.layer.sublayers copy];
        for (CALayer *sl in sls2) {
            if (objc_getAssociatedObject(sl, &kDKGlassGradKey)) [sl removeFromSuperlayer];
        }
    }
    UIVisualEffect *eff = DKBubbleGlassEffect();
    if (!eff) return;
    glassTarget.clipsToBounds = YES;
    glassTarget.layer.cornerRadius = radius;
    // 模糊玻璃垫底（自身带圆角+裁剪，让模糊按圆角显示）
    UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
    vev.frame = glassTarget.bounds;
    vev.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    vev.userInteractionEnabled = NO;
    vev.layer.cornerRadius = radius;
    vev.clipsToBounds = YES;
    [glassTarget insertSubview:vev atIndex:0];
    // 白高光渐变（液态玻璃高光）：白0.10→0.0，locations{0,0.20}，竖向
    CAGradientLayer *gl = [CAGradientLayer layer];
    gl.frame = glassTarget.bounds;
    gl.cornerRadius = radius;
    gl.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                  (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations = @[@0.0f, @0.20f];
    gl.startPoint = CGPointMake(0, 0);
    gl.endPoint = CGPointMake(0, 1);
    gl.zPosition = 0.1f;   // 垫在 vev 之上、文字之下
    objc_setAssociatedObject(gl, &kDKGlassGradKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [glassTarget.layer addSublayer:gl];
    // 细边框（液态玻璃描边）
    glassTarget.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    glassTarget.layer.borderWidth = 0.5;
    objc_setAssociatedObject(glassTarget, &kDKBubbleGlassKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// 整格外层手势视图: AWEIMGestureView 横跨整格(宽>=300) → 绝不给它套玻璃, 只清背景+移除已有玻璃
static BOOL DKIsFullCellGesture(UIView *v){
    if (!v) return NO;
    if ([NSStringFromClass([v class]) isEqualToString:@"AWEIMGestureView"] &&
        v.bounds.size.width >= 300 && v.bounds.size.height >= 30) return YES;
    return NO;
}
// 移除某视图上的玻璃与高光, 并清背景
static void DKRemoveGlass(UIView *v){
    if (!v) return;
    for (UIView *sv in [v.subviews copy])
        if ([sv isKindOfClass:[UIVisualEffectView class]]) [sv removeFromSuperview];
    for (CALayer *sl in [v.layer.sublayers copy])
        if (objc_getAssociatedObject(sl, &kDKGlassGradKey)) [sl removeFromSuperlayer];
    DKClearBubbleBackground(v);
}
// 媒体消息识别: 气泡子树含大图(>=80x80)或 AVPlayerLayer → 视频/图片消息, 不套玻璃避免遮住封面
static BOOL DKIsMediaBubble(UIView *root){
    if (!root) return NO;
    NSMutableArray *stack=[NSMutableArray array]; [stack addObject:root];
    int guard=0;
    while (stack.count && guard<600) {
        guard++; UIView *v=[stack lastObject]; [stack removeLastObject];
        if ([NSStringFromClass([v.layer class]) isEqualToString:@"AVPlayerLayer"]) return YES;
        if ([v isKindOfClass:[UIImageView class]] &&
            v.bounds.size.width>=80 && v.bounds.size.height>=80) return YES;
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return NO;
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
        // 整格外层手势视图: 总是移除其上玻璃+高光+清背景(去掉大的那层), 但继续递归找内部消息气泡
        BOOL isFullCell = DKIsFullCellGesture(v);
        if (isFullCell) DKRemoveGlass(v);
        BOOL isBubble = [v isKindOfClass:NSClassFromString(@"AWEIMMessageBubbleGradientView")]
                     || [lo containsString:@"bubble"] || [lo containsString:@"skylight"];
        // 富媒体卡片气泡(分享/图文): 内部 AWEIMGestureView 带深色背景 → 也是气泡背景
        BOOL isDarkGesture = [cn isEqualToString:@"AWEIMGestureView"]
                          && v.backgroundColor
                          && ![v.backgroundColor isEqual:[UIColor clearColor]]
                          && v.bounds.size.width>=80 && v.bounds.size.height>=30;
        if (isBubble) {
            if (!DKIsMediaBubble(v)) DKApplyGlassToView(v);   // 视频/图片消息跳过玻璃
        } else if (isDarkGesture && !isFullCell) {
            UIView *bubbleView = v.superview ?: v;
            if (!DKIsMediaBubble(bubbleView)) {               // 媒体消息跳过，避免遮住封面
                DKClearBubbleBackground(v);
                if (v.superview) DKApplyGlassToView(v.superview);
            }
        }
        // 递归子视图(整格外层手势内含消息气泡, 需继续找到它套消息玻璃)
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}
static void (*orig_bubbleLayoutSubviews)(id,SEL);
static void DKShowDebugTree(UIView *cell) __attribute__((unused));   // 前置声明
static void hook_bubbleLayoutSubviews(id self, SEL _cmd){
    orig_bubbleLayoutSubviews(self,_cmd);
    // @try { DKDebugBubbleContainer(self); } @catch(NSException *e){}   // 调试标签已关闭
    @try { DKApplyGlassToView(self); } @catch(NSException *e){}
}
// 兜底：hook 气泡 cell layoutSubviews，递归找气泡套玻璃
static void (*orig_cellLayoutSubviews)(id,SEL);
// ===== 调试：把消息视图树(类/frame/layer类型/圆角/隐藏)显示到屏幕 =====
static UILabel *g_dbgLabel = nil;
static void DKShowDebugTree(UIView *cell){
    return;   // 识别类名调试已去除
    if (!cell) return;
    NSMutableString *s = [NSMutableString string];
    // 从 cell 向上到 window 的父级链
    UIView *p = cell;
    while (p && s.length<700) {
        NSString *cn = NSStringFromClass([p class]) ?: @"?";
        NSString *lc = NSStringFromClass([p.layer class]) ?: @"?";
        [s appendFormat:@"\n[↑%@] %@ r%.1f%.0fx%.0f%@",
         cn, lc, p.layer.cornerRadius, p.bounds.size.width, p.bounds.size.height,
         (p.hidden||p.alpha<0.01)?@"H":@""];
        p = p.superview;
    }
    // 向下遍历所有子视图
    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:cell];
    int guard=0;
    while (stack.count>0 && s.length<1300 && guard<200) {
        guard++;
        UIView *v = [stack lastObject]; [stack removeLastObject];
        NSString *cn = NSStringFromClass([v class]) ?: @"?";
        NSString *lc = NSStringFromClass([v.layer class]) ?: @"?";
        [s appendFormat:@"\n[↓%@] %@ r%.1f %.0fx%.0f %@",
         cn, lc, v.layer.cornerRadius, v.bounds.size.width, v.bounds.size.height,
         (v.hidden||v.alpha<0.01)?@"H":@""];
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    @try {
        UIWindow *w = cell.window;
        if (!w) w = [[[UIApplication sharedApplication] windows] lastObject];
        if (!w) return;
        if (!g_dbgLabel) {
            g_dbgLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 100, 360, 200)];
            g_dbgLabel.numberOfLines = 0;
            g_dbgLabel.font = [UIFont systemFontOfSize:8];
            g_dbgLabel.textColor = [UIColor blackColor];
            g_dbgLabel.backgroundColor = [[UIColor yellowColor] colorWithAlphaComponent:0.92];
            g_dbgLabel.layer.borderWidth = 1;
            g_dbgLabel.layer.borderColor = [UIColor redColor].CGColor;
            g_dbgLabel.userInteractionEnabled = NO;
        }
        g_dbgLabel.text = s;
        CGRect f = g_dbgLabel.frame;
        CGFloat h = [s boundingRectWithSize:CGSizeMake(360, CGFLOAT_MAX)
                   options:NSStringDrawingUsesLineFragmentOrigin
                   attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:8]}
                   context:nil].size.height;
        f.size.height = MIN(h+8, 700);
        g_dbgLabel.frame = f;
        [w addSubview:g_dbgLabel];
        [w bringSubviewToFront:g_dbgLabel];
    } @catch(NSException *e){}
}
static void DKDebugOwnBubbles(UIView *cell) __attribute__((unused));   // 前置声明
static void hook_cellLayoutSubviews(id self, SEL _cmd){
    orig_cellLayoutSubviews(self,_cmd);
    @try { DKGlassifyCell(self); } @catch(NSException *e){}
    // @try { DKDebugOwnBubbles(self); } @catch(NSException *e){}   // 识别类名调试已去除
}
// ===== 专项调试：dump 含分享卡片(AWEIMFeedInfoCardView)的 cell, 看内容(图/文)是否被隐藏或覆盖 =====
static void DKDebugOwnBubbles(UIView *cell){
    return;   // 识别类名调试已去除
    if (!cell) return;
    // 只 dump 含分享卡片/Feed 的 cell
    BOOL hasCard = NO;
    NSMutableArray *probe=[NSMutableArray array]; [probe addObject:cell];
    int pg=0;
    while (probe.count && pg<400) { pg++; UIView *v=[probe lastObject]; [probe removeLastObject];
        NSString *cn=NSStringFromClass([v class])?:@"";
        if ([cn containsString:@"Feed"] || [cn containsString:@"Card"]) { hasCard=YES; break; }
        for (UIView *sub in v.subviews) [probe addObject:sub];
    }
    if (!hasCard) return;
    NSMutableString *s=[NSMutableString string];
    [s appendFormat:@"\n== CARDCELL %@ %.0fx%.0f ==", NSStringFromClass([cell class]),
     cell.bounds.size.width, cell.bounds.size.height];
    NSMutableArray *stack=[NSMutableArray array]; [stack addObject:cell];
    int guard=0;
    while (stack.count && s.length<1100 && guard<300) {
        guard++; UIView *v=[stack lastObject]; [stack removeLastObject];
        NSString *cn=NSStringFromClass([v class])?:@"?";
        NSString *state = (v.hidden||v.alpha<0.05) ? @"HIDDEN" : @"";
        NSString *lstate = [NSString stringWithFormat:@"lop=%.2f", v.layer.opacity];
        NSString *imgState = @"";
        if ([v isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView*)v;
            imgState = (iv.image ? [NSString stringWithFormat:@"IMG %.0fx%.0f", iv.image.size.width, iv.image.size.height]
                        : (v.layer.contents ? @"LAYERCONT" : @"NOIMG"));
        }
        [s appendFormat:@"\n%@ f%.0f,%.0f %.0fx%.0f r%.1f %@ bg=%@ %@ %@ %@",
         cn, v.frame.origin.x, v.frame.origin.y, v.bounds.size.width, v.bounds.size.height,
         v.layer.cornerRadius, NSStringFromClass([v.layer class])?:@"?",
         v.backgroundColor, state, lstate, imgState];
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    @try {
        UIWindow *w = cell.window ?: [[[UIApplication sharedApplication] windows] lastObject];
        if (!w) return;
        if (!g_dbgLabel) {
            g_dbgLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 60, 380, 240)];
            g_dbgLabel.numberOfLines = 0;
            g_dbgLabel.font = [UIFont systemFontOfSize:8];
            g_dbgLabel.textColor = [UIColor blackColor];
            g_dbgLabel.backgroundColor = [[UIColor yellowColor] colorWithAlphaComponent:0.95];
            g_dbgLabel.layer.borderWidth = 1;
            g_dbgLabel.layer.borderColor = [UIColor redColor].CGColor;
            g_dbgLabel.userInteractionEnabled = NO;
        }
        // 累积打印(保留最近 2300 字符), 不覆盖
        NSString *old = g_dbgLabel.text ?: @"";
        NSString *combined = [old stringByAppendingString:s];
        if (combined.length > 2300) combined = [combined substringFromIndex:combined.length-2300];
        g_dbgLabel.text = combined;
        CGRect f = g_dbgLabel.frame;
        CGFloat h = [combined boundingRectWithSize:CGSizeMake(380, CGFLOAT_MAX)
                   options:NSStringDrawingUsesLineFragmentOrigin
                   attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:8]}
                   context:nil].size.height;
        f.size.height = MIN(h+8, 780);
        g_dbgLabel.frame = f;
        [w addSubview:g_dbgLabel];
        [w bringSubviewToFront:g_dbgLabel];
    } @catch(NSException *e){}
}
// hook 消息表格 cellForRowAtIndexPath → 覆盖所有 cell（对方+自己发的）
static id (*orig_tableCellForRow)(id,SEL,id,id);
static id hook_tableCellForRow(id self, SEL _cmd, id tv, id ip){
    id cell = orig_tableCellForRow(self,_cmd,tv,ip);
    @try { DKGlassifyCell(cell); } @catch(NSException *e){}
    return cell;
}
// ===== 聊天长按操作面板清透玻璃：给面板主体套玻璃（同气泡玻璃配方）=====
// 递归清面板子树内所有不透明背景与深色子图层，让玻璃彻底透出
static void DKClearPanelDeepBackground(UIView *root){
    if(!root) return;
    NSMutableArray *stack=[NSMutableArray array]; [stack addObject:root];
    int guard=0;
    while (stack.count && guard<600){
        guard++; UIView *v=[stack lastObject]; [stack removeLastObject];
        if ([v isKindOfClass:[UIVisualEffectView class]]) continue;   // 保留玻璃层
        if (![v isKindOfClass:[UIImageView class]]) v.backgroundColor=[UIColor clearColor];
        v.layer.backgroundColor=[UIColor clearColor].CGColor;
        for (CALayer *sl in [v.layer.sublayers copy]) {
            if ([sl isKindOfClass:[CAGradientLayer class]]) {
                CAGradientLayer *g=(CAGradientLayer*)sl;
                if (g.colors.count && DKIsDarkColor((__bridge CGColorRef)g.colors[0])) sl.opacity=0.0f;
            } else if (sl.contents==nil && sl.backgroundColor && [sl.sublayers count]==0) {
                if (DKIsDarkColor(sl.backgroundColor)) sl.opacity=0.0f;
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}
static BOOL (*orig_emojiMenuLayoutSubviews)(id,SEL);
static void DKApplyGlassToPanel(UIView *panel){
    if (!panel) return;
    if (panel.bounds.size.width<10 || panel.bounds.size.height<10) return;
    DKClearBubbleBackground(panel);
    // 已有一层匹配玻璃 → 仅清背景返回(避免重复/叠加)
    for (UIView *sv in panel.subviews)
        if ([sv isKindOfClass:[UIVisualEffectView class]] &&
            CGRectEqualToRect(sv.frame, panel.bounds)) return;
    // 移除旧玻璃与高光
    for (UIView *sv in [panel.subviews copy])
        if ([sv isKindOfClass:[UIVisualEffectView class]]) [sv removeFromSuperview];
    for (CALayer *sl in [panel.layer.sublayers copy])
        if (objc_getAssociatedObject(sl,&kDKGlassGradKey)) [sl removeFromSuperlayer];
    // 递归清面板内所有不透明背景与深色子图层, 让玻璃彻底透出
    DKClearPanelDeepBackground(panel);
    UIVisualEffect *eff=DKBubbleGlassEffect(); if(!eff) return;
    panel.clipsToBounds=YES;
    CGFloat radius=panel.layer.cornerRadius>0?panel.layer.cornerRadius:22.0f;
    if (radius>22) radius=22;
    panel.layer.cornerRadius=radius;
    UIVisualEffectView *vev=[[UIVisualEffectView alloc] initWithEffect:eff];
    vev.frame=panel.bounds;
    vev.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    vev.userInteractionEnabled=NO;
    vev.layer.cornerRadius=radius; vev.clipsToBounds=YES;
    [panel insertSubview:vev atIndex:0];
    CAGradientLayer *gl=[CAGradientLayer layer];
    gl.frame=panel.bounds; gl.cornerRadius=radius;
    gl.colors=@[(id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations=@[@0.0f,@0.20f];
    gl.startPoint=CGPointMake(0,0); gl.endPoint=CGPointMake(0,1); gl.zPosition=0.1f;
    objc_setAssociatedObject(gl,&kDKGlassGradKey,@(YES),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [panel.layer addSublayer:gl];
    panel.layer.borderColor=[UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    panel.layer.borderWidth=0.5;
}
// 胶囊玻璃(快捷回复表情小胶囊/回个心互动按钮)：ultraThin模糊 + 淡白高光(0.06)增强玻璃质感、不遮文字图标；halfH=YES 圆角按高度一半
__attribute__((unused)) static void DKApplyGlassToCap(UIView *panel, BOOL halfH){
    if (!panel) return;
    if (panel.bounds.size.width<10 || panel.bounds.size.height<10) return;
    // 只清胶囊自身背景，绝不动子视图(图标/文字)
    panel.backgroundColor=[UIColor clearColor];
    panel.layer.backgroundColor=[UIColor clearColor].CGColor;
    for (UIView *sv in panel.subviews)
        if ([sv isKindOfClass:[UIVisualEffectView class]] && CGRectEqualToRect(sv.frame, panel.bounds)) return;
    for (UIView *sv in [panel.subviews copy])
        if ([sv isKindOfClass:[UIVisualEffectView class]]) [sv removeFromSuperview];
    for (CALayer *sl in [panel.layer.sublayers copy])
        if (objc_getAssociatedObject(sl,&kDKGlassGradKey)) [sl removeFromSuperlayer];
    UIVisualEffect *eff=DKBubbleGlassEffect(); if(!eff) return;
    panel.clipsToBounds=YES;
    CGFloat radius = halfH ? (panel.bounds.size.height*0.5f) : (MIN(panel.bounds.size.width,panel.bounds.size.height)*0.30f);
    if (radius>26) radius=26;
    if (radius<10) radius=10;
    panel.layer.cornerRadius=radius;
    UIVisualEffectView *vev=[[UIVisualEffectView alloc] initWithEffect:eff];
    vev.frame=panel.bounds; vev.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    vev.userInteractionEnabled=NO; vev.layer.cornerRadius=radius; vev.clipsToBounds=YES;
    [panel insertSubview:vev atIndex:0];
    CAGradientLayer *gl=[CAGradientLayer layer];
    gl.frame=panel.bounds; gl.cornerRadius=radius;
    gl.colors=@[(id)[UIColor colorWithWhite:1.0 alpha:0.06].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations=@[@0.0f,@0.30f];
    gl.startPoint=CGPointMake(0,0); gl.endPoint=CGPointMake(0,1); gl.zPosition=0.1f;
    objc_setAssociatedObject(gl,&kDKGlassGradKey,@(YES),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [panel.layer addSublayer:gl];
    panel.layer.borderColor=[UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    panel.layer.borderWidth=0.6;
}
// 递归找长按面板主体并套玻璃
static void DKGlassifyLongPressMenu(UIView *root){
    if(!root) return;
    NSMutableArray *stack=[NSMutableArray array]; [stack addObject:root];
    int guard=0;
    CGFloat sh=[UIScreen mainScreen].bounds.size.height;
    while (stack.count && guard<400){
        guard++; UIView *v=[stack lastObject]; [stack removeLastObject];
        NSString *cn=NSStringFromClass([v class])?:@"";
        NSString *lo=[cn lowercaseString];
        CGFloat w=v.bounds.size.width, h=v.bounds.size.height;
        // 面板主体：类名含 hoverable(AFDHoverableContainerView), 或 宽≈屏宽且高适中、父视图是菜单容器
        BOOL isPanel=[lo containsString:@"hoverable"];
        if (!isPanel && w>=300 && h>=60 && h<sh*0.5) {
            UIView *p=v.superview;
            NSString *pcn=p?NSStringFromClass([p class])?:@"":@"";
            if ([pcn containsString:@"EmojiReplyMenu"]) isPanel=YES;
        }
        if (isPanel) { @try{ DKApplyGlassToPanel(v); }@catch(NSException*e){} return; }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}
static void hook_emojiMenuLayoutSubviews(id self, SEL _cmd){
    orig_emojiMenuLayoutSubviews(self,_cmd);
    @try { DKGlassifyLongPressMenu(self); } @catch(NSException *e){}
}
// ===== 会话长按弹出菜单(AWEPopoverActionSheet)清透玻璃：找到含多个竖排按钮的菜单容器套玻璃 =====
// 清菜单容器内所有 UIButton 的深色内容层(contentLayer)：黑色是按钮背景绘制，不是 backgroundColor
// [调试] 聚焦定位：延迟后遍历所有 window，找出覆盖菜单区域、带背景/深色的视图(黑色真源)
__attribute__((unused)) static void DKClearButtonContentLayers(UIView *menu){
    if(!menu) return;
    NSMutableArray *stack=[NSMutableArray array]; [stack addObject:menu];
    int guard=0;
    while(stack.count && guard<300){
        guard++; UIView *v=[stack lastObject]; [stack removeLastObject];
        if([v isKindOfClass:[UIButton class]]){
            for(CALayer *sl in [v.layer.sublayers copy]){
                if(sl.contents && !sl.mask) sl.opacity=0.0f;
            }
        }
        for(UIView *s in v.subviews) [stack addObject:s];
    }
}
static UIView *DKFindPopoverMenu(UIView *root){
    if(!root) return nil;
    NSMutableArray *stack=[NSMutableArray array]; [stack addObject:root];
    int guard=0;
    while(stack.count && guard<500){
        guard++; UIView *v=[stack lastObject]; [stack removeLastObject];
        // 菜单容器：宽150~300, 高100~600, 含>=3个直接UIButton子视图(竖排菜单项)
        if (v.bounds.size.width>=150 && v.bounds.size.width<=300 &&
            v.bounds.size.height>=100 && v.bounds.size.height<=600) {
            int btnCount=0;
            for(UIView *s in v.subviews) if([s isKindOfClass:[UIButton class]]) btnCount++;
            if (btnCount>=3) return v;
        }
        for(UIView *s in v.subviews) [stack addObject:s];
    }
    return nil;
}
static UILabel *g_cv=nil; static NSString *g_cvlast=nil;
__attribute__((unused)) static void DKFindDarkCover(UIView *menu, UIWindow *win){
    if(!menu||!win) return;
    CGRect mf=[menu convertRect:menu.bounds toView:win];
    NSMutableArray *lines=[NSMutableArray array];
    NSMutableArray *stack=[NSMutableArray array];
    for(UIWindow *w in [[UIApplication sharedApplication] windows]) [stack addObject:@{@"v":w,@"d":@0}];
    int guard=0;
    while(stack.count && guard<2500){
        guard++; NSDictionary *e=[stack lastObject];[stack removeLastObject];
        UIView *v=e[@"v"]; int d=[e[@"d"] intValue];
        if(d>8) continue;
        CGRect vf=[v convertRect:v.bounds toView:win];
        if(CGRectIntersectsRect(vf, mf)){
            NSString *lrgb=@"";
            CGColorRef c=v.layer.backgroundColor;
            if(c && CGColorGetNumberOfComponents(c)>=4){ const CGFloat*cc=CGColorGetComponents(c); lrgb=[NSString stringWithFormat:@"lbg(%.0f,%.0f,%.0f,a%.0f)",cc[0]*255,cc[1]*255,cc[2]*255,cc[3]*255]; }
            NSString *ct=v.layer.contents?@"cY":@"c-";
            NSString *sh=(v.layer.shadowOpacity>0.01)?[NSString stringWithFormat:@" sh%.2f",v.layer.shadowOpacity]:@"";
            NSString *eff=@"";
            if([v isKindOfClass:[UIVisualEffectView class]]){ UIVisualEffectView *ev=(UIVisualEffectView*)v; eff=[NSString stringWithFormat:@" eff:%@",ev.effect?NSStringFromClass([ev.effect class]):@"nil"]; }
            [lines addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f@(%.0f,%.0f) op%.2f %@ %@%@%@", NSStringFromClass([v class]), vf.size.width, vf.size.height, vf.origin.x, vf.origin.y, v.layer.opacity, lrgb, ct, sh, eff]];
        }
        for(UIView *s in v.subviews) [stack addObject:@{@"v":s,@"d":@(d+1)}];
    }
    if(!lines.count) [lines addObject:@"(无视图覆盖菜单区域)"];
    NSString *tree=[lines componentsJoinedByString:@"\n"];
    if([g_cvlast isEqualToString:tree]) return; g_cvlast=tree;
    NSLog(@"[DKCover]\n%@",tree);
    if(!g_cv){ g_cv=[[UILabel alloc]init]; g_cv.backgroundColor=[UIColor colorWithWhite:0 alpha:0.85]; g_cv.textColor=[UIColor whiteColor]; g_cv.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightBold]; g_cv.numberOfLines=0; g_cv.layer.zPosition=100000; [win addSubview:g_cv]; }
    g_cv.text=tree;
    CGSize sz=[g_cv sizeThatFits:CGSizeMake(win.bounds.size.width-8,1200)];
    g_cv.frame=CGRectMake(0,40,win.bounds.size.width,sz.height+4);
}
// 清菜单按钮的深色背景源(backgroundColor/backgroundImage/UIButtonConfiguration filled背景)；
// 不清 contentLayer(那层是文字)
__attribute__((unused)) static void DKClearButtonConfigs(UIView *menu){
    if(!menu) return;
    NSMutableArray *stack=[NSMutableArray array]; [stack addObject:menu];
    int guard=0;
    while(stack.count && guard<300){
        guard++; UIView *v=[stack lastObject]; [stack removeLastObject];
        if([v isKindOfClass:[UIButton class]]){
            UIButton *b=(UIButton*)v;
            b.backgroundColor=[UIColor clearColor];
            b.layer.backgroundColor=[UIColor clearColor].CGColor;
            [b setBackgroundImage:nil forState:UIControlStateNormal];
            [b setBackgroundImage:nil forState:UIControlStateHighlighted];
            [b setBackgroundImage:nil forState:UIControlStateSelected];
            if(@available(iOS 15.0,*)){
                UIButtonConfiguration *cfg=[b configuration];
                if(cfg){
                    cfg.background.backgroundColor=[UIColor clearColor];
                    cfg.background.strokeColor=[UIColor clearColor];
                    [b setConfiguration:cfg];
                }
            }
        }
        for(UIView *s in v.subviews) [stack addObject:s];
    }
}
// 沿父链清所有深色子图层(含contents的深色背景图)+UIVisualEffectView暗色effect
__attribute__((unused)) static void DKClearAncSubLayersDeep(UIView *menu){
    UIView *anc=menu; int g=0;
    while(anc && g<20){
        if([anc isKindOfClass:[UIVisualEffectView class]]) ((UIVisualEffectView*)anc).effect=nil;
        for(CALayer *sl in [anc.layer.sublayers copy]){
            if([sl isKindOfClass:[CAGradientLayer class]]){ CAGradientLayer *gr=(CAGradientLayer*)sl; if(gr.colors.count && DKIsDarkColor((__bridge CGColorRef)gr.colors[0])) sl.opacity=0.0f; }
            else if(sl.backgroundColor && DKIsDarkColor(sl.backgroundColor)) sl.opacity=0.0f;  // 不管有无contents
        }
        anc=anc.superview;
    }
}
// [调试] dump菜单容器父链每一层的全部子图层(RGB+contents+opacity)：定位深色背景图
__attribute__((unused)) static void DKShowAncSubs(UIView *menu, UIWindow *win){
    if(!menu||!win) return;
    NSMutableArray *lines=[NSMutableArray array];
    UIView *a=menu; int i=0;
    while(a && i<16){
        [lines addObject:[NSString stringWithFormat:@"anc%ld: %@ %.0fx%.0f r%.0f", (long)i, NSStringFromClass([a class]), a.bounds.size.width, a.bounds.size.height, a.layer.cornerRadius]];
        for(CALayer *sl in [a.layer.sublayers copy]){
            NSString *rgb=@"";
            CGColorRef c=sl.backgroundColor;
            if(c && CGColorGetNumberOfComponents(c)>=4){ const CGFloat*cc=CGColorGetComponents(c); rgb=[NSString stringWithFormat:@"bg(%.0f,%.0f,%.0f,a%.0f)",cc[0]*255,cc[1]*255,cc[2]*255,cc[3]*255]; }
            NSString *ct=sl.contents?@"cY":@"c-";
            [lines addObject:[NSString stringWithFormat:@"   +%@ %@ %@ op%.2f", NSStringFromClass([sl class]), rgb, ct, sl.opacity]];
        }
        a=a.superview; i++;
    }
    NSString *tree=[lines componentsJoinedByString:@"\n"];
    if([g_cvlast isEqualToString:tree]) return; g_cvlast=tree;
    NSLog(@"[DKAncSubs]\n%@",tree);
    if(!g_cv){ g_cv=[[UILabel alloc]init]; g_cv.backgroundColor=[UIColor colorWithWhite:0 alpha:0.85]; g_cv.textColor=[UIColor whiteColor]; g_cv.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightBold]; g_cv.numberOfLines=0; g_cv.layer.zPosition=100000; [win addSubview:g_cv]; }
    g_cv.text=tree;
    CGSize sz=[g_cv sizeThatFits:CGSizeMake(win.bounds.size.width-8,1200)];
    g_cv.frame=CGRectMake(0,40,win.bounds.size.width,sz.height+4);
}
// 清菜单容器上所有 CAShapeLayer 的 fillColor(深浅都清，去掉深色圆角背景和浅色"白白"层) + 深色子图层；不碰按钮文字
__attribute__((unused)) static void DKClearShapeFill(UIView *menu){
    if(!menu) return;
    for(CALayer *sl in [menu.layer.sublayers copy]){
        if([sl isKindOfClass:[CAShapeLayer class]]){
            CAShapeLayer *sh=(CAShapeLayer*)sl;
            sh.fillColor=[UIColor clearColor].CGColor;   // 所有填充透明(深色圆角背景 + 浅色白层都去)
            if(sh.strokeColor && DKIsDarkColor(sh.strokeColor)) sh.strokeColor=[UIColor clearColor].CGColor;
        }
        if(sl.backgroundColor && DKIsDarkColor(sl.backgroundColor)) sl.opacity=0.0f;
    }
}
static void (*orig_popoverLayout)(id,SEL);
static void hook_popoverLayout(id self, SEL _cmd){
    orig_popoverLayout(self,_cmd);
    @try{
        UIView *menu = DKFindPopoverMenu(self);
        if (menu) {
            // 黑色真源=CAShapeLayer深色fillColor(圆角菜单背景)：清掉+套玻璃，文字在按钮contentLayer不碰
            DKClearShapeFill(menu);
            DKApplyGlassToPanel(menu);
            __weak UIView *wm = menu;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try{ if(wm){ DKClearShapeFill(wm); DKApplyGlassToPanel(wm); } }@catch(NSException *e){}
            });
        }
    }@catch(NSException *e){}
}
static BOOL g_bubbleHooksInstalled = NO;
static void (*orig_cardBelowEmojiLayout)(id,SEL);
static void hook_cardBelowEmojiLayout(id self, SEL _cmd);
static void (*orig_lightReplyLayout)(id,SEL);
static void hook_lightReplyLayout(id self, SEL _cmd);
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
    Class em = NSClassFromString(@"AWEIMEmojiReplyMenuView");
    if (em && !orig_emojiMenuLayoutSubviews) {
        MSHookMessageEx(em, sel_registerName("layoutSubviews"), (IMP)hook_emojiMenuLayoutSubviews, (IMP*)&orig_emojiMenuLayoutSubviews);
    }
    // 会话长按弹出菜单(AWEPopoverActionSheet)清透玻璃
    Class pp = NSClassFromString(@"AWEPopoverActionSheet");
    if (pp && !orig_popoverLayout) {
        MSHookMessageEx(pp, sel_registerName("layoutSubviews"), (IMP)hook_popoverLayout, (IMP*)&orig_popoverLayout);
    }
    // 聊天页视频/卡片下方快捷回复表情面板(AWEIMCardBelowQuickEmoticonBoxView)清透玻璃
    Class cbe = NSClassFromString(@"AWEIMCardBelowQuickEmoticonBoxView");
    if (cbe && !orig_cardBelowEmojiLayout) {
        MSHookMessageEx(cbe, sel_registerName("layoutSubviews"), (IMP)hook_cardBelowEmojiLayout, (IMP*)&orig_cardBelowEmojiLayout);
    }
    g_bubbleHooksInstalled = (orig_bubbleLayoutSubviews || orig_cellLayoutSubviews || orig_tableCellForRow || orig_emojiMenuLayoutSubviews || orig_popoverLayout || orig_cardBelowEmojiLayout);
    // 互动按钮(回个心/赞等, AWEIMLightInteractionReplyButton)清透玻璃
    Class lr = NSClassFromString(@"AWEIMLightInteractionReplyButton");
    if (lr && !orig_lightReplyLayout) {
        MSHookMessageEx(lr, sel_registerName("layoutSubviews"), (IMP)hook_lightReplyLayout, (IMP*)&orig_lightReplyLayout);
    }
}

// 描述UIColor近似颜色(找黄色拐弯箭头)
__attribute__((unused)) static NSString* DKColorDesc(UIColor *c){
    if(!c) return @"nil";
    if(c==[UIColor clearColor]) return @"clear";
    const CGFloat *comp=CGColorGetComponents(c.CGColor);
    if(!comp) return @"?";
    if(comp[3]<0.02f) return @"clear";
    return [NSString stringWithFormat:@"r%.0f,g%.0f,b%.0f,a%.2f",comp[0]*255,comp[1]*255,comp[2]*255,comp[3]];
}
// [调试] dump"回个心"所在消息cell子树(深度3), 标出UIImageView(箭头图)与CAShapeLayer(弧形线), 定位上方"拐弯箭头"
__attribute__((unused)) static void DKFindArrowStructure(UIView *btn, UIWindow *win){
    if(!btn||!win) return;
    UIView *cell=nil; UIView *p=btn;
    while(p){ if(fabs(p.bounds.size.width-402)<1 && fabs(p.bounds.size.height-160)<1){ cell=p; break; } p=p.superview; }
    NSMutableArray *lines=[NSMutableArray array];
    if(!cell){ [lines addObject:@"(未找到402x160消息容器)"]; }
    else {
        NSMutableArray *q=[NSMutableArray arrayWithObject:@[cell,@(0)]];
        int qi=0; int cnt=0;
        while(qi<(int)q.count && cnt<70){
            NSArray *ent=q[qi++]; UIView *v=ent[0]; int dep=[ent[1] intValue];
            NSString *ind=[@"" stringByPaddingToLength:dep*2 withString:@" " startingAtIndex:0];
            NSMutableString *ln=[NSMutableString stringWithFormat:@"%@%@ bg[%@] @(%d,%d)%.0fx%.0f", ind, NSStringFromClass([v class]), DKColorDesc(v.backgroundColor),(int)v.frame.origin.x,(int)v.frame.origin.y,v.bounds.size.width,v.bounds.size.height];
            if([v isKindOfClass:[UIImageView class]]) [ln appendString:@" [IMG]"];
            for(CALayer *sl in v.layer.sublayers){
                [ln appendFormat:@" <%@>", NSStringFromClass([sl class])];
                if([sl isKindOfClass:[CAShapeLayer class]]){
                    CAShapeLayer *sh=(CAShapeLayer*)sl;
                    const CGFloat *f=CGColorGetComponents(sh.fillColor); const CGFloat *s=CGColorGetComponents(sh.strokeColor);
                    if(f&&f[3]>0.02f) [ln appendFormat:@" fill(%d,%d)",(int)(f[0]*255),(int)(f[1]*255)];
                    if(s&&s[3]>0.02f) [ln appendFormat:@" stroke(%d,%d,%d)",(int)(s[0]*255),(int)(s[1]*255),(int)(s[2]*255)];
                    [ln appendString:@" [SHAPE]"];
                }
            }
            [lines addObject:ln];
            if(dep<3) for(UIView *ss in v.subviews){ if(cnt<70) [q addObject:@[ss,@(dep+1)]]; }
            cnt++;
        }
    }
    NSString *tree=[lines componentsJoinedByString:@"\n"];
    if([g_cvlast isEqualToString:tree]) return; g_cvlast=tree;
    NSLog(@"[DKArrow]\n%@",tree);
    if(!g_cv){ g_cv=[[UILabel alloc]init]; g_cv.backgroundColor=[UIColor colorWithWhite:0 alpha:0.85]; g_cv.textColor=[UIColor whiteColor]; g_cv.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightBold]; g_cv.numberOfLines=0; g_cv.layer.zPosition=100000; [win addSubview:g_cv]; }
    g_cv.text=tree;
    CGSize sz=[g_cv sizeThatFits:CGSizeMake(win.bounds.size.width-8,1500)];
    g_cv.frame=CGRectMake(0,40,win.bounds.size.width,sz.height+4);
}
static void hook_lightReplyLayout(id self, SEL _cmd){
    orig_lightReplyLayout(self,_cmd);
    @try{
        // 只清"回个心"按钮自身背景 + 套玻璃(29.30已到位)，不动子视图；不再给父视图套多余玻璃
        [(UIView*)self setBackgroundColor:[UIColor clearColor]];
        ((UIView*)self).layer.backgroundColor=[UIColor clearColor].CGColor;
        DKApplyGlassToCap(self, YES);
        __weak UIView *ws=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.3*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try{
                if(ws){
                    DKApplyGlassToCap(ws, YES);
                    UIWindow *rw=ws.window;
                    if(rw) DKFindArrowStructure(ws, rw);
                }
            }@catch(NSException *e){}
        });
    }@catch(NSException *e){}
}

// 清面板自身及子树所有背景(深浅都清，保留文字/图标contentLayer)，让玻璃完全透出
__attribute__((unused)) static void DKClearPanelBackgroundsAll(UIView *panel){
    if(!panel) return;
    panel.backgroundColor=[UIColor clearColor];
    panel.layer.backgroundColor=[UIColor clearColor].CGColor;
    for(CALayer *sl in [panel.layer.sublayers copy]){
        if([sl isKindOfClass:[CAShapeLayer class]]) ((CAShapeLayer*)sl).fillColor=[UIColor clearColor].CGColor;
        if(sl.backgroundColor) sl.opacity=0.0f;
    }
    for(UIView *s in panel.subviews) DKClearPanelBackgroundsAll(s);
}
// [调试] dump快捷表情容器(AWEIMCardBelowQuickEmoticonBoxView)子视图树，找独立胶囊按钮层级
__attribute__((unused)) static void DKShowCardEmojiSubs(UIView *root){
    if(!root) return;
    UIWindow *win=root.window; if(!win) return;
    NSMutableArray *lines=[NSMutableArray array];
    NSMutableArray *q=[NSMutableArray arrayWithObject:root];
    int qi=0;
    while(qi<(int)q.count && qi<160){
        UIView *v=q[qi++];
        NSMutableArray *anc=[NSMutableArray array];
        UIView *p=v.superview; int g=0;
        while(p && g<4){ [anc addObject:NSStringFromClass([p class])]; p=p.superview; g++; }
        [lines addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f ^%@", NSStringFromClass([v class]), v.bounds.size.width, v.bounds.size.height, [anc componentsJoinedByString:@">"]]];
        for(UIView *s in v.subviews){ if(q.count<160) [q addObject:s]; }
    }
    NSString *tree=[lines componentsJoinedByString:@"\n"];
    if([g_cvlast isEqualToString:tree]) return; g_cvlast=tree;
    NSLog(@"[DKCardEmoji]\n%@",tree);
    if(!g_cv){ g_cv=[[UILabel alloc]init]; g_cv.backgroundColor=[UIColor colorWithWhite:0 alpha:0.85]; g_cv.textColor=[UIColor whiteColor]; g_cv.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightBold]; g_cv.numberOfLines=0; g_cv.layer.zPosition=100000; [win addSubview:g_cv]; }
    g_cv.text=tree;
    CGSize sz=[g_cv sizeThatFits:CGSizeMake(win.bounds.size.width-8,1200)];
    g_cv.frame=CGRectMake(0,40,win.bounds.size.width,sz.height+4);
}
static void hook_cardBelowEmojiLayout(id self, SEL _cmd){
    orig_cardBelowEmojiLayout(self,_cmd);
    @try{
        // 只清容器自身背景(不递归，绝不动胶囊/图标/文字子视图)
        [(UIView*)self setBackgroundColor:[UIColor clearColor]];
        ((UIView*)self).layer.backgroundColor=[UIColor clearColor].CGColor;
        for(UIView *cap in [(UIView*)self subviews]){
            if(cap.bounds.size.width>=40 && cap.bounds.size.height>=40){
                @try{
                    // 只清胶囊自身背景 + 套玻璃，子视图(图标/文字)完全不动
                    cap.backgroundColor=[UIColor clearColor];
                    cap.layer.backgroundColor=[UIColor clearColor].CGColor;
                    DKApplyGlassToCap(cap, NO);
                }@catch(NSException *e){}
            }
        }
        __weak UIView *ws=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.4*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try{
                if(!ws) return;
                // 延迟只保证每个胶囊玻璃存在(防重复)，不再递归清背景(避免清掉玻璃/文字)
                for(UIView *cap in [(UIView*)ws subviews]){
                    if(cap.bounds.size.width>=40 && cap.bounds.size.height>=40){
                        @try{ DKApplyGlassToCap(cap, NO); }@catch(NSException *e){}
                    }
                }
            }@catch(NSException *e){}
        });
    }@catch(NSException *e){}
}

// ===== 聊天长按操作面板清透玻璃：长按消息弹出的操作面板(AWEIMEmojiReplyMenuView 内 AFDHoverableContainerView)套玻璃 =====
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
    // 聊天气泡清透玻璃 + 长按操作面板玻璃
    DKInstallBubbleHooks();
}

static void DKForceAllPrefs(void){
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // 评论玻璃(模糊) + 聊天玻璃(开 + 清透样式=2) 显式设置
    [d setBool:YES forKey:@"DYKillerCommentGlass"];          // 评论: 模糊
    [d setBool:YES forKey:@"DYKillerChatInputGlass"];        // 聊天: 玻璃开
    [d setInteger:2 forKey:@"DYKillerChatInputGlassClear"];  // 聊天: 清透样式
    [d setBool:YES forKey:@"DYKillerFeedMenuNoPanel"];        // 长按不弹出长按面板
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