"use client";

import { motion, useReducedMotion } from "motion/react";
import { useEffect, useRef, useState, type AnchorHTMLAttributes, type ReactNode } from "react";

type Ripple = {
  id: number;
  x: number;
  y: number;
  scale: number;
  released: boolean;
};

type InteriorLinkProps = Omit<AnchorHTMLAttributes<HTMLAnchorElement>, "children"> & {
  children: ReactNode;
  variant?: "primary" | "secondary" | "quiet" | "card";
};

const arrive = [0.23, 1, 0.32, 1] as const;

export function InteriorLink({
  children,
  className = "",
  variant = "secondary",
  onPointerDown,
  onPointerUp,
  onPointerCancel,
  onLostPointerCapture,
  onBlur,
  ...props
}: InteriorLinkProps) {
  const reducedMotion = useReducedMotion();
  const [pressed, setPressed] = useState(false);
  const [ripples, setRipples] = useState<Ripple[]>([]);
  const sequence = useRef(0);
  const timers = useRef<number[]>([]);

  useEffect(() => () => timers.current.forEach(window.clearTimeout), []);

  function begin(event: React.PointerEvent<HTMLAnchorElement>) {
    if (event.pointerType === "mouse" && event.button !== 0) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    const reach = Math.max(
      Math.hypot(x, y),
      Math.hypot(rect.width - x, y),
      Math.hypot(x, rect.height - y),
      Math.hypot(rect.width - x, rect.height - y),
    );
    const id = ++sequence.current;
    event.currentTarget.setPointerCapture?.(event.pointerId);
    setPressed(true);
    setRipples((current) => [
      ...current.slice(-2),
      { id, x, y, scale: Math.max(1, reach / 20), released: false },
    ]);
    onPointerDown?.(event);
  }

  function end(event?: React.PointerEvent<HTMLAnchorElement>) {
    setPressed(false);
    setRipples((current) => current.map((ripple) => ({ ...ripple, released: true })));
    const timeout = window.setTimeout(() => setRipples([]), 150);
    timers.current.push(timeout);
    if (event) onPointerUp?.(event);
  }

  return (
    <a
      {...props}
      data-interior-link=""
      data-pressed={pressed ? "true" : "false"}
      className={`interior-link interior-link--${variant} ${className}`}
      onPointerDown={begin}
      onPointerUp={end}
      onPointerCancel={(event) => {
        end();
        onPointerCancel?.(event);
      }}
      onLostPointerCapture={(event) => {
        end();
        onLostPointerCapture?.(event);
      }}
      onBlur={(event) => {
        end();
        onBlur?.(event);
      }}
      style={{
        transform: pressed && !reducedMotion ? "translateY(1px) scale(.992)" : undefined,
      }}
    >
      <span className="interior-link__ripples" aria-hidden="true">
        {ripples.map((ripple) => (
          <motion.span
            className="interior-link__ripple"
            key={ripple.id}
            style={{ left: ripple.x - 20, top: ripple.y - 20 }}
            initial={{ opacity: 0, transform: "scale(.95)" }}
            animate={{
              opacity: reducedMotion || ripple.released ? 0 : 1,
              transform: `scale(${ripple.scale})`,
            }}
            transition={{ duration: ripple.released ? 0.12 : 0.14, ease: arrive }}
          />
        ))}
      </span>
      <span className="interior-link__content">{children}</span>
    </a>
  );
}
