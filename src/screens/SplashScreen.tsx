import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

interface Props {
  onFinish: () => void;
}

const SplashScreen: React.FC<Props> = ({ onFinish }) => {
  const [phase, setPhase] = useState<'intro' | 'logo' | 'tagline' | 'out'>('intro');

  useEffect(() => {
    const t1 = setTimeout(() => setPhase('logo'), 400);
    const t2 = setTimeout(() => setPhase('tagline'), 1400);
    const t3 = setTimeout(() => setPhase('out'), 2800);
    const t4 = setTimeout(() => onFinish(), 3400);
    return () => { clearTimeout(t1); clearTimeout(t2); clearTimeout(t3); clearTimeout(t4); };
  }, [onFinish]);

  return (
    <AnimatePresence>
      {phase !== 'out' ? (
        <motion.div
          key="splash"
          className="w-full h-full flex flex-col items-center justify-center relative overflow-hidden"
          style={{ background: 'linear-gradient(135deg, #0f0f2e 0%, #1a1040 40%, #0d1b4b 100%)' }}
          exit={{ opacity: 0, scale: 1.05 }}
          transition={{ duration: 0.5 }}
        >
          {/* Animated rings */}
          {[1, 2, 3].map((i) => (
            <motion.div
              key={i}
              className="absolute rounded-full border border-indigo-500/20"
              style={{ width: i * 160, height: i * 160 }}
              animate={{ scale: [1, 1.1, 1], opacity: [0.3, 0.6, 0.3] }}
              transition={{ duration: 3, repeat: Infinity, delay: i * 0.4, ease: 'easeInOut' }}
            />
          ))}

          {/* Floating particles */}
          {Array.from({ length: 20 }).map((_, i) => (
            <motion.div
              key={i}
              className="absolute w-1 h-1 rounded-full bg-indigo-400/60"
              style={{
                left: `${Math.random() * 100}%`,
                top: `${Math.random() * 100}%`,
              }}
              animate={{
                y: [0, -20, 0],
                opacity: [0, 1, 0],
                scale: [0, 1.5, 0],
              }}
              transition={{
                duration: 2 + Math.random() * 2,
                repeat: Infinity,
                delay: Math.random() * 2,
                ease: 'easeInOut',
              }}
            />
          ))}

          {/* Hexagonal grid bg */}
          <div className="absolute inset-0 opacity-5" style={{
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='52' viewBox='0 0 60 52' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%236366f1' stroke-width='1'%3E%3Cpolygon points='30,1 59,17 59,49 30,51 1,49 1,17'/%3E%3C/g%3E%3C/svg%3E")`,
            backgroundSize: '60px 52px',
          }} />

          {/* Logo container */}
          <motion.div
            className="flex flex-col items-center z-10"
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: phase === 'intro' ? 0 : 1, y: phase === 'intro' ? 30 : 0 }}
            transition={{ duration: 0.7, ease: [0.34, 1.56, 0.64, 1] }}
          >
            {/* Icon */}
            <motion.div
              className="w-24 h-24 rounded-3xl flex items-center justify-center mb-6 relative"
              style={{
                background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
                boxShadow: '0 0 60px rgba(99,102,241,0.5), 0 0 120px rgba(99,102,241,0.2)',
              }}
              animate={{ rotate: [0, 5, -5, 0] }}
              transition={{ duration: 4, repeat: Infinity, ease: 'easeInOut' }}
            >
              <img src="/afos-logo.png" alt="AFOS" className="w-16 h-16 object-contain" />
            </motion.div>

            {/* AFOS text */}
            <div className="flex items-end gap-1 mb-2">
              {'AFOS'.split('').map((letter, i) => (
                <motion.span
                  key={i}
                  className="text-6xl font-black text-white tracking-wider"
                  style={{ textShadow: '0 0 40px rgba(99,102,241,0.8)' }}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: phase === 'intro' ? 0 : 1, y: phase === 'intro' ? 20 : 0 }}
                  transition={{ duration: 0.5, delay: i * 0.1 + 0.2 }}
                >
                  {letter}
                </motion.span>
              ))}
            </div>

            {/* Tagline */}
            <AnimatePresence>
              {(phase === 'tagline' || (phase as string) === 'out') && (
                <motion.div
                  className="text-center"
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.5 }}
                >
                  <p className="text-indigo-300 text-sm font-medium tracking-[0.3em] uppercase">
                    All Facilities One System
                  </p>
                  <motion.div
                    className="mt-3 h-0.5 bg-gradient-to-r from-transparent via-indigo-400 to-transparent"
                    initial={{ scaleX: 0 }}
                    animate={{ scaleX: 1 }}
                    transition={{ duration: 0.8, delay: 0.2 }}
                  />
                </motion.div>
              )}
            </AnimatePresence>
          </motion.div>

          {/* Bottom loading bar */}
          <motion.div
            className="absolute bottom-16 w-32 h-0.5 rounded-full overflow-hidden bg-indigo-900"
            initial={{ opacity: 0 }}
            animate={{ opacity: phase === 'tagline' ? 1 : 0 }}
          >
            <motion.div
              className="h-full bg-gradient-to-r from-indigo-400 to-purple-400 rounded-full"
              initial={{ width: '0%' }}
              animate={{ width: phase === 'tagline' ? '100%' : '0%' }}
              transition={{ duration: 1.2, ease: 'easeInOut' }}
            />
          </motion.div>

          <motion.p
            className="absolute bottom-10 text-indigo-500 text-xs"
            animate={{ opacity: [0.4, 1, 0.4] }}
            transition={{ duration: 1.5, repeat: Infinity }}
          >
            Smart Campus Platform
          </motion.p>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
};

export default SplashScreen;
