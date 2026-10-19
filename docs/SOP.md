# SOP · 标准作业流程

> 本文是「智慧树 / 知到 知识点掌握度自动提升」的操作手册。
> 人类照着做即可；Agent 建议先看 [AGENTS.md](../AGENTS.md) 的机器契约，再回来看这里的判定规则。

---

## 1. 目标

把课程「掌握度」页面里的**所有灰色知识点**刷成绿色：

- 遗漏点（灰）→ 答题 → 掌握度 ≥ 80 → 变绿
- 每个知识点 5 道题，随机生成、每次进入都会重排
- 完成标准：**遗漏点 = 0、薄弱点 = 0、平均掌握度 ≥ 98%**

---

## 2. 准备（Checklist）

| # | 检查项 | 怎么确认 |
|---|---|---|
| 1 | Windows 10/11 | `winver` |
| 2 | PowerShell ≥ 5.1 | `$PSVersionTable.PSVersion` |
| 3 | Edge 已登录智慧树 | 手动打开课程页能看到自己的名字 |
| 4 | 停在「掌握度」页 | URL 含 `/study/mastery`，页面上有「掌握度热力图」 |
| 5 | 浏览器缩放 100% | `Ctrl+0` |
| 6 | 没有别的自动化在跑 | 鼠标不要被其他脚本占用 |

---

## 3. 安装与启动

```powershell
# 解压后进入目录（GitHub 的 zip 会多套一层）
cd "C:\path\to\zhihuishu-mastery-tool-main"

# 自检
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action status
```

看到 `MODE=mastery`（或加 `-Json` 后 `"state":"mastery"`）即为就绪。

---

## 4. 单点作业流程

### 4.1 打开下一个灰色知识点

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action next
```

输出 5 道题的题干与选项。若提示：

- `NO_MISSING_POINT` → 当前视口没有灰色了，先向下滚动再试；
- `NO TOOLTIP` → 方块贴边被浮层挡住，先滚动一下重试；
- `EXAM NOT LOADED` → 页面没跳转，重试一次。

### 4.2 逐题作答

对每道题：

1. 读题干，判断题型（单选 / 判断 / 多选）；
2. 在选项里找**语义最贴切**的一项；
3. 记下字母，按顺序拼成答案串。

**答题原则**

- 以「教材原话 / 常识性表述」优先；
- 判断题里出现「完全」「唯一」「所有」这类绝对化措辞，多半是**错**；
- 多选题宁少勿滥：只勾选能明确对应的项；
- 不确定时用排除法，先排除明显违背常识的选项。

### 4.3 提交

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action submit -Answers "B|T|ACE|D|A"
```

输出 `RESULT: 100%,100%,5,5` 表示：掌握度 100%、答对 5 / 共 5 题。

### 4.4 回到掌握度页

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action back
```

会按 `Alt+←` 退回并点一次浏览器「刷新」，确保颜色和计数是最新的。

---

## 5. 判分与重做规则

| 得分 | 结果 | 处理 |
|---|---|---|
| 100% | 绿色 | 记为完成，进入下一个 |
| 80% | 绿色（刚刚过线） | 可接受；想更稳可以重做到 100% |
| 60% | 黄色（掌握一般） | **必须重做** |
| 0～40% | 红色 / 仍灰 | 重新 `next` 读题重做 |

重做注意：**题目会重新洗牌**，必须重新读题，不能复用上一轮的字母。

---

## 6. 批量推进节奏

```text
循环：
  scan（不够就滚动）
  next
  作答
  submit
  back
直到 遗漏点 = 0 且 薄弱点 = 0
```

经验值：单个知识点约 40～90 秒（含读题）；176 个点全量约 2～3 小时。

建议每 10～15 个点做一次核对：

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action status
```

并看页面顶部的「遗漏点个数」是否在下降。

---

## 7. 故障处理矩阵

| 现象 | 原因 | 处理 |
|---|---|---|
| `edge window not found` | Edge 未启动 / 最小化到托盘 / 窗口在别的桌面 | 打开 Edge 窗口后重试 |
| `NO GRAY VISIBLE` | 视口内没有灰色方块 | 向下滚动，再 `next` |
| `NO TOOLTIP` | 方块贴边、被浮层遮挡 | 滚动一点、重试一次 |
| `EXAM NOT LOADED` | 页面跳转慢 | 等 2 秒重试 |
| 颜色判断错（已绿却打开） | 缩放变化导致采样点偏移 | `Ctrl+0` 恢复 100% 缩放 |
| 页面白屏（只剩侧边栏） | SPA 偶发渲染失败 | 点浏览器刷新按钮，或 `back` |
| 提交后仍停在答题页 | 有题未作答，弹了确认框 | 工具会自动点「确定」；仍失败就重新 `next` |
| 掌握度不涨 | 得分 < 60 | 重新读题重做 |

---

## 8. 收尾验收

1. 刷新掌握度页；
2. 确认三个数字：**遗漏点 0、薄弱点 0、平均掌握度 ≥ 98%**；
3. 目测整页方块为绿色（可截图留档）；
4. `work/green.txt` 中记录了所有拿到 100 分的知识点，可作为过程日志。

---

## 9. 目录与产物

| 路径 | 说明 |
|---|---|
| `work/green.txt` | 已拿满分的知识点名称 |
| `work/seq.txt` | 扫描游标，避免每次从头找 |
| `work/current.txt` | 当前正在做的知识点 |
| `work/shots/` | 可选截图目录 |

这些文件都是本地状态，**不会上传**。
