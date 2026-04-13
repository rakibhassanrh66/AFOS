import React, { createContext, useContext, useState, useCallback } from 'react';
import type { User, AuthState } from '../types';
import { authService } from '../services/mockBackend';

interface AuthContextType extends AuthState {
  login: (email: string, password: string, role: 'student' | 'admin') => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, setState] = useState<AuthState>({
    user: null,
    isAuthenticated: false,
    isLoading: false,
    error: null,
  });

  const login = useCallback(async (email: string, password: string, role: 'student' | 'admin') => {
    setState((s) => ({ ...s, isLoading: true, error: null }));
    try {
      const user: User = await authService.login(email, password, role);
      setState({ user, isAuthenticated: true, isLoading: false, error: null });
    } catch (err: unknown) {
      setState((s) => ({
        ...s,
        isLoading: false,
        error: err instanceof Error ? err.message : 'Login failed',
      }));
      throw err;
    }
  }, []);

  const logout = useCallback(() => {
    setState({ user: null, isAuthenticated: false, isLoading: false, error: null });
  }, []);

  return (
    <AuthContext.Provider value={{ ...state, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};
