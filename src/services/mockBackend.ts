import type {
  User,
  ClassSchedule,
  TransportRoute,
  Payment,
  LibraryBook,
  DashboardStats,
  CartItem,
} from '../types';

// ─── Fake DB ────────────────────────────────────────────────────────────────
const USERS: User[] = [
  {
    id: 'STU-2024-001',
    name: 'Ahmad Farhan',
    email: 'ahmad.farhan@campus.edu',
    role: 'student',
    studentId: 'STU-2024-001',
    department: 'Computer Science',
    year: 'Year 3',
  },
  {
    id: 'ADM-001',
    name: 'Dr. Sarah Lim',
    email: 'sarah.lim@campus.edu',
    role: 'admin',
    studentId: 'ADM-001',
    department: 'Administration',
    year: 'Staff',
  },
];

const SCHEDULES: ClassSchedule[] = [
  { id: '1', subject: 'Data Structures', code: 'CS301', room: 'LT-4A', time: '08:00 - 10:00', day: 'Monday', lecturer: 'Dr. Kumar', type: 'lecture', color: '#6366f1' },
  { id: '2', subject: 'Algorithms', code: 'CS302', room: 'Lab-2B', time: '10:30 - 12:30', day: 'Monday', lecturer: 'Prof. Lee', type: 'lab', color: '#8b5cf6' },
  { id: '3', subject: 'Database Systems', code: 'CS303', room: 'LT-3C', time: '14:00 - 16:00', day: 'Tuesday', lecturer: 'Dr. Chen', type: 'lecture', color: '#06b6d4' },
  { id: '4', subject: 'Networks', code: 'CS304', room: 'Lab-1A', time: '08:00 - 10:00', day: 'Wednesday', lecturer: 'Prof. Ali', type: 'lab', color: '#10b981' },
  { id: '5', subject: 'Software Engineering', code: 'CS305', room: 'LT-2B', time: '13:00 - 15:00', day: 'Thursday', lecturer: 'Dr. Raj', type: 'tutorial', color: '#f59e0b' },
  { id: '6', subject: 'Operating Systems', code: 'CS306', room: 'LT-5A', time: '10:00 - 12:00', day: 'Friday', lecturer: 'Prof. Nadia', type: 'lecture', color: '#ef4444' },
];

const TRANSPORT: TransportRoute[] = [
  { id: '1', name: 'Campus Express A', route: 'Main Gate → Library → Hostel A → Cafeteria', departureTime: ['07:00', '08:30', '10:00', '12:30', '15:00', '17:30'], status: 'active', currentLocation: 'Library Block', eta: '5 min', busNumber: 'BUS-A01' },
  { id: '2', name: 'Campus Express B', route: 'North Gate → Faculty → Sports Complex → Hostel B', departureTime: ['07:15', '09:00', '11:00', '13:30', '16:00', '18:00'], status: 'active', currentLocation: 'Faculty Block', eta: '12 min', busNumber: 'BUS-B02' },
  { id: '3', name: 'City Link', route: 'Campus → City Center → Train Station', departureTime: ['08:00', '12:00', '17:00', '20:00'], status: 'delayed', currentLocation: 'City Center', eta: '25 min', busNumber: 'BUS-C03' },
];

const PAYMENTS: Payment[] = [
  { id: '1', title: 'Semester Tuition Fee', amount: 4500.00, dueDate: '2024-03-31', status: 'pending', type: 'Tuition' },
  { id: '2', title: 'Library Fine', amount: 12.50, dueDate: '2024-03-15', status: 'overdue', type: 'Fine' },
  { id: '3', title: 'Sports Complex Membership', amount: 85.00, dueDate: '2024-02-28', status: 'paid', type: 'Membership', receiptNo: 'RCP-2024-0234' },
  { id: '4', title: 'Hostel Deposit', amount: 600.00, dueDate: '2024-01-15', status: 'paid', type: 'Hostel', receiptNo: 'RCP-2024-0098' },
  { id: '5', title: 'Lab Access Fee', amount: 150.00, dueDate: '2024-04-01', status: 'pending', type: 'Lab' },
];

