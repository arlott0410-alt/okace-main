import { Component, type ErrorInfo, type ReactNode } from 'react';

type Props = { children: ReactNode };
type State = { hasError: boolean; error?: Error };

/**
 * จับ error จาก component ลูก — แสดงหน้าข้อความแทน white screen
 * ไม่กระทบ flow ระบบ แค่ป้องกันแอปล่มและให้ผู้ใช้กดโหลดใหม่ได้
 */
export default class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    console.error('ErrorBoundary caught:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-premium-dark flex items-center justify-center p-6">
          <div className="max-w-md w-full text-center">
            <h1 className="text-premium-gold text-lg font-medium mb-2">เกิดข้อผิดพลาด</h1>
            <p className="text-gray-400 text-sm mb-6">ระบบทำงานผิดปกติ กรุณากดปุ่มด้านล่างเพื่อโหลดหน้าใหม่</p>
            <button
              type="button"
              onClick={() => window.location.reload()}
              className="px-4 py-2 bg-premium-gold/20 text-premium-gold rounded hover:bg-premium-gold/30 transition"
            >
              โหลดใหม่
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
