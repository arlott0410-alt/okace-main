import { lazy } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './lib/auth';
import Layout from './components/Layout';
import ErrorBoundary from './components/ErrorBoundary';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';

const Meal = lazy(() => import('./pages/Meal'));
const HolidayGrid = lazy(() => import('./pages/HolidayGrid'));
const MassShiftAssignment = lazy(() => import('./pages/MassShiftAssignment'));
const DutyBoard = lazy(() => import('./pages/DutyBoard'));
const ScheduleCards = lazy(() => import('./pages/ScheduleCards'));
const PhotoVault = lazy(() => import('./pages/PhotoVault'));
const GroupLinks = lazy(() => import('./pages/GroupLinks'));
const History = lazy(() => import('./pages/History'));
const Settings = lazy(() => import('./pages/Settings'));
const ManagedWebsites = lazy(() => import('./pages/ManagedWebsites'));
const MyWebsites = lazy(() => import('./pages/MyWebsites'));
const MemberManagement = lazy(() => import('./pages/MemberManagement'));
const Account = lazy(() => import('./pages/Account'));
const ThirdPartyProviders = lazy(() => import('./pages/ThirdPartyProviders'));
function ProtectedRoute({ children, allowedRoles, staffOnly }: { children: React.ReactNode; allowedRoles?: string[]; staffOnly?: boolean }) {
  const { user, profile, loading } = useAuth();
  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-premium-dark">
        <div className="text-premium-gold animate-pulse">กำลังโหลด...</div>
      </div>
    );
  }
  if (!user) return <Navigate to="/login" replace />;
  if (allowedRoles && profile && !allowedRoles.includes(profile.role)) {
    return <Navigate to="/dashboard" replace />;
  }
  if (staffOnly && profile?.role === 'admin') {
    return <Navigate to="/dashboard" replace />;
  }
  return <>{children}</>;
}

export default function App() {
  return (
    <ErrorBoundary>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={
            <ProtectedRoute>
              <Layout />
            </ProtectedRoute>
          }
        >
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<Dashboard />} />
        {/* ลงเวลา menu removed; Timekeeping page and work_logs table retained for other features */}
        <Route path="จองพักอาหาร" element={<ProtectedRoute allowedRoles={['instructor', 'staff', 'manager', 'instructor_head']}><Meal /></ProtectedRoute>} />
        <Route path="ตารางวันหยุด" element={<HolidayGrid />} />
        <Route path="ย้ายกะจำนวนมาก" element={<ProtectedRoute allowedRoles={['admin', 'manager', 'instructor_head']}><MassShiftAssignment /></ProtectedRoute>} />
        <Route path="ประวัติย้ายกะ" element={<Navigate to="/ประวัติ" replace />} />
        <Route path="งานของฉัน" element={<Navigate to="/dashboard" replace />} />
        <Route path="จัดหน้าที่" element={<DutyBoard />} />
        <Route path="ตารางงาน" element={<ScheduleCards />} />
        <Route path="คลังเก็บไฟล์" element={<PhotoVault />} />
        <Route path="กลุ่มงาน" element={<GroupLinks />} />
        <Route path="บุคคลที่สาม" element={<ThirdPartyProviders />} />
        <Route path="ประวัติ" element={<History />} />
        <Route path="เว็บที่ดูแล" element={<ProtectedRoute allowedRoles={['admin', 'manager', 'instructor_head']}><ManagedWebsites /></ProtectedRoute>} />
        <Route path="เว็บที่ฉันดูแล" element={<ProtectedRoute allowedRoles={['instructor', 'staff']}><MyWebsites /></ProtectedRoute>} />
        <Route path="จัดการสมาชิก" element={<ProtectedRoute allowedRoles={['admin', 'manager', 'instructor_head']}><MemberManagement /></ProtectedRoute>} />
        <Route path="บัญชีของฉัน" element={<Account />} />
        <Route path="ตั้งค่า" element={<ProtectedRoute allowedRoles={['admin', 'manager']}><Settings /></ProtectedRoute>} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </ErrorBoundary>
  );
}