const BOOKS: LibraryBook[] = [
  { id: '1', title: 'Introduction to Algorithms', author: 'Cormen et al.', category: 'Computer Science', available: false, dueDate: '2024-03-20', coverColor: '#6366f1', isbn: '978-0262033848' },
  { id: '2', title: 'Clean Code', author: 'Robert C. Martin', category: 'Software Engineering', available: true, coverColor: '#10b981', isbn: '978-0132350884' },
  { id: '3', title: 'Database Design', author: 'C.J. Date', category: 'Databases', available: true, coverColor: '#f59e0b', isbn: '978-0321197849' },
  { id: '4', title: 'Computer Networks', author: 'Andrew Tanenbaum', category: 'Networking', available: false, dueDate: '2024-03-25', coverColor: '#ef4444', isbn: '978-0132126953' },
  { id: '5', title: 'Design Patterns', author: 'Gang of Four', category: 'Software Engineering', available: true, coverColor: '#8b5cf6', isbn: '978-0201633610' },
  { id: '6', title: 'The Pragmatic Programmer', author: 'Hunt & Thomas', category: 'Software Engineering', available: true, coverColor: '#06b6d4', isbn: '978-0135957059' },
];

let cartItems: CartItem[] = [];
let nextCartId = 1;

// ─── Simulate network delay ──────────────────────────────────────────────────
const delay = (ms = 800) => new Promise((res) => setTimeout(res, ms));

// ─── Auth API ────────────────────────────────────────────────────────────────
export const authService = {
  login: async (email: string, password: string, role: 'student' | 'admin'): Promise<User> => {
    await delay(1200);
    const credentials: Record<string, string> = {
      'ahmad.farhan@campus.edu': 'student123',
      'sarah.lim@campus.edu': 'admin123',
    };
    const user = USERS.find((u) => u.email === email && u.role === role);
    if (!user || credentials[email] !== password) {
      throw new Error('Invalid credentials. Please try again.');
    }
    return user;
  },

  logout: async (): Promise<void> => {
    await delay(300);
  },
};

// ─── Dashboard API ───────────────────────────────────────────────────────────
export const dashboardService = {
  getStats: async (): Promise<DashboardStats> => {
    await delay(600);
    return {
      upcomingClasses: 3,
      pendingPayments: 2,
      borrowedBooks: 2,
      nextBus: '15 min',
    };
  },
};

// ─── Schedule API ────────────────────────────────────────────────────────────
export const scheduleService = {
  getSchedule: async (): Promise<ClassSchedule[]> => {
    await delay(700);
    return SCHEDULES;
  },
};

// ─── Transport API ───────────────────────────────────────────────────────────
export const transportService = {
  getRoutes: async (): Promise<TransportRoute[]> => {
    await delay(900);
    return TRANSPORT;
  },
};

// ─── Payments API ────────────────────────────────────────────────────────────
export const paymentService = {
  getPayments: async (): Promise<Payment[]> => {
    await delay(750);
    return PAYMENTS;
  },
  makePayment: async (id: string): Promise<Payment> => {
    await delay(1500);
    const p = PAYMENTS.find((p) => p.id === id);
    if (!p) throw new Error('Payment not found');
    p.status = 'paid';
    p.receiptNo = `RCP-2024-${Math.floor(Math.random() * 9000 + 1000)}`;
    return p;
  },
};

// ─── Library API ─────────────────────────────────────────────────────────────
export const libraryService = {
  getBooks: async (): Promise<LibraryBook[]> => {
    await delay(800);
    return BOOKS;
  },
  borrowBook: async (id: string): Promise<LibraryBook> => {
    await delay(1000);
    const book = BOOKS.find((b) => b.id === id);
    if (!book) throw new Error('Book not found');
    if (!book.available) throw new Error('Book is not available');
    book.available = false;
    const due = new Date();
    due.setDate(due.getDate() + 14);
    book.dueDate = due.toISOString().split('T')[0];
    return book;
  },
};

// ─── Cart API (main feature) ─────────────────────────────────────────────────
export const cartService = {
  getCart: async (): Promise<CartItem[]> => {
    await delay(500);
    return [...cartItems];
  },
  addItem: async (item: Omit<CartItem, 'id'>): Promise<CartItem> => {
    await delay(600);
    const existing = cartItems.find((c) => c.name === item.name);
    if (existing) {
      existing.quantity += item.quantity;
      return existing;
    }
    const newItem: CartItem = { ...item, id: String(nextCartId++) };
    cartItems.push(newItem);
    return newItem;
  },
  removeItem: async (id: string): Promise<void> => {
    await delay(400);
    cartItems = cartItems.filter((c) => c.id !== id);
  },
  clearCart: async (): Promise<void> => {
    await delay(300);
    cartItems = [];
  },
};
