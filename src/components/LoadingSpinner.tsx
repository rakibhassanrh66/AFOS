import React from 'react';

interface Props {
  size?: 'sm' | 'md' | 'lg';
  color?: string;
  label?: string;
}

const sizes = { sm: 'w-5 h-5', md: 'w-8 h-8', lg: 'w-12 h-12' };

const LoadingSpinner: React.FC<Props> = ({ size = 'md', color = '#6366f1', label }) => (
  <div className="flex flex-col items-center justify-center gap-3">
    <svg
      className={`${sizes[size]} animate-spin`}
      viewBox="0 0 24 24"
      fill="none"
      style={{ color }}
    >
      <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" strokeLinecap="round"
        strokeDasharray="60" strokeDashoffset="20" opacity="0.25" />
      <path d="M12 2a10 10 0 0 1 10 10" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
    {label && <p className="text-sm font-medium" style={{ color }}>{label}</p>}
  </div>
);

export default LoadingSpinner;
