# Contextual Dictation Benchmark

`contextual-dictation-v1.3.json` is Lerro's fixed 60-case product benchmark. It covers Chinese, English, and mixed speech across Mail, Messages, Notes, Xcode, and Terminal.

Each result file contains all case IDs, generated output, and end-to-end latency:

```json
{
  "results": [
    {
      "id": "mail-01",
      "output": "...",
      "latencyMilliseconds": 842
    }
  ]
}
```

Validate the corpus or score a run:

```bash
python3 script/benchmark_contextual_dictation.py --validate
python3 script/benchmark_contextual_dictation.py --results path/to/results.json --output report.json
```

The report includes exact-match rate, normalized text similarity, protected-span accuracy, formatting accuracy, and p50/p95 latency. Keep the corpus unchanged within the v1.3 release line so local, remote, and competitor runs remain comparable.
