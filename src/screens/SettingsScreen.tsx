import React, { useState } from 'react';
import { motion } from 'framer-motion';
import {
  ArrowLeft, Bell, Moon, Globe, Shield, HelpCircle,
  ChevronRight, Info, Smartphone, Wifi
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';

interface Props { onBack: () => void }

const SettingsScreen: React.FC<Props> = ({ onBack }) => {
  const { user, logout } = useAuth();
  const [notifications, setNotifications] = useState(true);
  const [darkMode, setDarkMode] = useState(true);
  const [language] = useState('English');
  const [biometric, setBiometric] = useState(false);

  const Toggle: React.FC<{ value: boolean; onChange: () => void }> = ({ value, onChange }) => (
    <motion.button
      onClick={onChange}
      className="w-12 h-6 rounded-full relative transition-all"
      style={{ background: value ? 'linear-gradient(135deg, #6366f1, #8b5cf6)' : 'rgba(255,255,255,0.1)' }}
      whileTap={{ scale: 0.95 }}
    >
      <motion.div
        className="absolute top-0.5 w-5 h-5 rounded-full bg-white shadow-md"
        animate={{ left: value ? '26px' : '2px' }}
        transition={{ type: 'spring', stiffness: 400, damping: 28 }}
      />
    </motion.button>
  );

  const SECTIONS = [
    {
      title: 'Preferences',
      items: [
        {
          icon: Bell, label: 'Push Notifications', sub: 'Alerts for classes, payments',
          action: <Toggle value={notifications} onChange={() => setNotifications(!notifications)} />,
        },
        {
          icon: Moon, label: 'Dark Mode', sub: 'App appearance',
          action: <Toggle value={darkMode} onChange={() => setDarkMode(!darkMode)} />,
        },
        {
          icon: Shield, label: 'Biometric Login', sub: 'Fingerprint / Face ID',
          action: <Toggle value={biometric} onChange={() => setBiometric(!biometric)} />,
        },
        {
          icon: Globe, label: 'Language', sub: language,
          action: <ChevronRight size={18} className="text-indigo-500" />,
        },
      ],
    },
    {
      title: 'System',
      items: [
        {
          icon: Wifi, label: 'Connected Campus WiFi', sub: 'AFOS-Secure-Network',
          action: <div className="w-2 h-2 rounded-full bg-emerald-400" />,
        },
        {
          icon: Smartphone, label: 'App Version', sub: 'AFOS v2.4.1',
          action: <span className="text-indigo-600 text-xs">Latest</span>,
        },
      ],
    },
    {
      title: 'Support',
      items: [
        {
          icon: HelpCircle, label: 'Help & FAQ', sub: 'Get support',
          action: <ChevronRight size={18} className="text-indigo-500" />,
        },
        {
          icon: Info, label: 'About AFOS', sub: 'All Facilities One System',
          action: <ChevronRight size={18} className="text-indigo-500" />,
        },
      ],
    },
  ];

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-6" style={{ background: 'linear-gradient(135deg, #1a1040, #0f0f2e)' }}>
        <div className="flex items-center gap-3 mb-5">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <h2 className="text-white font-bold text-xl">Settings</h2>
        </div>

        {/* Profile card */}
        <motion.div
          className="flex items-center gap-4 p-4 rounded-3xl"
          style={{
            background: 'linear-gradient(135deg, rgba(99,102,241,0.15), rgba(139,92,246,0.1))',
            border: '1px solid rgba(99,102,241,0.2)',
          }}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
        >
          <div
            className="w-14 h-14 rounded-2xl flex items-center justify-center text-xl font-black text-white"
            style={{ background: 'linear-gradient(135deg, #6366f1, #8b5cf6)' }}
          >
            {user?.name?.[0]}
          </div>
          <div className="flex-1">
            <p className="text-white font-bold">{user?.name}</p>
            <p className="text-indigo-400 text-xs mt-0.5">{user?.email}</p>
            <span className="inline-block mt-1 text-xs px-2 py-0.5 rounded-full font-semibold capitalize"
              style={{ background: 'rgba(99,102,241,0.2)', color: '#a5b4fc' }}>
              {user?.role}
            </span>
          </div>
          <ChevronRight size={18} className="text-indigo-500" />
        </motion.div>
      </div>

      {/* Settings sections */}
      <div className="flex-1 px-5 py-5 flex flex-col gap-6">
        {SECTIONS.map((section, si) => (
          <motion.div
            key={section.title}
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: si * 0.1 }}
          >
            <p className="text-indigo-600 text-xs font-semibold uppercase tracking-widest mb-3 px-1">
              {section.title}
            </p>
            <div className="rounded-3xl overflow-hidden" style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)' }}>
              {section.items.map((item, ii) => {
                const Icon = item.icon;
                return (
                  <div
                    key={item.label}
                    className="flex items-center gap-3 px-4 py-4"
                    style={{ borderBottom: ii < section.items.length - 1 ? '1px solid rgba(255,255,255,0.05)' : 'none' }}
                  >
                    <div className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
                      style={{ background: 'rgba(99,102,241,0.12)' }}>
                      <Icon size={18} className="text-indigo-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-white text-sm font-semibold">{item.label}</p>
                      <p className="text-indigo-500 text-xs mt-0.5 truncate">{item.sub}</p>
                    </div>
                    {item.action}
                  </div>
                );
              })}
            </div>
          </motion.div>
        ))}

        {/* Logout */}
        <motion.button
          whileTap={{ scale: 0.97 }}
          onClick={logout}
          className="w-full py-4 rounded-3xl font-bold text-red-400 text-sm"
          style={{ background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.2)' }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4 }}
        >
          Sign Out
        </motion.button>

        <p className="text-center text-indigo-700 text-xs pb-4">
          AFOS © 2024 · Smart Campus Platform<br />
          All Facilities One System
        </p>
      </div>
    </div>
  );
};

export default SettingsScreen;
