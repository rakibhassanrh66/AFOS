import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowLeft, ShoppingCart, Plus, Trash2, CheckCircle, Package } from 'lucide-react';
import { cartService } from '../services/mockBackend';
import type { CartItem } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

interface Props { onBack: () => void }

const STORE_ITEMS = [
  { name: 'Spiral Notebook A4', price: 4.50, category: 'Stationery', emoji: '📓' },
  { name: 'Mechanical Pencil Set', price: 12.00, category: 'Stationery', emoji: '✏️' },
  { name: 'Campus Meal Set', price: 8.50, category: 'Food', emoji: '🍱' },
  { name: 'Energy Drink', price: 3.00, category: 'Food', emoji: '⚡' },
  { name: 'USB-C Hub 7-in-1', price: 45.00, category: 'Tech', emoji: '🔌' },
  { name: 'Wireless Mouse', price: 35.00, category: 'Tech', emoji: '🖱️' },
  { name: 'Print Credit (10 pages)', price: 2.00, category: 'Services', emoji: '🖨️' },
  { name: 'Locker Rental (1 month)', price: 15.00, category: 'Services', emoji: '🔒' },
];

const CATEGORIES = ['All', 'Stationery', 'Food', 'Tech', 'Services'];

const CartScreen: React.FC<Props> = ({ onBack }) => {
  const [cart, setCart] = useState<CartItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'store' | 'cart'>('store');
  const [catFilter, setCatFilter] = useState('All');
  const [adding, setAdding] = useState<string | null>(null);
  const [removing, setRemoving] = useState<string | null>(null);
  const [ordered, setOrdered] = useState(false);
  const [ordering, setOrdering] = useState(false);

  useEffect(() => {
    cartService.getCart().then((c) => { setCart(c); setLoading(false); });
  }, []);

  const addItem = async (item: (typeof STORE_ITEMS)[0]) => {
    setAdding(item.name);
    const newItem = await cartService.addItem({ name: item.name, price: item.price, quantity: 1, category: item.category });
    setCart(await cartService.getCart());
    setAdding(null);
    // switch to cart tab
    setTab('cart');
    void newItem;
  };

  const removeItem = async (id: string) => {
    setRemoving(id);
    await cartService.removeItem(id);
    setCart(await cartService.getCart());
    setRemoving(null);
  };

  const placeOrder = async () => {
    setOrdering(true);
    await cartService.clearCart();
    setCart([]);
    setOrdering(false);
    setOrdered(true);
    setTimeout(() => setOrdered(false), 4000);
  };

  const filteredStore = STORE_ITEMS.filter((s) => catFilter === 'All' || s.category === catFilter);
  const total = cart.reduce((a, c) => a + c.price * c.quantity, 0);
  const cartCount = cart.reduce((a, c) => a + c.quantity, 0);

  return (
    <div className="w-full min-h-full flex flex-col" style={{ background: '#0f0f1a' }}>
      {/* Header */}
      <div className="px-5 pt-5 pb-5 relative overflow-hidden"
        style={{ background: 'linear-gradient(135deg, #1a0f2e, #2e1a4b)' }}>
        <div className="absolute top-0 right-0 w-40 h-40 rounded-full bg-violet-600/10 blur-3xl" />
        <div className="flex items-center gap-3 mb-4">
          <motion.button whileTap={{ scale: 0.92 }} onClick={onBack}
            className="w-10 h-10 rounded-2xl flex items-center justify-center"
            style={{ background: 'rgba(255,255,255,0.08)' }}>
            <ArrowLeft size={20} className="text-white" />
          </motion.button>
          <div>
            <h2 className="text-white font-bold text-xl">Campus Store</h2>
            <p className="text-purple-400/70 text-xs">Order & collect on campus</p>
          </div>
          <motion.button
            whileTap={{ scale: 0.92 }}
            onClick={() => setTab('cart')}
            className="ml-auto w-10 h-10 rounded-2xl flex items-center justify-center relative"
            style={{ background: 'rgba(139,92,246,0.2)', border: '1px solid rgba(139,92,246,0.3)' }}
          >
            <ShoppingCart size={20} className="text-purple-400" />
            {cartCount > 0 && (
              <span className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-red-500 text-white text-xs flex items-center justify-center font-bold">
                {cartCount}
              </span>
            )}
          </motion.button>
        </div>

        {/* Tabs */}
        <div className="flex gap-2">
          {(['store', 'cart'] as const).map((t) => (
            <motion.button
              key={t}
              whileTap={{ scale: 0.97 }}
              onClick={() => setTab(t)}
              className="flex-1 py-2.5 rounded-2xl text-sm font-bold capitalize transition-all"
              style={{
                background: tab === t ? 'linear-gradient(135deg, #7c3aed, #8b5cf6)' : 'rgba(255,255,255,0.06)',
                color: tab === t ? 'white' : '#a78bfa',
                boxShadow: tab === t ? '0 4px 16px rgba(124,58,237,0.4)' : 'none',
              }}
            >
              {t === 'cart' ? `Cart (${cartCount})` : 'Browse Store'}
            </motion.button>
          ))}
        </div>
      </div>

      {/* Order success */}
      <AnimatePresence>
        {ordered && (
          <motion.div
            initial={{ opacity: 0, y: -15, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="mx-5 mt-4 flex items-center gap-3 px-4 py-4 rounded-2xl"
            style={{ background: 'rgba(139,92,246,0.2)', border: '1px solid rgba(139,92,246,0.4)' }}
          >
            <CheckCircle size={22} className="text-purple-400 shrink-0" />
            <div>
              <p className="text-white font-bold text-sm">Order Placed! 🎉</p>
              <p className="text-purple-300 text-xs mt-0.5">Collect at Campus Store Kiosk within 2 hours</p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <div className="flex-1 overflow-y-auto">
        {/* Store tab */}
        {tab === 'store' && (
          <div className="px-5 py-5">
            {/* Category filter */}
            <div className="flex gap-2 overflow-x-auto pb-2 scrollbar-hide mb-4">
              {CATEGORIES.map((c) => (
                <motion.button
                  key={c}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => setCatFilter(c)}
                  className="px-3 py-1.5 rounded-xl text-xs font-semibold shrink-0 transition-all"
                  style={{
                    background: catFilter === c ? 'rgba(139,92,246,0.3)' : 'rgba(255,255,255,0.05)',
                    color: catFilter === c ? '#c4b5fd' : '#7c3aed',
                    border: `1px solid ${catFilter === c ? 'rgba(139,92,246,0.5)' : 'transparent'}`,
                  }}
                >
                  {c}
                </motion.button>
              ))}
            </div>

            <div className="grid grid-cols-2 gap-3">
              {filteredStore.map((item, i) => {
                const isAdding = adding === item.name;
                const inCart = cart.some((c) => c.name === item.name);
                return (
                  <motion.div
                    key={item.name}
                    className="flex flex-col p-4 rounded-3xl relative overflow-hidden"
                    style={{
                      background: inCart ? 'rgba(139,92,246,0.08)' : 'rgba(255,255,255,0.04)',
                      border: `1px solid ${inCart ? 'rgba(139,92,246,0.3)' : 'rgba(255,255,255,0.07)'}`,
                    }}
                    initial={{ opacity: 0, y: 15 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: i * 0.06 }}
                  >
                    <span className="text-3xl mb-2">{item.emoji}</span>
                    <p className="text-white font-bold text-xs leading-tight">{item.name}</p>
                    <p className="text-purple-500 text-xs mt-0.5">{item.category}</p>
                    <p className="text-white font-black text-base mt-2">RM {item.price.toFixed(2)}</p>
                    <motion.button
                      whileTap={{ scale: 0.95 }}
                      onClick={() => addItem(item)}
                      disabled={isAdding}
                      className="mt-3 w-full py-2 rounded-xl text-xs font-bold flex items-center justify-center gap-1.5"
                      style={{
                        background: inCart
                          ? 'rgba(139,92,246,0.3)'
                          : 'linear-gradient(135deg, #7c3aed, #8b5cf6)',
                        color: 'white',
                        opacity: isAdding ? 0.7 : 1,
                        boxShadow: !inCart ? '0 4px 12px rgba(124,58,237,0.3)' : 'none',
                      }}
                    >
                      {isAdding ? <LoadingSpinner size="sm" color="white" /> : (
                        <><Plus size={12} />{inCart ? 'Add Again' : 'Add to Cart'}</>
                      )}
                    </motion.button>
                  </motion.div>
                );
              })}
            </div>
          </div>
        )}

        {/* Cart tab */}
        {tab === 'cart' && (
          <div className="px-5 py-5 flex flex-col gap-4">
            {loading ? (
              <div className="flex justify-center pt-16"><LoadingSpinner color="#8b5cf6" /></div>
            ) : cart.length === 0 ? (
              <motion.div
                className="flex flex-col items-center justify-center pt-20 gap-4"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
              >
                <Package size={60} className="text-indigo-700" />
                <p className="text-white font-bold text-lg">Your cart is empty</p>
                <p className="text-indigo-500 text-sm">Browse the store to add items</p>
                <motion.button
                  whileTap={{ scale: 0.97 }}
                  onClick={() => setTab('store')}
                  className="px-6 py-3 rounded-2xl text-sm font-bold text-white mt-2"
                  style={{ background: 'linear-gradient(135deg, #7c3aed, #8b5cf6)' }}
                >
                  Browse Store
                </motion.button>
              </motion.div>
            ) : (
              <>
                {/* Cart items */}
                {cart.map((item, i) => (
                  <motion.div
                    key={item.id}
                    className="flex items-center gap-3 p-4 rounded-3xl"
                    style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)' }}
                    initial={{ opacity: 0, x: -15 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: i * 0.07 }}
                    layout
                  >
                    <div
                      className="w-11 h-11 rounded-2xl flex items-center justify-center shrink-0 text-xl"
                      style={{ background: 'rgba(139,92,246,0.15)' }}
                    >
                      {STORE_ITEMS.find((s) => s.name === item.name)?.emoji ?? '📦'}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-white font-bold text-sm leading-tight truncate">{item.name}</p>
                      <p className="text-purple-400 text-xs mt-0.5">{item.category}</p>
                      <p className="text-white font-black text-sm mt-1">
                        RM {(item.price * item.quantity).toFixed(2)}
                        <span className="text-indigo-500 font-normal text-xs"> (RM {item.price.toFixed(2)} ea.)</span>
                      </p>
                    </div>

                    {/* Qty + remove */}
                    <div className="flex items-center gap-2">
                      <div className="flex items-center gap-2 px-2 py-1 rounded-xl"
                        style={{ background: 'rgba(139,92,246,0.15)' }}>
                        <span className="text-white font-bold text-sm w-5 text-center">{item.quantity}</span>
                      </div>
                      <motion.button
                        whileTap={{ scale: 0.9 }}
                        onClick={() => removeItem(item.id)}
                        disabled={removing === item.id}
                        className="w-8 h-8 rounded-xl flex items-center justify-center"
                        style={{ background: 'rgba(239,68,68,0.15)' }}
                      >
                        {removing === item.id
                          ? <LoadingSpinner size="sm" color="#f87171" />
                          : <Trash2 size={14} className="text-red-400" />
                        }
                      </motion.button>
                    </div>
                  </motion.div>
                ))}

                {/* Order summary */}
                <motion.div
                  className="rounded-3xl p-5"
                  style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(139,92,246,0.2)' }}
                  layout
                >
                  <h3 className="text-white font-bold text-sm mb-3">Order Summary</h3>
                  <div className="flex justify-between mb-1.5">
                    <span className="text-indigo-400 text-sm">Subtotal ({cartCount} items)</span>
                    <span className="text-white font-semibold text-sm">RM {total.toFixed(2)}</span>
                  </div>
                  <div className="flex justify-between mb-1.5">
                    <span className="text-indigo-400 text-sm">Service Fee</span>
                    <span className="text-white font-semibold text-sm">RM 0.50</span>
                  </div>
                  <div className="h-px bg-white/10 my-3" />
                  <div className="flex justify-between">
                    <span className="text-white font-bold">Total</span>
                    <span className="text-purple-400 font-black text-lg">RM {(total + 0.5).toFixed(2)}</span>
                  </div>
                </motion.div>

                {/* Place order */}
                <motion.button
                  whileTap={{ scale: 0.98 }}
                  disabled={ordering}
                  onClick={placeOrder}
                  className="w-full py-4 rounded-3xl font-black text-white text-sm flex items-center justify-center gap-2"
                  style={{
                    background: 'linear-gradient(135deg, #7c3aed, #8b5cf6)',
                    boxShadow: '0 8px 32px rgba(124,58,237,0.4)',
                    opacity: ordering ? 0.8 : 1,
                  }}
                  layout
                >
                  {ordering ? <LoadingSpinner size="sm" color="white" label="Processing..." /> : (
                    <><ShoppingCart size={18} /> Place Order · RM {(total + 0.5).toFixed(2)}</>
                  )}
                </motion.button>

                {/* Add more */}
                <motion.button
                  whileTap={{ scale: 0.97 }}
                  onClick={() => setTab('store')}
                  className="w-full py-3 rounded-2xl text-sm font-semibold text-purple-400"
                  style={{ border: '1px solid rgba(139,92,246,0.25)' }}
                >
                  <Plus size={14} className="inline mr-1" />
                  Add More Items
                </motion.button>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
};

export default CartScreen;
