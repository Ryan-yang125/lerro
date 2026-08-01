# Voice and Copy

## 声音

Lerro 的文案保持直接、平静、可信。每句话优先回答当前发生了什么、数据在哪里、用户
可以做什么。

## 规则

- 句子简短，动词靠前。
- 使用具体动作：听写、翻译、提问、改写、取消、插入。
- 权限文案说明用途与触发时机。
- 本地处理、模型下载和数据保留使用可验证事实。
- 错误信息给出恢复动作。
- 状态文案与 UI 状态一一对应。
- 产品名始终写作 `Lerro`，读音提示写作 `LEH-ro`。

## 功能命名

| 中文 | English |
| --- | --- |
| 听写 | Dictate |
| 翻译 | Translate |
| 问答 | Ask |
| 改写 | Rewrite |
| 免按住 | Hands-free |

## 推荐文案

| 场景 | 中文 | English |
| --- | --- | --- |
| 主标语 | 自在说，清楚写。 | Speak freely. Write clearly. |
| Idle | 按住 Fn 开始听写 | Hold Fn to dictate |
| Listening | 正在听写 | Listening |
| Processing | 正在整理文字 | Refining text |
| Success | 已写入当前光标 | Inserted at the cursor |
| Empty | 没有检测到可写入的内容 | No text was detected |
| Permission | 开启麦克风权限以开始听写 | Allow microphone access to dictate |
| Local model | 下载约 3.03 GB 的本地模型 | Download the 3.03 GB local model |
| Error | 写入失败。复制结果后可继续使用。 | Insertion failed. Copy the result to continue. |

## 按钮

按钮直接描述结果：`开始听写`、`停止并插入`、`复制结果`、`打开系统设置`、`稍后`。
确认对话框只服务不可逆动作，例如删除历史与录音。

## Release 文案

Release notes 先写用户可感知变化，再写权限、兼容性与升级注意事项。技术细节使用
SF Mono，并保持可复制的命令格式。
