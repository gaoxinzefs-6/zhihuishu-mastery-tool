# 智慧树 / 知到 知识点掌握度自动提升

> 一个基于 **Windows UI Automation + 屏幕像素判色** 的桌面自动化工具：
> 在 Edge 浏览器里自动定位「智慧树 · 掌握度」页面中的灰色知识点，打开答题弹窗、抓取题目、填入答案并提交，直到所有知识点变绿。

<p align="left">
  <img alt="platform" src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4">
  <img alt="powershell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## 🤖 给 Agent / 自动化调用（新增）

本仓库现在是一个**可被机器调用的工具**，不只能人肉敲：

```powershell
# 机器可读输出：单行 JSON + 明确的退出码
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action status -Json
# {"ok":true,"pid":13064,"window":"智慧树 ...","state":"mastery"}

powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action next -Json
# {"ok":true,"point":"顾恺之——“春蚕吐丝”","questions":[{"index":1,"type":"single","stem":"...","options":[{"key":"A","text":"..."}]}]}

powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action submit -Answers "B|T|ACE|D|A" -Json
# {"ok":true,"point":"...","score":100,"correct":5,"total":5}
```

| 文档 | 面向谁 | 内容 |
|---|---|---|
| [AGENTS.md](AGENTS.md) | AI Agent / harness | CLI 契约、JSON 结构、退出码、伪代码循环 |
| [docs/SOP.md](docs/SOP.md) | 人 + Agent | 标准作业流程、答题规则、故障处理矩阵 |
| [skills/zhihuishu-mastery/SKILL.md](skills/zhihuishu-mastery/SKILL.md) | 支持 Skill 的 Agent | 可直接加载的技能描述 |

退出码速查：`0` 成功 / `2` 不在掌握度页 / `3` 无灰色知识点 / `4` 打开失败 / `5` 提交失败。

> 工具是**半自动**的：`next` 负责开题和读题，**答案仍需你或你的模型给出**——平台每次进入都会重新随机出题，无法内置题库。

---

## ✨ 它做了什么

- 自动切换到浏览器里的「智慧树」标签页；
- 扫描「掌握度热力图」中每个知识点方块的颜色：
  - **绿色** `#8CE5A2` → 已掌握，跳过；
  - **灰色** `#CCCCCC` → 未掌握，进入答题；
- 点击灰色方块 → 弹出浮层 → 点「提升掌握度」→ 进入 5 道题；
- 读取题干与选项（单选 / 判断 / 多选都支持），按给定答案逐题作答并提交；
- 提交后回退到掌握度页并刷新，读取「遗漏点个数 / 平均掌握度」核对进度；
- 循环执行，直到遗漏点归零。

## 🧠 原理

浏览器页面里没有可以注入的接口，所以工具走的是「像人一样操作」的路线：

| 能力 | 实现方式 |
|---|---|
| 找到浏览器窗口 | `System.Windows.Automation`（UIA），按进程 + 顶层窗口定位 |
| 读页面文字 | UIA `TextPattern.DocumentRange.GetText()` |
| 判断方块颜色 | 屏幕取色（`CopyFromScreen`），采样方块左侧填充区域，避开文字 |
| 点击 / 悬停 | `SetCursorPos` + `mouse_event`（真实鼠标事件） |
| 切换标签页 | UIA `SelectionItemPattern` |
| 滚动 | 鼠标滚轮 + `ScrollItemPattern.ScrollIntoView()` |

关键细节：

1. **页面是 SPA，滚动后 UIA 坐标会短暂失真** —— 滚动后先等坐标稳定（`Wait-ScrollStable`）再取矩形，否则会点到隔壁方块。
2. **答题弹窗的内容不在 UIA 树里** —— 弹窗里的「掌握度: 0%」读不到，所以判色靠屏幕像素，而不是读文本。
3. **题目每次进入都会随机重排** —— 答案必须基于「本次看到的选项文本」再落字母，不能缓存上一次的字母。

## 📦 环境要求

- Windows 10 / 11
- PowerShell 5.1 及以上
- Microsoft Edge（登录好智慧树 / 知到账号，停在课程「掌握度」页面）
- 屏幕缩放建议 100%～150%（像素判色按物理像素工作）
- 运行期间**不要移动鼠标、不要切换标签页**

