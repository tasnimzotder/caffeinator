interface CoffeeIconProps {
  size?: number;
  className?: string;
}

export function CoffeeIcon({ size = 24, className = "" }: CoffeeIconProps) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      width={size}
      height={size}
      className={className}
    >
      {/* Half-open eye: flat top, curved bottom */}
      <line x1="3" y1="11" x2="21" y2="11" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <path d="M3 11 Q12 21 21 11" stroke="currentColor" strokeWidth="2" strokeLinecap="round" fill="none" />
      {/* Pupil */}
      <circle cx="12" cy="14" r="2.5" fill="currentColor" />
    </svg>
  );
}
