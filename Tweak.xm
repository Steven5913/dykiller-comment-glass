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
#import <QuartzCore/QuartzCore.h>
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

// 玻璃本体（圆盘/胶囊共用同一套配方：长按倍速那套）
static UIView *DKMakeGlassRect(CGFloat w, CGFloat h, CGFloat radius){
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    host.backgroundColor = [UIColor clearColor];
    host.userInteractionEnabled = NO;
    host.tag = DK_TAG;
    host.clipsToBounds = YES;
    host.layer.cornerRadius = radius;

    UIVisualEffect *eff = DKGlassEffect();
    if (eff) {
        UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
        vev.frame = host.bounds;
        vev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vev.userInteractionEnabled = NO;
        vev.layer.cornerRadius = radius;
        vev.clipsToBounds = YES;
        [host addSubview:vev];
    }
    CAGradientLayer *gl = [CAGradientLayer layer];
    gl.frame = host.bounds;
    gl.cornerRadius = radius;
    gl.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                  (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations = @[@0.0f, @0.20f];
    gl.startPoint = CGPointMake(0, 0);
    gl.endPoint = CGPointMake(0, 1);
    gl.zPosition = 0.1f;
    [host.layer addSublayer:gl];
    return host;
}

// 圆形玻璃盘
static UIView *DKMakeDisc(CGFloat d){
    return DKMakeGlassRect(d, d, d / 2.0);
}

#define DK_RING_NAME @"DKRing20261106"
// 环形描边：上下白、左右渐隐到无（用竖向三段渐变做 alpha 蒙版）
static void DKUpdateRing(UIView *g){
    if (!g) return;
    CGFloat d = g.bounds.size.width;
    if (d < 8) return;
    CAShapeLayer *ring = nil;
    for (CALayer *l in g.layer.sublayers) {
        if ([l.name isEqualToString:DK_RING_NAME]) { ring = (CAShapeLayer *)l; break; }
    }
    if (!ring) {
        ring = [CAShapeLayer layer];
        ring.name = DK_RING_NAME;
        ring.fillColor = nil;
        ring.strokeColor = [UIColor colorWithWhite:1.0 alpha:1.0].CGColor;
        ring.lineWidth = 0.5;
        ring.zPosition = 1.0f;

        CAGradientLayer *mask = [CAGradientLayer layer];
        mask.startPoint = CGPointMake(0.5, 0.0);
        mask.endPoint = CGPointMake(0.5, 1.0);
        mask.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.25].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.25].CGColor];
        mask.locations = @[@0.0f, @0.5f, @1.0f];
        ring.mask = mask;
        [g.layer addSublayer:ring];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ring.frame = g.bounds;
    CALayer *mask = ring.mask;
    if (mask) mask.frame = ring.bounds;
    CGRect rr = CGRectInset(g.bounds, 0.25, 0.25);
    CGFloat cr = g.layer.cornerRadius;
    if (cr <= 0.0) cr = rr.size.width / 2.0;
    CGFloat cap = MIN(rr.size.width, rr.size.height) / 2.0;
    if (cr > cap) cr = cap;
    ring.path = [UIBezierPath bezierPathWithRoundedRect:rr cornerRadius:cr].CGPath;
    [CATransaction commit];
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
    DKUpdateRing(g);
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

// 按矩形铺一块玻璃（胶囊/面板用；与圆盘同一套配方）
#define DK_REMOTE_TAG 20261109
// 提示条挂在独立覆盖窗（AWEMaskWindow）上时，UIVisualEffectView 取样不到主窗的视频画面，
// 材质会退化成一整块奶白（白雾）。这种宿主不在自己身上铺玻璃，改在 key window 的同位置铺，
// 上面盖着的是覆盖窗——文字照样在，玻璃能正常取样到视频
static BOOL DKApplyGlassRemote(UIView *host, CGRect r, CGFloat radius){
    UIWindow *key = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) { if (w.isKeyWindow) { key = w; break; } }
    if (!key) return NO;
    UIWindow *hw = host.window;
    if (!hw || hw == key) return NO;
    for (UIView *old in [key.subviews copy]) if (old.tag == DK_REMOTE_TAG) [old removeFromSuperview];
    CGRect wr = [host convertRect:r toView:key];
    UIView *g = DKMakeGlassRect(r.size.width, r.size.height, radius);
    g.frame = wr;
    g.tag = DK_REMOTE_TAG;
    [key addSubview:g];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [g removeFromSuperview];
    });
    return YES;
}

static void DKApplyGlassAt(UIView *host, CGRect r, CGFloat radius){
    if (!host) return;
    if (r.size.width < 8 || r.size.height < 8) return;
    if (isnan(r.origin.x) || isnan(r.origin.y)) return;
    UIView *g = nil;
    for (UIView *sv in host.subviews) {
        if (sv.tag != DK_TAG) continue;
        if (fabs((double)sv.bounds.size.width - (double)r.size.width) < 0.5 &&
            fabs((double)sv.bounds.size.height - (double)r.size.height) < 0.5) { g = sv; }
        else sv.hidden = YES;   // 尺寸变迁留下的旧玻璃层，留着会两层材质叠加成白雾
    }
    if (!g) {
        g = DKMakeGlassRect(r.size.width, r.size.height, radius);
        [host insertSubview:g atIndex:0];
    }
    if (fabs((double)g.layer.cornerRadius - (double)radius) > 0.5) {
        g.layer.cornerRadius = radius;
        for (UIView *sv in g.subviews) { if ([sv isKindOfClass:[UIVisualEffectView class]]) sv.layer.cornerRadius = radius; }
        for (CALayer *l in g.layer.sublayers) { if ([l isKindOfClass:[CAGradientLayer class]]) l.cornerRadius = radius; }
    }
    if (!CGRectEqualToRect(g.frame, r)) g.frame = r;
    DKUpdateRing(g);
}

// ===== 加号弹窗（AFDLeftExtensionPopoverSheetView）玻璃 =====
// 清掉弹窗里原有的白色底（背景色 + 白色 CAShape 底板），只保留文字/图标
static void DKPopoverClearWhites(UIView *v){
    if (!v) return;
    UIColor *bg = v.backgroundColor;
    if (bg) {
        CGFloat w = 0.0, a = 0.0;
        if ([bg getWhite:&w alpha:&a] && a > 0.05 && w > 0.80) v.backgroundColor = [UIColor clearColor];
    }
    for (CALayer *l in v.layer.sublayers) {
        if ([l isKindOfClass:[CAShapeLayer class]]) { l.hidden = YES; continue; }
        CGColorRef c = l.backgroundColor;
        if (!c) continue;
        UIColor *uc = [UIColor colorWithCGColor:c];
        CGFloat w = 0.0, a = 0.0;
        if ([uc getWhite:&w alpha:&a] && a > 0.05 && w > 0.80) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            l.backgroundColor = [UIColor clearColor].CGColor;
            [CATransaction commit];
        }
    }
    for (UIView *sv in v.subviews) DKPopoverClearWhites(sv);
}

