import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { GraduationCap, ShieldCheck, Eye, EyeOff, ArrowRight, AlertCircle } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import LoadingSpinner from '../components/LoadingSpinner';

const DEMO_CREDENTIALS = [
  { role: 'student' as const, email: 'ahmad.farhan@campus.edu', password: 'student123', label: 'Student Demo' },
  { role: 'admin' as const, email: 'sarah.lim@campus.edu', password: 'admin123', label: 'Admin Demo' },
];

const LoginScreen: React.FC = () => {
  const { login, isLoading, error } = useAuth();
  const [role, setRole] = useState<'student' | 'admin'>('student');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPass, setShowPass] = useState(false);
  const [localError, setLocalError] = useState('');

  const fillDemo = (d: typeof DEMO_CREDENTIALS[0]) => {
    setRole(d.role);
    setEmail(d.email);
    setPassword(d.password);
    setLocalError('');
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLocalError('');
    if (!email || !password) {
      setLocalError('Please fill in all fields.');
      return;
    }
    try {
      await login(email, password, role);
    } catch {
      // error handled in context
    }
  };

  const displayError = localError || error;

  return (
    <div
      className="w-full h-full flex flex-col relative overflow-hidden"
      style={{ background: 'linear-gradient(160deg, #0f0f2e 0%, #1a1040 50%, #0d1b4b 100%)' }}
    >
      {/* Decorative blobs */}
      <div className="absolute -top-20 -right-20 w-64 h-64 rounded-full bg-indigo-600/20 blur-3xl" />
      <div className="absolute -bottom-20 -left-20 w-64 h-64 rounded-full bg-purple-600/20 blur-3xl" />

      {/* Header */}
      <div className="pt-10 pb-6 px-7 z-10">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
        >
          <div className="flex items-center gap-3 mb-6">
            <div
              className="w-10 h-10 rounded-2xl flex items-center justify-center"
              style={{ background: 'linear-gradient(135deg, #6366f1, #8b5cf6)' }}
            >
              <img src="/afos-logo.png" alt="AFOS" className="w-7 h-7 object-contain" />
            </div>
            <span className="text-white font-black text-xl tracking-widest">AFOS</span>
          </div>
          <h1 className="text-white text-3xl font-bold mb-1">Welcome back 👋</h1>
          <p className="text-indigo-300 text-sm">Sign in to access your campus portal</p>
        </motion.div>
      </div>

      {/* Card */}
      <motion.div
        className="flex-1 mx-4 rounded-3xl p-6 flex flex-col gap-5 overflow-y-auto"
        style={{ background: 'rgba(255,255,255,0.04)', backdropFilter: 'blur(20px)', border: '1px solid rgba(255,255,255,0.08)' }}
        initial={{ opacity: 0, y: 40 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6, delay: 0.2 }}
      >
        {/* Role selector */}
        <div>
          <p className="text-indigo-300 text-xs font-semibold uppercase tracking-widest mb-3">Login As</p>
          <div className="flex gap-3">
            {(['student', 'admin'] as const).map((r) => (
              <motion.button
                key={r}
                onClick={() => setRole(r)}
                whileTap={{ scale: 0.97 }}
                className="flex-1 flex items-center gap-2 px-4 py-3 rounded-2xl transition-all duration-300 relative overflow-hidden"
                style={{
                  background: role === r
                    ? 'linear-gradient(135deg, #6366f1, #8b5cf6)'
                    : 'rgba(255,255,255,0.05)',
                  border: `1.5px solid ${role === r ? 'transparent' : 'rgba(255,255,255,0.1)'}`,
                  boxShadow: role === r ? '0 8px 24px rgba(99,102,241,0.35)' : 'none',
                }}
              >
                {r === 'student' ? (
                  <GraduationCap size={18} className={role === r ? 'text-white' : 'text-indigo-400'} />
                ) : (
                  <ShieldCheck size={18} className={role === r ? 'text-white' : 'text-indigo-400'} />
                )}
                <span className={`text-sm font-semibold capitalize ${role === r ? 'text-white' : 'text-indigo-300'}`}>
                  {r}
                </span>
              </motion.button>
            ))}
          </div>
        </div>

        {/* Form */}
        <form onSubmit={handleLogin} className="flex flex-col gap-4">
          {/* Email */}
          <div>
            <label className="text-indigo-300 text-xs font-semibold uppercase tracking-widest mb-2 block">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="your@campus.edu"
              className="w-full px-4 py-3.5 rounded-2xl text-white text-sm outline-none transition-all"
              style={{
                background: 'rgba(255,255,255,0.06)',
                border: '1.5px solid rgba(255,255,255,0.1)',
              }}
              onFocus={(e) => e.target.style.borderColor = '#6366f1'}
              onBlur={(e) => e.target.style.borderColor = 'rgba(255,255,255,0.1)'}
            />
          </div>

          {/* Password */}
          <div>
            <label className="text-indigo-300 text-xs font-semibold uppercase tracking-widest mb-2 block">Password</label>
            <div className="relative">
              <input
                type={showPass ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="w-full px-4 py-3.5 pr-12 rounded-2xl text-white text-sm outline-none transition-all"
                style={{
                  background: 'rgba(255,255,255,0.06)',
                  border: '1.5px solid rgba(255,255,255,0.1)',
                }}
                onFocus={(e) => e.target.style.borderColor = '#6366f1'}
                onBlur={(e) => e.target.style.borderColor = 'rgba(255,255,255,0.1)'}
              />
              <button
                type="button"
                onClick={() => setShowPass(!showPass)}
                className="absolute right-4 top-1/2 -translate-y-1/2 text-indigo-400"
              >
                {showPass ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          {/* Error */}
          <AnimatePresence>
            {displayError && (
              <motion.div
                initial={{ opacity: 0, y: -5, height: 0 }}
                animate={{ opacity: 1, y: 0, height: 'auto' }}
                exit={{ opacity: 0, y: -5, height: 0 }}
                className="flex items-center gap-2 px-4 py-3 rounded-2xl"
                style={{ background: 'rgba(239,68,68,0.15)', border: '1px solid rgba(239,68,68,0.3)' }}
              >
                <AlertCircle size={16} className="text-red-400 shrink-0" />
                <p className="text-red-400 text-xs">{displayError}</p>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Submit */}
          <motion.button
            type="submit"
            disabled={isLoading}
            whileTap={{ scale: 0.98 }}
            className="w-full py-4 rounded-2xl flex items-center justify-center gap-2 font-bold text-white text-sm relative overflow-hidden"
            style={{
              background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
              boxShadow: '0 8px 30px rgba(99,102,241,0.4)',
              opacity: isLoading ? 0.8 : 1,
            }}
          >
            {isLoading ? (
              <LoadingSpinner size="sm" color="white" />
            ) : (
              <>
                <span>Sign In</span>
                <ArrowRight size={18} />
              </>
            )}
          </motion.button>
        </form>

        {/* Demo credentials */}
        <div>
          <div className="flex items-center gap-3 mb-3">
            <div className="flex-1 h-px bg-white/10" />
            <span className="text-indigo-400 text-xs">Quick Demo</span>
            <div className="flex-1 h-px bg-white/10" />
          </div>
          <div className="flex gap-2">
            {DEMO_CREDENTIALS.map((d) => (
              <motion.button
                key={d.role}
                whileTap={{ scale: 0.97 }}
                onClick={() => fillDemo(d)}
                className="flex-1 py-2.5 rounded-xl text-xs font-semibold transition-all"
                style={{
                  background: 'rgba(99,102,241,0.12)',
                  border: '1px solid rgba(99,102,241,0.25)',
                  color: '#a5b4fc',
                }}
              >
                {d.label}
              </motion.button>
            ))}
          </div>
          <p className="text-indigo-500 text-xs text-center mt-3">
            Tap a demo button then Sign In ↑
          </p>
        </div>
      </motion.div>

      <div className="pb-6 text-center">
        <p className="text-indigo-600 text-xs mt-4">AFOS v2.4.1 · Smart Campus Platform</p>
      </div>
    </div>
  );
};

export default LoginScreen;
