import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowLeft, CreditCard, CheckCircle, Clock, AlertTriangle, X } from 'lucide-react';
import { paymentService } from '../services/mockBackend';
import type { Payment } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

interface Props { onBack: () => void }

const statusConfig: Record<string, { icon: React.ElementType; bg: string; color: string; label: string }> = {
  paid: { icon: CheckCircle, bg: 'rgba(16,185,129,0.15)', color: '#34d399', label: 'Paid' },
  pending: { icon: Clock, bg: 'rgba(245,158,11,0.15)', color: '#fbbf24', label: 'Pending' },
  overdue: { icon: AlertTriangle, bg: 'rgba(239,68,68,0.15)', color: '#f87171', label: 'Overdue' },
};

const PaymentScreen: React.FC<Props> = ({ onBack }) => {
  const [payments, setPayments] = useState<Payment[]>([]);
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  useEffect(() => {
    paymentService.getPayments().then((p) => { setPayments(p); setLoading(false); });
  }, []);

  const handlePay = async (id: string) => {
    setPaying(id);
    try {
      const updated = await paymentService.makePayment(id);
      setPayments((prev) => prev.map((p) => (p.id === id ? updated : p)));
      setSuccess(id);
      setTimeout(() => setSuccess(null), 3000);
    } finally {
      setPaying(null);
    }
  };

  const total = payments.filter((p) => p.status !== 'paid').reduce((a, p) => a + p.amount, 0);
  const paid = payments.filter((p) => p.status === 'paid').reduce((a, p) => a + p.amount, 0);

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-6 relative overflow-hidden"
        style={{ background: 'linear-gradient(135deg, #2e1a0f, #1a0f00)' }}>
        <div className="absolute top-0 right-0 w-40 h-40 rounded-full bg-amber-600/10 blur-3xl" />
        <div className="flex items-center gap-3 mb-5">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <div>
            <h2 className="text-white font-bold text-xl">Payments</h2>
            <p className="text-amber-400/70 text-xs">Financial Overview</p>
          </div>
        </div>

        {/* Summary card */}
        <motion.div
          className="rounded-3xl p-5 relative overflow-hidden"
          style={{
            background: 'linear-gradient(135deg, #d97706, #f59e0b)',
            boxShadow: '0 8px 32px rgba(245,158,11,0.35)',
          }}
          initial={{ opacity: 0, y: 15 }}
          animate={{ opacity: 1, y: 0 }}
        >
          <div className="absolute top-0 right-0 w-32 h-32 rounded-full bg-white/10 blur-2xl" />
          <p className="text-amber-100 text-xs font-semibold uppercase tracking-widest">Total Outstanding</p>
          <p className="text-white text-4xl font-black mt-1">RM {total.toFixed(2)}</p>
          <div className="flex items-center justify-between mt-4">
            <div>
              <p className="text-amber-200 text-xs">Total Paid</p>
              <p className="text-white font-bold text-sm">RM {paid.toFixed(2)}</p>
            </div>
            <div
              className="px-4 py-2 rounded-2xl"
              style={{ background: 'rgba(255,255,255,0.2)' }}
            >
              <CreditCard size={20} className="text-white" />
            </div>
          </div>
        </motion.div>
      </div>

      {/* Success toast */}
      <AnimatePresence>
        {success && (
          <motion.div
            initial={{ opacity: 0, y: -20, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -20, scale: 0.95 }}
            className="mx-5 mt-4 flex items-center gap-3 px-4 py-3.5 rounded-2xl"
            style={{ background: 'rgba(16,185,129,0.2)', border: '1px solid rgba(16,185,129,0.4)' }}
          >
            <CheckCircle size={20} className="text-emerald-400 shrink-0" />
            <p className="text-emerald-300 text-sm font-semibold">Payment successful! Receipt sent to your email.</p>
            <button onClick={() => setSuccess(null)} className="ml-auto">
              <X size={16} className="text-emerald-500" />
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      {/* List */}
      <div className="flex-1 px-5 py-5">
        {loading ? (
          <div className="flex justify-center pt-16"><LoadingSpinner label="Loading payments..." color="#f59e0b" /></div>
        ) : (
          <div className="flex flex-col gap-4">
            <h3 className="text-white font-bold text-base">All Transactions</h3>
            {payments.map((p, i) => {
              const cfg = statusConfig[p.status];
              const Icon = cfg.icon;
              const isPaying = paying === p.id;
              return (
                <motion.div
                  key={p.id}
                  className="rounded-3xl p-4 relative overflow-hidden"
                  style={{
                    background: 'rgba(255,255,255,0.04)',
                    border: `1px solid ${p.status === 'overdue' ? 'rgba(239,68,68,0.2)' : 'rgba(255,255,255,0.07)'}`,
                  }}
                  initial={{ opacity: 0, y: 15 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: i * 0.08 }}
                >
                  <div className="flex items-start gap-3">
                    <div className="w-11 h-11 rounded-2xl flex items-center justify-center shrink-0"
                      style={{ background: cfg.bg }}>
                      <Icon size={20} style={{ color: cfg.color }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-white font-bold text-sm leading-tight truncate">{p.title}</p>
                      <p className="text-indigo-500 text-xs mt-0.5">{p.type} · Due {p.dueDate}</p>
                      {p.receiptNo && (
                        <p className="text-indigo-600 text-xs mt-0.5">{p.receiptNo}</p>
                      )}
                    </div>
                    <div className="text-right shrink-0">
                      <p className="text-white font-black text-base">RM {p.amount.toFixed(2)}</p>
                      <span className="text-xs px-2 py-0.5 rounded-full font-semibold"
                        style={{ background: cfg.bg, color: cfg.color }}>{cfg.label}</span>
                    </div>
                  </div>

                  {p.status !== 'paid' && (
                    <motion.button
                      whileTap={{ scale: 0.97 }}
                      disabled={isPaying}
                      onClick={() => handlePay(p.id)}
                      className="w-full mt-4 py-3 rounded-2xl text-sm font-bold text-white flex items-center justify-center gap-2"
                      style={{
                        background: p.status === 'overdue'
                          ? 'linear-gradient(135deg, #dc2626, #ef4444)'
                          : 'linear-gradient(135deg, #d97706, #f59e0b)',
                        boxShadow: `0 4px 16px ${p.status === 'overdue' ? 'rgba(239,68,68,0.3)' : 'rgba(245,158,11,0.3)'}`,
                        opacity: isPaying ? 0.7 : 1,
                      }}
                    >
                      {isPaying ? <LoadingSpinner size="sm" color="white" /> : (
                        <>
                          <CreditCard size={16} />
                          {p.status === 'overdue' ? 'Pay Now (Overdue!)' : 'Pay Now'}
                        </>
                      )}
                    </motion.button>
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

export default PaymentScreen;