// 玻璃上黑字看不清：所有标题/标签统一改白色，分隔线改浅白
static void DKPopoverRecolor(UIView *v){
    if (!v) return;
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)v;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.55] forState:UIControlStateHighlighted];
        [b setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.55] forState:UIControlStateSelected];
        b.tintColor = [UIColor whiteColor];
    }
    if ([v isKindOfClass:[UILabel class]]) {
        ((UILabel *)v).textColor = [UIColor whiteColor];
    }
    if ([v isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)v;
        if (iv.image && iv.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
            iv.image = [iv.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
        iv.tintColor = [UIColor whiteColor];
    }
    if (v.frame.size.height > 0.0 && v.frame.size.height <= 1.0 && v.frame.size.width > 20.0) {
        v.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    }
    for (UIView *sv in v.subviews) DKPopoverRecolor(sv);
}

static void DKPopoverGlass(UIView *sheet){
    if (!sheet) return;
    UIView *content = nil;
    @try {
        id c = [sheet valueForKey:@"contentView"];
        if ([c isKindOfClass:[UIView class]]) content = (UIView *)c;
    } @catch (NSException *e) {}
    if (!content) {
        for (UIView *v in sheet.subviews) {
            if (v.frame.size.width >= 100.0 && v.frame.size.width <= 280.0 && v.frame.size.height >= 60.0) {
                content = v;
                break;
            }
        }
    }
    if (!content) return;
    if (content.bounds.size.width < 60.0 || content.bounds.size.height < 40.0) return;

    DKPopoverClearWhites(content);
    content.backgroundColor = [UIColor clearColor];
    content.layer.backgroundColor = [UIColor clearColor].CGColor;

    DKPopoverRecolor(content);

    CGFloat r = content.layer.cornerRadius;
    if (r <= 2.0) r = 13.0;
    DKApplyGlassAt(content, content.bounds, r);
}

// ===== 顶部导航栏（消息页）玻璃 =====
// 左边三条横线：单独一个圆盘；右边搜索+加号：共用一块胶囊
static void DKNavGlass(UIView *bar){
    if (!bar || bar.bounds.size.width < 300) return;
    UIView *row = nil;
    for (UIView *v in bar.subviews) {
        if (v.frame.size.width > 300 && fabs((double)v.frame.size.height - 44.0) < 1.5) { row = v; break; }
    }
    if (!row) return;

    UIView *leftEnt = nil, *rightBox = nil;
    for (UIView *v in row.subviews) {
        NSString *cn = NSStringFromClass([v class]);
        if ([cn isEqualToString:@"AWEIMMessageTabSideBarView"]) leftEnt = v;
        if (v.subviews.count >= 1 && fabs((double)v.frame.size.width - 92.0) < 2.0 &&
            fabs((double)v.frame.size.height - 32.0) < 2.0) {
            for (UIView *c in v.subviews) {
                if ([NSStringFromClass([c class]) isEqualToString:@"IESIMButton"]) { rightBox = v; break; }
            }
        }
    }

    if (leftEnt) {
        UIView *icon = nil;
        for (UIView *c in leftEnt.subviews) {
            if (c.frame.size.width >= 24 && c.frame.size.width <= 40 &&
                c.frame.size.height >= 24 && c.frame.size.height <= 40) { icon = c; break; }
        }
        if (icon) {
            CGRect ir = icon.bounds;
            @try { ir = [icon convertRect:icon.bounds toView:row]; } @catch(...) { ir = CGRectZero; }
            if (!CGRectIsEmpty(ir)) {
                CGFloat d = 40.0;
                DKApplyGlassAt(row, CGRectMake(CGRectGetMidX(ir) - d / 2.0,
                                               CGRectGetMidY(ir) - d / 2.0, d, d), d / 2.0);
            }
        }
    }
    if (rightBox) {
        // 加号位置不动，把「搜索」往右挪；用 transform 位移，
        // 父视图重新布局只会改 frame，不会清掉 transform，所以不会再被弹回
        for (UIView *c in rightBox.subviews) {
            if ([NSStringFromClass([c class]) isEqualToString:@"IESIMButton"]) {
                c.transform = CGAffineTransformMakeTranslation(16.0, 0);
            }
        }
        // 玻璃跟着两个图标走：按（含 transform 位移后的）实际占位取并集，左右各留 4pt
        CGRect u = CGRectNull;
        for (UIView *c in rightBox.subviews) {
            NSString *cn = NSStringFromClass([c class]);
            if (![cn isEqualToString:@"IESIMButton"] && ![cn isEqualToString:@"AWEButton"]) continue;
            CGRect f = c.frame;
            f.origin.x += c.transform.tx;
            u = CGRectIsNull(u) ? f : CGRectUnion(u, f);
        }
        if (!CGRectIsNull(u)) {
            u = CGRectInset(u, -4.0, 0);
            CGFloat h = 40.0;
            CGRect gr = [rightBox convertRect:CGRectMake(u.origin.x, CGRectGetMidY(rightBox.bounds) - h / 2.0,
                                                         u.size.width, h) toView:row];
            gr.origin.x -= 2.0;   // 加宽时保持中心不动
            gr.size.width += 4.0; // 宽度 +4
            gr.origin.x -= 8.0;   // 整体左移 8pt
            DKApplyGlassAt(row, gr, h / 2.0);
        }
    }
}

// ===== 视频详情页（AWEAwemeIMDetail…）：返回 / 搜索 / 底部输入框 玻璃 =====
// 左：返回按钮 Ø44；右：搜索图标 Ø44（都沿用同一套玻璃配方）
static void DKDetailScan(UIView *root, UIView **backBtn, UIView **searchIcon){
    if (!root) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSUInteger guard = 0;
    while (q.count > 0 && guard++ < 4000) {
        UIView *v = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        if (v.hidden || v.alpha < 0.01) continue;
        NSString *cn = NSStringFromClass([v class]);
        if (!*searchIcon && [cn isEqualToString:@"AWEDiscoverFeedEntranceView"]) *searchIcon = v;
        if (!*backBtn && [cn isEqualToString:@"AWEButton"] &&
            fabs((double)v.frame.size.width - 44.0) < 1.0 && fabs((double)v.frame.size.height - 44.0) < 1.0) {
            *backBtn = v;
        }
        for (UIView *c in v.subviews) [q addObject:c];
    }
}

static void DKDetailNavGlass(UIView *bar){
    if (!bar || bar.bounds.size.width < 300) return;
    UIView *backBtn = nil, *searchIcon = nil;
    DKDetailScan(bar, &backBtn, &searchIcon);
    if (backBtn) DKApplyDisc(backBtn, backBtn, 44.0);
    if (searchIcon && searchIcon.superview) DKApplyDisc(searchIcon.superview, searchIcon, 44.0);
}

// 从整页里找出真正承载返回/搜索的那条导航容器，再上玻璃
static void DKDetailPageGlass(UIView *root){
    if (!root || root.bounds.size.width < 300) return;
    UIView *navBar = nil;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSUInteger guard = 0;
    while (q.count > 0 && guard++ < 4000) {
        UIView *v = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        if (v.hidden || v.alpha < 0.01) continue;
        if ([NSStringFromClass([v class]) isEqualToString:@"AWEAwemeDetailNaviBarContainerView"] &&
            v.bounds.size.width > 300) { navBar = v; break; }
        for (UIView *c in v.subviews) [q addObject:c];
    }
    DKDetailNavGlass(navBar ? navBar : root);
}

// 底部输入框：清掉原本那层 15% 白底，铺同配方玻璃（胶囊圆角）
static void DKInputBarGlass(UIView *bar){
    if (!bar) return;
    if (bar.bounds.size.width < 120.0 || bar.bounds.size.height < 30.0) return;
    for (UIView *sv in bar.subviews) {
        UIColor *bg = sv.backgroundColor;
        if (!bg) continue;
        CGFloat w = 0.0, a = 0.0;
        if ([bg getWhite:&w alpha:&a] && a > 0.02 && w > 0.80) sv.backgroundColor = [UIColor clearColor];
    }
    bar.backgroundColor = [UIColor clearColor];
    CGFloat r = bar.bounds.size.height / 2.0;
    if (r > 24.0) r = 24.0;
    DKApplyGlassAt(bar, bar.bounds, r);
}

// ===== 底部输入框上方的快捷表情胶囊 =====
// 每个 cell 自带一层 UIVisualEffectView 模糊，先顶掉再铺同配方玻璃
static void DKHideBlurDeep(UIView *v){
    if (!v) return;
    for (UIView *s in v.subviews) {
        if (s.tag == DK_TAG) continue;      // 自己的玻璃子树一律不动
        if ([s isKindOfClass:[UIVisualEffectView class]]) { s.hidden = YES; continue; }
        DKHideBlurDeep(s);
    }
}

static void DKQuickEmojiGlass(UIView *cell){
    if (!cell) return;
    CGFloat w = cell.bounds.size.width, h = cell.bounds.size.height;
    if (w < 30.0 || h < 20.0 || h > 44.0) return;
    DKHideBlurDeep(cell);
    CGFloat r = h / 2.0;
    if (r > 16.0) r = 16.0;
    // 同一颗胶囊只留一层玻璃：cell 复用后宽度会变，旧的先并成一层的尺寸再复用
    UIView *keep = nil;
    for (UIView *sv in [cell.subviews copy]) {
        if (sv.tag != DK_TAG) continue;
        if (!keep) { keep = sv; continue; }
        [sv removeFromSuperview];
    }
    // cell 自身带的 15% 白底 + 圆角 8 的裁剪也要清掉，否则会压在我们玻璃上
    cell.backgroundColor = [UIColor clearColor];
    cell.layer.backgroundColor = NULL;
    if (fabs((double)cell.layer.cornerRadius - (double)r) > 0.5) cell.layer.cornerRadius = r;
    if (keep) {
        if (!CGRectEqualToRect(keep.frame, cell.bounds)) keep.frame = cell.bounds;
        if (fabs((double)keep.layer.cornerRadius - (double)r) > 0.5) {
            keep.layer.cornerRadius = r;
            for (UIView *sv in keep.subviews) {
                if ([sv isKindOfClass:[UIVisualEffectView class]]) sv.layer.cornerRadius = r;
            }
            for (CALayer *l in keep.layer.sublayers) {
                if ([l isKindOfClass:[CAGradientLayer class]]) l.cornerRadius = r;
            }
        }
    }
    DKApplyGlassAt(cell, cell.bounds, r);
}

static void DKQuickEmojiBar(UIView *bar){
    if (!bar) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:bar];
    NSUInteger guard = 0;
    while (q.count > 0 && guard++ < 600) {
        UIView *v = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        NSString *cn = NSStringFromClass([v class]) ?: @"";
        if ([cn isEqualToString:@"AWEIMInputActionBarFansGroupEntryViewCollectionViewCell"]) {
            DKQuickEmojiGlass(v);
            continue;
        }
        for (UIView *c in v.subviews) [q addObject:c];
    }
}

