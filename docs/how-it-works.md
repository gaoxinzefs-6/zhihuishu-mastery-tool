# 实现原理

## 1. 为什么不用 CDP / Playwright

智慧树掌握度页运行在用户已登录的 Edge 里，重新开一个带 `--remote-debugging-port` 的浏览器实例会丢失登录态，
而关闭现有 Edge 再重启又太打扰。所以这里选择「外部自动化」：UIA + 真实鼠标键盘事件。

代价是：没有 DOM、没有 JS、读不到弹窗里的动态文本。整个工具就是围绕这三个限制设计的。

## 2. 定位页面

```powershell
$win = AutomationElement.RootElement.FindFirst(
    Children,
    PropertyCondition(ProcessIdProperty, $edgePid))
```

Edge 顶层窗口只有一个 `Chrome_WidgetWin_1`，里面的网页内容通过 `Document` 控件暴露。
页面文字统一用 `TextPattern.DocumentRange.GetText(-1)` 读取，比逐个遍历文本节点稳。

## 3. 判断知识点状态

热力图里每个知识点是一个 `ListItem`，尺寸约 171×171（随缩放变化）。颜色只有几种：

| 状态 | 填充色 |
|---|---|
| 掌握较好（绿） | `#8CE5A2` (140,229,162) |
| 掌握一般（黄） | `#F5C26B` 左右 |
| 薄弱点（红） | 粉红 |
| 遗漏点（灰） | `#CCCCCC` (204,204,204) |

采样点在方块左侧 `(x+7, y+h/2)`：避开中间的文字（文字是纯黑 `#000000`，会干扰判色），
同时避开圆角（圆角处会采到页面白底 `#FFFFFF`）。

> 早期版本用 `(x+25, y+25)` 采样，遇到换行标题会把文字采进去，导致绿色方块被误判成灰色 —— 这是最大的坑。

## 4. 打开答题弹窗

灰色方块没有 `Invoke` 模式，只能模拟鼠标：

1. `ScrollItemPattern.ScrollIntoView()` 把方块滚进视口；
2. `Wait-ScrollStable()` 等坐标不再变化（SPA 滚动是平滑动画，坐标会滞后）；
3. `SetCursorPos` + 点击方块中心 → 页面弹出浮层（标题 + 掌握度 + 「提升掌握度」按钮）；
4. 用 UIA 找到「提升掌握度」文本，`Click-El` 点它 → 路由跳转到 `/exam?...` 页面。

浮层的文字**不在 UIA 树里**，所以不能靠读弹窗判断掌握度，只能信任前面的判色。

## 5. 答题页

答题页结构很固定：

```
Document
├─ Text   "1、题干……"
├─ RadioButton "A. 选项1"
├─ RadioButton "B. 选项2"
├─ ...
├─ Text   "下一题"
└─ Text   "提交"
```

- 单选：`RadioButton`，名字自带 `"A. xxx"` 前缀，按前缀匹配即可；
- 判断：`RadioButton` 名字是 `"对"` / `"错"`；
- 多选：`CheckBox`，名字同样带 `"A. xxx"` 前缀。

填答后校验 `SelectionItemPattern.Current.IsSelected`，没选中就补一次鼠标点击 —— 纯 `Invoke` 偶尔不生效。

## 6. 提交与判分

点「提交」后页面跳到结果页，文本里会出现：

```
100%        掌握度
总题数 5
已答对 5
```

用正则抓百分比和「已答对」，`>= 80%` 记入 `work/green.txt`，否则留待重做。

## 7. 为什么要点「刷新」

掌握度页是 SPA，从答题页 `Alt+Left` 回来时走的是 bfcache，DOM 不会重新拉数据，
颜色和「遗漏点个数」都是旧的。所以每次提交后都点一下浏览器工具栏的「刷新」按钮，强制重新渲染。

## 8. 进度落盘

- `work/seq.txt`：当前扫描到的知识点序号（DOM 顺序），避免每次从第一个开始找；
- `work/current.txt`：当前正在做的知识点名；
- `work/green.txt`：已拿到 100 分的知识点名，`next` 时跳过。
