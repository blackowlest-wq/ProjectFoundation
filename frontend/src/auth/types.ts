/**
 * 認証機能で共有するフロントエンド型定義。
 * バックエンドのログイン中利用者レスポンスと画面表示に必要な属性を表す。
 */
export type Role = 'EMPLOYEE' | 'MANAGER' | 'ADMIN';

export type CurrentUser = {
  userId: string;
  loginId: string;
  userName: string;
  role: Role;
  groupId: string | null;
  groupName: string | null;
  breakTypeId: string | null;
  breakTypeName: string | null;
  workTimeTypeId: string | null;
  workTimeTypeName: string | null;
};