// ===== 视频详情页（评论区浮层）：左上返回 + 底部评论输入框 =====
static void DKCommentInputGlass(UIView *root){
    if (!root) return;
    UIView *pill = nil;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSUInteger guard = 0;
    while (q.count > 0 && guard++ < 800) {
        UIView *v = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        if (v.tag == DK_TAG) continue;
        CGFloat h = v.bounds.size.height, w = v.bounds.size.width;
        if (h > 30.0 && h < 52.0 && w > 200.0 &&
            fabs((double)v.layer.cornerRadius - (double)(h / 2.0)) < 2.5) { pill = v; break; }
        for (UIView *c in v.subviews) [q addObject:c];
    }
    if (!pill || pill.tag == DK_TAG) return;
    // 胶囊自身的白底/圆角裁剪只是视觉，改背景色不会触发布局
    pill.backgroundColor = [UIColor clearColor];
    pill.layer.backgroundColor = NULL;
    for (UIView *sv in [pill.subviews copy]) {
        UIColor *bg = sv.backgroundColor;
        if (!bg) continue;
        CGFloat wv = 0.0, av = 0.0;
        if ([bg getWhite:&wv alpha:&av] && av > 0.02 && wv > 0.80) sv.backgroundColor = [UIColor clearColor];
    }
    // 玻璃铺在整条输入栏背景层上（不在胶囊/中间容器里插子视图，避免带动 app 重排）
    UIView *host = root.tag == DK_TAG ? pill.superview : root;
    if (!host) return;
    CGRect pr;
    @try { pr = [pill convertRect:pill.bounds toView:host]; } @catch (NSException *e) { return; }
    if (CGRectIsEmpty(pr) || isnan(pr.origin.x) || isnan(pr.origin.y)) return;
    pr = CGRectInset(pr, 6.0, 0);   // 左右各内缩 6pt（比上版加宽 4pt）
    CGFloat r = pr.size.height / 2.0;
    if (r > 22.0) r = 22.0;
    DKApplyGlassAt(host, pr, r);
}

// 详情页浮层：视频交互容器被 app 按「扣掉评论栏高度」重排后会整体上移，
// 这里把它的高度顶回父容器（子视图都是底对齐，恢复后即原来的满屏位置）
static void DKCommentRestoreHeight(UIView *root){
    if (!root) return;
    Class ic = NSClassFromString(@"AWEPlayInteractionViewController");
    if (!ic) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSUInteger guard = 0;
    while (q.count > 0 && guard++ < 5000) {
        UIView *v = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        id nr = v.nextResponder;
        if (nr && [nr isKindOfClass:ic] && v.superview) {
            CGFloat ph = v.superview.bounds.size.height;
            CGFloat d = ph - v.bounds.size.height;
            CGAffineTransform t = v.transform;
            if (d > 60.0 && d < 100.0 && ph > 400.0) {
                // 用位移把内容顶回原位，绝不改 frame（改 frame 会触发 app 无限重排）
                if (t.ty < 1.0) v.transform = CGAffineTransformMakeTranslation(0, d);
            } else if (d < 6.0 && t.ty > 1.0) {
                v.transform = CGAffineTransformIdentity;
            }
            continue;
        }
        for (UIView *c in v.subviews) [q addObject:c];
    }
}

