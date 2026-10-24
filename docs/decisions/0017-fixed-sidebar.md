# 0017：固定侧栏与页面自绘标题栏

- 状态：accepted
- 日期：2026-10-24
- 决策人：Lerro maintainers
- 替代：ADR 0014 中「主窗口使用 `NavigationSplitView`」与侧栏、工具栏的部分

## 背景

主窗口用 `NavigationSplitView` 时，侧栏可以折叠和拖宽。展开侧栏的动画里，系统每帧向详情列查询最小尺寸，
`ScrollView` 会测量整页内容，首页卡片和热力图跟着每帧重新布局，展开时明显卡顿。列宽设置
（`navigationSplitViewColumnWidth`）在拖动时不生效，拖宽的列宽还会写入偏好设置。Lerro 只有四个页面，
不需要可折叠、可拖宽的侧栏。

## 决策

- 主窗口使用 `.windowStyle(.hiddenTitleBar)`，根视图是 `LerroSplitLayout`：220 pt 固定侧栏（`LerroTheme.sidebarWidth`，
  右边缘叠一条 0.5 pt 分隔线）和页面。侧栏从窗口顶部开始，红绿灯按钮落在侧栏上方。
- 页面的「标题栏 + 内容」和历史页的「列表 + 详情」也用 `LerroSplitLayout`。它只按给定长度切分空间，不测量子视图。
  `HStack`、`VStack` 会先用 0 和无穷大的长度测量每个子视图来判断弹性，子视图是 `ScrollView` 时每次都要排版整页内容，
  宽度为 0 时文字逐字换行。用 819 条历史实测，每次切页主线程 150–180 ms，其中约 63% 花在这里。
- 首页并排的卡片用 `LerroEqualColumns`：等宽列，每张卡片只按列宽测量一次。
- 侧栏行是自绘按钮（`SidebarRow`）：SF Symbols 图标、标题、数量，选中用 `fillSelected`，悬停用 `fillHover`。
  侧栏空白处可拖动窗口。删除 `SidebarCommands`。
- 每个页面顶部是 `LerroPageHeader`：标题加页面控件，高 `LerroTheme.pageHeaderHeight`（52 pt），空白处可拖动窗口。
  搜索使用 `LerroSearchField`，替代 `.searchable` 和窗口工具栏。

## 页面常驻

- 四个页面在启动时全部创建，放在 `RootView` 的 `ZStack` 里，切换页面只改变哪一个可见。每次切页重建页面要花 80–130 ms，
  词典页的 `List` 重新计算行高约占 60 ms。
- 隐藏的页面设为 `opacity(0)`、不接收点击、对辅助功能隐藏（`opacity`、`allowsHitTesting`、`accessibilityHidden`）。
  页面根视图不使用环境值，也不使用 `.disabled`：这两者变化时，切页会让 SwiftUI 重新检查两个页面里的每个文本视图
  （实测每次切换多 10–20 ms），而且 `.disabled` 不能把隐藏页里的 `TextEditor` 和 `List` 移出 Tab 顺序。
- 键盘焦点逐个控件限制，修饰器在自己的 body 里读取 `session.destination`，切页只更新被限制的控件：
  文本输入框用 `lerroPageTextInput`，列表用 `lerroPageFocusable`，应用语气页的 `TextEditor` 只在该页可见时存在
  （`draft` 保留在 `AppToneEditor` 的 `@State` 里，未保存的文字不会丢）。
- 每次切页时窗口放弃当前键盘焦点（`RootView` 中对窗口调用 `makeFirstResponder(nil)`），
  隐藏页里持有焦点的控件（例如词典列表的 `.onDeleteCommand`）不会在其他页面响应按键。
- 原来依赖出现事件的工作改用 `onLerroPageVisibilityChange`，它在页面创建时和每次可见性变化时执行：
  词典页和应用语气页刷新可用应用列表，应用语气页处理 `app-tone-picker` fixture，历史详情在页面隐藏时停止录音播放。
- 窗口标题只在 `RootView` 里按当前页面设置一次，页面自己不再设置 `navigationTitle`。
- 页面在偏好和数据加载完成前就已创建。用数据初始化的 `@State` 要跟随数据变化，例如应用语气编辑框在草稿未改动时
  跟随已保存的语气要求更新。

## 备选方案

- 保留 `NavigationSplitView`，只修页面布局：热力图的反馈循环已修，但详情列每帧测量整页内容的开销仍在，
  而且列宽无法固定，未采用。
- 透明窗口工具栏加页面标题：macOS 26 的工具栏在非分栏窗口里把控件放到左侧，并用滚动边缘效果盖住
  工具栏区域里的内容，未采用。

## 后果

- 侧栏不能折叠或拖宽，没有展开动画，也就没有对应的卡顿。
- 页面控件位置由各页面决定；新增页面需要自己放 `LerroPageHeader`。
- 侧栏键盘上下选择随 `List` 一起去掉，点击和 VoiceOver 选中状态保留。

## 隐私与安全

只改界面布局，不涉及数据、权限和网络。

## 验证

切页耗时用临时探针测量：fixture 读入真实规模数据（855 条历史、40 个词条），在 988×690 窗口里轮流切换四个页面，
记录从改变 `destination` 到主线程进入休眠的时间，前后版本交替各跑 3 轮取中位数。
首页 192 → 91 ms，历史 144 → 111 ms，词典 151 → 128 ms，应用语气 103 → 82 ms（同时包含字符串表改为二进制 plist）。

页面常驻用同样方法对比每次切换都重建页面的版本，交替各跑 3 轮取中位数：首页 86 → 31 ms，历史 107 → 23 ms，
词典 127 → 56 ms，应用语气 88 → 59 ms。键盘焦点在 fixture 中用进程内合成的 Tab 键核对：首页按 Tab 不进入任何隐藏页的控件；
历史、词典、应用语气页只在本页控件之间循环；焦点在本页控件上时切页，窗口不再保留焦点。

用 inert fixture 截图核对四个页面在 1080×750 与 988×658、浅色与深色下的布局；在 fixture 中实测点击侧栏切换页面、
拖动侧栏空白处和标题栏空白处移动窗口。
