/**
 * ログイン中利用者をフロントエンドへ返すレスポンス。
 * 画面表示と初期日報作成に必要な所属・勤務設定だけを公開する。
 */
package com.example.dailyreport.auth;

public record CurrentUserResponse(
        String userId,
        String loginId,
        String userName,
        Role role,
        String groupId,
        String groupName,
        String breakTypeId,
        String breakTypeName,
        String workTimeTypeId,
        String workTimeTypeName
) {
    /**
     * 利用者Entityから、フロントエンドへ公開してよい属性だけをレスポンスへ写像する。
     */
    public static CurrentUserResponse from(AppUser user) {
        return new CurrentUserResponse(
                user.getUserId(),
                user.getLoginId(),
                user.getUserName(),
                user.getRole(),
                user.getGroupId(),
                user.getGroupName(),
                user.getBreakTypeId(),
                user.getBreakTypeName(),
                user.getWorkTimeTypeId(),
                user.getWorkTimeTypeName()
        );
    }
}