static void DKCommentPageGlass(UIView *root){
    if (!root || root.bounds.size.width < 300) return;
    UIView *navBar = nil, *inputBar = nil;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSUInteger guard = 0;
    while (q.count > 0 && guard++ < 5000) {
        UIView *v = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        NSString *cn = NSStringFromClass([v class]) ?: @"";
        if (!navBar && [cn isEqualToString:@"AWEAwemeDetailNaviBarContainerView"] &&
            v.bounds.size.width > 300) navBar = v;
        if (!inputBar && [cn isEqualToString:@"AWECommentInputBackgroundView"]) inputBar = v;
        for (UIView *c in v.subviews) [q addObject:c];
    }
    if (navBar) DKDetailNavGlass(navBar);
    if (inputBar) DKCommentInputGlass(inputBar);
    DKCommentRestoreHeight(root);
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

// 把头像本体统一成 d x d（与音乐唱片 44 一致），圆心保持不动
static void DKAvatarSize(UIView *btn, CGFloat d){
    if (!btn || d < 8) return;
    @try {
        CGRect f = btn.frame;
        if (CGRectIsEmpty(f)) return;
        CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
        if (fabs((double)f.size.width - (double)d) > 0.5 ||
            fabs((double)f.size.height - (double)d) > 0.5) {
            btn.bounds = CGRectMake(0, 0, d, d);
            btn.frame = CGRectMake(c.x - d / 2.0, c.y - d / 2.0, d, d);
        }
        btn.layer.cornerRadius = d / 2.0;
        btn.layer.masksToBounds = YES;
        // 里面的头像图片跟着铺满同一个圆
        for (UIView *s in btn.subviews) {
            NSString *scn = NSStringFromClass([s class]) ?: @"";
            if (![scn isEqualToString:@"UIImageView"]) continue;
            CGRect sf = s.frame;
            if (fabs((double)sf.size.width - (double)d) > 0.5 ||
                fabs((double)sf.size.height - (double)d) > 0.5) {
                s.frame = CGRectMake(0, 0, d, d);
            }
            s.layer.cornerRadius = d / 2.0;
            s.layer.masksToBounds = YES;
        }
    } @catch(...) {}
}

// 头像本体缩到 44（与音乐唱片同尺寸），只改内部图片视图、圆心不动，玻璃盘仍 Ø56
static void DKAvatarResize(UIView *btn){
    if (!btn) return;
    CGFloat want = 44.0;
    for (UIView *s in btn.subviews) {
        if (![s isKindOfClass:[UIImageView class]]) continue;
        CGFloat w = s.bounds.size.width, h = s.bounds.size.height;
        if (w < 34 || w > 54 || h < 34 || h > 54) continue;
        CGRect r = s.frame;
        if (fabs((double)r.size.width - (double)want) > 0.5 || fabs((double)r.size.height - (double)want) > 0.5) {
            CGPoint c = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
            s.frame = CGRectMake(c.x - want / 2.0, c.y - want / 2.0, want, want);
        }
        s.layer.cornerRadius = want / 2.0;
        s.layer.masksToBounds = YES;
        s.clipsToBounds = YES;
    }
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

// 头像那个 AWEButton 自己重排时会把内部图片再摆回 48，所以在它的 layoutSubviews 之后再压一次
static void (*orig_btnLayout)(id, SEL);
static void hook_btnLayout(id self, SEL _cmd){
    if (orig_btnLayout) orig_btnLayout(self, _cmd);
    @try {
        UIView *btn = (UIView *)self;
        UIView *sv = btn.superview;
        if (sv) {
            NSString *scn = NSStringFromClass([sv class]) ?: @"";
            if ([scn isEqualToString:@"AWEPlayInteractionUserProfilePictureView"]) {
                DKAvatarResize(btn);
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
        // 头像统一成 44x44（与音乐唱片同尺寸），圆心不动
        if (icon) DKAvatarSize(icon, 44.0);
        if (icon) {
            // 用头像本体的绝对矩形直接定圆心，避免二次换算误差
            CGRect btnRect = [icon convertRect:icon.bounds toView:v];
            DKApplyDiscAt(v, CGPointMake(CGRectGetMidX(btnRect), CGRectGetMidY(btnRect)), 56.0);
        } else {
            DKApplyDisc(v, v, 56.0);
        }
        DKAvatarClean(v, icon);
        DKAvatarResize(icon);
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
// ===== 底部「已私信给xxx」提示条：圆角取高度一半，主文案改白 =====
static void DKWhitenLabels(UIView *v){
    if (!v) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:v];
    int guard = 0;
    while (q.count > 0 && guard++ < 400) {
        UIView *c = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        if ([c isKindOfClass:[UILabel class]] && c.bounds.size.width >= 60.0) {
            ((UILabel *)c).textColor = [UIColor whiteColor];
        }
        for (UIView *s in c.subviews) [q addObject:s];
    }
}

static void DKShareToastFix(UIView *v){
    if (!v) return;
    CGFloat h = v.bounds.size.height;
    if (h < 8.0) return;
    CGFloat r = h / 2.0;
    if (fabs((double)v.layer.cornerRadius - (double)r) > 0.5) v.layer.cornerRadius = r;
    v.layer.masksToBounds = YES;
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:[UIVisualEffectView class]]) {
            if (fabs((double)s.layer.cornerRadius - (double)r) > 0.5) s.layer.cornerRadius = r;
            s.layer.masksToBounds = YES;
            for (UIView *ss in s.subviews) { ss.layer.cornerRadius = r; ss.layer.masksToBounds = YES; }
        }
    }
    DKWhitenLabels(v);
}

static void (*orig_tipsLayout)(id, SEL);
static void (*orig_shareLayout)(id, SEL);
static void hook_tipsLayout(id self, SEL _cmd){
    if (orig_tipsLayout) orig_tipsLayout(self, _cmd);
    @try { DKShareToastFix((UIView *)self); } @catch(NSException *e) {}
}
static void hook_shareLayout(id self, SEL _cmd){
    if (orig_shareLayout) orig_shareLayout(self, _cmd);
    @try { DKShareToastFix((UIView *)self); } @catch(NSException *e) {}
}

// ===== 收藏/取消收藏 提示条（AFDSnackBarCustomView）玻璃 + 白字白图标 =====
static NSString *DKToastText(UIView *v){
    if (!v) return nil;
    NSMutableArray *q = [NSMutableArray arrayWithObject:v];
    int guard = 0;
    while (q.count > 0 && guard++ < 60) {
        UIView *c = [q objectAtIndex:0];
        [q removeObjectAtIndex:0];
        if ([c isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)c).text;
            if (t.length) return t;
        }
        for (UIView *s in c.subviews) [q addObject:s];
    }
    return nil;
}
static void DKWhitenIconAndText(UIView *v){
    if (!v) return;
    if ([v isKindOfClass:[UILabel class]]) {
        ((UILabel *)v).textColor = [UIColor whiteColor];
    } else if ([v isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)v;
        if (iv.image) iv.image = [iv.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iv.tintColor = [UIColor whiteColor];
    }
    for (UIView *s in v.subviews) {
        if (s.tag == DK_TAG) continue;
        DKWhitenIconAndText(s);
    }
}
static void DKClearBackingDeep(UIView *v, int depth){
    if (!v || depth > 3) return;
    if (v.tag == DK_TAG) return;
    if ([v isKindOfClass:[UIVisualEffectView class]]) { v.hidden = YES; return; }
    if (v.backgroundColor && ![v.backgroundColor isEqual:[UIColor clearColor]]) {
        v.backgroundColor = [UIColor clearColor];
    }
    // 宿主自己的图层可能带整块底图（contents），这层是清 backgroundColor 清不掉的，会盖在玻璃上发白
    if (depth == 0 && v.layer.contents) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.layer.contents = nil;
        [CATransaction commit];
    }
    // 视图自身的图层底色也要清（此前只清了 backgroundColor，视图自己 layer 上的底色会盖在玻璃上发白）
    if (v.layer.backgroundColor) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.layer.backgroundColor = NULL;
        [CATransaction commit];
    }
    for (CALayer *l in v.layer.sublayers) {
        if (!l.backgroundColor) continue;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        l.backgroundColor = NULL;
        [CATransaction commit];
    }
    for (UIView *s in v.subviews) DKClearBackingDeep(s, depth + 1);
}
// ===== 临时取证浮层：取消提示条为什么还有白雾 =====
static UILabel *g_dkHud = nil;
static double g_dkHudAt = -10.0;
static void DKHudShow(NSString *body){
    double now = CFAbsoluteTimeGetCurrent();
    if (now - g_dkHudAt < 0.5) return;
    g_dkHudAt = now;
    NSString *text = [body copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = nil;
        for (UIWindow *win in [UIApplication sharedApplication].windows) { if (win.isKeyWindow) { w = win; break; } }
        if (!w) w = [[UIApplication sharedApplication].windows firstObject];
        if (!w) return;
        if (!g_dkHud) {
            g_dkHud = [[UILabel alloc] initWithFrame:CGRectMake(6, 120, w.bounds.size.width - 12, 460)];
            g_dkHud.numberOfLines = 0;
            g_dkHud.font = [UIFont systemFontOfSize:10];
            g_dkHud.textColor = [UIColor whiteColor];
            g_dkHud.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
            g_dkHud.userInteractionEnabled = NO;
            [w addSubview:g_dkHud];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [g_dkHud removeFromSuperview];
                g_dkHud = nil;
            });
        }
        g_dkHud.text = text;
        [w bringSubviewToFront:g_dkHud];
    });
}
static NSString *DKColorDesc(UIColor *c){
    if (!c) return @"nil";
    if ([c isEqual:[UIColor clearColor]]) return @"clear";
    CGColorRef g = c.CGColor;
    if (!g) return @"?";
    size_t n = CGColorGetNumberOfComponents(g);
    const CGFloat *cc = CGColorGetComponents(g);
    if (n == 4) return [NSString stringWithFormat:@"r%.2f g%.2f b%.2f a%.2f", cc[0], cc[1], cc[2], cc[3]];
    if (n == 2) return [NSString stringWithFormat:@"w%.2f a%.2f", cc[0], cc[1]];
    return @"?";
}
static void DKDumpCancelToast(UIView *v){
    NSMutableString *o = [NSMutableString string];
    [o appendFormat:@"BAR %@ %@ bg=%@ a=%.2f ownBg=%@ ownC=%d\n", NSStringFromClass(object_getClass(v)), NSStringFromCGRect(v.frame), DKColorDesc(v.backgroundColor), (double)v.alpha, v.layer.backgroundColor ? @"yes" : @"nil", v.layer.contents ? 1 : 0];
    UIView *p = v.superview;
    for (int i = 0; i < 3 && p; i++) {
        [o appendFormat:@"P%d %@ %@ bg=%@ layers=%lu\n", i, NSStringFromClass(object_getClass(p)), NSStringFromCGRect(p.frame), DKColorDesc(p.backgroundColor), (unsigned long)p.layer.sublayers.count];
        for (UIView *sib in p.subviews) {
            if (sib == v || sib.tag == DK_TAG) continue;
            if (!CGRectIntersectsRect(sib.frame, v.frame)) continue;
            [o appendFormat:@"  S %@ %@ bg=%@ hid=%d a=%.2f\n", NSStringFromClass(object_getClass(sib)), NSStringFromCGRect(sib.frame), DKColorDesc(sib.backgroundColor), (int)sib.hidden, (double)sib.alpha];
        }
        p = p.superview;
    }
    int gi = 0;
    for (UIView *sv in v.subviews) if (sv.tag == DK_TAG) {
        gi++;
        [o appendFormat:@"G %@ %@ hid=%d a=%.2f sub=%lu\n", NSStringFromClass(object_getClass(sv)), NSStringFromCGRect(sv.frame), (int)sv.hidden, (double)sv.alpha, (unsigned long)sv.subviews.count];
        for (UIView *gv in sv.subviews) {
            NSString *e = @"-";
            if ([gv isKindOfClass:[UIVisualEffectView class]]) {
                id eff = [(UIVisualEffectView *)gv effect];
                if (eff) e = [NSString stringWithFormat:@"%@", eff];
            }
            [o appendFormat:@"  Gs %@ hid=%d a=%.2f E=%@\n", NSStringFromClass(object_getClass(gv)), (int)gv.hidden, (double)gv.alpha, e];
        }
    }
    [o appendFormat:@"GLASS=%d\n", gi];
    UIWindow *win = v.window;
    if (win) {
        NSArray *wls = win.layer.sublayers;
        [o appendFormat:@"WIN %@ layers=%lu\n", NSStringFromClass(object_getClass(win)), (unsigned long)wls.count];
        for (CALayer *wl in wls) {
            if ([wls indexOfObject:wl] > 5) break;
            [o appendFormat:@"  W %@ hid=%d a=%.2f fr=%@\n", NSStringFromClass(object_getClass(wl)), (int)wl.hidden, (double)wl.opacity, NSStringFromCGRect(wl.frame)];
        }
    }
    NSArray *ls = v.layer.sublayers;
    for (CALayer *l in ls) {
        if (ls.count > 8 && [ls indexOfObject:l] > 7) break;
        [o appendFormat:@"L %@ bg=%@ hid=%d\n", NSStringFromClass(object_getClass(l)), l.backgroundColor ? @"dark" : @"nil", (int)l.hidden];
    }
    DKHudShow(o);
}

