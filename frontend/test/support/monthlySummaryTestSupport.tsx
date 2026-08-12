import type { CurrentUser } from '../../src/auth/types';

export { buttonByText, cleanupUi, click, flushEffects, keyDown, renderUi, setControlValue } from './uiTestSupport';

export const adminUser: CurrentUser = {
  userId: 'U003',
  loginId: 'admin001',
  userName: '鈴木 一郎',
  role: 'ADMIN',
  groupId: null,
  groupName: null,
  breakTypeId: null,
  breakTypeName: null,
  workTimeTypeId: null,
  workTimeTypeName: null,
};
