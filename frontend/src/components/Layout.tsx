import { Suspense } from 'react';
import { Outlet } from 'react-router-dom';
import { BranchesShiftsProvider } from '../lib/BranchesShiftsContext';
import { ToastProvider } from '../lib/ToastContext';
import Header from './Header';
import Nav from './Nav';
import { ContentArea } from './layout';

const PageFallback = () => (
  <div className="flex justify-center p-8 text-premium-gold animate-pulse">กำลังโหลด...</div>
);

/** AppShell: full-viewport layout — Topbar (Header), Sidebar (Nav), ContentArea (internal scroll, max 1440px). */
export default function Layout() {
  return (
    <ToastProvider>
    <BranchesShiftsProvider>
      <div className="min-h-screen bg-premium-dark flex flex-col">
        <Header />
        <div className="flex flex-1 min-h-0">
          <Nav />
          <main className="flex-1 min-h-0 min-w-0 overflow-auto okace-scroll">
            <ContentArea className="py-4 md:py-5 pb-20 md:pb-6 min-w-0">
              <Suspense fallback={<PageFallback />}>
                <Outlet />
              </Suspense>
            </ContentArea>
          </main>
        </div>
      </div>
    </BranchesShiftsProvider>
    </ToastProvider>
  );
}
