# AGENTS.md

> 给 **AI Agent / 自动化 harness** 的接入说明。人类用户请看 [README](README.md) 和 [SOP](docs/SOP.md)。

本仓库提供一个**可被机器调用的 CLI**：所有动作都支持 `-Json`，输出单行 JSON；失败用退出码区分。
你可以用任意语言（PowerShell / Python / Node）把它当子进程调用，不需要理解内部实现。

---

## 0. 一句话流程

```text
scan → next → 读题作答 → submit → 直到 scan.missing == 0
```

---

## 1. 环境前提（调用前必须成立）

1. 操作系统为 **Windows**，脚本依赖 UI Automation 与屏幕取色；
2. **Edge 已启动**，且已登录智慧树，页面停在课程「**掌握度**」页（URL 含 `/study/mastery`）；
3. 调用期间**不要移动鼠标、不要切换标签页**——工具用真实鼠标事件操作；
4. 屏幕缩放建议 100%～150%，浏览器缩放 100%（`Ctrl+0`）。

可用 `status` 自检：`state` 必须是 `mastery`。

---

## 2. CLI 契约

统一入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action <动作> [-Answers "<答案>"] [-Json]
```

| 动作 | 作用 | 是否改变页面 |
|---|---|---|
| `status` | 返回当前页面状态 | 否 |
| `scan` | 统计当前视口内知识点状态 | 否 |
| `list` | 列出当前视口内所有知识点 | 否 |
| `next` | 找下一个**灰色**知识点并打开，返回 5 道题 | 是 |
| `submit` | 按 `-Answers` 作答并提交 | 是 |
| `back` | 从答题页退回掌握度页并刷新 | 是 |

### 2.1 `status`

```json
{"ok":true,"pid":13064,"window":"智慧树 和另外 4 个页面 - 观峫 - Microsoft Edge","state":"mastery"}
```

`state` 取值：`mastery` / `exam` / `result` / `unknown`。

### 2.2 `scan`

```json
{"total":176,"mastered":11,"missing":0,"weak":0,"hidden":152,"ok":true}
```

> `hidden` 表示不在当前视口内的知识点（未采样颜色）。**`missing` 只统计当前视口**，
> 判断整体是否完成应看页面顶部的「遗漏点个数」，或反复 `scan` + 滚动。

### 2.3 `next`

```json
{
  "ok": true,
  "point": "顾恺之——“春蚕吐丝”",
  "questions": [
    {
      "index": 1,
      "type": "single",
      "stem": "“春蚕吐丝”笔法在顾恺之的代表作《女史箴图》中如何体现？",
      "options": [
        {"key":"A","text":"通过流畅的线条表现人物衣饰的生动"},
        {"key":"B","text":"通过浓烈的色彩突出画面的视觉冲击"}
      ]
    }
  ]
}
```

- `type`：`single` 单选 / `judge` 判断 / `multi` 多选
- `questions` 长度通常是 5，顺序即作答顺序

### 2.4 `submit`

```json
{"ok":true,"point":"...","score":100,"correct":5,"total":5,"state":"result"}
```

`-Answers` 语法：

| 题型 | 写法 | 示例 |
|---|---|---|
| 单选 | 字母 | `B` |
| 判断 | `T` / `F` | `T` |
| 多选 | 连写字母 | `ACE` |
| 多题拼接 | `\|` 分隔 | `B\|T\|ACE\|D\|A` |

### 2.5 退出码

| 码 | 含义 | Agent 应采取的动作 |
|---|---|---|
| `0` | 成功 | 继续下一步 |
| `1` | 未捕获异常 | 读 `error` 字段，停止并上报 |
| `2` | 当前不在掌握度页 | 先 `back`，或提示用户切页 |
| `3` | 没有灰色知识点 | 检查页面是否滚动到底 / 是否已全部完成 |
| `4` | 打开知识点失败（`NO TOOLTIP` 等） | 重试一次；仍失败则跳过并记录 |
| `5` | 提交失败 / 缺答案 | 检查 `error`，重新 `next` |

---

## 3. Agent 循环（伪代码）

```python
while True:
    s = cli("scan")                     # 需要时先滚动页面再扫
    if s["missing"] == 0 and page_done():
        break

    r = cli("next")                     # 退出码 3 表示没有灰色点了
    if r["code"] == 3:
        scroll_down()
        continue

    answers = solve(r["questions"])     # ← 由你（LLM）逐题作答
    sub = cli("submit", "|".join(answers))

    if sub.get("score", 0) < 100:
        retry_once(r["point"])          # 题目会重排，需要重新读题

    cli("back")                         # 回掌握度页并刷新
    log(r["point"], sub["score"])
```

### 答题建议（给 LLM）

- 题目由平台**随机生成/重排**：同一知识点两次进入，题目和选项顺序都可能不同，**不要缓存答案**；
- 优先按题干语义作答，选项通常是「教材原文 / 常识性表述」；
- 有把握的先选，不确定的再退一步用排除法；
- `score` 低于 80 分该点会退回灰色/黄色，需要重做——重做时**重新读题**，不要复用上次字母。

---

## 4. 完成判定

课程「掌握度」页顶部会显示：

- **遗漏点数** = 0
- **薄弱点数** = 0
- 平均掌握度 ≥ 98%

三者同时满足即可视为完成。可用 `run.ps1 -Action status` 确认仍在掌握度页，再截图或读页面文字核对数字。

---

## 5. 安全与边界

- 工具**不会**替你上传任何数据，所有状态只写本地 `work/` 目录；
- 它是一个**半自动**工具：`next` 只负责开题和读题，**答案必须由你（或人类）提供**；
- 请勿并行运行多个实例，鼠标是全局资源，会互相打架；
- 使用前请确认符合你所在平台/课程的使用条款。
