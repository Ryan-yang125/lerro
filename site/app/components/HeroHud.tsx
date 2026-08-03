"use client";

import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "motion/react";

type HudStage = "listening" | "processing";

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

export function HeroHud() {
  const reducedMotion = useReducedMotion();
  const [stage, setStage] = useState<HudStage>("listening");
  const [bars, setBars] = useState(quietBars);
  const seed = useRef(0x4c455252);
  const tick = useRef(0);
  const stageStartedAt = useRef(0);
  const displayedStage: HudStage = reducedMotion ? "listening" : stage;
  const displayedBars = reducedMotion ? reducedBars : bars;

  useEffect(() => {
    if (reducedMotion) return;

    stageStartedAt.current = performance.now();
    const timer = window.setInterval(() => {
      const elapsed = performance.now() - stageStartedAt.current;

      if (stage === "listening") {
        if (elapsed >= 3400) {
          setStage("processing");
          stageStartedAt.current = performance.now();
          return;
        }

        tick.current += 1;
        const frame = createVoiceFrame(tick.current, seed.current);
        seed.current = frame.seed;
        setBars(frame.bars);
        return;
      }

      if (elapsed >= 1440) {
        setStage("listening");
        setBars(quietBars);
        stageStartedAt.current = performance.now();
      }
    }, 50);

    return () => window.clearInterval(timer);
  }, [reducedMotion, stage]);

  return (
    <div className="hero-hud-wrap" aria-hidden="true">
      <div className={`hero-hud hero-hud--${displayedStage}`} data-stage={displayedStage}>
        <div className="hero-hud__waveform">
          {displayedBars.map((height, index) => (
            <span
              className="hero-hud__bar"
              key={index}
              style={{ transform: `scaleY(${height})` }}
            />
          ))}
        </div>
        <div className="hero-hud__processing">
          <span />
          <span />
          <span />
        </div>
      </div>
    </div>
  );
}
