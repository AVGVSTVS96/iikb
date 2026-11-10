import { GITHUB, WORDMARK } from "@/lib/brand";

interface Props {
  className?: string;
}

export const Wordmark = ({ className }: Props) => (
  <svg viewBox={WORDMARK.viewBox} className={className} aria-hidden="true" fill="currentColor">
    <path transform={WORDMARK.transform} d={WORDMARK.d} />
  </svg>
);

export const WordmarkSymbol = () => (
  <svg width="0" height="0" className="absolute" aria-hidden="true">
    <symbol id="wordmark" viewBox={WORDMARK.viewBox}>
      <path transform={WORDMARK.transform} d={WORDMARK.d} />
    </symbol>
  </svg>
);

export const GitHub = ({ className }: Props) => (
  <svg viewBox="0 0 16 16" className={className} aria-hidden="true" fill="currentColor">
    <path d={GITHUB} />
  </svg>
);

export const TestFlight = ({ className }: Props) => (
  <svg
    viewBox="0 0 24 24"
    className={className}
    aria-hidden="true"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.8"
  >
    <circle cx="12" cy="12" r="9.2" />
    <circle cx="12" cy="12" r="5.2" />
    <circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none" />
  </svg>
);

export const Android = ({ className }: Props) => (
  <svg viewBox="0 0 24 24" className={className} aria-hidden="true" fill="currentColor">
    <path d="M17.6 9.48 19.44 6.3a.38.38 0 0 0-.66-.38l-1.86 3.22a11.4 11.4 0 0 0-9.84 0L5.22 5.92a.38.38 0 1 0-.66.38L6.4 9.48A10.8 10.8 0 0 0 1 18h22a10.8 10.8 0 0 0-5.4-8.52ZM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Z" />
  </svg>
);
