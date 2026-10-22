/** Runs `fn` once when each matching element first becomes 35% visible, and marks it with `.on-view`. */
export function onView(selector: string, fn?: (el: Element) => void): void {
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.classList.add("on-view");
        fn?.(e.target);
        io.unobserve(e.target);
      }
    },
    { threshold: 0.35 },
  );
  document.querySelectorAll(selector).forEach((el) => io.observe(el));
}

export const prefersReducedMotion = (): boolean => matchMedia("(prefers-reduced-motion: reduce)").matches;