// 取消提示条（DUXBottomNotification）会在图层树上画白色/渐变装饰层，清 backgroundColor 清不掉，
// 这里按“这层是否属于文本或图标视图”来判断，其它装饰层一律隐藏
static void DKStripDecorLayers(UIView *v){
    if (!v) return;
    NSMutableArray *keep = [NSMutableArray array];
    for (UIView *s in v.subviews) {
        // 自家玻璃层必须保留，否则会把玻璃一起当装饰层隐藏掉（白雾的元凶）
        if (s.tag == DK_TAG) { [keep addObject:s]; continue; }
        if ([s isKindOfClass:[UILabel class]] || [s isKindOfClass:[UIImageView class]] || [s isKindOfClass:[UIControl class]]) [keep addObject:s];
    }
    NSMutableArray *ls = [NSMutableArray arrayWithArray:v.layer.sublayers];
    for (CALayer *l in ls) {
        if (!l || l == v.layer) continue;
        id d = l.delegate;
        BOOL keepIt = NO;
        if ([d isKindOfClass:[UIView class]] && d != v) {
            for (UIView *k in keep) if ((UIView *)d == k) { keepIt = YES; break; }
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        l.backgroundColor = NULL;
        if (!keepIt) {
            l.hidden = YES;
            l.contents = nil;
        }
        [CATransaction commit];
    }
}

static void DKFeedFavToast(UIView *v){
    if (!v) return;
    CGRect b = v.bounds;
    if (b.size.width < 40.0 || b.size.height < 8.0) return;
    NSString *t = DKToastText(v);
    if (!t.length || [t rangeOfString:@"收藏"].location == NSNotFound) return;
    CGFloat r = b.size.height / 2.0;
    DKClearBackingDeep(v, 0);
    BOOL isCancelBar = [NSStringFromClass(object_getClass(v)) isEqualToString:@"AWEPlayInteractionSnackBar"];
    if (isCancelBar) DKStripDecorLayers(v);
    if (fabs((double)v.layer.cornerRadius - (double)r) > 0.5) v.layer.cornerRadius = r;
    v.layer.masksToBounds = YES;
    if (!DKApplyGlassRemote(v, b, r)) {
        DKApplyGlassAt(v, b, r);
        for (UIView *sv in v.subviews) if (sv.tag == DK_TAG) sv.layer.hidden = NO;
    }
    // 浅色外观下 UIGlassEffect 自带一层白色调，大面积铺在提示条上就成了白雾；
    // 只把这块玻璃切到深色外观取材质，配方结构不变
    for (UIView *sv in v.subviews) {
        if (sv.tag != DK_TAG) continue;
        sv.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        for (UIView *inner in sv.subviews) inner.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    @try { DKDumpCancelToast(v); } @catch (NSException *e) {}
    DKWhitenIconAndText(v);
}
static void (*orig_snackLayout)(id, SEL);
static void hook_snackLayout(id self, SEL _cmd){
    if (orig_snackLayout) orig_snackLayout(self, _cmd);
    @try { DKFeedFavToast((UIView *)self); } @catch (NSException *e) {}
}
// 取消收藏用的是另一套：AWEPlayInteractionSnackBar（DUXBottomNotification）
static void (*orig_playSnackLayout)(id, SEL);
static void hook_playSnackLayout(id self, SEL _cmd){
    if (orig_playSnackLayout) orig_playSnackLayout(self, _cmd);
    @try { DKFeedFavToast((UIView *)self); } @catch (NSException *e) {}
}

// ===== 游戏标签 / 弹幕按钮 / 全屏观看 三处胶囊玻璃（沿用六按钮同一套配料） =====
static void DKGlassPill(UIView *v){
    if (!v) return;
    CGRect b = v.bounds;
    if (b.size.width < 8.0 || b.size.height < 8.0) return;
    if (isnan(b.size.width) || isnan(b.size.height)) return;
    DKApplyGlassAt(v, b, b.size.height / 2.0);
}

// 弹幕按钮 / 全屏观看 两处胶囊玻璃
static void (*orig_pillLayout2)(id, SEL);
static void hook_pillLayout2(id self, SEL _cmd){
    if (orig_pillLayout2) orig_pillLayout2(self, _cmd);
    @try { DKGlassPill((UIView *)self); } @catch(NSException *e) {}
}
static void (*orig_pillLayout3)(id, SEL);
static void hook_pillLayout3(id self, SEL _cmd){
    if (orig_pillLayout3) orig_pillLayout3(self, _cmd);
    @try { DKGlassPill((UIView *)self); } @catch(NSException *e) {}
}

// ===== 停掉点赞 / 收藏按钮上的爆心、星标等弹出动画 =====
static BOOL DKNameLooksLikeFav(NSString *n){
    if (!n || n.length == 0) return NO;
    NSString *l = [n lowercaseString];
    if ([l containsString:@"collectionview"]) return NO;
    static NSArray *kws;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kws = @[@"likeanim", @"digganim", @"favoranim", @"collectanim", @"heartanim",
                @"likebubble", @"favoriteburst", @"diggburst", @"burst", @"particle",
                @"explode", @"confetti"];
    });
    for (NSString *k in kws) if ([l containsString:k]) return YES;
    static NSArray *cls;
    static dispatch_once_t once2;
    dispatch_once(&once2, ^{
        cls = @[@"aweedigg", @"awelike", @"aweplayinteractionlike", @"aweplayinteractiondigg",
                @"awefoointeractionlike", @"awefavor", @"aweplayinteractionfavor",
                @"awecollect", @"aweplayinteractioncollect"];
    });
    for (NSString *k in cls) if ([l containsString:k]) return YES;
    return NO;
}

// 用无障碍文案识别「点赞 / 收藏」按钮（抖音给这两个按钮都设了中文 a11y 文案）
static BOOL DKViewIsFavTarget(UIView *v){
    if (!v) return NO;
    NSString *lab = v.accessibilityLabel;
    NSString *ident = v.accessibilityIdentifier;
    for (NSString *t in @[lab ?: @"", ident ?: @""]) {
        if (t.length == 0) continue;
        if ([t containsString:@"赞"] || [t containsString:@"收藏"] ||
            [t containsString:@"Digg"] || [t containsString:@"Like"] ||
            [t containsString:@"Favorite"] || [t containsString:@"Collect"]) return YES;
    }
    return NO;
}

// 父链里是否有「点赞 / 收藏」按钮
static BOOL DKViewOrChildIsFav(UIView *v){
    if (DKViewIsFavTarget(v)) return YES;
    for (UIView *c in v.subviews) {
        if (DKViewIsFavTarget(c)) return YES;
        for (UIView *cc in c.subviews) if (DKViewIsFavTarget(cc)) return YES;
    }
    return NO;
}
static BOOL DKViewInFavAncestor(UIView *v){
    int depth = 0;
    while (v && depth++ < 12) {
        if (DKViewOrChildIsFav(v)) return YES;
        if (DKNameLooksLikeFav(NSStringFromClass([v class]))) return YES;
        v = v.superview;
    }
    return NO;
}
// 爆心 / 星标是 Lottie（LOTAnimationView）当场插进按钮里的
static BOOL DKIsLottieClass(NSString *cn){
    if (cn.length == 0) return NO;
    return [cn hasPrefix:@"LOT"] || [cn hasPrefix:@"lottie"] || [cn containsString:@"Lottie"];
}
// 加速并隐藏 Lottie：动画看不见，但完成回调照常触发（否则图标状态不会翻转）
static void DKHideLottieFast(UIView *v){
    if (!v) return;
    v.alpha = 0.0;
    v.userInteractionEnabled = NO;
    SEL spd = NSSelectorFromString(@"setAnimationSpeed:");
    if ([v respondsToSelector:spd]) {
        NSMethodSignature *sig = [v methodSignatureForSelector:spd];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:v]; [inv setSelector:spd];
            double speed = 12.0;
            [inv setArgument:&speed atIndex:2];
            [inv invoke];
        }
    }
}
static void (*orig_dk_addSubview)(id, SEL, UIView *);
static void dk_addSubview(id self, SEL _cmd, UIView *v){
    BOOL favLot = NO;
    @try {
        if (v && DKIsLottieClass(NSStringFromClass([v class])) &&
            DKViewInFavAncestor((UIView *)self)) favLot = YES;
    } @catch (NSException *e) {}
    if (orig_dk_addSubview) orig_dk_addSubview(self, _cmd, v);
    if (favLot) @try { DKHideLottieFast(v); } @catch (NSException *e) {}
}

