# 0015：实时识别改用 SpeechTranscriber

- 状态：accepted
- 日期：2026-10-18
- 决策人：Lerro maintainers
- 关联任务/PR：Lerro v1.7 识别准确度
- 替代：ADR 0012 中词典进入 Apple Speech contextual strings 的部分

## 背景

日常听写的主要错误出现在中文里夹英文词：`DictationTranscriber` 把英文识别成同音中文或无关英文
（system design → steam D站，Codex → Cox），还会整段丢词（「可以现在这个体验真的非常好」只出
「真的非常好」）。离线重跑同一录音得到与实时识别逐字相同的结果，丢词来自模型本身。

## 方案对比

在维护者 40 段真实录音上离线比较（28 段中英混说，参考答案由两个独立引擎互证与对话上下文推断）：

| 方案 | 英文词正确 | 每段转写耗时中位数 | 实时 partial | 标点 | 词典 contextual strings |
| --- | --- | --- | --- | --- | --- |
| DictationTranscriber（原方案） | 24/61（39%），会丢整段 | 847 ms | 有 | 有 | 生效（6/40 段变化） |
| SpeechTranscriber | 38/61（62%） | 258 ms | 有（`.progressiveTranscription`） | 有，中文标点两侧多空格 | 不生效（0/40 段变化） |
| SenseVoice-Small（sherpa-onnx） | 36/61（59%） | 226 ms | 无 | 无，英文全大写 | 不支持 |

即使给 DictationTranscriber 加入针对这批录音的英文词，英文正确率也只到约 49%，丢词不变。

## 决策

实时识别使用 `SpeechTranscriber(locale:preset:.progressiveTranscription)`，接口与原方案同属
SpeechAnalyzer，开麦先行、缓冲和预热引擎保持不变。
`TranscriptSpacing.normalize` 去掉中文标点两侧的空格。由于 SpeechTranscriber 忽略
contextual strings，删除 `SpeechVocabularyTerm` 与词典到 Apple Speech 的通路；词典继续通过
AI prompt 的 `known_terms` 与 glossary 生效。

## 后果

- 中英混说的识别质量和最终结果速度提升；Apple-only 模式下词典不再影响识别。
- 纯苹果模式会保留「嗯、呃」等口头禅，AI 润色负责去除。
- 换模型或系统升级后，用同一批录音离线复测可以重新比较。
