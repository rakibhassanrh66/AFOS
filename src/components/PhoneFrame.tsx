import React from 'react';

interface Props {
  children: React.ReactNode;
}

const PhoneFrame: React.FC<Props> = ({ children }) => (
  <div className="min-h-screen bg-gradient-to-br from-slate-900 via-indigo-950 to-slate-900 flex items-center justify-center p-4">
    {/* Ambient glow */}
    <div className="absolute w-96 h-96 rounded-full bg-indigo-600/20 blur-3xl top-1/4 -left-20 pointer-events-none" />
    <div className="absolute w-80 h-80 rounded-full bg-purple-600/15 blur-3xl bottom-1/4 -right-10 pointer-events-none" />

    {/* Phone shell */}
    <div
      className="relative w-full max-w-[390px] rounded-[3rem] overflow-hidden shadow-2xl"
      style={{
        background: '#0f0f1a',
        boxShadow: '0 0 0 2px #2d2d4e, 0 0 0 4px #1a1a2e, 0 40px 80px rgba(0,0,0,0.8)',
        height: '844px',
      }}
    >
      {/* Status bar */}
      <div className="flex items-center justify-between px-6 pt-3 pb-1 bg-black/30 backdrop-blur-sm">
        <span className="text-white text-xs font-semibold">9:41</span>
        <div className="w-24 h-6 bg-black rounded-full" />
        <div className="flex items-center gap-1">
          <div className="flex gap-0.5 items-end h-3">
            {[2, 3, 4, 5].map((h) => (
              <div key={h} className="w-1 bg-white rounded-sm" style={{ height: `${h * 2.5}px` }} />
            ))}
          </div>
          <span className="text-white text-xs">●</span>
          <span className="text-white text-xs font-semibold">100%</span>
        </div>
      </div>

      {/* App content */}
      <div className="h-[calc(844px-52px)] overflow-y-auto overflow-x-hidden scrollbar-hide">
        {children}
      </div>
    </div>
  </div>
);

export default PhoneFrame;