## 🚀 快速开始

```powershell
# 1. 打开 Edge，进入：智慧树 → 艺术与审美 → 掌握度
#    确认页面上能看到「掌握度热力图」和知识点方块

# 2. 看当前页面状态
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action status

# 3. 打开下一个灰色知识点，并抓取 5 道题
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action next

# 4. 按抓到的题目给出答案并提交
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action submit -Answers "B|B|A|B|B"
```

`-Answers` 的写法：

| 题型 | 写法 | 说明 |
|---|---|---|
| 单选 | `B` | 直接给选项字母 |
| 判断 | `T` / `F` | T = 对，F = 错 |
| 多选 | `AC` | 连写多个字母 |
| 多题 | `B\|T\|AC\|D\|A` | 用 `|` 分隔每一题 |

> 提交后脚本会打印 `RESULT: 100%,...,5,5`，第一个百分比就是掌握度；低于 80% 建议重做。

## 🗂 目录结构

```
zhihuishu-mastery-tool/
├─ run.ps1              # 命令行入口（人类 + Agent 共用）
├─ AGENTS.md            # ★ 给 AI Agent 的接入说明与 CLI 契约
├─ src/
│  ├─ Core.ps1          # UIA / 鼠标 / 取色 / 截图 等底层能力
│  ├─ PageLib.ps1       # ★ 页面级能力：扫描知识点、开题、读题、提交
│  ├─ Api.ps1           # ★ 机器可读 CLI：JSON 输出 + 退出码
│  ├─ Mastery.ps1       # 掌握度页：扫描灰色方块、打开答题（交互式）
│  ├─ Exam.ps1          # 答题页：读题、选项、翻页、提交（交互式）
│  ├─ Pipeline.ps1      # 组合流程：判分、回退、记录已完成知识点
│  ├─ EdgeTools.ps1     # 浏览器级操作：切标签、截图、找元素
│  └─ UiTree.ps1        # 调试：打印 UIA 树，适配新页面时用
├─ skills/
│  └─ zhihuishu-mastery/SKILL.md   # ★ 可直接被 Skill 系统加载
├─ docs/
│  ├─ SOP.md            # ★ 标准作业流程（人 + Agent）
│  ├─ how-it-works.md   # 深入一点的原理解析
│  └─ pitfalls.md       # 踩过的坑与规避方式
├─ work/                # 运行时数据（进度、完成清单），不入库
└─ README.md
```

## 🔁 推荐工作流

```text
status → next（看题）→ submit（作答）→ 重复 next / submit
```

每完成一个知识点，`work/green.txt` 会记录名称，`work/seq.txt` 记录顺序游标，
下次 `next` 会从游标继续，避免在已掌握的知识点上重复作答。

## ❓ 常见问题

**Q：提示「NO TOOLTIP」/ 打不开知识点？**
A：方块可能贴边或被浮层挡住。先 `-Action next` 重试；仍失败就把页面稍微滚动一下再试。

**Q：鼠标在自己乱动？**
A：这是工具在逐个方块上悬停/点击。运行时请不要接管鼠标；不想要这个行为就按 Ctrl+C 终止。

**Q：识别出的颜色不对？**
A：屏幕缩放或浏览器缩放变化会让采样点偏移。把浏览器缩放恢复为 100%（Ctrl+0）后重试。

**Q：提交后掌握度不是 100%？**
A：题目是随机抽取的，答案给错就会低于 100%。低于 80% 的知识点会重新变成灰色/黄色，再 `next` 一次重做即可。

**Q：会不会重复做已经绿色的知识点？**
A：不会。`next` 会先按填充色过滤绿色方块，再结合 `work/green.txt` 跳过已完成项。

## ⚠️ 免责声明

- 本项目仅用于学习 **Windows UI 自动化 / UIA / 屏幕取色** 等技术，**请勿用于任何违反平台服务条款或学术诚信规范的用途**。
- 自动化操作可能触发平台的风控策略，使用前请自行评估风险，**后果自负**。
- 代码按「现状」提供，不保证适配智慧树后续的页面改版。

## 📄 License

[MIT](LICENSE)
