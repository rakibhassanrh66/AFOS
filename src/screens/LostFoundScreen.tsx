import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { ArrowLeft, MapPin, Plus, Search, Clock } from 'lucide-react';

interface Props { onBack: () => void }

const ITEMS = [
  { id: '1', name: 'Blue Water Bottle', location: 'Library 2F', time: '2h ago', status: 'found', emoji: '🍶', reporter: 'Amirah K.' },
  { id: '2', name: 'Black Laptop Bag', location: 'Cafeteria', time: '5h ago', status: 'lost', emoji: '💼', reporter: 'Farhan A.' },
  { id: '3', name: 'Student ID Card', location: 'LT-3C', time: '1d ago', status: 'found', emoji: '🪪', reporter: 'Security' },
  { id: '4', name: 'Wireless Earbuds', location: 'Sports Complex', time: '2d ago', status: 'lost', emoji: '🎧', reporter: 'Zara M.' },
  { id: '5', name: 'Calculator (Casio)', location: 'Lab-2B', time: '3d ago', status: 'found', emoji: '🔢', reporter: 'Raj P.' },
];

const LostFoundScreen: React.FC<Props> = ({ onBack }) => {
  const [filter, setFilter] = useState<'all' | 'lost' | 'found'>('all');
  const [search, setSearch] = useState('');

  const filtered = ITEMS.filter((item) => {
    const matchFilter = filter === 'all' || item.status === filter;
    const matchSearch = item.name.toLowerCase().includes(search.toLowerCase());
    return matchFilter && matchSearch;
  });

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-5" style={{ background: 'linear-gradient(135deg, #2e0f1a, #1a0020)' }}>
        <div className="flex items-center gap-3 mb-4">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <div>
            <h2 className="text-white font-bold text-xl">Lost & Found</h2>
            <p className="text-pink-400/70 text-xs">Report & recover items</p>
          </div>
          <motion.button
            whileTap={{ scale: 0.92 }}
            className="ml-auto w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(236,72,153,0.2)', border: '1px solid rgba(236,72,153,0.3)' }}
          >
            <Plus size={20} className="text-pink-400" />
          </motion.button>
        </div>

        {/* Search */}
        <div className="flex items-center gap-3 px-4 py-3 rounded-2xl mb-3"
          style={{ background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.08)' }}>
          <Search size={16} className="text-pink-500 shrink-0" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search items..."
            className="bg-transparent text-white text-sm outline-none flex-1 placeholder-pink-900"
          />
        </div>

        {/* Filter */}
        <div className="flex gap-2">
          {(['all', 'lost', 'found'] as const).map((f) => (
            <motion.button
              key={f}
              whileTap={{ scale: 0.95 }}
              onClick={() => setFilter(f)}
              className="flex-1 py-2 rounded-xl text-xs font-bold capitalize transition-all"
              style={{
                background: filter === f
                  ? f === 'lost' ? 'rgba(239,68,68,0.3)' : f === 'found' ? 'rgba(16,185,129,0.3)' : 'rgba(236,72,153,0.3)'
                  : 'rgba(255,255,255,0.06)',
                color: filter === f
                  ? f === 'lost' ? '#f87171' : f === 'found' ? '#34d399' : '#f9a8d4'
                  : '#9ca3af',
                border: `1px solid ${filter === f
                  ? f === 'lost' ? 'rgba(239,68,68,0.4)' : f === 'found' ? 'rgba(16,185,129,0.4)' : 'rgba(236,72,153,0.4)'
                  : 'transparent'}`,
              }}
            >
              {f}
            </motion.button>
          ))}
        </div>
      </div>

      {/* Items */}
      <div className="flex-1 px-5 py-5 flex flex-col gap-3">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center pt-20 gap-3">
            <span className="text-5xl">🔍</span>
            <p className="text-white font-bold">No items found</p>
          </div>
        ) : filtered.map((item, i) => (
          <motion.div
            key={item.id}
            className="flex items-center gap-4 p-4 rounded-3xl"
            style={{
              background: 'rgba(255,255,255,0.04)',
              border: `1px solid ${item.status === 'found' ? 'rgba(16,185,129,0.15)' : 'rgba(239,68,68,0.15)'}`,
            }}
            initial={{ opacity: 0, x: -15 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.08 }}
          >
            <div
              className="w-12 h-12 rounded-2xl flex items-center justify-center text-2xl shrink-0"
              style={{ background: item.status === 'found' ? 'rgba(16,185,129,0.12)' : 'rgba(239,68,68,0.12)' }}
            >
              {item.emoji}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-white font-bold text-sm">{item.name}</p>
              <div className="flex items-center gap-1.5 mt-1">
                <MapPin size={11} className="text-indigo-500" />
                <span className="text-indigo-400 text-xs">{item.location}</span>
              </div>
              <div className="flex items-center gap-1.5 mt-0.5">
                <Clock size={11} className="text-indigo-600" />
                <span className="text-indigo-500 text-xs">{item.time} by {item.reporter}</span>
              </div>
            </div>
            <span
              className="text-xs px-2.5 py-1 rounded-full font-bold shrink-0"
              style={{
                background: item.status === 'found' ? 'rgba(16,185,129,0.2)' : 'rgba(239,68,68,0.2)',
                color: item.status === 'found' ? '#34d399' : '#f87171',
              }}
            >
              {item.status.toUpperCase()}
            </span>
          </motion.div>
        ))}

        {/* Report button */}
        <motion.button
          whileTap={{ scale: 0.98 }}
          className="w-full py-4 rounded-3xl font-bold text-white text-sm flex items-center justify-center gap-2 mt-2"
          style={{
            background: 'linear-gradient(135deg, #be185d, #ec4899)',
            boxShadow: '0 8px 24px rgba(236,72,153,0.3)',
          }}
        >
          <Plus size={18} />
          Report Lost / Found Item
        </motion.button>
      </div>
    </div>
  );
};

export default LostFoundScreen;
