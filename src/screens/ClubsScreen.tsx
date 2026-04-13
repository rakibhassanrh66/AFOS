import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { ArrowLeft, Users, Calendar, ChevronRight, Star } from 'lucide-react';

interface Props { onBack: () => void }

const CLUBS = [
  { id: '1', name: 'Computer Science Society', members: 234, category: 'Academic', emoji: '💻', color: '#6366f1', nextEvent: 'Hackathon 2024', eventDate: 'Mar 15', joined: true },
  { id: '2', name: 'Photography Club', members: 89, category: 'Arts', emoji: '📷', color: '#ec4899', nextEvent: 'Campus Shoot', eventDate: 'Mar 20', joined: false },
  { id: '3', name: 'Debate Society', members: 56, category: 'Academic', emoji: '🎙️', color: '#f59e0b', nextEvent: 'Inter-U Debate', eventDate: 'Apr 2', joined: false },
  { id: '4', name: 'Futsal Club', members: 145, category: 'Sports', emoji: '⚽', color: '#10b981', nextEvent: 'Training Session', eventDate: 'Mar 14', joined: true },
  { id: '5', name: 'Robotics Club', members: 67, category: 'Tech', emoji: '🤖', color: '#06b6d4', nextEvent: 'Bot Battle', eventDate: 'Apr 10', joined: false },
  { id: '6', name: 'Music Society', members: 112, category: 'Arts', emoji: '🎵', color: '#8b5cf6', nextEvent: 'Live Concert', eventDate: 'Mar 28', joined: false },
];

const CATEGORIES = ['All', 'Academic', 'Arts', 'Sports', 'Tech'];

const ClubsScreen: React.FC<Props> = ({ onBack }) => {
  const [category, setCategory] = useState('All');
  const [joined, setJoined] = useState<string[]>(['1', '4']);

  const filtered = CLUBS.filter((c) => category === 'All' || c.category === category);

  const toggleJoin = (id: string) => {
    setJoined((prev) => prev.includes(id) ? prev.filter((j) => j !== id) : [...prev, id]);
  };

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-5" style={{ background: 'linear-gradient(135deg, #0f1a0a, #1a2e0f)' }}>
        <div className="flex items-center gap-3 mb-4">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <div>
            <h2 className="text-white font-bold text-xl">Campus Clubs</h2>
            <p className="text-lime-400/70 text-xs">{CLUBS.length} clubs · {joined.length} joined</p>
          </div>
          <div className="ml-auto flex items-center gap-1 px-3 py-1.5 rounded-xl"
            style={{ background: 'rgba(132,204,22,0.15)' }}>
            <Star size={12} className="text-lime-400" />
            <span className="text-lime-400 text-xs font-semibold">{joined.length} Joined</span>
          </div>
        </div>

        {/* Category tabs */}
        <div className="flex gap-2 overflow-x-auto pb-1 scrollbar-hide">
          {CATEGORIES.map((c) => (
            <motion.button
              key={c}
              whileTap={{ scale: 0.95 }}
              onClick={() => setCategory(c)}
              className="px-3 py-2 rounded-xl text-xs font-semibold shrink-0 transition-all"
              style={{
                background: category === c ? 'rgba(132,204,22,0.25)' : 'rgba(255,255,255,0.06)',
                color: category === c ? '#bef264' : '#84cc16',
                border: `1px solid ${category === c ? 'rgba(132,204,22,0.4)' : 'transparent'}`,
              }}
            >
              {c}
            </motion.button>
          ))}
        </div>
      </div>

      {/* Clubs list */}
      <div className="flex-1 px-5 py-5 flex flex-col gap-3">
        {filtered.map((club, i) => {
          const isJoined = joined.includes(club.id);
          return (
            <motion.div
              key={club.id}
              className="p-4 rounded-3xl"
              style={{
                background: 'rgba(255,255,255,0.04)',
                border: `1px solid ${isJoined ? `${club.color}30` : 'rgba(255,255,255,0.07)'}`,
              }}
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.07 }}
            >
              <div className="flex items-start gap-3">
                <div
                  className="w-12 h-12 rounded-2xl flex items-center justify-center text-2xl shrink-0"
                  style={{ background: `${club.color}20` }}
                >
                  {club.emoji}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-white font-bold text-sm leading-tight truncate flex-1">{club.name}</p>
                    {isJoined && <Star size={12} className="text-yellow-400 fill-yellow-400 shrink-0" />}
                  </div>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-xs px-2 py-0.5 rounded-lg font-medium"
                      style={{ background: `${club.color}15`, color: club.color }}>
                      {club.category}
                    </span>
                    <div className="flex items-center gap-1">
                      <Users size={11} className="text-indigo-500" />
                      <span className="text-indigo-400 text-xs">{club.members}</span>
                    </div>
                  </div>

                  {/* Next event */}
                  <div className="flex items-center gap-2 mt-2 px-3 py-2 rounded-xl"
                    style={{ background: 'rgba(255,255,255,0.04)' }}>
                    <Calendar size={12} style={{ color: club.color }} />
                    <span className="text-indigo-300 text-xs flex-1">{club.nextEvent}</span>
                    <span className="text-xs font-semibold" style={{ color: club.color }}>{club.eventDate}</span>
                    <ChevronRight size={12} className="text-indigo-600" />
                  </div>
                </div>
              </div>

              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={() => toggleJoin(club.id)}
                className="w-full mt-3 py-2.5 rounded-2xl text-xs font-bold transition-all"
                style={{
                  background: isJoined
                    ? 'rgba(255,255,255,0.06)'
                    : `linear-gradient(135deg, ${club.color}cc, ${club.color})`,
                  color: isJoined ? '#9ca3af' : 'white',
                  border: isJoined ? '1px solid rgba(255,255,255,0.1)' : 'none',
                  boxShadow: !isJoined ? `0 4px 12px ${club.color}40` : 'none',
                }}
              >
                {isJoined ? '✓ Joined — Click to Leave' : `Join ${club.name.split(' ')[0]} Club`}
              </motion.button>
            </motion.div>
          );
        })}
        <div className="h-4" />
      </div>
    </div>
  );
};

export default ClubsScreen;
