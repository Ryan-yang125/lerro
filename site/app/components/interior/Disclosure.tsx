"use client";

import { motion, useReducedMotion } from "motion/react";
import { useId, useState, type ReactNode } from "react";

type DisclosureProps = {
  summary: ReactNode;
  children: ReactNode;
  defaultOpen?: boolean;
};

export function Disclosure({ summary, children, defaultOpen = false }: DisclosureProps) {
  const [open, setOpen] = useState(defaultOpen);
  const id = useId();
  const reducedMotion = useReducedMotion();

  return (
    <div className="interior-disclosure" data-open={open ? "true" : "false"}>
      <h3>
        <button
          type="button"
          aria-expanded={open}
          aria-controls={`${id}-panel`}
          onClick={() => setOpen((current) => !current)}
        >
          <span>{summary}</span>
          <motion.svg
            width="16"
            height="16"
            viewBox="0 0 256 256"
            fill="none"
            aria-hidden="true"
            initial={false}
            animate={{ transform: `rotate(${open ? 180 : 0}deg)` }}
            transition={reducedMotion ? { duration: 0 } : { type: "spring", stiffness: 700, damping: 46, mass: 0.5 }}
          >
            <path d="M208 96l-80 80-80-80" stroke="currentColor" strokeWidth="16" strokeLinecap="round" strokeLinejoin="round" />
          </motion.svg>
        </button>
      </h3>
      <div id={`${id}-panel`} role="region" hidden={!open}>
        <motion.div
          initial={false}
          animate={{ opacity: open ? 1 : 0 }}
          transition={reducedMotion ? { duration: 0 } : { duration: 0.18, ease: [0.23, 1, 0.32, 1] }}
        >
          {children}
        </motion.div>
      </div>
    </div>
  );
}