static void (*orig_dk_lotPlay)(id, SEL);
static void dk_lotPlay(id self, SEL _cmd){
    BOOL fav = NO;
    @try { fav = DKViewInFavAncestor(((UIView *)self).superview); } @catch (NSException *e) {}
    if (fav) @try { DKHideLottieFast((UIView *)self); } @catch (NSException *e) {}
    if (orig_dk_lotPlay) orig_dk_lotPlay(self, _cmd);
}
static void (*orig_dk_lotPlayRange)(id, SEL, id, id, id);
static void dk_lotPlayRange(id self, SEL _cmd, id a, id b, id c){
    BOOL fav = NO;
    @try { fav = DKViewInFavAncestor(((UIView *)self).superview); } @catch (NSException *e) {}
    if (fav) @try { DKHideLottieFast((UIView *)self); } @catch (NSException *e) {}
    if (orig_dk_lotPlayRange) orig_dk_lotPlayRange(self, _cmd, a, b, c);
}

// ===== 收藏按钮震动 + 点赞震动统一 =====
static NSInteger DK_FAV_STYLE = 2; // UIImpactFeedbackStyleMedium

static double dk_lastTouchAt = -1.0;
static double dk_likeArmAt = -1.0;
static double dk_favArmAt = -1.0;
static double dk_lastFavPlayAt = -10.0;
static double dk_lastLikeReplaceAt = -10.0;
static BOOL dk_replaying = NO;
static NSInteger dk_curImpactStyle = 0;

static void DKHandleFavText(NSString *t);

static BOOL DKViewLabelContains(UIView *v, NSArray *kws){
    if (!v) return NO;
    NSMutableArray *texts = [NSMutableArray array];
    for (int lv = 0; lv < 4 && v; lv++) {
        if (v.accessibilityLabel) [texts addObject:v.accessibilityLabel];
        if (v.accessibilityIdentifier) [texts addObject:v.accessibilityIdentifier];
        for (UIView *c in v.subviews) {
            if (c.accessibilityLabel) [texts addObject:c.accessibilityLabel];
            if (c.accessibilityIdentifier) [texts addObject:c.accessibilityIdentifier];
        }
        v = v.superview;
    }
    for (NSString *t in texts) {
        for (NSString *k in kws) if ([t rangeOfString:k].location != NSNotFound) return YES;
    }
    return NO;
}
static BOOL DKIsLikeButton(UIView *v){
    static NSArray *k;
    static dispatch_once_t o; dispatch_once(&o, ^{ k = @[@"赞", @"Digg", @"Like"]; });
    return DKViewLabelContains(v, k);
}
static BOOL DKIsFavButton(UIView *v){
    static NSArray *k;
    static dispatch_once_t o; dispatch_once(&o, ^{ k = @[@"收藏", @"Favorite", @"Collect"]; });
    return DKViewLabelContains(v, k);
}
static void DKPlayImpact(NSInteger style){
    dk_replaying = YES;
    @try {
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:(UIImpactFeedbackStyle)style];
        [g prepare];
        [g impactOccurred];
    } @catch (NSException *e) {}
    dk_replaying = NO;
}

static void (*orig_dk_sendEvent)(id, SEL, UIEvent *);
static void dk_sendEvent(id self, SEL _cmd, UIEvent *e){
    @try {
        if (e && e.type == UIEventTypeTouches && e.allTouches.count > 0) {
            dk_lastTouchAt = CFAbsoluteTimeGetCurrent();
            for (UITouch *t in e.allTouches) {
                UIView *v = t.view;
                if (!v) continue;
                if (DKIsLikeButton(v)) { dk_likeArmAt = dk_lastTouchAt; break; }
                if (DKIsFavButton(v)) dk_favArmAt = dk_lastTouchAt;
            }
        }
    } @catch (NSException *e2) {}
    if (orig_dk_sendEvent) orig_dk_sendEvent(self, _cmd, e);
}

// 收藏/取消一律只看 app 自己的提示文案（与收藏量大小无关）
static void (*orig_dk_labelText)(id, SEL, NSString *);
static void dk_labelText(id self, SEL _cmd, NSString *t){
    if (orig_dk_labelText) orig_dk_labelText(self, _cmd, t);
    @try { DKHandleFavText(t); } @catch (NSException *e) {}
}
static void (*orig_dk_labelAttr)(id, SEL, NSAttributedString *);
static void dk_labelAttr(id self, SEL _cmd, NSAttributedString *t){
    if (orig_dk_labelAttr) orig_dk_labelAttr(self, _cmd, t);
    @try { DKHandleFavText([t string]); } @catch (NSException *e) {}
}

static BOOL DKShouldReplaceLikeHaptic(void){
    if (dk_replaying) return NO;
    double now = CFAbsoluteTimeGetCurrent();
    if (dk_likeArmAt <= 0.0 || now - dk_likeArmAt > 1.2) return NO;
    if (now - dk_lastLikeReplaceAt < 0.5) return YES;
    dk_lastLikeReplaceAt = now;
    DKPlayImpact(DK_FAV_STYLE);
    return YES;
}

static id (*orig_dk_impactInit)(id, SEL, NSInteger);
static id dk_impactInit(id self, SEL _cmd, NSInteger style){
    dk_curImpactStyle = style;
    return orig_dk_impactInit ? orig_dk_impactInit(self, _cmd, style) : nil;
}
static void (*orig_dk_impact)(id, SEL);
static void dk_impact(id self, SEL _cmd){
    if (DKShouldReplaceLikeHaptic()) return;
    if (orig_dk_impact) orig_dk_impact(self, _cmd);
}
static void (*orig_dk_impactIntensity)(id, SEL, double);
static void dk_impactIntensity(id self, SEL _cmd, double inten){
    if (DKShouldReplaceLikeHaptic()) return;
    if (orig_dk_impactIntensity) orig_dk_impactIntensity(self, _cmd, inten);
}
static void (*orig_dk_note)(id, SEL, NSInteger);
static void dk_note(id self, SEL _cmd, NSInteger t){
    if (DKShouldReplaceLikeHaptic()) return;
    if (orig_dk_note) orig_dk_note(self, _cmd, t);
}
static void (*orig_dk_selChanged)(id, SEL);
static void dk_selChanged(id self, SEL _cmd){
    if (DKShouldReplaceLikeHaptic()) return;
    if (orig_dk_selChanged) orig_dk_selChanged(self, _cmd);
}

// ===== 收藏方向判定：靠 app 自己的成功/取消提示文案（与收藏量大小无关） =====
static double dk_favCancelAt = -10.0;

static void DKFireFavOnce(void){
    dispatch_async(dispatch_get_main_queue(), ^{
        double now = CFAbsoluteTimeGetCurrent();
        if (now - dk_lastFavPlayAt < 0.35) return;
        dk_lastFavPlayAt = now;
        DKPlayImpact(DK_FAV_STYLE);
    });
}
static BOOL DKTextIsFavCancel(NSString *t){
    if (!t.length) return NO;
    if ([t containsString:@"已取消"]) return YES;
    if ([t containsString:@"取消收藏"]) return YES;
    return NO;
}
static BOOL DKTextIsFavSuccess(NSString *t){
    if (!t.length) return NO;
    if ([t containsString:@"取消"]) return NO;
    if ([t containsString:@"收藏成功"]) return YES;
    if ([t containsString:@"已添加到"]) return YES;
    if ([t containsString:@"已收藏"]) return YES;
    return NO;
}
static void DKHandleFavText(NSString *t){
    if (!t.length) return;
    BOOL armed = (dk_favArmAt > 0.0 && CFAbsoluteTimeGetCurrent() - dk_favArmAt < 4.0);
    if (!armed) return;
    if (DKTextIsFavCancel(t)) { dk_favCancelAt = CFAbsoluteTimeGetCurrent(); return; }
    if (DKTextIsFavSuccess(t)) {
        if (CFAbsoluteTimeGetCurrent() - dk_favCancelAt < 0.6) return;
        DKFireFavOnce();
    }
}
static void (*orig_dk_setA11yLabel)(id, SEL, NSString *);
static void dk_setA11yLabel(id self, SEL _cmd, NSString *v){
    if (orig_dk_setA11yLabel) orig_dk_setA11yLabel(self, _cmd, v);
    @try { DKHandleFavText(v); } @catch (NSException *e) {}
}
static void (*orig_dk_setA11yValue)(id, SEL, NSString *);
static void dk_setA11yValue(id self, SEL _cmd, NSString *v){
    if (orig_dk_setA11yValue) orig_dk_setA11yValue(self, _cmd, v);
    @try { DKHandleFavText(v); } @catch (NSException *e) {}
}

