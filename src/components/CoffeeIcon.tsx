interface CoffeeIconProps {
  size?: number;
  className?: string;
}

export function CoffeeIcon({ size = 24, className = "" }: CoffeeIconProps) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 512 512"
      width={size}
      height={size}
      className={className}
    >
      {/* Steam */}
      <path
        d="M256 24c0 40 32 40 32 80s-32 40-32 80"
        stroke="currentColor"
        strokeWidth="20"
        strokeLinecap="round"
        fill="none"
      />
      {/* Cup body */}
      <path
        d="M96 192h320l-32 280c-2 22-22 32-48 32H176c-26 0-46-10-48-32L96 192z"
        stroke="currentColor"
        strokeWidth="20"
        strokeLinejoin="round"
        fill="none"
      />
      {/* Lid */}
      <rect
        x="72"
        y="160"
        width="368"
        height="40"
        rx="8"
        stroke="currentColor"
        strokeWidth="20"
        fill="none"
      />
      {/* Lid top */}
      <rect
        x="104"
        y="136"
        width="304"
        height="32"
        rx="6"
        stroke="currentColor"
        strokeWidth="20"
        fill="none"
      />
      {/* Sleeve bands */}
      <path
        d="M120 320h272"
        stroke="currentColor"
        strokeWidth="20"
        strokeLinecap="round"
      />
      <path
        d="M132 372h248"
        stroke="currentColor"
        strokeWidth="20"
        strokeLinecap="round"
      />
    </svg>
  );
}
