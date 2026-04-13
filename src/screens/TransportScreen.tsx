import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { ArrowLeft, Bus, Clock, MapPin, Navigation, Wifi } from 'lucide-react';
import { transportService } from '../services/mockBackend';
import type { TransportRoute } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

interface Props { onBack: () => void }

const statusStyle: Record<string, { bg: string; color: string; label: string }> = {
  active: { bg: 'rgba(16,185,129,0.2)', color: '#34d399', label: 'Active' },
  delayed: { bg: 'rgba(245,158,11,0.2)', color: '#fbbf24', label: 'Delayed' },
  cancelled: { bg: 'rgba(239,68,68,0.2)', color: '#f87171', label: 'Cancelled' },
};

const TransportScreen: React.FC<Props> = ({ onBack }) => {
  const [routes, setRoutes] = useState<TransportRoute[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    transportService.getRoutes().then((r) => { setRoutes(r); setLoading(false); });
  }, []);

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-6" style={{ background: 'linear-gradient(135deg, #0f2e0f, #0d1b0d)' }}>
        <div className="flex items-center gap-3 mb-4">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <div>
            <h2 className="text-white font-bold text-xl">Campus Transport</h2>
            <div className="flex items-center gap-1.5 mt-0.5">
              <div className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
              <p className="text-emerald-400 text-xs font-semibold">Live Tracking</p>
            </div>
          </div>
        </div>

        {/* Mini map placeholder */}
        <motion.div
          className="rounded-3xl overflow-hidden relative"
          style={{
            height: 140,
            background: 'linear-gradient(135deg, #0a2a0a, #0d2a1a)',
            border: '1px solid rgba(16,185,129,0.2)',
          }}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
        >
          {/* Fake map grid */}
          <div className="absolute inset-0 opacity-10" style={{
            backgroundImage: 'linear-gradient(rgba(16,185,129,0.5) 1px, transparent 1px), linear-gradient(90deg, rgba(16,185,129,0.5) 1px, transparent 1px)',
            backgroundSize: '30px 30px',
          }} />
          {/* Animated bus dot */}
          <motion.div
            className="absolute w-4 h-4 rounded-full bg-emerald-400 shadow-lg flex items-center justify-center"
            style={{ top: '40%', left: '30%', boxShadow: '0 0 12px rgba(52,211,153,0.8)' }}
            animate={{ x: [0, 40, 80, 40, 0], y: [0, -20, 0, 20, 0] }}
            transition={{ duration: 8, repeat: Infinity, ease: 'linear' }}
          >
            <div className="w-2 h-2 rounded-full bg-white" />
          </motion.div>
          <motion.div
            className="absolute w-3 h-3 rounded-full bg-amber-400"
            style={{ top: '60%', left: '60%', boxShadow: '0 0 10px rgba(251,191,36,0.7)' }}
            animate={{ x: [0, -30, -60, -30, 0], y: [0, 15, 0, -15, 0] }}
            transition={{ duration: 10, repeat: Infinity, ease: 'linear', delay: 2 }}
          >
            <div className="w-1.5 h-1.5 rounded-full bg-white" />
          </motion.div>
          {/* Campus label */}
          <div className="absolute bottom-3 left-3 right-3 flex items-center justify-between">
            <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl"
              style={{ background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(8px)' }}>
              <Wifi size={12} className="text-emerald-400" />
              <span className="text-emerald-400 text-xs font-semibold">Live GPS — 3 buses tracked</span>
            </div>
          </div>
        </motion.div>
      </div>

      {/* Routes */}
      <div className="flex-1 px-5 py-5">
        {loading ? (
          <div className="flex justify-center pt-16"><LoadingSpinner label="Fetching routes..." color="#10b981" /></div>
        ) : (
          <div className="flex flex-col gap-4">
            <h3 className="text-white font-bold text-base">Active Routes</h3>
            {routes.map((route, i) => {
              const st = statusStyle[route.status];
              const isOpen = selected === route.id;
              return (
                <motion.div
                  key={route.id}
                  className="rounded-3xl overflow-hidden"
                  style={{
                    background: 'rgba(255,255,255,0.04)',
                    border: `1px solid ${isOpen ? 'rgba(16,185,129,0.3)' : 'rgba(255,255,255,0.07)'}`,
                  }}
                  initial={{ opacity: 0, y: 15 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: i * 0.1 }}
                >
                  {/* Route header */}
                  <motion.button
                    className="w-full p-4 text-left"
                    whileTap={{ scale: 0.99 }}
                    onClick={() => setSelected(isOpen ? null : route.id)}
                  >
                    <div className="flex items-start justify-between">
                      <div className="flex items-center gap-3">
                        <div className="w-11 h-11 rounded-2xl flex items-center justify-center"
                          style={{ background: 'rgba(16,185,129,0.15)' }}>
                          <Bus size={22} className="text-emerald-400" />
                        </div>
                        <div>
                          <p className="text-white font-bold text-sm">{route.name}</p>
                          <p className="text-indigo-500 text-xs">{route.busNumber}</p>
                        </div>
                      </div>
                      <span className="text-xs px-2.5 py-1 rounded-full font-semibold"
                        style={{ background: st.bg, color: st.color }}>{st.label}</span>
                    </div>

                    {/* ETA chip */}
                    {route.eta && (
                      <div className="flex items-center gap-2 mt-3">
                        <Navigation size={12} className="text-emerald-400" />
                        <span className="text-emerald-400 text-xs font-semibold">
                          {route.currentLocation} · ETA {route.eta}
                        </span>
                      </div>
                    )}
                  </motion.button>

                  {/* Expanded content */}
                  {isOpen && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      className="px-4 pb-4"
                      style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}
                    >
                      <div className="pt-4 flex flex-col gap-3">
                        {/* Route path */}
                        <div className="flex items-start gap-2">
                          <MapPin size={13} className="text-emerald-500 mt-0.5 shrink-0" />
                          <p className="text-indigo-300 text-xs leading-relaxed">{route.route}</p>
                        </div>

                        {/* Departure times */}
                        <div>
                          <div className="flex items-center gap-2 mb-2">
                            <Clock size={13} className="text-indigo-500" />
                            <span className="text-indigo-400 text-xs font-semibold">Departure Times</span>
                          </div>
                          <div className="flex flex-wrap gap-2">
                            {route.departureTime.map((t) => (
                              <span key={t} className="px-2.5 py-1 rounded-xl text-xs font-semibold"
                                style={{ background: 'rgba(16,185,129,0.12)', color: '#6ee7b7' }}>
                                {t}
                              </span>
                            ))}
                          </div>
                        </div>

                        <motion.button
                          whileTap={{ scale: 0.97 }}
                          className="w-full py-3 rounded-2xl text-sm font-bold text-white flex items-center justify-center gap-2 mt-1"
                          style={{ background: 'linear-gradient(135deg, #059669, #10b981)', boxShadow: '0 4px 16px rgba(16,185,129,0.3)' }}
                        >
                          <Navigation size={16} />
                          Track This Bus
                        </motion.button>
                      </div>
                    </motion.div>
                  )}
                </motion.div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};

export default TransportScreen;