static void DKInstallFavHaptic(void){
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c1 = objc_getClass("UIImpactFeedbackGenerator");
    if (c1) {
        MSHookMessageEx(c1, sel_registerName("initWithStyle:"), (IMP)dk_impactInit, (IMP *)&orig_dk_impactInit);
        MSHookMessageEx(c1, sel_registerName("impactOccurred"), (IMP)dk_impact, (IMP *)&orig_dk_impact);
        MSHookMessageEx(c1, sel_registerName("impactOccurredWithIntensity:"), (IMP)dk_impactIntensity, (IMP *)&orig_dk_impactIntensity);
    }
    Class c2 = objc_getClass("UINotificationFeedbackGenerator");
    if (c2) MSHookMessageEx(c2, sel_registerName("notificationOccurred:"), (IMP)dk_note, (IMP *)&orig_dk_note);
    Class c3 = objc_getClass("UISelectionFeedbackGenerator");
    if (c3) MSHookMessageEx(c3, sel_registerName("selectionChanged"), (IMP)dk_selChanged, (IMP *)&orig_dk_selChanged);
    Class app = objc_getClass("UIApplication");
    if (app) MSHookMessageEx(app, sel_registerName("sendEvent:"), (IMP)dk_sendEvent, (IMP *)&orig_dk_sendEvent);
    Class lab = objc_getClass("UILabel");
    if (lab) {
        MSHookMessageEx(lab, sel_registerName("setText:"), (IMP)dk_labelText, (IMP *)&orig_dk_labelText);
        MSHookMessageEx(lab, sel_registerName("setAttributedText:"), (IMP)dk_labelAttr, (IMP *)&orig_dk_labelAttr);
    }
    Class uv2 = objc_getClass("UIView");
    if (uv2) {
        MSHookMessageEx(uv2, sel_registerName("setAccessibilityValue:"), (IMP)dk_setA11yValue, (IMP *)&orig_dk_setA11yValue);
        MSHookMessageEx(uv2, sel_registerName("setAccessibilityLabel:"), (IMP)dk_setA11yLabel, (IMP *)&orig_dk_setA11yLabel);
    }
}

static void DKInstallNoFavAnim(void){
    DKInstallFavHaptic();
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class uv = objc_getClass("UIView");
    if (uv) MSHookMessageEx(uv, sel_registerName("addSubview:"), (IMP)dk_addSubview, (IMP *)&orig_dk_addSubview);
    Class lo = objc_getClass("LOTAnimationView");
    if (lo) {
        MSHookMessageEx(lo, sel_registerName("play"), (IMP)dk_lotPlay, (IMP *)&orig_dk_lotPlay);
        MSHookMessageEx(lo, sel_registerName("playFromFrame:toFrame:completion:"), (IMP)dk_lotPlayRange, (IMP *)&orig_dk_lotPlayRange);
    }
}

// ===== 强制开启「移除全部昵称上方标签」(DYKillerPlaybackRemoveAllAnchors)，其余开关不受影响 =====
#define DK_KEY_RM_ANCHORS @"DYKillerPlaybackRemoveAllAnchors"
static BOOL (*orig_dk_boolForKey)(id, SEL, NSString *);
static NSInteger (*orig_dk_integerForKey)(id, SEL, NSString *);
static id (*orig_dk_objectForKey)(id, SEL, NSString *);
static NSString *(*orig_dk_stringForKey)(id, SEL, NSString *);
static BOOL dk_boolForKey(id self, SEL _cmd, NSString *key){
    if (key && [key isEqualToString:DK_KEY_RM_ANCHORS]) return YES;
    return orig_dk_boolForKey ? orig_dk_boolForKey(self, _cmd, key) : NO;
}
static NSInteger dk_integerForKey(id self, SEL _cmd, NSString *key){
    if (key && [key isEqualToString:DK_KEY_RM_ANCHORS]) return 1;
    return orig_dk_integerForKey ? orig_dk_integerForKey(self, _cmd, key) : 0;
}
static id dk_objectForKey(id self, SEL _cmd, NSString *key){
    if (key && [key isEqualToString:DK_KEY_RM_ANCHORS]) return @YES;
    return orig_dk_objectForKey ? orig_dk_objectForKey(self, _cmd, key) : nil;
}
static NSString *dk_stringForKey(id self, SEL _cmd, NSString *key){
    if (key && [key isEqualToString:DK_KEY_RM_ANCHORS]) return @"1";
    return orig_dk_stringForKey ? orig_dk_stringForKey(self, _cmd, key) : nil;
}
static void DKForceRemoveAllAnchors(void){
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:DK_KEY_RM_ANCHORS];
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:DK_KEY_RM_ANCHORS];
    [[NSUserDefaults standardUserDefaults] synchronize];
    Class ud = objc_getClass("NSUserDefaults");
    if (ud) {
        MSHookMessageEx(ud, sel_registerName("boolForKey:"), (IMP)dk_boolForKey, (IMP *)&orig_dk_boolForKey);
        MSHookMessageEx(ud, sel_registerName("integerForKey:"), (IMP)dk_integerForKey, (IMP *)&orig_dk_integerForKey);
        MSHookMessageEx(ud, sel_registerName("objectForKey:"), (IMP)dk_objectForKey, (IMP *)&orig_dk_objectForKey);
        MSHookMessageEx(ud, sel_registerName("stringForKey:"), (IMP)dk_stringForKey, (IMP *)&orig_dk_stringForKey);
    }
}

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


static void (*orig_navLayout)(id, SEL);
static void hook_navLayout(id self, SEL _cmd){
    orig_navLayout(self, _cmd);
    @try { DKNavGlass((UIView *)self); } @catch(NSException *e) {}
}

static void (*orig_cdNavLayout)(id, SEL);
static void hook_cdNavLayout(id self, SEL _cmd){
    if (orig_cdNavLayout) orig_cdNavLayout(self, _cmd);
    @try {
        UIView *v = (UIView *)self;
        if (v.bounds.size.width > 300) {
            dispatch_async(dispatch_get_main_queue(), ^{ DKDetailNavGlass(v); });
        }
    } @catch(NSException *e) {}
}

static void (*orig_cdInputLayout)(id, SEL);
static void hook_cdInputLayout(id self, SEL _cmd){
    if (orig_cdInputLayout) orig_cdInputLayout(self, _cmd);
    @try {
        UIView *v = (UIView *)self;
        dispatch_async(dispatch_get_main_queue(), ^{ DKCommentInputGlass(v); });
    } @catch(NSException *e) {}
}

static void (*orig_cdVCLayout)(id, SEL);
static void hook_cdVCLayout(id self, SEL _cmd){
    if (orig_cdVCLayout) orig_cdVCLayout(self, _cmd);
    // 布局回调里插视图会触发重入，延到本次布局结束后再铺
    @try {
        UIView *v = ((UIViewController *)self).view;
        dispatch_async(dispatch_get_main_queue(), ^{ DKCommentPageGlass(v); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKCommentPageGlass(v); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKCommentPageGlass(v); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.90 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKCommentPageGlass(v); });
    } @catch(NSException *e) {}
}

static void (*orig_quickCellLayout)(id, SEL);
static void hook_quickCellLayout(id self, SEL _cmd){
    if (orig_quickCellLayout) orig_quickCellLayout(self, _cmd);
    @try { DKQuickEmojiGlass((UIView *)self); } @catch(NSException *e) {}
}

static void (*orig_quickBarLayout)(id, SEL);
static void hook_quickBarLayout(id self, SEL _cmd){
    if (orig_quickBarLayout) orig_quickBarLayout(self, _cmd);
    @try { DKQuickEmojiBar((UIView *)self); } @catch(NSException *e) {}
}

static void (*orig_detailVCLayout)(id, SEL, BOOL);
static void hook_detailVCLayout(id self, SEL _cmd, BOOL animated){
    if (orig_detailVCLayout) orig_detailVCLayout(self, _cmd, animated);
    @try {
        UIView *v = [(UIViewController *)self view];
        DKDetailPageGlass(v);
        // 子视图常比 VC 晚一轮布局，补几次
        for (NSNumber *sec in @[@0.05, @0.15, @0.35, @0.70]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                DKDetailPageGlass([(UIViewController *)self view]);
            });
        }
    } @catch(NSException *e) {}
}

static void (*orig_detailNavLayout)(id, SEL);
static void hook_detailNavLayout(id self, SEL _cmd){
    if (orig_detailNavLayout) orig_detailNavLayout(self, _cmd);
    @try { DKDetailNavGlass((UIView *)self); } @catch(NSException *e) {}
}

