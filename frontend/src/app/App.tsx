/**
 * フロントエンド全体のルートコンポーネント。
 * 起動時にログイン状態を確認し、未ログインならログイン画面、ログイン済みならロール別の初期画面を表示する。
 */
import { useEffect, useState } from 'react';
import { fetchMe, initialPathFor, logout } from '../auth/authApi';
import { LoginForm } from '../auth/LoginForm';
import { DailyReportCalendarList } from '../dailyReport/DailyReportCalendarList';
import { DailyReportForm } from '../dailyReport/DailyReportForm';
import type { CurrentUser, Role } from '../auth/types';
import '../styles.css';

const pageTitleByRole: Record<Role, string> = {
  EMPLOYEE: '日報カレンダー・一覧',
  MANAGER: '日報カレンダー・一覧',
  ADMIN: '日報カレンダー・一覧',
};

const roleLabelByRole: Record<Role, string> = {
  EMPLOYEE: '社員',
  MANAGER: '上長',
  ADMIN: '管理者',
};

/**
 * 認証済み利用者向けの共通画面を表示し、ロールに応じて日報機能を切り替える。
 */
function AuthenticatedHome({
  user,
  onLogout,
  onUnauthorized,
  logoutError,
}: {
  user: CurrentUser;
  onLogout: () => void;
  onUnauthorized: () => void;
  logoutError: string;
}) {
  return (
    <main className="shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">日報管理</p>
          <h1>{pageTitleByRole[user.role]}</h1>
        </div>
        <button className="secondary" onClick={onLogout}>
          ログアウト
        </button>
      </header>
      <section className="summary">
        <dl>
          <div>
            <dt>利用者</dt>
            <dd>{user.userName}</dd>
          </div>
          <div>
            <dt>ロール</dt>
            <dd>{roleLabelByRole[user.role]}</dd>
          </div>
          <div>
            <dt>所属</dt>
            <dd>{user.groupName ?? '-'}</dd>
          </div>
        </dl>
      </section>
      {logoutError && <p className="error" role="alert">{logoutError}</p>}
      <DailyReportCalendarList user={user} onUnauthorized={onUnauthorized} />
      {user.role === 'EMPLOYEE' && <DailyReportForm user={user} />}
    </main>
  );
}

/**
 * 起動時のセッション確認と、ログイン済み・未ログイン画面の切り替えを管理する。
 */
function App() {
  const [user, setUser] = useState<CurrentUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [sessionMessage, setSessionMessage] = useState('');
  const [logoutError, setLogoutError] = useState('');

  useEffect(() => {
    // How: 起動時にCookieセッションを確認し、応答後にloadingを解除して認証済み/未ログイン画面を選ぶ。
    fetchMe()
      .then(setUser)
      .finally(() => setLoading(false));
  }, []);

  /**
   * ログイン成功時の利用者状態とロール別初期URLを更新する。
   */
  function handleLogin(currentUser: CurrentUser) {
    // How: 認証成功後に利用者状態を更新し、ロール別の初期URLへ履歴を置き換える。
    setUser(currentUser);
    setSessionMessage('');
    setLogoutError('');
    // Why not: 現在のURLをそのまま残すとロール変更後に権限外画面へ留まるため、ログイン直後はロール別の初期URLへ遷移する。
    window.history.replaceState(null, '', initialPathFor(currentUser.role));
  }

  /**
   * ログアウトAPI成功時だけ画面状態とURLをログイン画面へ戻し、失敗時は認証状態を維持する。
   */
  async function handleLogout() {
    setLogoutError('');
    try {
      await logout();
      setUser(null);
      setSessionMessage('');
      // Why not: ログアウト後に保護画面URLを残すと再表示時の誤認を招くため、ログイン画面へ戻す。
      window.history.replaceState(null, '', '/login');
    } catch {
      setLogoutError('ログアウトに失敗しました。時間をおいて再度お試しください。');
    }
  }

  /**
   * 一覧取得などで401を受けた場合に利用者状態を破棄し、ログイン画面へ戻す。
   */
  function handleUnauthorized() {
    setUser(null);
    setSessionMessage('ログインが必要です。');
    setLogoutError('');
    window.history.replaceState(null, '', '/login');
  }

  // How: セッション確認が終わるまで画面を確定せず、読み込み中表示だけを返す。
  if (loading) {
    return <main className="shell">読み込み中...</main>;
  }

  // How: 未認証なら保護画面を表示せず、セッションメッセージ付きのログイン画面へ切り替える。
  if (!user) {
    return (
      <>
        {sessionMessage && <p className="error" role="alert">{sessionMessage}</p>}
        <LoginForm onLogin={handleLogin} />
      </>
    );
  }

  return (
    <AuthenticatedHome
      user={user}
      onLogout={handleLogout}
      onUnauthorized={handleUnauthorized}
      logoutError={logoutError}
    />
  );
}

export default App;
