import React from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  LayoutDashboard, Calendar, CreditCard, BookOpen,
  Settings, LogOut, ChevronRight, X, Bus, Users,
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';

type Screen = 'dashboard' | 'schedule' | 'transport' | 'payment' | 'library' | 'lostfound' | 'clubs' | 'settings' | 'cart';

interface Props {
  open: boolean;
  onClose: () => void;
  onNavigate: (screen: Screen) => void;
  current: Screen;
}

const menuItems = [
  { id: 'dashboard' as Screen, label: 'Dashboard', icon: LayoutDashboard },
  { id: 'schedule' as Screen, label: 'Schedule', icon: Calendar },
  { id: 'transport' as Screen, label: 'Transport', icon: Bus },
  { id: 'payment' as Screen, label: 'Payments', icon: CreditCard },
  { id: 'library' as Screen, label: 'Library', icon: BookOpen },
  { id: 'clubs' as Screen, label: 'Clubs', icon: Users },
  { id: 'settings' as Screen, label: 'Settings', icon: Settings },
];

const roleColors: Record<string, string> = {
  student: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
  admin: 'linear-gradient(135deg, #f59e0b, #ef4444)',
};

const Drawer: React.FC<Props> = ({ open, onClose, onNavigate, current }) => {
  const { user, logout } = useAuth();

  return (
    <AnimatePresence>
      {open && (
        <>
          {/* Backdrop */}
          <motion.div
            key="backdrop"
            className="absolute inset-0 z-40"
            style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />

          {/* Drawer panel */}
          <motion.div
            key="drawer"
            className="absolute left-0 top-0 bottom-0 z-50 w-4/5 max-w-[300px] flex flex-col overflow-hidden"
            style={{
              background: 'linear-gradient(160deg, #0f0f2e 0%, #1a1040 100%)',
              borderRight: '1px solid rgba(255,255,255,0.08)',
            }}
            initial={{ x: '-100%' }}
            animate={{ x: 0 }}
            exit={{ x: '-100%' }}
            transition={{ type: 'spring', damping: 28, stiffness: 280 }}
          >
            {/* Close btn */}
            <button
              onClick={onClose}
              className="absolute top-4 right-4 z-10 w-8 h-8 rounded-full flex items-center justify-center"
              style={{ background: 'rgba(255,255,255,0.08)' }}
            >
              <X size={16} className="text-indigo-300" />
            </button>

            {/* Profile section */}
            <div className="px-6 pt-10 pb-6" style={{ borderBottom: '1px solid rgba(255,255,255,0.07)' }}>
              <motion.div
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.15 }}
              >
                {/* Avatar */}
                <div
                  className="w-16 h-16 rounded-2xl flex items-center justify-center text-2xl font-black text-white mb-4 relative"
                  style={{
                    background: roleColors[user?.role ?? 'student'],
                    boxShadow: '0 8px 24px rgba(99,102,241,0.4)',
                  }}
                >
                  {user?.name?.[0] ?? 'U'}
                  <div
                    className="absolute -bottom-1 -right-1 w-4 h-4 rounded-full border-2 border-indigo-950"
                    style={{ background: '#10b981' }}
                  />
                </div>

                <h3 className="text-white font-bold text-base leading-tight">{user?.name}</h3>
                <p className="text-indigo-400 text-xs mt-0.5">{user?.studentId}</p>
                <div className="flex items-center gap-2 mt-2">
                  <span
                    className="text-xs px-2.5 py-1 rounded-full font-semibold capitalize"
                    style={{
                      background: user?.role === 'admin' ? 'rgba(245,158,11,0.2)' : 'rgba(99,102,241,0.2)',
                      color: user?.role === 'admin' ? '#fbbf24' : '#a5b4fc',
                    }}
                  >
                    {user?.role}
                  </span>
                  <span className="text-indigo-500 text-xs">{user?.department}</span>
                </div>
              </motion.div>
            </div>

            {/* Menu items */}
            <div className="flex-1 px-4 py-4 overflow-y-auto">
              <p className="text-indigo-600 text-xs font-semibold uppercase tracking-widest px-2 mb-3">Navigation</p>
              <div className="flex flex-col gap-1">
                {menuItems.map((item, i) => {
                  const Icon = item.icon;
                  const isActive = current === item.id;
                  return (
                    <motion.button
                      key={item.id}
                      initial={{ opacity: 0, x: -20 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: 0.1 + i * 0.05 }}
                      whileTap={{ scale: 0.98 }}
                      onClick={() => { onNavigate(item.id); onClose(); }}
                      className="flex items-center gap-3 px-4 py-3.5 rounded-2xl w-full transition-all relative"
                      style={{
                        background: isActive
                          ? 'linear-gradient(135deg, rgba(99,102,241,0.3), rgba(139,92,246,0.2))'
                          : 'transparent',
                        border: isActive ? '1px solid rgba(99,102,241,0.3)' : '1px solid transparent',
                      }}
                    >
                      <div
                        className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
                        style={{
                          background: isActive
                            ? 'linear-gradient(135deg, #6366f1, #8b5cf6)'
                            : 'rgba(255,255,255,0.06)',
                        }}
                      >
                        <Icon size={18} className={isActive ? 'text-white' : 'text-indigo-400'} />
                      </div>
                      <span className={`text-sm font-semibold flex-1 text-left ${isActive ? 'text-white' : 'text-indigo-300'}`}>
                        {item.label}
                      </span>
                      {isActive && <ChevronRight size={16} className="text-indigo-400" />}
                    </motion.button>
                  );
                })}
              </div>
            </div>

            {/* Logout */}
            <div className="px-4 pb-8" style={{ borderTop: '1px solid rgba(255,255,255,0.07)' }}>
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={logout}
                className="flex items-center gap-3 px-4 py-3.5 rounded-2xl w-full mt-4"
                style={{ background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.2)' }}
              >
                <div className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: 'rgba(239,68,68,0.2)' }}>
                  <LogOut size={18} className="text-red-400" />
                </div>
                <span className="text-red-400 text-sm font-semibold">Logout</span>
              </motion.button>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

export default Drawer;
