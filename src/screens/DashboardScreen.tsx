import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import {
  Menu, Bell, Calendar, Bus, CreditCard, BookOpen,
  Search, MapPin, Users, ShoppingCart, TrendingUp,
  Clock, ChevronRight, Wifi,
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { dashboardService } from '../services/mockBackend';
import type { DashboardStats } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

type Screen = 'dashboard' | 'schedule' | 'transport' | 'payment' | 'library' | 'lostfound' | 'clubs' | 'settings' | 'cart';

interface Props {
  onOpenDrawer: () => void;
  onNavigate: (screen: Screen) => void;
}

const MODULE_CARDS = [
  { id: 'schedule' as Screen, label: 'Class Schedule', icon: Calendar, color: '#6366f1', bg: 'rgba(99,102,241,0.15)', stat: 'upcomingClasses', unit: 'today', emoji: '📚' },
  { id: 'transport' as Screen, label: 'Transport', icon: Bus, color: '#10b981', bg: 'rgba(16,185,129,0.15)', stat: 'nextBus', unit: '', emoji: '🚌' },
  { id: 'payment' as Screen, label: 'Payments', icon: CreditCard, color: '#f59e0b', bg: 'rgba(245,158,11,0.15)', stat: 'pendingPayments', unit: 'due', emoji: '💳' },
  { id: 'library' as Screen, label: 'Library', icon: BookOpen, color: '#06b6d4', bg: 'rgba(6,182,212,0.15)', stat: 'borrowedBooks', unit: 'books', emoji: '📖' },
  { id: 'lostfound' as Screen, label: 'Lost & Found', icon: MapPin, color: '#ec4899', bg: 'rgba(236,72,153,0.15)', stat: null, unit: '', emoji: '🔍' },
  { id: 'clubs' as Screen, label: 'Clubs', icon: Users, color: '#8b5cf6', bg: 'rgba(139,92,246,0.15)', stat: null, unit: '', emoji: '🎯' },
];

const QUICK_UPDATES = [
  { text: 'CS301 class moved to LT-5B', time: '10m ago', color: '#6366f1' },
  { text: 'Library fine payment due', time: '2h ago', color: '#ef4444' },
  { text: 'Bus-A01 arriving in 5 mins', time: 'Live', color: '#10b981' },
];

const DashboardScreen: React.FC<Props> = ({ onOpenDrawer, onNavigate }) => {
  const { user } = useAuth();
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [time, setTime] = useState(new Date());

  useEffect(() => {
    dashboardService.getStats().then((s) => { setStats(s); setLoading(false); });
    const t = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(t);
  }, []);

  const greeting = () => {
    const h = time.getHours();
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  };

  const getStatValue = (key: string | null): number | string | null => {
    if (!key || !stats) return null;
    const map: Record<string, number | string> = {
      upcomingClasses: stats.upcomingClasses,
      pendingPayments: stats.pendingPayments,
      borrowedBooks: stats.borrowedBooks,
      nextBus: stats.nextBus,
    };
    return map[key] ?? null;
  };

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div
        className="px-5 pt-4 pb-6 relative overflow-hidden"
        style={{ background: 'linear-gradient(135deg, #0f0f2e 0%, #1a1040 100%)' }}
      >
        {/* bg decoration */}
        <div className="absolute top-0 right-0 w-48 h-48 rounded-full bg-indigo-600/10 blur-3xl" />
        <div className="absolute -bottom-10 -left-10 w-36 h-36 rounded-full bg-purple-600/10 blur-3xl" />

        {/* Top bar */}
        <div className="flex items-center justify-between mb-5 relative z-10">
          <motion.button
            whileTap={{ scale: 0.92 }}
            onClick={onOpenDrawer}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.1)' }}
          >
            <Menu size={20} className="text-white" />
          </motion.button>

          <div className="flex items-center gap-1">
            <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span className="text-emerald-400 text-xs font-semibold">Online</span>
            <Wifi size={12} className="text-emerald-400 ml-1" />
          </div>

          <motion.button
            whileTap={{ scale: 0.92 }}
            className="w-10 h-10 rounded-2xl flex items-center justify-center relative"
            style={{ background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.1)' }}
          >
            <Bell size={20} className="text-white" />
            <span className="absolute top-2 right-2 w-2 h-2 rounded-full bg-red-500" />
          </motion.button>
        </div>

        {/* Greeting */}
        <motion.div
          className="relative z-10"
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
        >
          <p className="text-indigo-400 text-sm font-medium">{greeting()},</p>
          <h2 className="text-white text-2xl font-bold mt-0.5">{user?.name?.split(' ')[0]} 👋</h2>
          <p className="text-indigo-500 text-xs mt-1">{user?.department} · {user?.year}</p>
        </motion.div>

        {/* Time + date pill */}
        <motion.div
          className="mt-4 flex items-center gap-3 relative z-10"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.3 }}
        >
          <div
            className="flex items-center gap-2 px-4 py-2.5 rounded-2xl"
            style={{ background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.08)' }}
          >
            <Clock size={14} className="text-indigo-400" />
            <span className="text-white text-sm font-semibold font-mono">
              {time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </span>
          </div>
          <div
            className="flex items-center gap-2 px-4 py-2.5 rounded-2xl"
            style={{ background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.08)' }}
          >
            <span className="text-white text-sm font-semibold">
              {time.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })}
            </span>
          </div>
        </motion.div>

        {/* Search bar */}
        <motion.div
          className="mt-4 flex items-center gap-3 px-4 py-3 rounded-2xl relative z-10"
          style={{ background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.08)' }}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4 }}
        >
          <Search size={16} className="text-indigo-400 shrink-0" />
          <span className="text-indigo-500 text-sm">Search modules, schedules...</span>
        </motion.div>
      </div>

      {/* Content */}
      <div className="flex-1 px-5 py-5 flex flex-col gap-6">

        {/* Stats row */}
        {loading ? (
          <div className="flex justify-center py-4"><LoadingSpinner size="sm" /></div>
        ) : (
          <motion.div
            className="grid grid-cols-3 gap-3"
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
          >
            {[
              { label: 'Classes', value: stats?.upcomingClasses, icon: '📅', color: '#6366f1' },
              { label: 'Dues', value: `RM${stats?.pendingPayments}`, icon: '💰', color: '#f59e0b' },
              { label: 'Books', value: stats?.borrowedBooks, icon: '📚', color: '#06b6d4' },
            ].map((s) => (
              <div
                key={s.label}
                className="flex flex-col items-center py-3 px-2 rounded-2xl"
                style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)' }}
              >
                <span className="text-xl mb-1">{s.icon}</span>
                <span className="text-white font-bold text-lg leading-none">{s.value}</span>
                <span className="text-indigo-500 text-xs mt-1">{s.label}</span>
              </div>
            ))}
          </motion.div>
        )}

        {/* Quick access banner */}
        <motion.div
          className="relative rounded-3xl overflow-hidden p-5 cursor-pointer"
          whileHover={{ scale: 1.01 }}
          style={{ background: 'linear-gradient(135deg, #6366f1, #8b5cf6)' }}
          whileTap={{ scale: 0.98 }}
          onClick={() => onNavigate('cart')}
          initial={{ opacity: 0, y: 15 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
        >
          <div className="absolute top-0 right-0 w-32 h-32 rounded-full bg-white/10 blur-2xl" />
          <div className="flex items-center justify-between relative z-10">
            <div>
              <p className="text-indigo-200 text-xs font-semibold uppercase tracking-widest">New Feature</p>
              <h3 className="text-white font-bold text-lg mt-0.5">Campus Store 🛒</h3>
              <p className="text-indigo-200 text-xs mt-1">Order supplies, food & services</p>
            </div>
            <div className="flex items-center gap-2">
              <div
                className="w-12 h-12 rounded-2xl flex items-center justify-center"
                style={{ background: 'rgba(255,255,255,0.2)' }}
              >
                <ShoppingCart size={22} className="text-white" />
              </div>
              <ChevronRight size={20} className="text-white/60" />
            </div>
          </div>
          <div className="flex items-center gap-2 mt-3">
            <TrendingUp size={14} className="text-indigo-200" />
            <span className="text-indigo-200 text-xs">847 students ordered today</span>
          </div>
        </motion.div>

        {/* Module grid */}
        <div>
          <h3 className="text-white font-bold text-base mb-4">Campus Services</h3>
          <div className="grid grid-cols-2 gap-3">
            {MODULE_CARDS.map((mod, i) => {
              const Icon = mod.icon;
              const statVal = getStatValue(mod.stat);
              return (
                <motion.button
                  key={mod.id}
                  whileTap={{ scale: 0.96 }}
                  onClick={() => onNavigate(mod.id)}
                  className="flex flex-col items-start p-4 rounded-3xl relative overflow-hidden"
                  style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)' }}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.1 + i * 0.07 }}
                >
                  <div className="absolute top-0 right-0 text-3xl opacity-15 -rotate-12 mt-1 mr-1">{mod.emoji}</div>

                  <div
                    className="w-11 h-11 rounded-2xl flex items-center justify-center mb-3"
                    style={{ background: mod.bg }}
                  >
                    <Icon size={22} style={{ color: mod.color }} />
                  </div>
                  <p className="text-white text-sm font-bold leading-tight">{mod.label}</p>
                  {statVal !== null && statVal !== undefined ? (
                    <p className="text-xs mt-1 font-semibold" style={{ color: mod.color }}>
                      {statVal} {mod.unit}
                    </p>
                  ) : (
                    <p className="text-indigo-600 text-xs mt-1">Tap to open</p>
                  )}
                </motion.button>
              );
            })}
          </div>
        </div>

        {/* Quick updates */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-white font-bold text-base">Live Updates</h3>
            <span className="text-indigo-400 text-xs font-semibold">View all</span>
          </div>
          <div className="flex flex-col gap-2">
            {QUICK_UPDATES.map((u, i) => (
              <motion.div
                key={i}
                className="flex items-center gap-3 px-4 py-3.5 rounded-2xl"
                style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.06)' }}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.4 + i * 0.1 }}
              >
                <div className="w-2 h-2 rounded-full shrink-0" style={{ background: u.color }} />
                <p className="text-indigo-200 text-xs flex-1 font-medium">{u.text}</p>
                <span className="text-indigo-600 text-xs shrink-0">{u.time}</span>
              </motion.div>
            ))}
          </div>
        </div>

        <div className="h-4" />
      </div>
    </div>
  );
};

export default DashboardScreen;
