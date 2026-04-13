import React, { useState, useCallback } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { AuthProvider, useAuth } from './context/AuthContext';
import PhoneFrame from './components/PhoneFrame';
import SplashScreen from './screens/SplashScreen';
import LoginScreen from './screens/LoginScreen';
import DashboardScreen from './screens/DashboardScreen';
import ScheduleScreen from './screens/ScheduleScreen';
import TransportScreen from './screens/TransportScreen';
import PaymentScreen from './screens/PaymentScreen';
import LibraryScreen from './screens/LibraryScreen';
import CartScreen from './screens/CartScreen';
import LostFoundScreen from './screens/LostFoundScreen';
import ClubsScreen from './screens/ClubsScreen';
import SettingsScreen from './screens/SettingsScreen';
import Drawer from './components/Drawer';

type AppScreen = 'splash' | 'login' | 'dashboard' | 'schedule' | 'transport' | 'payment' | 'library' | 'lostfound' | 'clubs' | 'settings' | 'cart';

// ─── Inner app (requires auth context) ────────────────────────────────────────
const AppInner: React.FC = () => {
  const { isAuthenticated } = useAuth();
  const [screen, setScreen] = useState<AppScreen>('splash');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [prevScreen, setPrevScreen] = useState<AppScreen>('dashboard');

  const navigate = useCallback((s: AppScreen) => {
    setPrevScreen(screen);
    setScreen(s);
  }, [screen]);

  const handleSplashFinish = useCallback(() => {
    setScreen('login');
  }, []);

  // Auto redirect after auth
  React.useEffect(() => {
    if (isAuthenticated && screen === 'login') {
      setScreen('dashboard');
    }
    if (!isAuthenticated && screen !== 'splash' && screen !== 'login') {
      setScreen('login');
    }
  }, [isAuthenticated, screen]);

  // Which screen renders inside the phone
  const renderScreen = () => {
    switch (screen) {
      case 'splash':
        return <SplashScreen onFinish={handleSplashFinish} />;
      case 'login':
        return <LoginScreen />;
      case 'dashboard':
        return (
          <DashboardScreen
            onOpenDrawer={() => setDrawerOpen(true)}
            onNavigate={(s) => navigate(s as AppScreen)}
          />
        );
      case 'schedule':
        return <ScheduleScreen onBack={() => navigate('dashboard')} />;
      case 'transport':
        return <TransportScreen onBack={() => navigate('dashboard')} />;
      case 'payment':
        return <PaymentScreen onBack={() => navigate('dashboard')} />;
      case 'library':
        return <LibraryScreen onBack={() => navigate('dashboard')} />;
      case 'cart':
        return <CartScreen onBack={() => navigate('dashboard')} />;
      case 'lostfound':
        return <LostFoundScreen onBack={() => navigate('dashboard')} />;
      case 'clubs':
        return <ClubsScreen onBack={() => navigate('dashboard')} />;
      case 'settings':
        return <SettingsScreen onBack={() => navigate('dashboard')} />;
      default:
        return null;
    }
  };

  const isBack = ['schedule', 'transport', 'payment', 'library', 'cart', 'lostfound', 'clubs', 'settings'].includes(screen);
  void prevScreen;

  return (
    <PhoneFrame>
      {/* Drawer (only when authenticated) */}
      {isAuthenticated && (
        <Drawer
          open={drawerOpen}
          onClose={() => setDrawerOpen(false)}
          onNavigate={(s) => navigate(s as AppScreen)}
          current={screen as Parameters<typeof Drawer>[0]['current']}
        />
      )}

      {/* Screen transition */}
      <AnimatePresence mode="wait">
        <motion.div
          key={screen}
          className="w-full h-full"
          initial={{ opacity: 0, x: isBack ? 30 : 0, y: isBack ? 0 : 10 }}
          animate={{ opacity: 1, x: 0, y: 0 }}
          exit={{ opacity: 0, x: isBack ? -30 : 0, y: isBack ? 0 : -10 }}
          transition={{ duration: 0.28, ease: [0.4, 0, 0.2, 1] }}
          style={{ position: 'absolute', inset: 0, overflowY: 'auto' }}
        >
          {renderScreen()}
        </motion.div>
      </AnimatePresence>
    </PhoneFrame>
  );
};

// ─── Root with info panel ──────────────────────────────────────────────────────
const App: React.FC = () => {
  return (
    <AuthProvider>
      <div className="relative">
        <AppInner />
        {/* Info overlay in corners */}
        <InfoBadge />
      </div>
    </AuthProvider>
  );
};

// ─── Info badge for demo context ──────────────────────────────────────────────
const InfoBadge: React.FC = () => {
  const [show, setShow] = useState(false);
  return (
    <>
      <motion.button
        className="fixed bottom-6 right-6 z-[100] w-12 h-12 rounded-full flex items-center justify-center text-lg shadow-2xl"
        style={{ background: 'linear-gradient(135deg, #6366f1, #8b5cf6)' }}
        whileTap={{ scale: 0.95 }}
        onClick={() => setShow(!show)}
        animate={{ rotate: show ? 45 : 0 }}
      >
        {show ? '✕' : 'ℹ'}
      </motion.button>

      <AnimatePresence>
        {show && (
          <motion.div
            className="fixed bottom-20 right-6 z-[100] w-72 rounded-3xl p-5 shadow-2xl"
            style={{
              background: 'linear-gradient(135deg, #0f0f2e, #1a1040)',
              border: '1px solid rgba(99,102,241,0.3)',
              boxShadow: '0 20px 60px rgba(0,0,0,0.8)',
            }}
            initial={{ opacity: 0, y: 20, scale: 0.9 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 20, scale: 0.9 }}
          >
            <div className="flex items-center gap-2 mb-3">
              <img src="/afos-logo.png" alt="AFOS" className="w-8 h-8 rounded-xl" />
              <span className="text-white font-black text-lg tracking-widest">AFOS</span>
              <span className="text-indigo-500 text-xs ml-auto">Demo v2.4</span>
            </div>
            <p className="text-indigo-200 text-xs font-semibold mb-3 leading-relaxed">
              All Facilities One System — Smart Campus Platform
            </p>
            <div className="flex flex-col gap-2">
              <div className="p-3 rounded-2xl" style={{ background: 'rgba(99,102,241,0.12)' }}>
                <p className="text-indigo-300 text-xs font-bold mb-1.5">🎓 Student Login</p>
                <p className="text-indigo-400 text-xs">Email: ahmad.farhan@campus.edu</p>
                <p className="text-indigo-400 text-xs">Pass: student123</p>
              </div>
              <div className="p-3 rounded-2xl" style={{ background: 'rgba(245,158,11,0.1)' }}>
                <p className="text-amber-300 text-xs font-bold mb-1.5">🛡️ Admin Login</p>
                <p className="text-amber-400 text-xs">Email: sarah.lim@campus.edu</p>
                <p className="text-amber-400 text-xs">Pass: admin123</p>
              </div>
            </div>
            <p className="text-indigo-700 text-xs text-center mt-3">
              Tap "Quick Demo" buttons in login screen
            </p>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
};

export default App;
