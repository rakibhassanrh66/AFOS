export type UserRole = 'student' | 'admin';

export interface User {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  studentId?: string;
  department?: string;
  avatar?: string;
  year?: string;
}

export interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
}

export interface ClassSchedule {
  id: string;
  subject: string;
  code: string;
  room: string;
  time: string;
  day: string;
  lecturer: string;
  type: 'lecture' | 'lab' | 'tutorial';
  color: string;
}

export interface TransportRoute {
  id: string;
  name: string;
  route: string;
  departureTime: string[];
  status: 'active' | 'delayed' | 'cancelled';
  currentLocation?: string;
  eta?: string;
  busNumber: string;
}

export interface Payment {
  id: string;
  title: string;
  amount: number;
  dueDate: string;
  status: 'paid' | 'pending' | 'overdue';
  type: string;
  receiptNo?: string;
}

export interface LibraryBook {
  id: string;
  title: string;
  author: string;
  category: string;
  available: boolean;
  dueDate?: string;
  coverColor: string;
  isbn: string;
}

export interface CartItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
  category: string;
}

export interface DashboardStats {
  upcomingClasses: number;
  pendingPayments: number;
  borrowedBooks: number;
  nextBus: string;
}
