import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowLeft, BookOpen, Search, CheckCircle, X } from 'lucide-react';
import { libraryService } from '../services/mockBackend';
import type { LibraryBook } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

interface Props { onBack: () => void }

const CATEGORIES = ['All', 'Computer Science', 'Software Engineering', 'Databases', 'Networking'];

const LibraryScreen: React.FC<Props> = ({ onBack }) => {
  const [books, setBooks] = useState<LibraryBook[]>([]);
  const [loading, setLoading] = useState(true);
  const [category, setCategory] = useState('All');
  const [search, setSearch] = useState('');
  const [borrowing, setBorrowing] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  useEffect(() => {
    libraryService.getBooks().then((b) => { setBooks(b); setLoading(false); });
  }, []);

  const filtered = books.filter((b) => {
    const matchCat = category === 'All' || b.category === category;
    const matchSearch = b.title.toLowerCase().includes(search.toLowerCase())
      || b.author.toLowerCase().includes(search.toLowerCase());
    return matchCat && matchSearch;
  });

  const handleBorrow = async (id: string) => {
    setBorrowing(id);
    try {
      const updated = await libraryService.borrowBook(id);
      setBooks((prev) => prev.map((b) => (b.id === id ? updated : b)));
      setToast('Book borrowed! Due in 14 days.');
      setTimeout(() => setToast(null), 3000);
    } catch (e: unknown) {
      setToast(e instanceof Error ? e.message : 'Error');
      setTimeout(() => setToast(null), 2000);
    } finally {
      setBorrowing(null);
    }
  };

  const available = books.filter((b) => b.available).length;

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-5" style={{ background: 'linear-gradient(135deg, #0a1e2e, #0d1b3e)' }}>
        <div className="flex items-center gap-3 mb-4">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <div>
            <h2 className="text-white font-bold text-xl">Library</h2>
            <p className="text-cyan-400/70 text-xs">{available} books available</p>
          </div>
          <div className="ml-auto w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(6,182,212,0.15)' }}>
            <BookOpen size={20} className="text-cyan-400" />
          </div>
        </div>

        {/* Search */}
        <div className="flex items-center gap-3 px-4 py-3 rounded-2xl mb-4"
          style={{ background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.08)' }}>
          <Search size={16} className="text-cyan-500 shrink-0" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search books or authors..."
            className="bg-transparent text-white text-sm outline-none flex-1 placeholder-indigo-600"
          />
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
                background: category === c ? 'linear-gradient(135deg, #0891b2, #06b6d4)' : 'rgba(255,255,255,0.06)',
                color: category === c ? 'white' : '#67e8f9',
                boxShadow: category === c ? '0 4px 12px rgba(6,182,212,0.3)' : 'none',
              }}
            >
              {c}
            </motion.button>
          ))}
        </div>
      </div>

      {/* Toast */}
      <AnimatePresence>
        {toast && (
          <motion.div
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            className="mx-5 mt-3 flex items-center gap-3 px-4 py-3 rounded-2xl"
            style={{ background: 'rgba(6,182,212,0.2)', border: '1px solid rgba(6,182,212,0.3)' }}
          >
            <CheckCircle size={16} className="text-cyan-400 shrink-0" />
            <p className="text-cyan-300 text-sm flex-1">{toast}</p>
            <button onClick={() => setToast(null)} title="Close notification"><X size={14} className="text-cyan-500" /></button>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Books grid */}
      <div className="flex-1 px-5 py-5">
        {loading ? (
          <div className="flex justify-center pt-16"><LoadingSpinner label="Loading books..." color="#06b6d4" /></div>
        ) : (
          <div className="flex flex-col gap-4">
            <p className="text-indigo-500 text-xs">{filtered.length} results</p>
            {filtered.map((book, i) => (
              <motion.div
                key={book.id}
                className="flex gap-4 p-4 rounded-3xl"
                style={{
                  background: 'rgba(255,255,255,0.04)',
                  border: `1px solid ${book.available ? 'rgba(6,182,212,0.15)' : 'rgba(255,255,255,0.06)'}`,
                }}
                initial={{ opacity: 0, x: -15 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: i * 0.07 }}
              >
                {/* Book cover */}
                <div
                  className="w-14 h-20 rounded-2xl flex items-center justify-center shrink-0 relative overflow-hidden"
                  style={{ background: book.coverColor }}
                >
                  <div className="absolute inset-0 opacity-20 bg-gradient-to-br from-white to-transparent" />
                  <BookOpen size={20} className="text-white relative z-10" />
                  {!book.available && (
                    <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
                      <span className="text-white text-xs font-bold rotate-[-20deg]">Out</span>
                    </div>
                  )}
                </div>

                {/* Info */}
                <div className="flex-1 min-w-0">
                  <h4 className="text-white font-bold text-sm leading-tight">{book.title}</h4>
                  <p className="text-indigo-400 text-xs mt-0.5">{book.author}</p>
                  <span className="inline-block mt-1.5 text-xs px-2 py-0.5 rounded-lg font-medium"
                    style={{ background: 'rgba(6,182,212,0.1)', color: '#67e8f9' }}>
                    {book.category}
                  </span>

                  {book.dueDate && (
                    <p className="text-amber-400 text-xs mt-1.5">Due: {book.dueDate}</p>
                  )}

                  <motion.button
                    whileTap={{ scale: 0.97 }}
                    disabled={!book.available || borrowing === book.id}
                    onClick={() => book.available && handleBorrow(book.id)}
                    className="mt-2.5 px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5"
                    style={{
                      background: book.available
                        ? 'linear-gradient(135deg, #0891b2, #06b6d4)'
                        : 'rgba(255,255,255,0.05)',
                      color: book.available ? 'white' : '#4b5563',
                      opacity: borrowing === book.id ? 0.7 : 1,
                      cursor: book.available ? 'pointer' : 'default',
                    }}
                  >
                    {borrowing === book.id ? (
                      <LoadingSpinner size="sm" color="white" />
                    ) : book.available ? (
                      <><BookOpen size={12} /> Borrow</>
                    ) : (
                      'Unavailable'
                    )}
                  </motion.button>
                </div>
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default LibraryScreen;