static void (*orig_inputBarLayout)(id, SEL);
static void hook_inputBarLayout(id self, SEL _cmd){
    if (orig_inputBarLayout) orig_inputBarLayout(self, _cmd);
    @try { DKInputBarGlass((UIView *)self); } @catch(NSException *e) {}
}

static void (*orig_pop_setButtons)(id, SEL, id);
static void hook_pop_setButtons(id self, SEL _cmd, id arr){
    if (orig_pop_setButtons) orig_pop_setButtons(self, _cmd, arr);
    @try { DKPopoverGlass((UIView *)self); } @catch(NSException *e) {}
}

static void (*orig_pop_setContent)(id, SEL, id);
static void hook_pop_setContent(id self, SEL _cmd, id v){
    if (orig_pop_setContent) orig_pop_setContent(self, _cmd, v);
    @try { DKPopoverGlass((UIView *)self); } @catch(NSException *e) {}
}

static void (*orig_popoverLayout)(id, SEL);
static void hook_popoverLayout(id self, SEL _cmd){
    if (orig_popoverLayout) orig_popoverLayout(self, _cmd);
    @try {
        UIView *sheet = (UIView *)self;
        DKPopoverGlass(sheet);
        // app 在布局/赋值过程中会把标题色写回黑色，这里再补几次
        for (double t = 0.03; t <= 0.62; t += 0.15) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try { DKPopoverGlass(sheet); } @catch(NSException *e) {}
            });
        }
    } @catch(NSException *e) {}
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
        Class btnCls = NSClassFromString(@"AWEButton");
        if (btnCls && !orig_btnLayout) {
            MSHookMessageEx(btnCls, sel_registerName("layoutSubviews"), (IMP)hook_btnLayout, (IMP *)&orig_btnLayout);
        }
        Class ring = NSClassFromString(@"AFDColorRingView");
        if (ring && !orig_ringLayout) {
            MSHookMessageEx(ring, sel_registerName("layoutSubviews"), (IMP)hook_ringLayout, (IMP *)&orig_ringLayout);
        }
        Class danmuC = NSClassFromString(@"AWEPlayDanmakuInputContainView");
        if (danmuC) MSHookMessageEx(danmuC, sel_registerName("layoutSubviews"), (IMP)hook_pillLayout2, (IMP *)&orig_pillLayout2);
        Class landC = NSClassFromString(@"AWELandscapeFeedEntryView");
        if (landC) MSHookMessageEx(landC, sel_registerName("layoutSubviews"), (IMP)hook_pillLayout3, (IMP *)&orig_pillLayout3);
        Class tipsC = NSClassFromString(@"AWEIMBottomTipsContainerView");
        if (tipsC) MSHookMessageEx(tipsC, sel_registerName("layoutSubviews"), (IMP)hook_tipsLayout, (IMP *)&orig_tipsLayout);
        Class snackC = NSClassFromString(@"AFDSnackBarCustomView");
        if (snackC) MSHookMessageEx(snackC, sel_registerName("layoutSubviews"), (IMP)hook_snackLayout, (IMP *)&orig_snackLayout);
        Class playSnack = NSClassFromString(@"AWEPlayInteractionSnackBar");
        if (playSnack) MSHookMessageEx(playSnack, sel_registerName("layoutSubviews"), (IMP)hook_playSnackLayout, (IMP *)&orig_playSnackLayout);
        Class shareC = NSClassFromString(@"AWEIMBottomShareTipsView");
        if (shareC) MSHookMessageEx(shareC, sel_registerName("layoutSubviews"), (IMP)hook_shareLayout, (IMP *)&orig_shareLayout);
        Class rail = NSClassFromString(@"AWEElementStackView");
        if (rail && !orig_railLayout) {
            MSHookMessageEx(rail, sel_registerName("layoutSubviews"), (IMP)hook_railLayout, (IMP *)&orig_railLayout);
        }
        // 消息页顶部导航栏
        Class nav = NSClassFromString(@"AWENavigationBar");
        if (nav && !orig_navLayout) {
            MSHookMessageEx(nav, sel_registerName("layoutSubviews"), (IMP)hook_navLayout, (IMP *)&orig_navLayout);
        }
        // 加号弹窗（消息页右上角加号弹出的小菜单）
        Class pop = NSClassFromString(@"AFDLeftExtensionPopoverSheetView");
        if (pop) {
            if (!orig_popoverLayout) {
                MSHookMessageEx(pop, sel_registerName("layoutSubviews"), (IMP)hook_popoverLayout, (IMP *)&orig_popoverLayout);
            }
            if (!orig_pop_setButtons) {
                MSHookMessageEx(pop, sel_registerName("setActionButtons:"), (IMP)hook_pop_setButtons, (IMP *)&orig_pop_setButtons);
            }
            if (!orig_pop_setContent) {
                MSHookMessageEx(pop, sel_registerName("setContentView:"), (IMP)hook_pop_setContent, (IMP *)&orig_pop_setContent);
            }
        }
        // 视频详情页：返回 / 搜索 / 底部输入框
        Class cdNav = NSClassFromString(@"AWEAwemeDetailNaviBarContainerView");
        if (cdNav && !orig_cdNavLayout) {
            MSHookMessageEx(cdNav, sel_registerName("layoutSubviews"), (IMP)hook_cdNavLayout, (IMP *)&orig_cdNavLayout);
        }
        Class cdInput = NSClassFromString(@"AWECommentInputBackgroundView");
        if (cdInput && !orig_cdInputLayout) {
            MSHookMessageEx(cdInput, sel_registerName("layoutSubviews"), (IMP)hook_cdInputLayout, (IMP *)&orig_cdInputLayout);
        }
        Class cdVC = NSClassFromString(@"AWEAwemeDetailTableViewController");
        if (cdVC && !orig_cdVCLayout) {
            MSHookMessageEx(cdVC, sel_registerName("viewDidLayoutSubviews"), (IMP)hook_cdVCLayout, (IMP *)&orig_cdVCLayout);
        }
        Class qcell = NSClassFromString(@"AWEIMInputActionBarFansGroupEntryViewCollectionViewCell");
        if (qcell && !orig_quickCellLayout) {
            MSHookMessageEx(qcell, sel_registerName("layoutSubviews"), (IMP)hook_quickCellLayout, (IMP *)&orig_quickCellLayout);
        }
        Class qbar = NSClassFromString(@"AWEIMInputActionBarFansGroupEntryView");
        if (qbar && !orig_quickBarLayout) {
            MSHookMessageEx(qbar, sel_registerName("layoutSubviews"), (IMP)hook_quickBarLayout, (IMP *)&orig_quickBarLayout);
        }
        Class dvc = NSClassFromString(@"AWEAwemeIMDetailTableViewController");
        if (dvc && !orig_detailVCLayout) {
            MSHookMessageEx(dvc, sel_registerName("viewDidLayoutSubviews"),
                            (IMP)hook_detailVCLayout, (IMP *)&orig_detailVCLayout);
        }
        Class dnav = NSClassFromString(@"AWEAwemeDetailNaviBarContainerView");
        if (dnav && !orig_detailNavLayout) {
            MSHookMessageEx(dnav, sel_registerName("layoutSubviews"), (IMP)hook_detailNavLayout, (IMP *)&orig_detailNavLayout);
        }
        Class ibar = NSClassFromString(@"AWEIMFeedBottomQuickEmojiInputBar");
        if (ibar && !orig_inputBarLayout) {
            MSHookMessageEx(ibar, sel_registerName("layoutSubviews"), (IMP)hook_inputBarLayout, (IMP *)&orig_inputBarLayout);
        }
        // 页面级兜底
        Class pi = NSClassFromString(@"AWEPlayInteractionViewController");
        if (pi) {
            if (!orig_piLayout) MSHookMessageEx(pi, sel_registerName("viewDidLayoutSubviews"), (IMP)hook_piLayout, (IMP *)&orig_piLayout);
            if (!orig_piAppear) MSHookMessageEx(pi, sel_registerName("viewDidAppear:"), (IMP)hook_piAppear, (IMP *)&orig_piAppear);
        }
    } @catch(NSException *e) {}
    if (orig_elemLayout || orig_railLayout || orig_piLayout || orig_navLayout || orig_popoverLayout ||
        orig_detailVCLayout || orig_detailNavLayout || orig_inputBarLayout ||
        orig_quickCellLayout || orig_quickBarLayout ||
        orig_cdNavLayout || orig_cdInputLayout || orig_cdVCLayout) g_hooked = YES;
}

static __attribute__((constructor)) void DKInit(void){
    DKInstallNoFavAnim();
    DKForceRemoveAllAnchors();
    DKTryInstall();
    dispatch_async(dispatch_get_main_queue(), ^{ DKTryInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKTryInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DKTryInstall(); });
}
