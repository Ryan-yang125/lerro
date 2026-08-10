"use client";

import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "motion/react";

type HudStage = "listening" | "processing" | "receipt" | "editing" | "editProcessing" | "edited";
type HudSurface = "listening" | "processing" | "receipt";

const quietBars = [0.18, 0.24, 0.2, 0.3, 0.23, 0.28, 0.19, 0.25, 0.21, 0.17];
const reducedBars = [0.32, 0.62, 0.86, 0.5, 1, 0.72, 0.4, 0.9, 0.56, 0.76];

function nextRandom(seed: number) {
  const next = (seed * 1664525 + 1013904223) >>> 0;
  return [next, next / 4294967296] as const;
}

function createVoiceFrame(tick: number, seed: number) {
  let nextSeed = seed;
  const envelope = 0.42 + 0.5 * Math.max(0, Math.sin(tick * 0.19));
  const center = 2 + ((tick * 0.17) % 5);

  const bars = quietBars.map((roomTone, index) => {
    let random;
    [nextSeed, random] = nextRandom(nextSeed);
    const distance = Math.abs(index - center);
    const voice = envelope * Math.pow(0.6, distance) * (0.82 + random * 0.18);
    return Math.min(1, Math.max(roomTone, roomTone + voice));
  });

  return { bars, seed: nextSeed };
}

export function HeroHud({ locale }: { locale: "en" | "zh" }) {
  const reducedMotion = useReducedMotion();
  const [stage, setStage] = useState<HudStage>("listening");
  const [bars, setBars] = useState(quietBars);
  const seed = useRef(0x4c455252);
  const tick = useRef(0);
  const stageStartedAt = useRef(0);
  const displayedStage: HudStage = reducedMotion ? "listening" : stage;
  const surface: HudSurface = displayedStage === "editing"
    ? "listening"
    : displayedStage === "editProcessing"
      ? "processing"
      : displayedStage === "edited"
        ? "receipt"
        : displayedStage;
  const displayedBars = reducedMotion ? reducedBars : bars;

  useEffect(() => {
    if (reducedMotion) return;

    stageStartedAt.current = performance.now();
    const timer = window.setInterval(() => {
      const elapsed = performance.now() - stageStartedAt.current;

      if (stage === "listening" || stage === "editing") {
        if (elapsed >= 3400) {
          setStage(stage === "listening" ? "processing" : "editProcessing");
          stageStartedAt.current = performance.now();
          return;
        }

        tick.current += 1;
        const frame = createVoiceFrame(tick.current, seed.current);
        seed.current = frame.seed;
        setBars(frame.bars);
        return;
      }

      if (stage === "processing" && elapsed >= 1440) {
        setStage("receipt");
        stageStartedAt.current = performance.now();
        return;
      }

      if (stage === "receipt" && elapsed >= 2200) {
        setStage("editing");
        setBars(quietBars);
        stageStartedAt.current = performance.now();
        return;
      }

      if (stage === "editProcessing" && elapsed >= 1200) {
        setStage("edited");
        stageStartedAt.current = performance.now();
        return;
      }

      if (stage === "edited" && elapsed >= 2200) {
        setStage("listening");
        setBars(quietBars);
        stageStartedAt.current = performance.now();
        return;
      }

    }, 50);

    return () => window.clearInterval(timer);
  }, [reducedMotion, stage]);

  const copy = locale === "zh"
    ? {
        app: "邮件",
        transcript: "明天下午三点把新版发布清单发给设计和工程团队。",
        editedTranscript: "明天下午三点把发布清单发给团队。",
        editInstruction: "把刚才改短一点。",
        receipt: "已写入邮件 · Fn 修改",
        editedReceipt: "已修改邮件 · 2 个版本",
        undo: "撤回",
        correct: "修正",
      }
    : {
        app: "Mail",
        transcript: "Send the release checklist to design and engineering at 3 PM tomorrow.",
        editedTranscript: "Send the release checklist to the team at 3 PM tomorrow.",
        editInstruction: "Make that shorter.",
        receipt: "Inserted in Mail · Fn to edit",
        editedReceipt: "Edited in Mail · 2 versions",
        undo: "Undo",
        correct: "Correct",
      };

  return (
    <div className="hero-hud-wrap" aria-hidden="true">
      <div className={`hero-hud hero-hud--${surface}`} data-stage={displayedStage}>
        <div className="hero-hud__live">
          <strong>{copy.app}</strong>
          <span>{displayedStage === "editing" || displayedStage === "editProcessing" ? copy.editInstruction : copy.transcript}</span>
          <div className="hero-hud__activity">
            <div className="hero-hud__waveform">
              {displayedBars.map((height, index) => (
                <i
                  className="hero-hud__bar"
                  key={index}
                  style={{ transform: `scaleY(${height})` }}
                />
              ))}
            </div>
            <div className="hero-hud__processing">
              <i />
              <i />
              <i />
            </div>
          </div>
        </div>
        <div className="hero-hud__receipt">
          <span className="hero-hud__check">✓</span>
          <span>
            <strong>{displayedStage === "edited" ? copy.editedReceipt : copy.receipt}</strong>
            <small>{displayedStage === "edited" ? copy.editedTranscript : copy.transcript}</small>
          </span>
          <b>{copy.undo}</b>
          <b>{copy.correct}</b>
        </div>
      </div>
    </div>
  );
}
