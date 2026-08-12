"use client";

import { useEffect, useRef, useState, type CSSProperties } from "react";
import { useReducedMotion } from "motion/react";

type HudStage = "listening" | "processing" | "delivered";

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
  const [transcriptStep, setTranscriptStep] = useState(1);
  const seed = useRef(0x4c455252);
  const tick = useRef(0);
  const stageStartedAt = useRef(0);

  const copy = locale === "zh"
    ? {
        app: "邮件",
        transcript: ["明天", "明天下午三点", "明天下午三点把新版", "明天下午三点把新版发布清单", "明天下午三点把新版发布清单发给", "明天下午三点把新版发布清单发给设计和工程团队。"],
      }
    : {
        app: "Mail",
        transcript: ["Send", "Send the release", "Send the release checklist", "Send the release checklist to design", "Send the release checklist to design and engineering", "Send the release checklist to design and engineering at 3 PM tomorrow."],
      };

  useEffect(() => {
    if (reducedMotion) return;

    stageStartedAt.current = performance.now();
    const timer = window.setInterval(() => {
      const elapsed = performance.now() - stageStartedAt.current;

      if (stage === "listening") {
        if (elapsed >= 3800) {
          setStage("processing");
          stageStartedAt.current = performance.now();
          return;
        }

        setTranscriptStep(Math.min(copy.transcript.length, 1 + Math.floor(elapsed / 560)));
        tick.current += 1;
        const frame = createVoiceFrame(tick.current, seed.current);
        seed.current = frame.seed;
        setBars(frame.bars);
        return;
      }

      if (stage === "processing" && elapsed >= 1180) {
        setStage("delivered");
        stageStartedAt.current = performance.now();
        return;
      }

      if (stage === "delivered" && elapsed >= 820) {
        setTranscriptStep(1);
        setBars(quietBars);
        setStage("listening");
      }
    }, 50);

    return () => window.clearInterval(timer);
  }, [copy.transcript.length, reducedMotion, stage]);

  const effectiveStep = reducedMotion ? copy.transcript.length : transcriptStep;
  const transcript = copy.transcript[effectiveStep - 1];
  const growth = (effectiveStep - 1) / (copy.transcript.length - 1);
  const width = stage === "listening" && !reducedMotion ? 132 + growth * 238 : 370;
  const displayedBars = reducedMotion ? reducedBars : bars;
  const style = { "--hero-hud-width": `${width}px` } as CSSProperties;

  return (
    <div className="hero-hud-wrap" aria-hidden="true">
      <div className={`hero-hud hero-hud--${stage}`} data-stage={stage} style={style}>
        <strong>{copy.app}</strong>
        <span className="hero-hud__transcript">{transcript}</span>
        <div className="hero-hud__controls">
          <span className="hero-hud__button">×</span>
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
          <span className="hero-hud__button">✓</span>
        </div>
      </div>
    </div>
  );
}
