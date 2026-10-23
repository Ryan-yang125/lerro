# Voice and Copy

## 声音

Lerro 的文案保持直接、平静、可信。每句话优先回答当前发生了什么、数据在哪里、用户
可以做什么。

读者是普通上班族。对外文案用回微信、写邮件、整理周报这类日常场景，不写开发者术语
（API、模型、服务商、提示词）。对外说法以官网文案
[`site/src/data/home.ts`](../../site/src/data/home.ts) 为准，README、截图、发布说明和
宣传物料都跟它保持一致。

## 规则

- 句子简短，动词靠前。
- 使用具体动作：说、写进去、整理、翻译、改口、复制。
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
| AI 整理 | AI cleanup |
| 词典 | Dictionary |
| 应用语气（官网卖点写「口吻」） | App tone |
| 免按住 | Hands-free |

不再使用的旧叫法：「AI 润色」「智能」「智能处理」「远端 AI」「自带 Key」「BYOK」、
「按词典改错」。词典的卖点写「常说的名字和词，会自己记住」：AI 改对两次以后自动记下，
不用手动加。

## 推荐文案

| 场景 | 中文 | English |
| --- | --- | --- |
| 主标语 | 说出来，就写好了 | Speak it. It's written. |
| Idle | 按一下 Fn 开始说话 | Press Fn to start talking |
| Listening | 正在听 | Listening |
| Processing | AI 整理中… | Cleaning up… |
| Success | 写好了 | Written |
| Empty | 没有检测到可写入的内容 | No text was detected |
| Permission | 开启麦克风权限以开始听写 | Allow microphone access to dictate |
| Error | 写入失败。复制结果后可继续使用。 | Insertion failed. Copy the result to continue. |

## 按钮

按钮直接描述结果：`开始听写`、`停止并插入`、`复制结果`、`打开系统设置`、`稍后`。
确认对话框只服务不可逆动作，例如删除历史与录音。

## Release 文案

Release notes 先写用户可感知变化，再写权限、兼容性与升级注意事项。技术细节使用
SF Mono，并保持可复制的命令格式。
