import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { ArrowLeft, Calendar, Clock, MapPin, User } from 'lucide-react';
import { scheduleService } from '../services/mockBackend';
import type { ClassSchedule } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

interface Props { onBack: () => void }

const typeBadge: Record<string, { bg: string; color: string }> = {
  lecture: { bg: 'rgba(99,102,241,0.2)', color: '#a5b4fc' },
  lab: { bg: 'rgba(16,185,129,0.2)', color: '#6ee7b7' },
  tutorial: { bg: 'rgba(245,158,11,0.2)', color: '#fcd34d' },
};

const ScheduleScreen: React.FC<Props> = ({ onBack }) => {
  const [schedule, setSchedule] = useState<ClassSchedule[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeDay, setActiveDay] = useState('Monday');

  useEffect(() => {
    scheduleService.getSchedule().then((s) => { setSchedule(s); setLoading(false); });
  }, []);

  const filtered = schedule.filter((s) => s.day === activeDay);
  const today = new Date().toLocaleDateString('en', { weekday: 'long' });

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-6" style={{ background: 'linear-gradient(135deg, #0f0f2e, #1a1040)' }}>
        <div className="flex items-center gap-3 mb-5">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <div>
            <h2 className="text-white font-bold text-xl">Class Schedule</h2>
            <p className="text-indigo-400 text-xs">Semester 2, 2024</p>
          </div>
          <div className="ml-auto w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(99,102,241,0.2)' }}>
            <Calendar size={20} className="text-indigo-400" />
          </div>
        </div>

        {/* Day tabs */}
        <div className="flex gap-2 overflow-x-auto pb-1 scrollbar-hide">
          {DAYS.map((d) => {
            const isToday = d === today;
            const isActive = d === activeDay;
            return (
              <motion.button
                key={d}
                whileTap={{ scale: 0.95 }}
                onClick={() => setActiveDay(d)}
                className="flex flex-col items-center px-4 py-2.5 rounded-2xl shrink-0 transition-all"
                style={{
                  background: isActive ? 'linear-gradient(135deg, #6366f1, #8b5cf6)' : 'rgba(255,255,255,0.06)',
                  border: isToday && !isActive ? '1.5px solid rgba(99,102,241,0.5)' : '1.5px solid transparent',
                  boxShadow: isActive ? '0 4px 16px rgba(99,102,241,0.35)' : 'none',
                }}
              >
                <span className={`text-xs font-bold ${isActive ? 'text-white' : 'text-indigo-400'}`}>{d.slice(0, 3)}</span>
                {isToday && <div className="w-1 h-1 rounded-full bg-emerald-400 mt-1" />}
              </motion.button>
            );
          })}
        </div>
      </div>

      <div className="flex-1 px-5 py-5">
        {loading ? (
          <div className="flex justify-center pt-16"><LoadingSpinner label="Loading schedule..." /></div>
        ) : filtered.length === 0 ? (
          <motion.div className="flex flex-col items-center justify-center pt-20 gap-4"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
            <span className="text-6xl">🎉</span>
            <p className="text-white font-bold text-lg">No classes today!</p>
            <p className="text-indigo-500 text-sm">Enjoy your day off</p>
          </motion.div>
        ) : (
          <div className="flex flex-col gap-4">
            {/* Timeline */}
            <div className="relative">
              <div className="absolute left-5 top-0 bottom-0 w-0.5 bg-gradient-to-b from-indigo-600 to-transparent opacity-30" />
              {filtered.map((cls, i) => {
                const badge = typeBadge[cls.type] ?? typeBadge.lecture;
                return (
                  <motion.div
                    key={cls.id}
                    className="flex gap-4 mb-4"
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: i * 0.1 }}
                  >
                    {/* Timeline dot */}
                    <div className="flex flex-col items-center shrink-0 pt-4">
                      <div className="w-3 h-3 rounded-full ring-2 ring-indigo-600 z-10"
                        style={{ background: cls.color }} />
                    </div>

                    {/* Card */}
                    <div
                      className="flex-1 rounded-3xl p-4 relative overflow-hidden"
                      style={{
                        background: 'rgba(255,255,255,0.04)',
                        border: `1px solid ${cls.color}30`,
                        borderLeft: `3px solid ${cls.color}`,
                      }}
                    >
                      <div className="absolute top-0 right-0 w-24 h-24 rounded-full blur-2xl opacity-10"
                        style={{ background: cls.color }} />

                      <div className="flex items-start justify-between mb-2">
                        <div>
                          <h4 className="text-white font-bold text-sm leading-tight">{cls.subject}</h4>
                          <p className="text-indigo-500 text-xs">{cls.code}</p>
                        </div>
                        <span className="text-xs px-2.5 py-1 rounded-full font-semibold capitalize"
                          style={{ background: badge.bg, color: badge.color }}>
                          {cls.type}
                        </span>
                      </div>

                      <div className="flex flex-col gap-1.5 mt-3">
                        <div className="flex items-center gap-2">
                          <Clock size={12} className="text-indigo-500" />
                          <span className="text-indigo-300 text-xs">{cls.time}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <MapPin size={12} className="text-indigo-500" />
                          <span className="text-indigo-300 text-xs">{cls.room}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <User size={12} className="text-indigo-500" />
                          <span className="text-indigo-300 text-xs">{cls.lecturer}</span>
                        </div>
                      </div>
                    </div>
                  </motion.div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default ScheduleScreen;
